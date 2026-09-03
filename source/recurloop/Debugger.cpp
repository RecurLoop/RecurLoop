#include <recurloop/Debugger.hpp>

#include <compiler/DebugInfo.hpp>
#include <compiler/TypeSystem.hpp>
#include <context/Context.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <utilities/Byte.hpp>
#include <utilities/Exception.hpp>

#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <bit>
#include <cerrno>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <memory>
#include <optional>
#include <sstream>
#include <string_view>
#include <unordered_map>

namespace recurloop {
  namespace {
    constexpr std::string_view BreakpointsName{"\0debug-breakpoints", 18};

    enum class BreakpointKind : std::uint64_t { Phrase = 1, Line = 2, Function = 3 };

    struct BreakpointRecord {
      std::uint64_t id = 0;
      BreakpointKind kind = BreakpointKind::Phrase;
      std::uint64_t line = 0;
      std::uint64_t textBytes = 0;
      std::uint64_t active = 1;
    };

    struct Breakpoint {
      BreakpointRecord record;
      std::string text;
    };

    struct NativeBreakpoint {
      std::uintptr_t address = 0;
      std::uint8_t original = 0;
      bool installed = false;
    };

    struct ExecutableState {
      pid_t pid = -1;
      std::filesystem::path path;
      std::vector<compiler::DebugPoint> points;
      std::unordered_map<std::uintptr_t, NativeBreakpoint> breakpoints;
      std::optional<std::uintptr_t> currentBreakpoint;
      std::optional<std::size_t> currentPoint;
      int pendingSignal = 0;
      std::uintptr_t instruction = 0;
    };

    struct DebugRuntime {
      DebuggerState state;
      ExecutableState executable;
    };

    struct DebuggerStates {
      std::unordered_map<context::Context *, std::unique_ptr<DebugRuntime>> values;
    };

    DebuggerStates &debuggerStates() {
      static thread_local DebuggerStates states;
      return states;
    }

    DebugRuntime &debugRuntime(context::Context &context) {
      DebuggerStates &states = debuggerStates();
      std::unique_ptr<DebugRuntime> &runtime = states.values[&context];
      if (!runtime) runtime = std::make_unique<DebugRuntime>();
      return *runtime;
    }

    DebuggerState &debuggerState(context::Context &context) {
      return debugRuntime(context).state;
    }

    ExecutableState &executableState(context::Context &context) {
      return debugRuntime(context).executable;
    }

    std::string trim(std::string value) {
      const auto begin = std::find_if_not(value.begin(), value.end(), [](unsigned char c) { return std::isspace(c); });
      const auto end =
          std::find_if_not(value.rbegin(), value.rend(), [](unsigned char c) { return std::isspace(c); }).base();
      return begin < end ? std::string(begin, end) : std::string{};
    }

    char peek(context::Context &context) {
      while (context.source.buffer.bits == 0 && context.source.more) context::Source::load(context, false);
      return context.source.buffer.bits == 0 ? '\0'
                                             : context.source.buffer.str[context.source.buffer.offset / Byte::length];
    }

    std::string readLine(context::Context &context) {
      std::string result;
      while (peek(context) != '\0' && peek(context) != '\n') {
        result.push_back(peek(context));
        context::Source::progress(context, Byte::length);
      }
      return trim(std::move(result));
    }

    lexicon::Phrase exact(lexicon::Phrase dictionary, std::string_view key) {
      if (dictionary.isNull() || !dictionary.containsSubdictionary()) return lexicon::Phrase(dictionary.getLexicon());
      lexicon::Match match = dictionary.matchExact(
          Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length,
          [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); });
      return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
    }

    lexicon::Phrase breakpointDictionary(context::Context &context) {
      lexicon::Phrase debug = exact(context.lexicon.phrase(), "debug");
      lexicon::Phrase result = exact(debug, BreakpointsName);
      if (result.isNull()) THROW(, "debugger breakpoint dictionary is unavailable")
      return result;
    }

    Breakpoint decodeBreakpoint(lexicon::Phrase phrase) {
      if (phrase.payloadSize() < sizeof(BreakpointRecord)) THROW(, "debugger breakpoint payload is truncated")
      Breakpoint result;
      phrase.fetch(0, result.record);
      if (result.record.textBytes > std::numeric_limits<Size>::max() ||
          phrase.payloadSize() != sizeof(BreakpointRecord) + result.record.textBytes)
        THROW(, "debugger breakpoint payload is invalid")
      if (result.record.textBytes != 0) {
        const char *text = reinterpret_cast<const char *>(
            phrase.content(sizeof(BreakpointRecord), static_cast<Size>(result.record.textBytes)).toPtr());
        result.text.assign(text, result.record.textBytes);
      }
      return result;
    }

