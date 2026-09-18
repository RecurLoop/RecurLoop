#if !defined(__RECURLOOP_RECURLOOP_CPP)
  #define __RECURLOOP_RECURLOOP_CPP
  #include <recurloop/Recurloop.hpp>
  #include <recurloop/Assembler.hpp>
  #include <recurloop/Blocks.hpp>
  #include <recurloop/Debugger.hpp>
  #include <recurloop/Execution.hpp>
  #include <recurloop/EngineImage.hpp>
  #include <recurloop/HostAbi.hpp>
  #include <recurloop/ContextApi.hpp>
  #include <recurloop/TranslationUnits.hpp>

  #include <sys/mman.h>
  #include <sys/syscall.h>
  #include <unistd.h>

  #include <cerrno>
  #include <cstring>
  #include <cstdlib>
  #include <filesystem>
  #include <sstream>
  #include <string_view>

namespace recurloop {
  void Recurloop::initializeConfig(int argc, char **argv) {
    constexpr Size SOURCE_BUFFER_SIZE = (Size)1024 * 64;
    constexpr Size LEXICON_SIZE = (Size)1024 * 1024 * 64;
    constexpr Size RUNTIME_SIZE = (Size)1024 * 1024 * 16;
    constexpr Size WORKSPACE_KEY_SIZE = (Size)1024 * 1024 * 8;
    constexpr Size WORKSPACE_CODE_SIZE = (Size)1024 * 1024 * 8;

    // Keep source buffering independent from the fixed arenas.  The previous
    // aggregate initializer accidentally assigned LEXICON_SIZE to the source
    // buffer and shifted the following sizes by one field.  Besides shrinking
    // the lexicon to 16 MiB, every source refill reserved 64 MiB.
    context.config = {};
    context.config.source.buffer.size = SOURCE_BUFFER_SIZE;
    context.config.lexicon.memory.size = LEXICON_SIZE;
    context.config.runtime.memory.size = RUNTIME_SIZE;
    context.config.workspace.key.memory.size = WORKSPACE_KEY_SIZE;
    context.config.workspace.code.memory.size = WORKSPACE_CODE_SIZE;
    context.config.exception.continues = false;
    context.exec.status = 0;
    context.exec.start = std::chrono::high_resolution_clock::now();
    context.exec.args = {1, argc, argv, true};
    context.exec.pendingException = nullptr;
    context.exec.pendingNativeEntry = 0;
    context.exec.pendingNativeSymbol.clear();
    context.exec.definitionSymbolOverride.clear();
    context.exec.pendingFunctionVariant.clear();
    context.exec.pendingPhrasePayload.clear();
    context.exec.hasPendingPhraseSerializable = false;
    context.exec.hasPendingPhrasePermanent = false;
    context.exec.hasPendingPhraseRewritable = false;
    context.exec.invoked = nullptr;
    Debugger::initialize(context);
    context.io = {nullptr, &std::cout, &std::cerr};
    context.source = {"", 1, 1, true, {}};
  }

  void Recurloop::initializeLexicon() {
    auto lexiconMemory = malloc(context.config.lexicon.memory.size);
    if (!lexiconMemory) THROW(, "cannot allocate lexicon memory")
    context.lexicon = lexicon::Lexicon(lexiconMemory, context.config.lexicon.memory.size).clear();
  }

