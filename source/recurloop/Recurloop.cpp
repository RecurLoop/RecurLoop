#if !defined(__RECURLOOP_RECURLOOP_CPP)
  #define __RECURLOOP_RECURLOOP_CPP
  #include <recurloop/Recurloop.hpp>
  #include <recurloop/Assembler.hpp>
  #include <recurloop/Debugger.hpp>
  #include <recurloop/Execution.hpp>
  #include <recurloop/EngineImage.hpp>
  #include <recurloop/TranslationUnits.hpp>

  #include <sys/mman.h>
  #include <sys/syscall.h>
  #include <unistd.h>

  #include <cerrno>
  #include <cstring>

namespace recurloop {
  void Recurloop::initializeConfig(int argc, char **argv) {
    constexpr Size LEXICON_SIZE = (Size)1024 * 1024 * 64;
    constexpr Size RUNTIME_SIZE = (Size)1024 * 1024 * 16;
    constexpr Size WORKSPACE_SIZE = (Size)1024 * 1024 * 16;
    constexpr Size WORKSPACE_KEY_SIZE = (Size)1024 * 1024 * 8;
    constexpr Size WORKSPACE_CODE_SIZE = (Size)1024 * 1024 * 8;

    context.config = {{{LEXICON_SIZE}},
                      {{RUNTIME_SIZE}},
                      {{WORKSPACE_SIZE}},
                      {{{WORKSPACE_KEY_SIZE}}, {{WORKSPACE_CODE_SIZE}}},
                      {false}};
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
    int fd = syscall(SYS_memfd_create, "jit_mem", 0);
    if (fd < 0) THROW(, "cannot create JIT memory file: " << std::strerror(errno));

    if (ftruncate(fd, context.config.runtime.memory.size) != 0) {
      const int error = errno;
      close(fd);
      THROW(, "cannot size JIT memory file: " << std::strerror(error));
    }

    void *runtimeMemory = mmap(nullptr, context.config.runtime.memory.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (runtimeMemory == MAP_FAILED) {
      const int error = errno;
      close(fd);
      THROW(, "cannot map writable JIT memory: " << std::strerror(error));
    }

    void *runtimeExecutable =
        mmap(nullptr, context.config.runtime.memory.size, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
    if (runtimeExecutable == MAP_FAILED) {
      const int error = errno;
      munmap(runtimeMemory, context.config.runtime.memory.size);
      close(fd);
      THROW(, "cannot map executable JIT memory: " << std::strerror(error));
    }

    close(fd);
    context.runtime = JitMemory(runtimeMemory, runtimeExecutable, context.config.runtime.memory.size).clear();
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

  static void processSourceBuffer(context::Context &context) {
    auto filter = [](lexicon::Dictionary *dictionary, lexicon::Match *candidate) -> bool {
      return candidate->getPhrase().isElaboratable();
    };

    while (context.source.buffer.bits > 0 || context.source.more) {
      const SourceLocation sourceLocation{context.source.path, context.source.line, context.source.position};
      try {
        if (context.source.buffer.bits > 0) {
          const DebugLocation debugLocation{context.source.path, context.source.line, context.source.position};
          lexicon::Dictionary dictionary = context::Lookup::current(context).getSubdictionary();
          lexicon::Phrase matched = context::Source::matchLongest(context, dictionary, filter, true);

          if (matched.isNull()) handleUndefinedPhrase(context);

          Debugger::beforeElaborate(context, matched, debugLocation);
          matched.elaborate(context);
        } else {
          context::Source::load(context, false);
        }
      } catch (const std::exception &error) {
        rethrowAt(sourceLocation, error);
      } catch (...) {
        THROW_AT(sourceLocation, "unknown internal error")
      }
    }

    // All data should be processed
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

  Recurloop &Recurloop::initialize(int argc, char **argv) {
    initializeConfig(argc, argv);
    initializeLexicon();
    initializeRuntime();
    initializeWorkspace();
    context.translationUnits = std::make_shared<TranslationUnitRegistry>(context);

    // Prepare Language
    lexicon::Phrase undefined(&context.lexicon);

    lexicon::Phrase root = context.lexicon.make(context::Lookup::enter)
                               .setType(undefined)
                               .enableSubdictionary()
                               .setSuccessor(undefined)
                               .save();
    root.setSuccessor(root).save();
    context.actions().define("lookup.enter", context::Lookup::enter);
    context::Lookup::enter(context, root);

    Language::setup(context);

    while (context.exec.args.index < context.exec.args.count &&
           (std::string_view(context.exec.args.ptr[context.exec.args.index]) == "--import" ||
            std::string_view(context.exec.args.ptr[context.exec.args.index]) == "--engine-image")) {
      if (++context.exec.args.index >= context.exec.args.count) THROW(, "--import requires a path")
      EngineImage::load(context, context.exec.args.ptr[context.exec.args.index++]);
    }

    root = context.lexicon.phrase();
    context::Lookup::in(context, root);
    context::Staging::push(context, root);
    context::Reference::in(context, root);

    return *this;
  }

  int Recurloop::execute() {
    executeMainLoop(context);
    return context.exec.status;
  }
} // namespace recurloop
#endif