    std::vector<Breakpoint> breakpoints(context::Context &context) {
      lexicon::Phrase dictionary = breakpointDictionary(context);
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      std::vector<Breakpoint> result;
      for (lexicon::Dictionary cursor = dictionary.fore(populated); !cursor.isNull(); cursor = cursor.next(populated)) {
        lexicon::Phrase phrase = cursor.getPhrase();
        if (!phrase.isNull()) result.push_back(decodeBreakpoint(phrase));
      }
      std::sort(result.begin(), result.end(),
                [](const Breakpoint &left, const Breakpoint &right) { return left.record.id < right.record.id; });
      return result;
    }

    std::uint64_t nextBreakpointId(context::Context &context, DebuggerState &state) {
      for (const Breakpoint &breakpoint : breakpoints(context))
        state.nextBreakpoint = std::max(state.nextBreakpoint, breakpoint.record.id + 1);
      return state.nextBreakpoint++;
    }

    void saveBreakpoint(context::Context &context, const Breakpoint &breakpoint) {
      lexicon::Phrase dictionary = breakpointDictionary(context);
      lexicon::Phrase phrase = dictionary.append(std::to_string(breakpoint.record.id))
                                   .make()
                                   .setType(lexicon::phrase::type::getData(dictionary))
                                   .save()
                                   .store(breakpoint.record);
      if (!breakpoint.text.empty()) {
        Byte output = phrase.allocate(breakpoint.text.size());
        Byte::copy(Byte(const_cast<char *>(breakpoint.text.data())), output, breakpoint.text.size());
      }
      phrase.save();
    }

    std::string stringArgument(context::Context &context, std::string_view operation) {
      const std::string expression = readLine(context);
      if (expression.empty()) THROW(, operation << " requires a string")
      const context::Value value = Expressions::evaluate(context, expression);
      if (!value.isString()) THROW(, operation << " requires a string")
      if (value.asString().find('\0') != std::string::npos) THROW(, operation << " string contains a NUL byte")
      return value.asString();
    }

    bool samePath(std::string_view left, std::string_view right) {
      if (left == right) return true;
      return std::filesystem::path(left).filename() == std::filesystem::path(right).filename();
    }

    bool stoppable(std::string_view phrase) {
      return !phrase.empty() && std::any_of(phrase.begin(), phrase.end(),
                                            [](unsigned char character) { return !std::isspace(character); });
    }

    bool matches(context::Context &context, const DebuggerState::Event &event) {
      for (const Breakpoint &breakpoint : breakpoints(context)) {
        if (breakpoint.record.active == 0) continue;
        if (breakpoint.record.kind == BreakpointKind::Phrase && breakpoint.text == event.phrase) return true;
        if (breakpoint.record.kind == BreakpointKind::Line && breakpoint.record.line == event.location.line &&
            samePath(breakpoint.text, event.location.path))
          return true;
      }
      return false;
    }

    const char *modeName(DebuggerState::Mode mode) {
      switch (mode) {
      case DebuggerState::Mode::Continue: return "continue";
      case DebuggerState::Mode::Step: return "step";
      case DebuggerState::Mode::Next: return "next";
      case DebuggerState::Mode::Finish: return "finish";
      }
      return "unknown";
    }

    void printEvent(context::Context &context, const DebuggerState::Event &event, std::string_view prefix) {
      *context.io.out << "[debug] " << prefix << " " << (event.location.path.empty() ? "<input>" : event.location.path)
                      << ":" << event.location.line << ":" << event.location.position << " phrase \"" << event.phrase
                      << "\" depth " << event.depth << "\n";
    }

    [[noreturn]] void ptraceFailure(std::string_view operation) {
      const int error = errno;
      std::ostringstream message;
      message << "executable debugger " << operation << " failed: " << std::strerror(error);
      throw Exception(__FILE__, __LINE__, __PRETTY_FUNCTION__, message.str());
    }

    user_regs_struct registersOf(const ExecutableState &target) {
      user_regs_struct registers{};
      errno = 0;
      if (ptrace(PTRACE_GETREGS, target.pid, nullptr, &registers) == -1) ptraceFailure("get registers");
      return registers;
    }

    void writeRegisters(const ExecutableState &target, const user_regs_struct &registers) {
      errno = 0;
      if (ptrace(PTRACE_SETREGS, target.pid, nullptr, &registers) == -1) ptraceFailure("set registers");
    }

