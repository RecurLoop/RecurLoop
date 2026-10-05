#include <recurloop/Debugger.hpp>

#include <compiler/DebugInfo.hpp>
#include <compiler/TypeSystem.hpp>
#include <context/Context.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <utilities/Byte.hpp>
#include <utilities/Exception.hpp>

#include <elf.h>
#include <fcntl.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <bit>
#include <cerrno>
#include <charconv>
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

    struct NativeThread {
      bool stopped = true;
      int pendingSignal = 0;
      std::uintptr_t instruction = 0;
      std::optional<std::uintptr_t> breakpoint;
      std::optional<std::size_t> point;
    };

    struct ExecutableState {
      pid_t pid = -1; // selected thread
      pid_t leader = -1;
      std::unordered_map<pid_t, NativeThread> threads;
      bool controllerTerminal = false;
      bool initialStop = true;
      std::optional<int> exitStatus;
      std::filesystem::path path;
      std::vector<compiler::DebugPoint> points;
      std::unordered_map<std::string, const compiler::DebugLocal *> schemas;
      bool positionIndependent = false;
      std::uintptr_t loadBias = 0;
      std::unordered_map<std::uintptr_t, NativeBreakpoint> breakpoints;
      std::optional<std::uintptr_t> currentBreakpoint;
      std::optional<std::size_t> currentPoint;
      int pendingSignal = 0;
      std::uintptr_t instruction = 0;
      std::uintptr_t selectedFrame = 0;
      std::optional<std::size_t> selectedPoint;
    };

    struct DebugRuntime {
      DebuggerState state;
      ExecutableState executable;
      std::string terminal;
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
      const std::filesystem::path a(left), b(right);
      if (!a.has_parent_path() || !b.has_parent_path()) return a.filename() == b.filename();
      return std::filesystem::absolute(a).lexically_normal() == std::filesystem::absolute(b).lexically_normal();
    }

    std::string hexText(std::string_view value) {
      static constexpr char digits[] = "0123456789abcdef";
      std::string result;
      result.reserve(value.size() * 2);
      for (const unsigned char byte : value) {
        result.push_back(digits[byte >> 4]);
        result.push_back(digits[byte & 0x0f]);
      }
      return result;
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
      if (error == EPERM || error == EACCES)
        message << " (the operating system denied ptrace; check the workspace/container tracing policy)";
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

    std::vector<compiler::DebugPoint> readDebugPoints(const std::filesystem::path &path, bool &positionIndependent) {
      std::ifstream input(path, std::ios::binary);
      if (!input.is_open()) THROW(, "cannot open emitted executable '" << path.string() << "'")
      std::vector<std::uint8_t> bytes{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
      if (input.bad()) THROW(, "cannot read emitted executable '" << path.string() << "'")
      if (bytes.size() < sizeof(Elf64_Ehdr)) THROW(, "emitted executable has a truncated ELF header")
      Elf64_Ehdr header{};
      std::memcpy(&header, bytes.data(), sizeof(header));
      if (std::memcmp(header.e_ident, ELFMAG, SELFMAG) != 0) THROW(, "emitted executable is not ELF")
      positionIndependent = header.e_type == ET_DYN;
      std::vector<compiler::DebugPoint> points = compiler::DebugInfo::readExecutable(bytes);
      if (points.empty()) THROW(, "emitted executable contains no debuggable RecurLoop statements")
      return points;
    }

    std::uintptr_t executableLoadBias(const ExecutableState &target) {
      if (!target.positionIndependent) return 0;
      std::ifstream maps("/proc/" + std::to_string(target.pid) + "/maps");
      if (!maps.is_open()) THROW(, "executable debugger cannot read target memory map")

      std::string line;
      while (std::getline(maps, line)) {
        std::istringstream fields(line);
        std::string addresses;
        std::string permissions;
        std::string offsetText;
        std::string device;
        std::string inode;
        if (!(fields >> addresses >> permissions >> offsetText >> device >> inode)) continue;
        std::string mappedPath;
        std::getline(fields, mappedPath);
        mappedPath = trim(std::move(mappedPath));
        if (mappedPath.empty()) continue;
        static constexpr std::string_view deleted = " (deleted)";
        if (mappedPath.ends_with(deleted)) mappedPath.resize(mappedPath.size() - deleted.size());
        std::error_code equivalentError;
        if (!std::filesystem::equivalent(target.path, mappedPath, equivalentError) || equivalentError) continue;

        const std::size_t separator = addresses.find('-');
        if (separator == std::string::npos) continue;
        std::uintptr_t start = 0;
        std::uintptr_t offset = 0;
        const auto startResult = std::from_chars(addresses.data(), addresses.data() + separator, start, 16);
        const auto offsetResult = std::from_chars(offsetText.data(), offsetText.data() + offsetText.size(), offset, 16);
        if (startResult.ec != std::errc{} || offsetResult.ec != std::errc{} || start < offset) continue;
        return start - offset;
      }
      THROW(, "executable debugger cannot locate the target executable mapping")
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
      ExecutableState &target = executableState(context);
      target.selectedFrame = 0;
      target.selectedPoint.reset();
      if (!target.currentPoint) {
        *context.io.out << "[debug] executable " << reason << " " << target.path.string() << " rip 0x" << std::hex
                        << target.instruction << std::dec << "\n";
        if (reason != "at") *context.io.out << "[debug-event]\tstop\t" << reason << "\t\t0\t0\t\t\n";
        return;
      }
      const compiler::DebugPoint &point = target.points[*target.currentPoint];
      const std::string_view path = point.path.empty() ? std::string_view{"<input>"} : std::string_view{point.path};
      *context.io.out << "[debug] " << reason << " " << path << ":" << point.line << ":" << point.column << " phrase \""
                      << point.phrase << "\" function \"" << point.function << "\" rip 0x" << std::hex << point.address
                      << std::dec << "\n";
      // Stable machine-readable execution-stop event for debugger clients. Text
      // fields are hex encoded so paths/phrases never need delimiter escaping.
      // `where` is an inspection command, not a new execution stop.
      if (reason != "at")
        *context.io.out << "[debug-event]\tstop\t" << reason << "\t" << hexText(path) << "\t" << point.line << "\t"
                        << point.column << "\t" << hexText(point.phrase) << "\t" << hexText(point.function) << "\t"
                        << target.pid << "\n";
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
      target.leader = -1;
      target.threads.clear();
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

    std::optional<std::uint64_t> resolvedLine(const ExecutableState &target, const Breakpoint &breakpoint) {
      if (breakpoint.record.kind != BreakpointKind::Line) return std::nullopt;
      std::optional<std::uint64_t> next;
      for (const compiler::DebugPoint &point : target.points) {
        if (!samePath(breakpoint.text, point.path)) continue;
        if (point.line == breakpoint.record.line) return point.line;
        if (point.line > breakpoint.record.line && (!next || point.line < *next)) next = point.line;
      }
      return next;
    }

    std::size_t installConfiguredBreakpoint(ExecutableState &target, const Breakpoint &breakpoint) {
      std::size_t installed = 0;
      std::optional<std::uint64_t> line;
      if (breakpoint.record.kind == BreakpointKind::Line) line = resolvedLine(target, breakpoint);
      for (const compiler::DebugPoint &point : target.points) {
        bool selected = false;
        if (breakpoint.record.kind == BreakpointKind::Line) {
          selected = line && point.line == *line && samePath(breakpoint.text, point.path);
        } else {
          selected = matches(breakpoint, point);
        }
        if (!selected) continue;
        installBreakpoint(target, point.address);
        ++installed;
        if (breakpoint.record.kind == BreakpointKind::Function) break;
      }
      return installed;
    }

    void installConfiguredBreakpoints(context::Context &context) {
      ExecutableState &target = executableState(context);
      restoreAllBreakpoints(target);
      target.breakpoints.clear();
      const std::vector<Breakpoint> configured = breakpoints(context);
      for (const Breakpoint &breakpoint : configured) {
        if (breakpoint.record.active == 0) continue;
        installConfiguredBreakpoint(target, breakpoint);
      }
      if (target.currentPoint && target.breakpoints.contains(target.instruction))
        target.currentBreakpoint = target.instruction;
      else if (target.currentBreakpoint && !target.breakpoints.contains(*target.currentBreakpoint))
        target.currentBreakpoint.reset();
      for (auto &[pid, thread] : target.threads) {
        if (target.breakpoints.contains(thread.instruction))
          thread.breakpoint = thread.instruction;
        else
          thread.breakpoint.reset();
      }
    }

    pid_t waitTrace(pid_t pid, int &status) {
      pid_t result;
      do {
        result = waitpid(pid, &status, __WALL);
      } while (result == -1 && errno == EINTR);
      if (result == -1) ptraceFailure("wait");
      return result;
    }

    void saveThread(ExecutableState &target) {
      if (!target.threads.contains(target.pid)) return;
      auto &thread = target.threads.at(target.pid);
      thread.instruction = target.instruction;
      thread.point = target.currentPoint;
      thread.breakpoint = target.currentBreakpoint;
      thread.pendingSignal = target.pendingSignal;
    }

    void selectThread(ExecutableState &target, pid_t pid) {
      saveThread(target);
      const auto found = target.threads.find(pid);
      if (found == target.threads.end() || !found->second.stopped) THROW(, "debug thread is not stopped")
      target.pid = pid;
      target.instruction = found->second.instruction;
      target.currentPoint = found->second.point;
      target.currentBreakpoint = found->second.breakpoint;
      target.pendingSignal = found->second.pendingSignal;
      target.selectedFrame = 0;
      target.selectedPoint.reset();
    }

    // Normalize every stopped thread before exposing the all-stop snapshot.
    // More than one thread may have hit the same shared INT3 before interruption.
    void recordThreadStop(ExecutableState &target, pid_t pid, int status) {
      auto &thread = target.threads[pid];
      thread.stopped = true;
      user_regs_struct registers{};
      if (ptrace(PTRACE_GETREGS, pid, nullptr, &registers) == -1) ptraceFailure("get thread registers");
      const auto signal = WSTOPSIG(status);
      const unsigned event = static_cast<unsigned>(status) >> 16;
      thread.pendingSignal = event || signal == SIGSTOP ? 0 : signal;
      if (!event && signal == SIGINT && target.controllerTerminal) {
        siginfo_t information{};
        if (ptrace(PTRACE_GETSIGINFO, pid, nullptr, &information) == 0 && information.si_code == SI_KERNEL)
          thread.pendingSignal = 0;
      }
      thread.breakpoint.reset();
      if (!event && signal == SIGTRAP) {
        siginfo_t information{};
        if (ptrace(PTRACE_GETSIGINFO, pid, nullptr, &information) == -1) ptraceFailure("get trap information");
        if (information.si_code == TRAP_TRACE)
          thread.pendingSignal = 0;
        else if (registers.rip && (information.si_code == TRAP_BRKPT || information.si_code == SI_KERNEL)) {
          const auto address = registers.rip - 1;
          auto found = target.breakpoints.find(address);
          if (found != target.breakpoints.end()) {
            // The shared byte may already have been restored by another stop.
            const auto selected = target.pid;
            target.pid = pid;
            restoreBreakpoint(target, found->second);
            target.pid = selected;
            registers.rip = address;
            if (ptrace(PTRACE_SETREGS, pid, nullptr, &registers) == -1) ptraceFailure("rewind thread breakpoint");
            thread.breakpoint = address;
            thread.pendingSignal = 0;
          }
        }
      }
      thread.instruction = registers.rip;
      thread.point = pointAt(target, registers.rip);
      if (pid == target.pid) {
        target.instruction = thread.instruction;
        target.currentPoint = thread.point;
        target.currentBreakpoint = thread.breakpoint;
        target.pendingSignal = thread.pendingSignal;
      }
    }

    bool acceptThread(ExecutableState &target, pid_t pid) {
      std::ifstream information("/proc/" + std::to_string(pid) + "/status");
      std::string line;
      while (std::getline(information, line)) {
        if (!line.starts_with("Tgid:")) continue;
        std::istringstream input(line.substr(5));
        pid_t group = -1;
        input >> group;
        if (group == target.leader) return true;
        if (ptrace(PTRACE_DETACH, pid, nullptr, nullptr) == -1) ptraceFailure("detach cloned process");
        return false;
      }
      THROW(, "cannot determine cloned thread group")
    }

    void registerClone(ExecutableState &target, pid_t parent) {
      unsigned long child = 0;
      if (ptrace(PTRACE_GETEVENTMSG, parent, nullptr, &child) == -1) ptraceFailure("get cloned thread");
      // The newborn is auto-attached and initially stopped. Await that stop
      // before any CONT or memory/register operation is attempted.
      if (target.threads.contains(static_cast<pid_t>(child))) return;
      int status = 0;
      waitTrace(static_cast<pid_t>(child), status);
      if (WIFSTOPPED(status)) {
        if (!acceptThread(target, static_cast<pid_t>(child))) return;
        recordThreadStop(target, static_cast<pid_t>(child), status);
      }
    }

    void resumeThread(ExecutableState &target, pid_t pid) {
      auto &thread = target.threads.at(pid);
      if (ptrace(PTRACE_CONT, pid, nullptr,
                 reinterpret_cast<void *>(static_cast<std::intptr_t>(thread.pendingSignal))) == -1)
        ptraceFailure("continue thread");
      thread.pendingSignal = 0;
      thread.stopped = false;
    }

    bool recordExit(context::Context &context, pid_t pid, int status) {
      auto &target = executableState(context);
      if (pid == target.leader) target.exitStatus = status;
      target.threads.erase(pid);
      if (target.threads.empty()) {
        finishExecutable(context, target.exitStatus.value_or(status));
        return true;
      }
      if (target.pid == pid) {
        const auto &[survivor, thread] = *target.threads.begin();
        target.pid = survivor;
        target.instruction = thread.instruction;
        target.currentBreakpoint = thread.breakpoint;
        target.currentPoint = thread.point;
        target.pendingSignal = thread.pendingSignal;
        target.selectedFrame = 0;
        target.selectedPoint.reset();
      }
      return false;
    }

    void stopOtherThreads(context::Context &context, pid_t selected) {
      auto &target = executableState(context);
      for (const auto &[pid, thread] : target.threads) {
        if (!thread.stopped && ptrace(PTRACE_INTERRUPT, pid, nullptr, nullptr) == -1 && errno != ESRCH)
          ptraceFailure("interrupt thread");
      }
      while (std::ranges::any_of(target.threads, [](const auto &entry) { return !entry.second.stopped; })) {
        int status = 0;
        const auto pid = waitTrace(-target.leader, status);
        if (WIFEXITED(status) || WIFSIGNALED(status)) {
          if (recordExit(context, pid, status)) return;
          continue;
        }
        if (!WIFSTOPPED(status)) continue;
        if (!target.threads.contains(pid) && !acceptThread(target, pid)) continue;
        recordThreadStop(target, pid, status);
        if ((static_cast<unsigned>(status) >> 16) == PTRACE_EVENT_CLONE) registerClone(target, pid);
      }
      if (target.threads.contains(selected))
        selectThread(target, selected);
      else if (!target.threads.empty())
        selectThread(target, target.threads.begin()->first);
    }

    bool waitForExecutable(context::Context &context) {
      auto &target = executableState(context);
      while (!target.threads.empty()) {
        int status = 0;
        const auto pid = waitTrace(-target.leader, status);
        if (WIFEXITED(status) || WIFSIGNALED(status)) {
          if (recordExit(context, pid, status)) return false;
          continue;
        }
        if (!WIFSTOPPED(status)) continue;
        const bool newborn = !target.threads.contains(pid);
        if (newborn && !acceptThread(target, pid)) continue;
        recordThreadStop(target, pid, status);
        if (newborn) {
          resumeThread(target, pid);
          continue;
        }
        const auto event = static_cast<unsigned>(status) >> 16;
        if (event == PTRACE_EVENT_CLONE) {
          registerClone(target, pid);
          std::vector<pid_t> stopped;
          for (const auto &[tid, thread] : target.threads)
            if (thread.stopped) stopped.push_back(tid);
          for (const auto tid : stopped) resumeThread(target, tid);
          continue;
        }
        // INTERRUPT creates a distinct ptrace event, without injecting a
        // process-wide signal into the application's thread group.
        stopOtherThreads(context, pid);
        if (target.pid <= 0) return false;
        printExecutablePoint(context, target.currentBreakpoint                                    ? "breakpoint"
                                      : target.pendingSignal                                      ? "signal"
                                      : event == PTRACE_EVENT_STOP || WSTOPSIG(status) == SIGSTOP ? "paused"
                                                                                                  : "stopped");
        return true;
      }
      return false;
    }

    bool stepOverCurrentBreakpoint(context::Context &context, bool reinsert) {
      auto &target = executableState(context);
      if (!target.currentBreakpoint) return true;
      const auto address = *target.currentBreakpoint;
      auto &breakpoint = target.breakpoints.at(address);
      restoreBreakpoint(target, breakpoint);
      const auto pid = target.pid;
      if (ptrace(PTRACE_SINGLESTEP, pid, nullptr, nullptr) == -1) ptraceFailure("step over breakpoint");
      int status = 0;
      waitTrace(pid, status);
      if (WIFEXITED(status) || WIFSIGNALED(status)) {
        recordExit(context, pid, status);
        return false;
      }
      if (!WIFSTOPPED(status)) THROW(, "unexpected breakpoint-step wait status")
      recordThreadStop(target, pid, status);
      if ((static_cast<unsigned>(status) >> 16) == PTRACE_EVENT_CLONE) registerClone(target, pid);
      target.currentBreakpoint.reset();
      selectThread(target, pid);
      if (reinsert) reinsertBreakpoint(target, breakpoint);
      return true;
    }

    volatile sig_atomic_t interruptedThread = -1;

    void pauseNativeTarget(int) {
      const auto saved = errno;
      const auto pid = interruptedThread;
      if (pid > 0) syscall(SYS_ptrace, PTRACE_INTERRUPT, pid, nullptr, nullptr);
      errno = saved;
    }

    struct NativeInterruptScope {
      struct sigaction previous{}, previousPause{};
      bool installed = false, pauseInstalled = false;
      sig_atomic_t previousThread = -1;
      explicit NativeInterruptScope(pid_t pid) {
        // Only a terminal CLI owns SIGINT. Editor controllers use their own
        // pause channel; background server threads never change signal policy.
        struct sigaction action{};
        action.sa_handler = pauseNativeTarget;
        sigemptyset(&action.sa_mask);
        if (isatty(STDIN_FILENO)) installed = sigaction(SIGINT, &action, &previous) == 0;
        pauseInstalled = sigaction(SIGUSR1, &action, &previousPause) == 0;
        previousThread = interruptedThread;
        if (installed || pauseInstalled) interruptedThread = pid;
      }
      ~NativeInterruptScope() {
        interruptedThread = previousThread;
        if (installed) sigaction(SIGINT, &previous, nullptr);
        if (pauseInstalled) sigaction(SIGUSR1, &previousPause, nullptr);
      }
    };

    struct NativeForegroundScope {
      pid_t previous = -1;
      sigset_t previousMask{};
      explicit NativeForegroundScope(const ExecutableState &target) {
        if (!target.controllerTerminal || !isatty(STDIN_FILENO)) return;
        previous = tcgetpgrp(STDIN_FILENO);
        if (previous != getpgrp()) {
          previous = -1;
          return;
        }
        sigset_t mask;
        sigemptyset(&mask);
        sigaddset(&mask, SIGTTOU);
        sigprocmask(SIG_BLOCK, &mask, &previousMask);
        if (tcsetpgrp(STDIN_FILENO, target.leader) == -1) {
          previous = -1;
          sigprocmask(SIG_SETMASK, &previousMask, nullptr);
        }
      }
      ~NativeForegroundScope() {
        if (previous < 0) return;
        tcsetpgrp(STDIN_FILENO, previous);
        sigprocmask(SIG_SETMASK, &previousMask, nullptr);
      }
    };

    void continueExecutable(context::Context &context) {
      auto &target = executableState(context);
      if (target.pid <= 0) THROW(, "no executable target is stopped")
      target.initialStop = false;
      const auto selected = target.pid;
      NativeInterruptScope interrupt(selected);
      NativeForegroundScope foreground(target);
      saveThread(target);
      std::vector<pid_t> ids;
      for (const auto &[pid, thread] : target.threads) ids.push_back(pid);
      // Move every thread past its pending INT3 while the others stay stopped.
      for (const auto pid : ids) {
        if (!target.threads.contains(pid)) continue;
        selectThread(target, pid);
        stepOverCurrentBreakpoint(context, true);
        if (target.pid <= 0) return;
        saveThread(target);
      }
      if (target.threads.contains(selected)) selectThread(target, selected);
      for (const auto &[pid, thread] : target.threads) resumeThread(target, pid);
      waitForExecutable(context);
    }

    void stepExecutable(context::Context &context, DebuggerState::Mode mode) {
      auto &target = executableState(context);
      if (target.pid <= 0) THROW(, "no executable target is stopped")
      if (target.initialStop && !target.currentPoint) {
        // Reach the first source statement without single-stepping the dynamic
        // loader. Temporary statement breakpoints are removed before exposing
        // the stopped target to subsequent controller commands.
        for (const auto &point : target.points) installBreakpoint(target, point.address);
        continueExecutable(context);
        if (target.pid > 0) {
          installConfiguredBreakpoints(context);
          saveThread(target);
        }
        return;
      }
      target.initialStop = false;
      NativeInterruptScope interrupt(target.pid);
      NativeForegroundScope foreground(target);
      const auto initial = registersOf(target);
      bool moved = target.currentBreakpoint.has_value();
      if (!stepOverCurrentBreakpoint(context, false)) return;
      restoreAllBreakpoints(target);
      while (target.pid > 0) {
        // SINGLESTEP used to pass an INT3 can itself reach the next statement.
        // Inspect that location before executing another instruction.
        if (moved) {
          const auto current = registersOf(target);
          const auto point = pointAt(target, current.rip);
          const bool breakpoint = target.breakpoints.contains(current.rip);
          if (point && (breakpoint || mode == DebuggerState::Mode::Step ||
                        (mode == DebuggerState::Mode::Next && current.rsp >= initial.rsp) ||
                        (mode == DebuggerState::Mode::Finish && current.rsp > initial.rsp))) {
            target.currentPoint = point;
            installConfiguredBreakpoints(context);
            if (target.breakpoints.contains(current.rip)) target.currentBreakpoint = current.rip;
            saveThread(target);
            printExecutablePoint(context, breakpoint ? "breakpoint" : "stopped");
            return;
          }
        }
        moved = true;
        const auto pid = target.pid;
        if (ptrace(PTRACE_SINGLESTEP, pid, nullptr,
                   reinterpret_cast<void *>(static_cast<std::intptr_t>(target.pendingSignal))) == -1)
          ptraceFailure("source step");
        target.pendingSignal = 0;
        int status = 0;
        waitTrace(pid, status);
        if (WIFEXITED(status) || WIFSIGNALED(status)) {
          if (!recordExit(context, pid, status)) {
            selectThread(target, target.pid);
            installConfiguredBreakpoints(context);
            printExecutablePoint(context, "stopped");
          }
          return;
        }
        if (!WIFSTOPPED(status)) THROW(, "unexpected source-step wait status")
        recordThreadStop(target, pid, status);
        target.currentBreakpoint.reset();
        selectThread(target, pid);
        const auto event = static_cast<unsigned>(status) >> 16;
        if (event == PTRACE_EVENT_CLONE) {
          registerClone(target, pid);
          continue;
        }
        if (target.pendingSignal || event == PTRACE_EVENT_STOP) {
          installConfiguredBreakpoints(context);
          printExecutablePoint(context, target.pendingSignal ? "signal" : "stopped");
          return;
        }
      }
    }

    const compiler::DebugPoint &currentExecutablePoint(context::Context &context) {
      const ExecutableState &target = executableState(context);
      const auto point = target.selectedPoint ? target.selectedPoint : target.currentPoint;
      if (target.pid <= 0 || !point) THROW(, "executable is not stopped at a RecurLoop statement")
      return target.points[*point];
    }

    std::uintptr_t localAddress(const ExecutableState &target, const compiler::DebugLocal &local) {
      const auto base = target.selectedFrame ? target.selectedFrame : registersOf(target).rbp;
      if (base < local.frameOffset) THROW(, "invalid frame offset for local '" << local.name << "'")
      return base - local.frameOffset;
    }

    std::uint64_t readScalar(const ExecutableState &target, std::uintptr_t address, std::uint32_t size) {
      if (size == 0 || size > sizeof(long)) THROW(, "debugger scalar size is invalid")
      std::uint64_t result = 0;
      // Aligned reads also handle packed fields at page boundaries.
      for (std::uint32_t at = 0; at < size;) {
        const auto aligned = (address + at) & ~(sizeof(long) - 1);
        const auto offset = (address + at) - aligned;
        errno = 0;
        const auto word =
            static_cast<unsigned long>(ptrace(PTRACE_PEEKDATA, target.pid, reinterpret_cast<void *>(aligned), nullptr));
        if (errno) ptraceFailure("read variable");
        for (auto byte = offset; byte < sizeof(long) && at < size; ++byte, ++at)
          result |= ((word >> (byte * 8)) & 255) << (at * 8);
      }
      return result;
    }

    std::uint64_t readLocalValue(const ExecutableState &target, const compiler::DebugLocal &local) {
      return readScalar(target, localAddress(target, local), local.size);
    }

    const compiler::DebugLocal &schemaOf(const ExecutableState &target, const compiler::DebugLocal &local) {
      if (!local.children.empty()) return local;
      const auto found = target.schemas.find(local.type);
      return found == target.schemas.end() ? local : *found->second;
    }

    struct VariableView {
      compiler::DebugLocal local;
      std::uintptr_t address;
      std::string path;
    };

    std::uint64_t childCount(const ExecutableState &target, const VariableView &view) {
      const auto &schema = schemaOf(target, view.local);
      if (schema.children.empty()) return 0;
      const auto kind = static_cast<compiler::TypeKind>(schema.kind);
      if (kind == compiler::TypeKind::Array) return schema.elementCount;
      if (kind == compiler::TypeKind::Pointer) return readScalar(target, view.address, view.local.size) ? 1 : 0;
      return schema.children.size();
    }

    VariableView variableAt(context::Context &context, std::string path) {
      const auto &target = executableState(context);
      const auto &locals = currentExecutablePoint(context).locals;
      // Pointer member spelling is accepted alongside explicit [0] expansion.
      for (std::size_t at; (at = path.find("->")) != std::string::npos;) path.replace(at, 2, "[0].");
      const auto end = path.find_first_of(".[");
      const auto root = path.substr(0, end);
      const auto found = std::ranges::find(locals, root, &compiler::DebugLocal::name);
      if (found == locals.end()) THROW(, "unknown debug variable '" << root << "'")
      VariableView view{*found, localAddress(target, *found), root};
      std::size_t at = root.size();
      while (at < path.size()) {
        const auto &schema = schemaOf(target, view.local);
        const auto kind = static_cast<compiler::TypeKind>(schema.kind);
        if (path[at] == '.' && kind == compiler::TypeKind::Structure) {
          const auto begin = ++at;
          const auto next = path.find_first_of(".[", at);
          at = next == std::string::npos ? path.size() : next;
          const auto name = path.substr(begin, at - begin);
          const auto child = std::ranges::find(schema.children, name, &compiler::DebugLocal::name);
          if (child == schema.children.end()) THROW(, "unknown debug record member '" << name << "'")
          view.address += child->memberOffset;
          auto metadata = *child;
          view.local = std::move(metadata);
          view.path += '.' + name;
        } else if (path[at] == '[' && (kind == compiler::TypeKind::Array || kind == compiler::TypeKind::Pointer)) {
          const auto begin = ++at;
          const auto close = path.find(']', at);
          if (close == std::string::npos || schema.children.empty()) THROW(, "invalid debug array access")
          std::uint64_t index = 0;
          const auto parsed = std::from_chars(path.data() + begin, path.data() + close, index);
          const auto count = kind == compiler::TypeKind::Pointer ? 1 : schema.elementCount;
          if (parsed.ec != std::errc{} || parsed.ptr != path.data() + close || index >= count)
            THROW(, "debug array index is out of bounds")
          if (kind == compiler::TypeKind::Pointer) {
            view.address = readScalar(target, view.address, view.local.size);
            if (!view.address) THROW(, "cannot dereference a null debug pointer")
          }
          auto metadata = schema.children.front();
          view.local = std::move(metadata);
          view.address += index * view.local.size;
          view.path += '[' + std::to_string(index) + ']';
          at = close + 1;
        } else
          THROW(, "invalid debug variable path '" << path << "'")
      }
      return view;
    }

    std::string formatVariable(const ExecutableState &target, const VariableView &view) {
      const auto &local = view.local;
      const auto kind = static_cast<compiler::TypeKind>(local.kind);
      if (kind == compiler::TypeKind::Structure) return "{" + std::to_string(childCount(target, view)) + " fields}";
      if (kind == compiler::TypeKind::Array) return "[" + std::to_string(local.elementCount) + " elements]";
      if (local.size == 0 || local.size > sizeof(long)) return "<" + std::to_string(local.size) + " bytes>";
      const auto bits = readScalar(target, view.address, local.size);
      std::ostringstream text;
      if (kind == compiler::TypeKind::FloatingPoint && local.size == sizeof(float))
        text << std::bit_cast<float>(static_cast<std::uint32_t>(bits));
      else if (kind == compiler::TypeKind::FloatingPoint && local.size == sizeof(double))
        text << std::bit_cast<double>(bits);
      else if (kind == compiler::TypeKind::Pointer)
        text << "0x" << std::hex << bits;
      else if (local.type == "bool")
        text << (bits == 0 ? "false" : "true");
      else if (local.signedValue) {
        const unsigned width = local.size * 8;
        text << (width == 64 ? static_cast<std::int64_t>(bits)
                             : static_cast<std::int64_t>(bits << (64 - width)) >> (64 - width));
      } else
        text << bits;
      return text.str();
    }

    void printVariable(context::Context &context, const VariableView &view) {
      const auto &target = executableState(context);
      const auto value = formatVariable(target, view);
      *context.io.out << "[debug] " << view.path << ":" << view.local.type << " = " << value << "\n";
      *context.io.out << "[debug-variable]\t" << hexText(view.path) << "\t" << hexText(view.local.name) << "\t"
                      << hexText(view.local.type) << "\t" << hexText(value) << "\t" << childCount(target, view) << "\t"
                      << static_cast<unsigned>(view.local.kind) << "\n";
    }

    void printLocal(context::Context &context, const compiler::DebugLocal &local) {
      printVariable(context, {local, localAddress(executableState(context), local), local.name});
    }

    struct NativeFrame {
      std::uintptr_t base;
      std::size_t point;
    };

    std::vector<NativeFrame> nativeFrames(const ExecutableState &target) {
      std::vector<NativeFrame> frames;
      if (target.pid <= 0) return frames;
      auto registers = registersOf(target);
      if (target.currentPoint) frames.push_back({registers.rbp, *target.currentPoint});
      std::uintptr_t base = registers.rbp;
      for (unsigned depth = 0; base && depth < 128; ++depth) {
        errno = 0;
        const long parent = ptrace(PTRACE_PEEKDATA, target.pid, reinterpret_cast<void *>(base), nullptr);
        if (parent == -1 && errno) break;
        errno = 0;
        const long address =
            ptrace(PTRACE_PEEKDATA, target.pid, reinterpret_cast<void *>(base + sizeof(long)), nullptr);
        if (address == -1 && errno) break;
        if (static_cast<std::uintptr_t>(parent) <= base ||
            static_cast<std::uintptr_t>(parent) - base > 16 * 1024 * 1024)
          break;
        base = static_cast<std::uintptr_t>(parent);
        const auto next = std::lower_bound(
            target.points.begin(), target.points.end(), static_cast<std::uintptr_t>(address),
            [](const compiler::DebugPoint &point, std::uintptr_t value) { return point.address < value; });
        if (next == target.points.begin()) break;
        const auto point = std::prev(next);
        // Do not mislabel a libc/runtime frame using the final application point.
        if (static_cast<std::uintptr_t>(address) - point->address > 4096) break;
        frames.push_back({base, static_cast<std::size_t>(point - target.points.begin())});
      }
      return frames;
    }

    context::Value scalarValue(const ExecutableState &target, const VariableView &view) {
      const auto &local = view.local;
      const auto kind = static_cast<compiler::TypeKind>(local.kind);
      if (kind == compiler::TypeKind::Structure || kind == compiler::TypeKind::Array)
        THROW(, "aggregate values require debug value/children")
      const auto bits = readScalar(target, view.address, local.size);
      if (kind == compiler::TypeKind::FloatingPoint && local.size == 4)
        return context::Value(static_cast<double>(std::bit_cast<float>(static_cast<std::uint32_t>(bits))));
      if (kind == compiler::TypeKind::FloatingPoint && local.size == 8)
        return context::Value(std::bit_cast<double>(bits));
      if (local.type == "bool") return context::Value(bits != 0);
      const unsigned width = local.size * 8;
      return context::Value(local.signedValue && width < 64
                                ? static_cast<std::int64_t>(bits << (64 - width)) >> (64 - width)
                                : static_cast<std::int64_t>(bits));
    }

    context::Value evaluateNative(context::Context &context, const std::string &expression) {
      auto values = context.values();
      values.pushScope();
      try {
        const auto &target = executableState(context);
        const auto &locals = currentExecutablePoint(context).locals;
        for (const auto &local : locals) {
          const auto kind = static_cast<compiler::TypeKind>(local.kind);
          if (local.size == 0 || local.size > sizeof(long) || kind == compiler::TypeKind::Structure ||
              kind == compiler::TypeKind::Array)
            continue;
          values.define(local.name, scalarValue(target, {local, localAddress(target, local), local.name}));
        }
        // Resolve native member/index paths to scalar bindings before using the
        // ordinary expression evaluator. No target function is invoked.
        std::string rewritten;
        std::size_t sequence = 0;
        for (std::size_t at = 0; at < expression.size();) {
          const auto begin = at;
          if (expression[at] == '\'' || expression[at] == '"') {
            const char quote = expression[at++];
            while (at < expression.size()) {
              if (expression[at++] == '\\' && at < expression.size()) {
                ++at;
                continue;
              }
              if (expression[at - 1] == quote) break;
            }
            rewritten += expression.substr(begin, at - begin);
            continue;
          }
          if (!std::isalpha(static_cast<unsigned char>(expression[at])) && expression[at] != '_') {
            rewritten += expression[at++];
            continue;
          }
          while (at < expression.size() &&
                 (std::isalnum(static_cast<unsigned char>(expression[at])) || expression[at] == '_'))
            ++at;
          const auto name = expression.substr(begin, at - begin);
          const auto root = std::ranges::find(locals, name, &compiler::DebugLocal::name);
          if (root == locals.end()) {
            rewritten += name;
            continue;
          }
          std::string path = name;
          while (at < expression.size()) {
            if (expression[at] == '.' || expression.substr(at, 2) == "->") {
              const bool pointer = expression[at] == '-';
              at += pointer ? 2 : 1;
              const auto member = at;
              while (at < expression.size() &&
                     (std::isalnum(static_cast<unsigned char>(expression[at])) || expression[at] == '_'))
                ++at;
              if (member == at) THROW(, "debug expression requires a member name")
              path += (pointer ? "->" : ".") + expression.substr(member, at - member);
            } else if (expression[at] == '[') {
              const auto end = expression.find(']', ++at);
              if (end == std::string::npos) THROW(, "debug expression has an unterminated index")
              const auto index = Expressions::evaluate(context, expression.substr(at, end - at));
              if (!index.isInteger() || index.asInteger() < 0)
                THROW(, "debug array index must be a nonnegative integer")
              path += '[' + std::to_string(index.asInteger()) + ']';
              at = end + 1;
            } else
              break;
          }
          const auto binding = "__recurloop_debug_value_" + std::to_string(sequence++);
          values.define(binding, scalarValue(target, variableAt(context, path)));
          rewritten += binding;
        }
        auto result = Expressions::evaluate(context, rewritten);
        values.popScope();
        return result;
      } catch (...) {
        values.popScope();
        throw;
      }
    }

    void terminateExecutable(ExecutableState &target) {
      if (target.leader <= 0) return;
      // SIGKILL works for running, signal-stopped and ptrace-stopped tracees.
      kill(target.leader, SIGKILL);
      int status = 0;
      while (true) {
        const auto pid = waitpid(-target.leader, &status, __WALL);
        if (pid < 0) {
          if (errno == EINTR) continue;
          break;
        }
      }
      target.pid = -1;
      target.leader = -1;
      target.threads.clear();
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
    actions.define("debugger.children", children);
    actions.define("debugger.value", value);
    actions.define("debugger.threads", threads);
    actions.define("debugger.thread", thread);
    actions.define("debugger.registers", registers);
    actions.define("debugger.terminal", terminal);
    actions.define("debugger.stack", stack);
    actions.define("debugger.frame", frame);
    actions.define("debugger.set", set);
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
    if (state(context).target == DebuggerState::Target::Executable) {
      installConfiguredBreakpoints(context);
      const ExecutableState &target = executableState(context);
      const std::optional<std::uint64_t> resolved = resolvedLine(target, breakpoint);
      if (resolved)
        *context.io.out << "[debug] breakpoint " << breakpoint.record.id << " " << breakpoint.text << ":" << line
                        << " resolved " << breakpoint.text << ":" << *resolved << "\n";
      else
        *context.io.out << "[debug] breakpoint " << breakpoint.record.id << " " << breakpoint.text << ":" << line
                        << " unresolved\n";
    } else {
      *context.io.out << "[debug] breakpoint " << breakpoint.record.id << " " << breakpoint.text << ":" << line << "\n";
    }
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
      const auto value = evaluateNative(context, expression);
      *context.io.out << "[debug] " << value.typeName() << " " << value.format() << "\n";
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
    bool positionIndependent = false;
    std::vector<compiler::DebugPoint> points = readDebugPoints(path, positionIndependent);

    context::Lookup::leave(context, invoked);
    DebuggerState &runtime = state(context);
    ExecutableState &target = executableState(context);
    if (runtime.active || target.pid > 0) THROW(, "a debugger target is already active")
    target = {};
    target.path = path;
    target.points = std::move(points);
    const auto schema = [&](const auto &self, const compiler::DebugLocal &local) -> void {
      if (!local.children.empty()) target.schemas.try_emplace(local.type, &local);
      for (const auto &child : local.children) self(self, child);
    };
    for (const auto &point : target.points)
      for (const auto &local : point.locals) schema(schema, local);
    target.positionIndependent = positionIndependent;

    int gate[2], failures[2];
    if (pipe2(gate, O_CLOEXEC) == -1) ptraceFailure("create launch gate");
    if (pipe2(failures, O_CLOEXEC) == -1) {
      const auto error = errno;
      close(gate[0]);
      close(gate[1]);
      errno = error;
      ptraceFailure("create launch error pipe");
    }
    const auto terminal = debugRuntime(context).terminal;
    target.controllerTerminal = terminal.empty();
    const pid_t pid = fork();
    if (pid == -1) {
      const auto error = errno;
      for (const auto fd : {gate[0], gate[1], failures[0], failures[1]}) close(fd);
      errno = error;
      ptraceFailure("fork target");
    }
    if (pid == 0) {
      close(gate[1]);
      close(failures[0]);
      const auto fail = [&](int stage) {
        const int record[2]{stage, errno};
        const auto ignored = write(failures[1], record, sizeof(record));
        (void)ignored;
        _exit(127);
      };
      if (setpgid(0, 0) == -1) fail(1);
      char ready;
      ssize_t bytes;
      do {
        bytes = read(gate[0], &ready, 1);
      } while (bytes == -1 && errno == EINTR);
      if (bytes != 1) _exit(127);
      close(gate[0]);
      if (!terminal.empty()) {
        const int fd = open(terminal.c_str(), O_RDWR | O_NOCTTY);
        if (fd < 0) fail(2);
        for (int standard = 0; standard < 3; ++standard)
          if (dup2(fd, standard) < 0) fail(2);
        if (fd > 2) close(fd);
      }
      execl(path.c_str(), path.c_str(), static_cast<char *>(nullptr));
      fail(3);
    }
    close(gate[0]);
    close(failures[1]);
    target.pid = target.leader = pid;
    // A private process group keeps waitpid from consuming unrelated children.
    setpgid(pid, pid);
    runtime.active = true;
    runtime.target = DebuggerState::Target::Executable;
    runtime.paused = true;
    try {
      NativeInterruptScope interrupt(pid);
      const auto options = static_cast<std::uintptr_t>(PTRACE_O_EXITKILL | PTRACE_O_TRACECLONE | PTRACE_O_TRACEEXEC);
      if (ptrace(PTRACE_SEIZE, pid, nullptr, reinterpret_cast<void *>(options)) == -1) ptraceFailure("seize target");
      if (ptrace(PTRACE_INTERRUPT, pid, nullptr, nullptr) == -1) ptraceFailure("initial interrupt");
      int status = 0;
      waitTrace(pid, status);
      if (!WIFSTOPPED(status)) THROW(, "debug target did not stop before exec")
      const char ready = 1;
      if (write(gate[1], &ready, 1) != 1) ptraceFailure("release launch gate");
      close(gate[1]);
      gate[1] = -1;
      if (ptrace(PTRACE_CONT, pid, nullptr, nullptr) == -1) ptraceFailure("continue to exec");
      waitTrace(pid, status);
      if (!WIFSTOPPED(status) || (static_cast<unsigned>(status) >> 16) != PTRACE_EVENT_EXEC) {
        if (WIFSTOPPED(status)) THROW(, "debug target received signal " << WSTOPSIG(status) << " before exec")
        int record[2]{};
        const auto bytes = read(failures[0], record, sizeof(record));
        if (bytes == sizeof(record))
          THROW(, "debug target launch failed at " << (record[0] == 1   ? "process group"
                                                       : record[0] == 2 ? "terminal"
                                                                        : "exec")
                                                   << ": " << std::strerror(record[1]))
        THROW(, "debug target exited before exec stop")
      }
      close(failures[0]);
      failures[0] = -1;
      target.threads.emplace(pid, NativeThread{});
      target.loadBias = executableLoadBias(target);
      if (target.loadBias != 0)
        for (compiler::DebugPoint &point : target.points) point.address += target.loadBias;
      installConfiguredBreakpoints(context);
      target.instruction = registersOf(target).rip;
      target.currentPoint = pointAt(target, target.instruction);
      saveThread(target);
      *context.io.out << "[debug] executable started pid " << target.pid << "\n";
      printExecutablePoint(context, "stopped");
      controller(context, runtime);
    } catch (...) {
      if (gate[1] >= 0) close(gate[1]);
      if (failures[0] >= 0) close(failures[0]);
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

  void Debugger::value(context::Context &context, lexicon::Phrase &) {
    printVariable(context, variableAt(context, stringArgument(context, "debug value")));
  }

  void Debugger::threads(context::Context &context, lexicon::Phrase &) {
    auto &target = executableState(context);
    if (target.pid <= 0) THROW(, "debug threads requires an active executable")
    std::vector<pid_t> ids;
    for (const auto &[pid, thread] : target.threads) ids.push_back(pid);
    std::ranges::sort(ids);
    for (const auto pid : ids) {
      std::string name;
      std::ifstream input("/proc/" + std::to_string(pid) + "/comm");
      std::getline(input, name);
      *context.io.out << "[debug-thread]\t" << pid << "\t" << hexText(name) << "\t" << (pid == target.pid) << "\n";
    }
  }

  void Debugger::thread(context::Context &context, lexicon::Phrase &) {
    const auto text = readLine(context);
    pid_t pid = 0;
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), pid);
    if (parsed.ec != std::errc{} || parsed.ptr != text.data() + text.size())
      THROW(, "debug thread requires a thread id")
    selectThread(executableState(context), pid);
  }

  void Debugger::children(context::Context &context, lexicon::Phrase &) {
    auto source = readLine(context);
    const auto comma = source.find(',');
    const auto value = Expressions::evaluate(context, source.substr(0, comma));
    if (!value.isString()) THROW(, "debug children requires a variable path string")
    std::uint64_t start = 0, count = 100;
    if (comma != std::string::npos) {
      auto range = source.substr(comma + 1);
      std::replace(range.begin(), range.end(), ',', ' ');
      std::istringstream input(range);
      if (!(input >> start >> count) || (input >> std::ws && !input.eof()) || count > 1024)
        THROW(, "debug children expects path, start, count (at most 1024)")
    }
    const auto view = variableAt(context, value.asString());
    const auto &target = executableState(context);
    const auto &schema = schemaOf(target, view.local);
    const auto total = childCount(target, view);
    const auto end = start >= total ? start : start + std::min(count, total - start);
    const auto kind = static_cast<compiler::TypeKind>(view.local.kind);
    for (auto index = start; index < end; ++index) {
      if (kind == compiler::TypeKind::Structure)
        printVariable(context, variableAt(context, view.path + '.' + schema.children[index].name));
      else {
        auto child = variableAt(context, view.path + '[' + std::to_string(index) + ']');
        child.local.name = '[' + std::to_string(index) + ']';
        printVariable(context, child);
      }
    }
  }

  void Debugger::terminal(context::Context &context, lexicon::Phrase &) {
    const auto path = stringArgument(context, "debug terminal");
    const int fd = open(path.c_str(), O_RDWR | O_NOCTTY);
    if (fd < 0 || !isatty(fd)) {
      if (fd >= 0) close(fd);
      THROW(, "debug terminal requires a writable TTY")
    }
    close(fd);
    debugRuntime(context).terminal = path;
  }

  void Debugger::stack(context::Context &context, lexicon::Phrase &) {
    const auto &target = executableState(context);
    const auto frames = nativeFrames(target);
    for (std::size_t id = 0; id < frames.size(); ++id) {
      const auto &point = target.points[frames[id].point];
      *context.io.out << "[debug-frame]\t" << id << "\t" << hexText(point.path) << "\t" << point.line << "\t"
                      << point.column << "\t" << hexText(point.function) << "\n";
    }
  }

  void Debugger::frame(context::Context &context, lexicon::Phrase &) {
    const auto text = trim(readLine(context));
    std::size_t id = 0;
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), id);
    auto &target = executableState(context);
    const auto frames = nativeFrames(target);
    if (parsed.ec != std::errc{} || parsed.ptr != text.data() + text.size() || id >= frames.size())
      THROW(, "invalid debug frame")
    target.selectedFrame = frames[id].base;
    target.selectedPoint = frames[id].point;
  }

  void Debugger::set(context::Context &context, lexicon::Phrase &) {
    const auto text = readLine(context);
    const auto separator = text.find('=');
    if (separator == std::string::npos) THROW(, "debug set requires name = expression")
    const auto name = trim(text.substr(0, separator));
    const auto view = variableAt(context, name);
    const auto *found = &view.local;
    if (found->size == 0 || found->size > sizeof(long) ||
        static_cast<compiler::TypeKind>(found->kind) == compiler::TypeKind::Structure ||
        static_cast<compiler::TypeKind>(found->kind) == compiler::TypeKind::Array)
      THROW(, "variable is not a writable scalar")
    const auto value = evaluateNative(context, text.substr(separator + 1));
    std::uint64_t bits;
    if (static_cast<compiler::TypeKind>(found->kind) == compiler::TypeKind::FloatingPoint)
      bits = found->size == 4 ? std::bit_cast<std::uint32_t>(static_cast<float>(value.asReal()))
                              : std::bit_cast<std::uint64_t>(value.asReal());
    else
      bits = value.isBoolean() ? value.asBoolean() : value.asInteger();
    auto &target = executableState(context);
    // Read-modify-write each aligned word: packed members may cross words/pages.
    for (std::uint32_t at = 0; at < found->size;) {
      const auto aligned = (view.address + at) & ~(sizeof(long) - 1);
      const auto offset = (view.address + at) - aligned;
      errno = 0;
      auto word =
          static_cast<unsigned long>(ptrace(PTRACE_PEEKDATA, target.pid, reinterpret_cast<void *>(aligned), nullptr));
      if (errno) ptraceFailure("read variable for assignment");
      for (auto byte = offset; byte < sizeof(long) && at < found->size; ++byte, ++at) {
        const auto shift = byte * 8;
        word = (word & ~(255UL << shift)) | (((bits >> (at * 8)) & 255) << shift);
      }
      if (ptrace(PTRACE_POKEDATA, target.pid, reinterpret_cast<void *>(aligned), reinterpret_cast<void *>(word)) == -1)
        ptraceFailure("write variable");
    }
    printVariable(context, view);
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