  void Recurloop::initializeRuntime() {
    const auto mapJitMemory = [&](const char *name) {
      int fd = syscall(SYS_memfd_create, name, 0);
      if (fd < 0) THROW(, "cannot create JIT memory file: " << std::strerror(errno))

      if (ftruncate(fd, context.config.runtime.memory.size) != 0) {
        const int error = errno;
        close(fd);
        THROW(, "cannot size JIT memory file: " << std::strerror(error));
      }

      void *memory = mmap(nullptr, context.config.runtime.memory.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
      if (memory == MAP_FAILED) {
        const int error = errno;
        close(fd);
        THROW(, "cannot map writable JIT memory: " << std::strerror(error));
      }

      void *executable =
          mmap(nullptr, context.config.runtime.memory.size, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
      if (executable == MAP_FAILED) {
        const int error = errno;
        munmap(memory, context.config.runtime.memory.size);
        close(fd);
        THROW(, "cannot map executable JIT memory: " << std::strerror(error));
      }

      close(fd);
      return JitMemory(memory, executable, context.config.runtime.memory.size).clear();
    };

    context.runtime = mapJitMemory("recurloop_runtime");
    context.actionRuntime = mapJitMemory("recurloop_actions");
  }

  void Recurloop::initializeWorkspace() {
    auto workspaceKeyMemory = malloc(context.config.workspace.key.memory.size);
    if (!workspaceKeyMemory) THROW(, "cannot allocate workspace key memory")
    context.workspace.key = Appender(workspaceKeyMemory, context.config.workspace.key.memory.size).clear();

    auto workspaceCodeMemory = malloc(context.config.workspace.code.memory.size);
    if (!workspaceCodeMemory) THROW(, "cannot allocate workspace code memory")
    context.workspace.code = Appender(workspaceCodeMemory, context.config.workspace.code.memory.size).clear();
  }

  void Recurloop::cleanupMemory() {
    free(context.lexicon.getMemory().toPtr());
    free(context.workspace.key.getMemory().toPtr());
    munmap(context.runtime.getMemory().toPtr(), context.runtime.getCapacity());
    munmap(context.runtime.getExecutable().toPtr(), context.runtime.getCapacity());
    munmap(context.actionRuntime.getMemory().toPtr(), context.actionRuntime.getCapacity());
    munmap(context.actionRuntime.getExecutable().toPtr(), context.actionRuntime.getCapacity());
  }

  Recurloop::Recurloop() {}

  Recurloop::~Recurloop() {
    Debugger::release(context);
    cleanupMemory();
  }

  static bool hasNewlineInBuffer(context::Context &context, const std::string &bufferStr, std::size_t &keyProgress) {
    while ((keyProgress - context.source.buffer.offset) < context.source.buffer.bits) {
      char ch = bufferStr[keyProgress / Byte::length];
      if (ch == '\n') return true;
      keyProgress += Byte::length;
    }
    return false;
  }

  static std::string extractPhraseForError(const std::string &bufferStr, std::size_t offsetBytes, std::size_t maxLen) {
    std::string phrase(bufferStr.begin() + offsetBytes, bufferStr.end());
    std::size_t newlinePos = phrase.find('\n');
    if (newlinePos != std::string::npos) phrase = phrase.substr(0, newlinePos);

    phrase = helper::string::escape(phrase);
    if (phrase.length() > maxLen) phrase = phrase.substr(0, maxLen - 3) + "...";

    return phrase;
  }

  static void skipToNextLine(context::Context &context) {
    while (context.source.buffer.bits > 0 || context.source.more) {
      if (context.source.buffer.bits == 0) {
        context::Source::load(context, true);
        continue;
      }

      Size availableBytes = context.source.buffer.bits / Byte::length;
      Size startByte = context.source.buffer.offset / Byte::length;

      bool hasNewLine = false;
      for (Size i = 0; i < availableBytes; ++i) {
        char ch = context.source.buffer.str.data()[startByte + i];
        context::Source::progress(context, Byte::length);

        if (ch == '\n') {
          hasNewLine = true;
          break;
        }

        if (context.source.buffer.bits == 0) break;
      }

      if (hasNewLine) break;
    }
  }

  namespace {
    constexpr std::string_view SourceHookMarker{"\0source-hook", 12};

    lexicon::Phrase sourceHook(context::Context &context) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Match match = root.matchExact(
          Byte(const_cast<char *>(SourceHookMarker.data())), 0, SourceHookMarker.size() * Byte::length,
          [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); });
      if (match.isNull()) return lexicon::Phrase(&context.lexicon);
      lexicon::Phrase marker = match.getPhrase();
      if (!marker.containsPrototype()) return lexicon::Phrase(&context.lexicon);
      return marker.getPrototype();
    }

    bool runSourceHook(context::Context &context) {
      lexicon::Phrase root = context.lexicon.phrase();
      if (context::Lookup::current(context).getAddress() != root.getAddress()) return false;

      lexicon::Phrase hook = sourceHook(context);
      if (hook.isNull() || !hook.isElaboratable()) return false;

      const Size line = context.source.line;
      const Size position = context.source.position;
      hook.elaborate(context);
      return context.source.line != line || context.source.position != position;
    }
  } // namespace