    std::vector<compiler::DebugPoint> readDebugPoints(const std::filesystem::path &path) {
      std::ifstream input(path, std::ios::binary);
      if (!input.is_open()) THROW(, "cannot open emitted executable '" << path.string() << "'")
      std::vector<std::uint8_t> bytes{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
      if (input.bad()) THROW(, "cannot read emitted executable '" << path.string() << "'")
      std::vector<compiler::DebugPoint> points = compiler::DebugInfo::readExecutable(bytes);
      if (points.empty()) THROW(, "emitted executable contains no debuggable RecurLoop statements")
      return points;
    }

    std::optional<std::size_t> pointAt(const ExecutableState &target, std::uintptr_t address) {
      const auto found = std::lower_bound(
          target.points.begin(), target.points.end(), address,
          [](const compiler::DebugPoint &point, std::uintptr_t value) { return point.address < value; });
      if (found == target.points.end() || found->address != address) return std::nullopt;
      return static_cast<std::size_t>(found - target.points.begin());
    }

    bool matches(const Breakpoint &breakpoint, const compiler::DebugPoint &point) {
      if (breakpoint.record.active == 0) return false;
      if (breakpoint.record.kind == BreakpointKind::Phrase) return breakpoint.text == point.phrase;
      if (breakpoint.record.kind == BreakpointKind::Function) return breakpoint.text == point.function;
      return breakpoint.record.kind == BreakpointKind::Line && breakpoint.record.line == point.line &&
             samePath(breakpoint.text, point.path);
    }

    std::uint8_t patchTextByte(ExecutableState &target, std::uintptr_t address, std::uint8_t value,
                               std::string_view operation) {
      const std::uintptr_t wordAddress = address & ~(sizeof(long) - 1);
      const unsigned shift = static_cast<unsigned>((address - wordAddress) * 8);
      errno = 0;
      const long word = ptrace(PTRACE_PEEKTEXT, target.pid, reinterpret_cast<void *>(wordAddress), nullptr);
      if (word == -1 && errno != 0) ptraceFailure(operation);
      const auto bits = static_cast<unsigned long>(word);
      const std::uint8_t previous = static_cast<std::uint8_t>(bits >> shift);
      const unsigned long patched = (bits & ~(0xffUL << shift)) | (static_cast<unsigned long>(value) << shift);
      errno = 0;
      if (ptrace(PTRACE_POKETEXT, target.pid, reinterpret_cast<void *>(wordAddress), patched) == -1)
        ptraceFailure(operation);
      return previous;
    }

    void installBreakpoint(ExecutableState &target, std::uintptr_t address) {
      if (target.breakpoints.contains(address)) return;
      const std::uint8_t original = patchTextByte(target, address, 0xcc, "install breakpoint");
      target.breakpoints.emplace(address, NativeBreakpoint{address, original, true});
    }

    void restoreBreakpoint(ExecutableState &target, NativeBreakpoint &breakpoint) {
      if (!breakpoint.installed) return;
      patchTextByte(target, breakpoint.address, breakpoint.original, "restore breakpoint");
      breakpoint.installed = false;
    }

    void reinsertBreakpoint(ExecutableState &target, NativeBreakpoint &breakpoint) {
      if (breakpoint.installed) return;
      patchTextByte(target, breakpoint.address, 0xcc, "reinsert breakpoint");
      breakpoint.installed = true;
    }

    void printExecutablePoint(context::Context &context, std::string_view reason) {
      const ExecutableState &target = executableState(context);
      if (!target.currentPoint) {
        *context.io.out << "[debug] executable " << reason << " " << target.path.string() << " rip 0x" << std::hex
                        << target.instruction << std::dec << "\n";
        return;
      }
      const compiler::DebugPoint &point = target.points[*target.currentPoint];
      *context.io.out << "[debug] " << reason << " " << (point.path.empty() ? "<input>" : point.path) << ":"
                      << point.line << ":" << point.column << " phrase \"" << point.phrase << "\" function \""
                      << point.function << "\" rip 0x" << std::hex << point.address << std::dec << "\n";
    }

    bool finishExecutable(context::Context &context, int status) {
      DebuggerState &state = debuggerState(context);
      ExecutableState &target = executableState(context);
      if (WIFEXITED(status))
        *context.io.out << "[debug] executable exited with status " << WEXITSTATUS(status) << "\n";
      else if (WIFSIGNALED(status))
        *context.io.out << "[debug] executable terminated by signal " << WTERMSIG(status) << "\n";
      else
        return false;
      target.pid = -1;
      target.breakpoints.clear();
      target.currentBreakpoint.reset();
      target.currentPoint.reset();
      state.active = false;
      state.paused = false;
      state.target = DebuggerState::Target::None;
      return true;
    }

    void restoreAllBreakpoints(ExecutableState &target) {
      for (auto &[address, breakpoint] : target.breakpoints) restoreBreakpoint(target, breakpoint);
    }

    void installConfiguredBreakpoints(context::Context &context) {
      ExecutableState &target = executableState(context);
      restoreAllBreakpoints(target);
      target.breakpoints.clear();
      const std::vector<Breakpoint> configured = breakpoints(context);
      for (const Breakpoint &breakpoint : configured) {
        if (breakpoint.record.active == 0) continue;
        for (const compiler::DebugPoint &point : target.points) {
          if (!matches(breakpoint, point)) continue;
          installBreakpoint(target, point.address);
          if (breakpoint.record.kind == BreakpointKind::Function) break;
        }
      }
      if (target.currentPoint && target.breakpoints.contains(target.instruction))
        target.currentBreakpoint = target.instruction;
      else if (target.currentBreakpoint && !target.breakpoints.contains(*target.currentBreakpoint))
        target.currentBreakpoint.reset();
    }

    bool waitForExecutable(context::Context &context) {
      ExecutableState &target = executableState(context);
      int status = 0;
      if (waitpid(target.pid, &status, 0) == -1) ptraceFailure("wait");
      if (finishExecutable(context, status)) return false;
      if (!WIFSTOPPED(status)) THROW(, "executable debugger received an unexpected wait status")

      target.pendingSignal = WSTOPSIG(status) == SIGTRAP ? 0 : WSTOPSIG(status);
      user_regs_struct registers = registersOf(target);
      target.instruction = registers.rip;
      target.currentPoint = pointAt(target, target.instruction);
      if (WSTOPSIG(status) == SIGTRAP && registers.rip != 0) {
        const std::uintptr_t address = registers.rip - 1;
        auto found = target.breakpoints.find(address);
        if (found != target.breakpoints.end() && found->second.installed) {
          restoreBreakpoint(target, found->second);
          registers.rip = address;
          writeRegisters(target, registers);
          target.instruction = address;
          target.currentBreakpoint = address;
          target.currentPoint = pointAt(target, address);
          printExecutablePoint(context, "breakpoint");
          return true;
        }
      }
      target.currentBreakpoint.reset();
      printExecutablePoint(context, target.pendingSignal == 0 ? "stopped" : "signal");
      return true;
    }

    bool stepOverCurrentBreakpoint(context::Context &context, bool reinsert) {
      ExecutableState &target = executableState(context);
      if (!target.currentBreakpoint) return true;
      const std::uintptr_t address = *target.currentBreakpoint;
      NativeBreakpoint &breakpoint = target.breakpoints.at(address);
      restoreBreakpoint(target, breakpoint);
      errno = 0;
      if (ptrace(PTRACE_SINGLESTEP, target.pid, nullptr, nullptr) == -1) ptraceFailure("step over breakpoint");
      int status = 0;
      if (waitpid(target.pid, &status, 0) == -1) ptraceFailure("wait after breakpoint");
      if (finishExecutable(context, status)) return false;
      if (!WIFSTOPPED(status)) THROW(, "executable debugger received an unexpected step status")
      if (reinsert) reinsertBreakpoint(target, breakpoint);
      target.pendingSignal = WSTOPSIG(status) == SIGTRAP ? 0 : WSTOPSIG(status);
      target.currentBreakpoint.reset();
      target.instruction = registersOf(target).rip;
      target.currentPoint = pointAt(target, target.instruction);
      return true;
    }

    void continueExecutable(context::Context &context) {
      ExecutableState &target = executableState(context);
      if (target.pid <= 0) THROW(, "no executable target is stopped")
      if (!stepOverCurrentBreakpoint(context, true)) return;
      errno = 0;
      if (ptrace(PTRACE_CONT, target.pid, nullptr,
                 reinterpret_cast<void *>(static_cast<std::intptr_t>(target.pendingSignal))) == -1)
        ptraceFailure("continue");
      target.pendingSignal = 0;
      waitForExecutable(context);
    }

    void stepExecutable(context::Context &context, DebuggerState::Mode mode) {
      ExecutableState &target = executableState(context);
      if (target.pid <= 0) THROW(, "no executable target is stopped")
      const user_regs_struct initial = registersOf(target);
      const std::uintptr_t startAddress =
          target.currentPoint ? target.points[*target.currentPoint].address : initial.rip;
      if (!stepOverCurrentBreakpoint(context, false)) return;
      restoreAllBreakpoints(target);

      while (target.pid > 0) {
        errno = 0;
        if (ptrace(PTRACE_SINGLESTEP, target.pid, nullptr,
                   reinterpret_cast<void *>(static_cast<std::intptr_t>(target.pendingSignal))) == -1)
          ptraceFailure("source step");
        target.pendingSignal = 0;
        int status = 0;
        if (waitpid(target.pid, &status, 0) == -1) ptraceFailure("wait during source step");
        if (finishExecutable(context, status)) return;
        if (!WIFSTOPPED(status)) THROW(, "executable debugger received an unexpected source-step status")
        if (WSTOPSIG(status) != SIGTRAP) {
          target.pendingSignal = WSTOPSIG(status);
          target.instruction = registersOf(target).rip;
          target.currentPoint = pointAt(target, target.instruction);
          installConfiguredBreakpoints(context);
          printExecutablePoint(context, "signal");
          return;
        }

        const user_regs_struct current = registersOf(target);
        const std::optional<std::size_t> point = pointAt(target, current.rip);
        if (!point || target.points[*point].address == startAddress) continue;
        const bool stop = mode == DebuggerState::Mode::Step ||
                          (mode == DebuggerState::Mode::Next && current.rsp >= initial.rsp) ||
                          (mode == DebuggerState::Mode::Finish && current.rsp > initial.rsp);
        if (!stop) continue;

        target.instruction = current.rip;
        target.currentPoint = point;
        installConfiguredBreakpoints(context);
        if (target.breakpoints.contains(current.rip)) target.currentBreakpoint = current.rip;
        printExecutablePoint(context, "stopped");
        return;
      }
    }

    const compiler::DebugPoint &currentExecutablePoint(context::Context &context) {
      const ExecutableState &target = executableState(context);
      if (target.pid <= 0 || !target.currentPoint) THROW(, "executable is not stopped at a RecurLoop statement")
      return target.points[*target.currentPoint];
    }

    std::uint64_t readLocalValue(const ExecutableState &target, const compiler::DebugLocal &local) {
      if (local.size == 0 || local.size > sizeof(long))
        THROW(, "debugger cannot read local '" << local.name << "' with size " << local.size)
      const user_regs_struct registers = registersOf(target);
      if (registers.rbp < local.frameOffset) THROW(, "invalid frame offset for local '" << local.name << "'")
      errno = 0;
      const long word =
          ptrace(PTRACE_PEEKDATA, target.pid, reinterpret_cast<void *>(registers.rbp - local.frameOffset), nullptr);
      if (word == -1 && errno != 0) ptraceFailure("read local");
      std::uint64_t value = static_cast<std::uint64_t>(word);
      if (local.size < sizeof(value)) value &= (std::uint64_t{1} << (local.size * 8)) - 1;
      return value;
    }

    void printLocal(context::Context &context, const compiler::DebugLocal &local) {
      const std::uint64_t bits = readLocalValue(executableState(context), local);
      *context.io.out << "[debug] " << local.name << ":" << local.type << " = ";
      const auto kind = static_cast<compiler::TypeKind>(local.kind);
      if (kind == compiler::TypeKind::FloatingPoint && local.size == sizeof(float)) {
        *context.io.out << std::bit_cast<float>(static_cast<std::uint32_t>(bits));
      } else if (kind == compiler::TypeKind::FloatingPoint && local.size == sizeof(double)) {
        *context.io.out << std::bit_cast<double>(bits);
      } else if (kind == compiler::TypeKind::Pointer) {
        *context.io.out << "0x" << std::hex << bits << std::dec;
      } else if (local.type == "bool") {
        *context.io.out << (bits == 0 ? "false" : "true");
      } else if (local.signedValue) {
        const unsigned width = local.size * 8;
        const std::int64_t value = width == 64 ? static_cast<std::int64_t>(bits)
                                               : static_cast<std::int64_t>(bits << (64 - width)) >> (64 - width);
        *context.io.out << value;
      } else {
        *context.io.out << bits;
      }
      *context.io.out << "\n";
    }

    void terminateExecutable(ExecutableState &target) {
      if (target.pid <= 0) return;
      ptrace(PTRACE_KILL, target.pid, nullptr, nullptr);
      waitpid(target.pid, nullptr, 0);
      target.pid = -1;
    }

    void controller(context::Context &context, DebuggerState &state) {
      state.paused = true;
      while (state.paused) {
        *context.io.out << "debug> " << std::flush;
        std::string command;
        if (!std::getline(std::cin, command)) {
          if (state.target == DebuggerState::Target::Executable) {
            terminateExecutable(executableState(context));
            state.active = false;
            state.target = DebuggerState::Target::None;
            *context.io.out << "\n[debug] controller input closed; executable terminated\n";
          } else {
            *context.io.out << "\n[debug] controller input closed; continuing\n";
            state.mode = DebuggerState::Mode::Continue;
          }
          state.paused = false;
          break;
        }
        command = trim(std::move(command));
        if (command.empty()) continue;
        if (!command.starts_with("debug")) command = "debug:" + command;
        command.push_back('\n');

        const context::Lookup savedLookup = context.lookup;
        lexicon::Phrase root = context.lexicon.phrase();
        context::Lookup::in(context, root);
        state.controller = true;
        try {
          executeSource(context, command, "<debugger>", 1);
        } catch (const std::exception &error) {
          *context.io.err << "[debug] " << error.what() << "\n";
        }
        state.controller = false;
        context.lookup = savedLookup;
      }
    }

    void setMode(context::Context &context, DebuggerState::Mode mode) {
      DebuggerState &state = debuggerState(context);
      state.mode = mode;
      state.resumeDepth = state.current.depth;
      state.paused = false;
      *context.io.out << "[debug] " << modeName(mode) << "\n";
    }
  } // namespace