  static void handleUndefinedPhrase(context::Context &context) {
    constexpr std::size_t maxLen = 50;
    const std::string &bufferStr = context.source.buffer.str;
    std::size_t offsetBytes = context.source.buffer.offset / Byte::length;
    std::size_t keyProgress = context.source.buffer.offset;

    // Try to load more input until we reach a newline or at least maxLen characters
    while (context.source.more && bufferStr.length() - offsetBytes <= maxLen) {
      if (hasNewlineInBuffer(context, bufferStr, keyProgress)) break;
      context::Source::load(context, false);
    }

    std::string phrase = extractPhraseForError(bufferStr, offsetBytes, maxLen);
    const SourceLocation location{context.source.path, context.source.line, context.source.position};

    skipToNextLine(context);

    THROW_AT(location, "undefined phrase \"" << phrase << "\"; lookup dictionary is \""
                                             << context::Lookup::current(context).getKeyEscaped() << "\"")
  }

  [[noreturn]] static void rethrowAt(const SourceLocation &location, const std::exception &error) {
    if (const auto *exception = dynamic_cast<const Exception *>(&error)) {
      if (exception->hasSourceLocation()) throw;
      THROW_AT(location, exception->description())
    }
    THROW_AT(location, error.what())
  }

  static void processSourceStep(context::Context &context) {
    auto filter = [](lexicon::Dictionary *dictionary, lexicon::Match *candidate) -> bool {
      return candidate->getPhrase().isElaboratable();
    };

    const SourceLocation sourceLocation{context.source.path, context.source.line, context.source.position};
    try {
      if (context.source.buffer.bits > 0) {
        const DebugLocation debugLocation{context.source.path, context.source.line, context.source.position};
        if (runSourceHook(context)) return;
        lexicon::Dictionary dictionary = context::Lookup::current(context).getSubdictionary();
        lexicon::Phrase matched = context::Source::matchLongest(context, dictionary, filter, true);

        if (matched.isNull()) handleUndefinedPhrase(context);

        Debugger::beforeElaborate(context, matched, debugLocation);
        matched.elaborate(context);
      } else if (context.source.more) {
        // Empty-buffer refill is also a sliding refill.  Without this the
        // already-consumed prefix survives line after line even though normal
        // source execution is strictly left-to-right.
        context::Source::load(context, true);
      }
    } catch (const std::exception &error) {
      rethrowAt(sourceLocation, error);
    } catch (...) {
      THROW_AT(sourceLocation, "unknown internal error")
    }
  }

  static void finishSource(context::Context &context) {
    const SourceLocation endLocation{context.source.path, context.source.line, context.source.position};
    try {
      if (0 < context.source.buffer.bits)
        THROW(, "unprocessed input: '" << context.source.buffer.str.substr(context.source.buffer.offset / Byte::length,
                                                                           50)
                                       << "'")
      Assembler::sourceEnd(context);
    } catch (const std::exception &error) {
      rethrowAt(endLocation, error);
    } catch (...) {
      THROW_AT(endLocation, "unknown internal error")
    }
  }

  static void processSourceBuffer(context::Context &context) {
    while (context.source.buffer.bits > 0 || context.source.more) processSourceStep(context);
    finishSource(context);
  }

  namespace {
    struct ValueScope {
      explicit ValueScope(context::Context &context, bool enabled) : context(context), enabled(enabled) {
        if (enabled) context.values().pushScope();
      }
      ~ValueScope() {
        if (enabled) context.values().popScope();
      }
      context::Context &context;
      bool enabled;
    };
  } // namespace

  void executeCurrentBlock(context::Context &context, bool scoped) {
    const Size lookup = context::Lookup::current(context).getAddress();
    ValueScope values(context, scoped);

    while (true) {
      // The opening brace was consumed by Blocks::begin().  A close brace is
      // the boundary only after nested source grammars/scopes have returned to
      // the lookup dictionary in which the block started.
      if (context::Lookup::current(context).getAddress() == lookup && Blocks::consume(context, "}")) return;

      if (context.source.buffer.bits == 0 && !context.source.more) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "unterminated block; expected '}'")
      }
      processSourceStep(context);
    }
  }

  void executeSource(context::Context &context, std::string_view source, std::string_view path, Size line,
                     Size position) {
    const context::Source outerSource = context.source;
    std::istream *const outerInput = context.io.in;

    context.source = {
        std::string(path), line, position, false, {std::string(source), 0, 0, source.size() * Byte::length}};
    context.io.in = nullptr;
    Debugger::sourceEnter(context);
    try {
      processSourceBuffer(context);
    } catch (...) {
      Debugger::sourceLeave(context);
      context.source = outerSource;
      context.io.in = outerInput;
      throw;
    }
    Debugger::sourceLeave(context);
    context.source = outerSource;
    context.io.in = outerInput;
  }

  void executeStream(context::Context &context, std::istream &source, std::string_view path, Size line,
                     Size position) {
    const context::Source outerSource = context.source;
    std::istream *const outerInput = context.io.in;
    const int outerArgumentIndex = context.exec.args.index;

    context.source = {std::string(path), line, position, true, {}};
    context.io.in = &source;
    // A nested stream is a bounded translation unit.  Prevent Source::load()
    // from falling through into the caller's remaining command-line inputs
    // when this stream reaches EOF.
    context.exec.args.index = context.exec.args.count;

    Debugger::sourceEnter(context);
    try {
      processSourceBuffer(context);
    } catch (...) {
      Debugger::sourceLeave(context);
      context.source = outerSource;
      context.io.in = outerInput;
      context.exec.args.index = outerArgumentIndex;
      throw;
    }
    Debugger::sourceLeave(context);
    context.source = outerSource;
    context.io.in = outerInput;
    context.exec.args.index = outerArgumentIndex;
  }

  static void executeMainLoop(context::Context &context) {
    context.source.more = (context.io.in && !context.io.in->eof()) || context.exec.args.index < context.exec.args.count;

    do {
      try {
        processSourceBuffer(context);
        break;
      } catch (const Exception &e) {
        *context.io.err << RED_TEXT << e.what() << RESET << std::endl;

        if (!context.config.exception.continues || !context.source.more) {
          context.exec.status = e.status();
          break;
        }

        context.exec.status = 0;
        context::Source::progress(context, context.source.buffer.bits);
        context::Source::load(context, false);
      }
    } while (true);
  }

  void Recurloop::initializeRoot() {
    lexicon::Phrase undefined(&context.lexicon);
    lexicon::Phrase root = context.lexicon.make(context::Lookup::enter)
                               .setType(undefined)
                               .enableSubdictionary()
                               .setSuccessor(undefined)
                               .save();
    root.setSuccessor(root).save();
    context.actions().define("lookup.enter", context::Lookup::enter);
    context.lookup = {};
    context.staging = {};
    context.reference = {};
    context::Lookup::enter(context, root);
    context::Staging::push(context, root);
    context::Reference::in(context, root);
  }

  namespace {
    void appendLibraryPathList(std::vector<std::filesystem::path> &paths, const char *value) {
      if (value == nullptr || *value == '\0') return;
#if defined(_WIN32)
      constexpr char separator = ';';
#else
      constexpr char separator = ':';
#endif
      std::string_view list(value);
      std::size_t begin = 0;
      while (begin <= list.size()) {
        const std::size_t end = list.find(separator, begin);
        const std::string_view item = list.substr(begin, end == std::string_view::npos ? list.size() - begin : end - begin);
        if (!item.empty()) paths.emplace_back(item);
        if (end == std::string_view::npos) break;
        begin = end + 1;
      }
    }

    std::filesystem::path resolveLibraryImage(context::Context &context, std::string_view requested,
                                               const std::vector<std::filesystem::path> &explicitPaths) {
      namespace fs = std::filesystem;
      fs::path name(requested);
      if (name.has_parent_path() || name.is_absolute()) {
        if (fs::exists(name)) return fs::absolute(name).lexically_normal();
        THROW(, "library image not found: " << name.string())
      }
      if (name.extension() != ".rli") name += ".rli";

      std::vector<fs::path> paths = explicitPaths;
      appendLibraryPathList(paths, std::getenv("RECURLOOP_LIBRARY_PATH"));

      if (context.exec.args.ptr != nullptr && context.exec.args.count > 0 && context.exec.args.ptr[0] != nullptr) {
        fs::path executable(context.exec.args.ptr[0]);
        if (executable.has_parent_path()) {
          std::error_code error;
          executable = fs::absolute(executable, error).lexically_normal();
          if (!error) {
            const fs::path prefixOrBuild = executable.parent_path().parent_path();
            paths.push_back(prefixOrBuild / "libraries");
            paths.push_back(prefixOrBuild / "share" / "recurloop" / "libraries");
          }
        }
      }

#ifdef RECURLOOP_DEFAULT_LIBRARY_DIR
      paths.emplace_back(RECURLOOP_DEFAULT_LIBRARY_DIR);
#endif
      paths.push_back(fs::current_path() / "libraries");

      for (const fs::path &directory : paths) {
        std::error_code error;
        const fs::path candidate = fs::absolute(directory / name, error).lexically_normal();
        if (!error && fs::exists(candidate)) return candidate;
      }

      std::ostringstream message;
      message << "library image '" << requested << "' was not found";
      if (!paths.empty()) {
        message << " in";
        for (const auto &path : paths) message << "\n  " << path.string();
      }
      THROW(, message.str())
    }
  } // namespace

  void Recurloop::initializeBase(int argc, char **argv) {
    initializeConfig(argc, argv);
    initializeLexicon();
    initializeRuntime();
    initializeWorkspace();
    context.translationUnits = std::make_shared<TranslationUnitRegistry>(context);
    initializeRoot();
  }

  void Recurloop::resetToKernel() {
    context.lexicon.clear();
    context.workspace.key.clear();
    context.workspace.code.clear();
    context.exec.pendingException = nullptr;
    context.exec.pendingNativeEntry = 0;
    context.exec.pendingNativeSymbol.clear();
    context.exec.definitionSymbolOverride.clear();
    context.exec.pendingFunctionVariant.clear();
    context.exec.pendingPhrasePayload.clear();
    context.exec.hasPendingPhraseSerializable = false;
    context.exec.hasPendingPhrasePermanent = false;
    context.exec.hasPendingPhraseRewritable = false;
    context.exec.invoked = nullptr;
    initializeRoot();
    context.actions().replace(hostActions);
  }

  void Recurloop::processStartupOperations() {
    std::vector<std::filesystem::path> libraryPaths;
    while (context.exec.args.index < context.exec.args.count) {
      const std::string_view option(context.exec.args.ptr[context.exec.args.index]);
      if (option == "--reset") {
        ++context.exec.args.index;
        resetToKernel();
        continue;
      }
      if (option == "--import") {
        if (++context.exec.args.index >= context.exec.args.count) THROW(, "--import requires a path")
        EngineImage::load(context, context.exec.args.ptr[context.exec.args.index++]);
        continue;
      }
      if (option == "--library-path") {
        if (++context.exec.args.index >= context.exec.args.count) THROW(, "--library-path requires a path")
        libraryPaths.emplace_back(context.exec.args.ptr[context.exec.args.index++]);
        continue;
      }
      if (option == "--library") {
        if (++context.exec.args.index >= context.exec.args.count) THROW(, "--library requires a name or path")
        const std::string_view name(context.exec.args.ptr[context.exec.args.index++]);
        EngineImage::load(context, resolveLibraryImage(context, name, libraryPaths).string());
        continue;
      }
      if (option == "--bootstrap" || option == "--language-image" || option == "--engine-image")
        THROW(, "option '" << option << "' was removed; use --reset and --import")
      break;
    }
  }

  Recurloop &Recurloop::initializeEmbedded(int argc, char **argv, std::span<const std::uint8_t> coreImage) {
    initializeBase(argc, argv);

    // Final runtime startup does not construct the compatibility language.
    // Stable C++ action names are process-local Host ABI, while the complete
    // language graph comes from the embedded core image.
    HostAbi::registerActions(context);
    hostActions = context.actions().snapshot();
    EngineImage::decode(context, coreImage);

    // Host functions are process-local addresses and are intentionally not
    // serialized in .rli. Rebind them against the restored typed language.
    ContextApi::bind(context);

    processStartupOperations();
    return *this;
  }

  int Recurloop::execute() {
    executeMainLoop(context);
    return context.exec.status;
  }
} // namespace recurloop
#endif