  void Debugger::initialize(context::Context &context) {
    DebuggerStates &states = debuggerStates();
    states.values[&context] = std::make_unique<DebugRuntime>();
  }

  void Debugger::release(context::Context &context) {
    DebuggerStates &states = debuggerStates();
    auto found = states.values.find(&context);
    if (found != states.values.end()) terminateExecutable(found->second->executable);
    states.values.erase(&context);
  }

  DebuggerState &Debugger::state(context::Context &context) {
    return debuggerState(context);
  }

  void Debugger::registerActions(context::Context &context) {
    context::Actions actions = context.actions();
    actions.define("debugger.break-phrase", breakPhrase);
    actions.define("debugger.break-line", breakLine);
    actions.define("debugger.break-function", breakFunction);
    actions.define("debugger.delete", deleteBreakpoint);
    actions.define("debugger.breakpoints", listBreakpoints);
    actions.define("debugger.trace", trace);
    actions.define("debugger.run", run);
    actions.define("debugger.continue", resume);
    actions.define("debugger.step", step);
    actions.define("debugger.next", next);
    actions.define("debugger.finish", finish);
    actions.define("debugger.where", where);
    actions.define("debugger.evaluate", evaluate);
    actions.define("debugger.executable-run", runExecutable);
    actions.define("debugger.locals", locals);
    actions.define("debugger.registers", registers);
  }

  void Debugger::setup(context::Context &context, lexicon::Phrase debug) {
    if (exact(debug, BreakpointsName).isNull())
      debug.append(Byte(const_cast<char *>(BreakpointsName.data())), 0, BreakpointsName.size() * Byte::length)
          .make()
          .enableSubdictionary()
          .setType(lexicon::phrase::type::getData(debug))
          .save();
    state(context);
  }

  void Debugger::sourceEnter(context::Context &context) {
    DebuggerState &runtime = state(context);
    if (runtime.active && !runtime.controller) ++runtime.sourceDepth;
  }

  void Debugger::sourceLeave(context::Context &context) {
    DebuggerState &runtime = state(context);
    if (runtime.active && !runtime.controller && runtime.sourceDepth != 0) --runtime.sourceDepth;
  }

  void Debugger::beforeElaborate(context::Context &context, lexicon::Phrase &phrase, const DebugLocation &location) {
    DebuggerState &runtime = state(context);
    if (!runtime.active || runtime.controller) return;
    const std::string name = phrase.getKey();
    if (!stoppable(name)) return;

    DebuggerState::Event event{location, name, runtime.sourceDepth, ++runtime.sequence, false};
    event.breakpoint = matches(context, event);
    runtime.current = event;
    if (runtime.trace) printEvent(context, event, "event");

    const bool modeStop = runtime.mode == DebuggerState::Mode::Step ||
                          (runtime.mode == DebuggerState::Mode::Next && event.depth <= runtime.resumeDepth) ||
                          (runtime.mode == DebuggerState::Mode::Finish && event.depth < runtime.resumeDepth);
    if (!event.breakpoint && !modeStop) return;
    runtime.mode = DebuggerState::Mode::Continue;
    printEvent(context, event, event.breakpoint ? "breakpoint" : "stopped");
    controller(context, runtime);
  }

  void Debugger::breakPhrase(context::Context &context, lexicon::Phrase &) {
    Breakpoint breakpoint;
    breakpoint.record.id = nextBreakpointId(context, state(context));
    breakpoint.record.kind = BreakpointKind::Phrase;
    breakpoint.text = stringArgument(context, "debug break phrase");
    breakpoint.record.textBytes = breakpoint.text.size();
    saveBreakpoint(context, breakpoint);
    if (state(context).target == DebuggerState::Target::Executable) installConfiguredBreakpoints(context);
    *context.io.out << "[debug] breakpoint " << breakpoint.record.id << " phrase \"" << breakpoint.text << "\"\n";
  }

  void Debugger::breakLine(context::Context &context, lexicon::Phrase &) {
    const std::string specification = readLine(context);
    const std::size_t separator = specification.rfind(':');
    if (separator == std::string::npos) THROW(, "debug break line expects \"path\":line")
    const context::Value path = Expressions::evaluate(context, trim(specification.substr(0, separator)));
    if (!path.isString() || path.asString().empty()) THROW(, "debug break line requires a non-empty path")
    const std::string number = trim(specification.substr(separator + 1));
    std::size_t consumed = 0;
    std::uint64_t line = 0;
    try {
      line = std::stoull(number, &consumed);
    } catch (...) {
      THROW(, "debug break line requires a positive line number")
    }
    if (line == 0 || consumed != number.size()) THROW(, "debug break line requires a positive line number")

    Breakpoint breakpoint;
    breakpoint.record.id = nextBreakpointId(context, state(context));
    breakpoint.record.kind = BreakpointKind::Line;
    breakpoint.record.line = line;
    breakpoint.text = path.asString();
    breakpoint.record.textBytes = breakpoint.text.size();
    saveBreakpoint(context, breakpoint);
    if (state(context).target == DebuggerState::Target::Executable) installConfiguredBreakpoints(context);
    *context.io.out << "[debug] breakpoint " << breakpoint.record.id << " " << breakpoint.text << ":" << line << "\n";
  }

  void Debugger::breakFunction(context::Context &context, lexicon::Phrase &) {
    Breakpoint breakpoint;
    breakpoint.record.id = nextBreakpointId(context, state(context));
    breakpoint.record.kind = BreakpointKind::Function;
    breakpoint.text = stringArgument(context, "debug break function");
    breakpoint.record.textBytes = breakpoint.text.size();
    saveBreakpoint(context, breakpoint);
    if (state(context).target == DebuggerState::Target::Executable) installConfiguredBreakpoints(context);
    *context.io.out << "[debug] breakpoint " << breakpoint.record.id << " function \"" << breakpoint.text << "\"\n";
  }

  void Debugger::deleteBreakpoint(context::Context &context, lexicon::Phrase &) {
    const std::string argument = readLine(context);
    std::size_t consumed = 0;
    std::uint64_t id = 0;
    try {
      id = std::stoull(argument, &consumed);
    } catch (...) {
      THROW(, "debug delete requires a breakpoint id")
    }
    if (id == 0 || consumed != argument.size()) THROW(, "debug delete requires a breakpoint id")
    for (Breakpoint breakpoint : breakpoints(context)) {
      if (breakpoint.record.id != id || breakpoint.record.active == 0) continue;
      breakpoint.record.active = 0;
      saveBreakpoint(context, breakpoint);
      if (state(context).target == DebuggerState::Target::Executable) installConfiguredBreakpoints(context);
      *context.io.out << "[debug] deleted breakpoint " << id << "\n";
      return;
    }
    THROW(, "debug breakpoint " << id << " does not exist")
  }

  void Debugger::listBreakpoints(context::Context &context, lexicon::Phrase &) {
    bool any = false;
    for (const Breakpoint &breakpoint : breakpoints(context)) {
      if (breakpoint.record.active == 0) continue;
      any = true;
      *context.io.out << "[debug] " << breakpoint.record.id << " ";
      switch (breakpoint.record.kind) {
      case BreakpointKind::Phrase: *context.io.out << "phrase \"" << breakpoint.text << "\""; break;
      case BreakpointKind::Line: *context.io.out << breakpoint.text << ":" << breakpoint.record.line; break;
      case BreakpointKind::Function: *context.io.out << "function \"" << breakpoint.text << "\""; break;
      }
      *context.io.out << "\n";
    }
    if (!any) *context.io.out << "[debug] no breakpoints\n";
  }

  void Debugger::trace(context::Context &context, lexicon::Phrase &invoked) {
    const std::string argument = readLine(context);
    DebuggerState &runtime = state(context);
    lexicon::Phrase value = LanguageGrammar::resolve(context, invoked, argument);
    lexicon::Phrase metadata = LanguageGrammar::metadata(value, sizeof(std::uint8_t));
    if (metadata.isNull()) THROW(, "debug trace expects an on/off phrase")
    std::uint8_t enabled = 0;
    metadata.fetch(0, enabled);
    runtime.trace = enabled != 0;
    *context.io.out << "[debug] trace " << (runtime.trace ? "on" : "off") << "\n";
  }

  void Debugger::run(context::Context &context, lexicon::Phrase &invoked) {
    const std::string requested = stringArgument(context, "debug run");
    std::filesystem::path path(requested);
    if (path.is_relative() && !context.source.path.empty() && context.source.path.front() != '<')
      path = std::filesystem::path(context.source.path).parent_path() / path;
    std::error_code error;
    path = std::filesystem::absolute(path, error).lexically_normal();
    if (error) THROW(, "debug run cannot resolve path: " << error.message())

    std::ifstream input(path, std::ios::binary);
    if (!input.is_open()) THROW(, "debug run cannot open '" << path.string() << "'")
    const std::string source{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
    if (input.bad()) THROW(, "debug run cannot read '" << path.string() << "'")

    // `debug run` owns the nested execution, so close its lookup scope before
    // entering the target. The command is deliberately callable, not scoped-callable.
    context::Lookup::leave(context, invoked);
    DebuggerState &runtime = state(context);
    if (runtime.active) THROW(, "a debugger target is already active")
    runtime.active = true;
    runtime.target = DebuggerState::Target::Source;
    runtime.paused = false;
    runtime.mode = DebuggerState::Mode::Continue;
    runtime.sourceDepth = 0;
    runtime.sequence = 0;
    runtime.current = {};
    *context.io.out << "[debug] running " << path.string() << "\n";
    try {
      executeSource(context, source, path.string(), 1);
    } catch (...) {
      runtime.active = false;
      runtime.target = DebuggerState::Target::None;
      throw;
    }
    runtime.active = false;
    runtime.target = DebuggerState::Target::None;
    *context.io.out << "[debug] finished " << path.string() << "\n";
  }

  void Debugger::resume(context::Context &context, lexicon::Phrase &) {
    if (state(context).target == DebuggerState::Target::Executable) {
      *context.io.out << "[debug] continue\n";
      continueExecutable(context);
      return;
    }
    setMode(context, DebuggerState::Mode::Continue);
  }
  void Debugger::step(context::Context &context, lexicon::Phrase &) {
    if (state(context).target == DebuggerState::Target::Executable) {
      *context.io.out << "[debug] step\n";
      stepExecutable(context, DebuggerState::Mode::Step);
      return;
    }
    setMode(context, DebuggerState::Mode::Step);
  }
  void Debugger::next(context::Context &context, lexicon::Phrase &) {
    if (state(context).target == DebuggerState::Target::Executable) {
      *context.io.out << "[debug] next\n";
      stepExecutable(context, DebuggerState::Mode::Next);
      return;
    }
    setMode(context, DebuggerState::Mode::Next);
  }
  void Debugger::finish(context::Context &context, lexicon::Phrase &) {
    if (state(context).target == DebuggerState::Target::Executable) {
      *context.io.out << "[debug] finish\n";
      stepExecutable(context, DebuggerState::Mode::Finish);
      return;
    }
    setMode(context, DebuggerState::Mode::Finish);
  }

  void Debugger::where(context::Context &context, lexicon::Phrase &) {
    if (state(context).target == DebuggerState::Target::Executable) {
      ExecutableState &target = executableState(context);
      target.instruction = registersOf(target).rip;
      target.currentPoint = pointAt(target, target.instruction);
      printExecutablePoint(context, "at");
      return;
    }
    const DebuggerState::Event &event = state(context).current;
    if (event.sequence == 0) {
      *context.io.out << "[debug] target is not stopped\n";
      return;
    }
    printEvent(context, event, "at");
  }

  void Debugger::evaluate(context::Context &context, lexicon::Phrase &) {
    const std::string expression = readLine(context);
    if (expression.empty()) THROW(, "debug eval requires an expression")
    if (state(context).target == DebuggerState::Target::Executable) {
      const compiler::DebugPoint &point = currentExecutablePoint(context);
      const auto found = std::find_if(point.locals.begin(), point.locals.end(),
                                      [&](const compiler::DebugLocal &local) { return local.name == expression; });
      if (found == point.locals.end()) THROW(, "local '" << expression << "' is not visible here")
      printLocal(context, *found);
      return;
    }
    const context::Value value = Expressions::evaluate(context, expression);
    *context.io.out << "[debug] " << value.typeName() << " " << value.format() << "\n";
  }

  void Debugger::runExecutable(context::Context &context, lexicon::Phrase &invoked) {
    const std::string requested = stringArgument(context, "debug executable run");
    std::filesystem::path path(requested);
    if (path.is_relative() && !context.source.path.empty() && context.source.path.front() != '<')
      path = std::filesystem::path(context.source.path).parent_path() / path;
    std::error_code error;
    path = std::filesystem::absolute(path, error).lexically_normal();
    if (error || !std::filesystem::is_regular_file(path))
      THROW(, "debug executable run cannot resolve '" << requested << "'")
    std::vector<compiler::DebugPoint> points = readDebugPoints(path);

    context::Lookup::leave(context, invoked);
    DebuggerState &runtime = state(context);
    ExecutableState &target = executableState(context);
    if (runtime.active || target.pid > 0) THROW(, "a debugger target is already active")
    target = {};
    target.path = path;
    target.points = std::move(points);

    const pid_t pid = fork();
    if (pid == -1) THROW(, "debug executable run cannot fork: " << std::strerror(errno))
    if (pid == 0) {
      if (ptrace(PTRACE_TRACEME, 0, nullptr, nullptr) == -1) _exit(126);
      execl(path.c_str(), path.c_str(), static_cast<char *>(nullptr));
      _exit(127);
    }
    target.pid = pid;
    runtime.active = true;
    runtime.target = DebuggerState::Target::Executable;
    runtime.paused = true;

    int status = 0;
    if (waitpid(pid, &status, 0) == -1) ptraceFailure("initial wait");
    if (!WIFSTOPPED(status)) {
      target.pid = -1;
      runtime.active = false;
      runtime.target = DebuggerState::Target::None;
      if (WIFEXITED(status))
        THROW(, "executable target exited before its initial stop with status " << WEXITSTATUS(status)
                                                                                << " (ptrace or exec failed)")
      if (WIFSIGNALED(status))
        THROW(, "executable target terminated before its initial stop with signal " << WTERMSIG(status))
      THROW(, "executable target did not stop after exec")
    }
    try {
      installConfiguredBreakpoints(context);
      target.instruction = registersOf(target).rip;
      target.currentPoint = pointAt(target, target.instruction);
      *context.io.out << "[debug] executable started pid " << target.pid << "\n";
      printExecutablePoint(context, "stopped");
      controller(context, runtime);
    } catch (...) {
      terminateExecutable(target);
      runtime.active = false;
      runtime.target = DebuggerState::Target::None;
      throw;
    }
  }

  void Debugger::locals(context::Context &context, lexicon::Phrase &) {
    if (state(context).target != DebuggerState::Target::Executable)
      THROW(, "debug locals requires an emitted executable target")
    const compiler::DebugPoint &point = currentExecutablePoint(context);
    if (point.locals.empty()) {
      *context.io.out << "[debug] no visible locals\n";
      return;
    }
    for (const compiler::DebugLocal &local : point.locals) printLocal(context, local);
  }

  void Debugger::registers(context::Context &context, lexicon::Phrase &) {
    if (state(context).target != DebuggerState::Target::Executable)
      THROW(, "debug registers requires an executable target")
    const user_regs_struct value = registersOf(executableState(context));
    *context.io.out << "[debug] registers rip=0x" << std::hex << value.rip << " rsp=0x" << value.rsp << " rbp=0x"
                    << value.rbp << " rax=0x" << value.rax << " rbx=0x" << value.rbx << " rcx=0x" << value.rcx
                    << " rdx=0x" << value.rdx << std::dec << "\n";
  }
} // namespace recurloop
