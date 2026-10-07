#include <recurloop/Generation.hpp>

#include <recurloop/Debugger.hpp>
#include <recurloop/EngineImage.hpp>

#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <cstdlib>

#ifdef __linux__
  #include <fcntl.h>
  #include <linux/memfd.h>
#endif

namespace recurloop {
  namespace {
    int createMemfd(const char *name, Size size) {
#ifdef __linux__
      const int fd = static_cast<int>(syscall(SYS_memfd_create, name, MFD_CLOEXEC | MFD_ALLOW_SEALING));
#else
      const int fd = -1;
#endif
      if (fd < 0) THROW(, "cannot create generation memory file: " << std::strerror(errno))
      if (ftruncate(fd, static_cast<off_t>(size)) != 0) {
        const int error = errno;
        close(fd);
        THROW(, "cannot size generation memory file: " << std::strerror(error))
      }
      return fd;
    }

    void discardPrivateTail(context::Context &context, Size keep, Size used) noexcept {
      if (used <= keep || context.lexicon.getMemory().isNull()) return;
      const long rawPage = sysconf(_SC_PAGESIZE);
      if (rawPage <= 0) return;
      const Size page = static_cast<Size>(rawPage);
      const Size start = ((keep + page - 1) / page) * page;
      const Size end = ((used + page - 1) / page) * page;
      if (end <= start || start >= context.lexicon.memorySize()) return;
      const Size boundedEnd = std::min(end, context.lexicon.memorySize());
      madvise(static_cast<std::uint8_t *>(context.lexicon.getMemory().toPtr()) + start, boundedEnd - start,
              MADV_DONTNEED);
    }

    void writeAll(int fd, const void *memory, Size bytes) {
      const auto *cursor = static_cast<const std::uint8_t *>(memory);
      Size offset = 0;
      while (offset < bytes) {
        const ssize_t written = pwrite(fd, cursor + offset, bytes - offset, static_cast<off_t>(offset));
        if (written < 0) {
          if (errno == EINTR) continue;
          THROW(, "cannot snapshot lexicon generation: " << std::strerror(errno))
        }
        if (written == 0) THROW(, "cannot snapshot lexicon generation: short write")
        offset += static_cast<Size>(written);
      }
    }
  } // namespace

  LexiconGeneration::~LexiconGeneration() {
    if (fd_ >= 0) close(fd_);
  }

  std::shared_ptr<const LexiconGeneration> LexiconGeneration::capture(context::Context &context, GenerationId id) {
    if (context.lexicon.getMemory().isNull()) THROW(, "cannot capture an uninitialized lexicon")
    const Size capacity = context.lexicon.memorySize();
    const Size used = context.lexicon.memoryUsed();
    const int fd = createMemfd("recurloop_lexicon_generation", capacity);
    try {
      writeAll(fd, context.lexicon.getMemory().toPtr(), used);
#ifdef __linux__
      // Private writable mappings stay legal after F_SEAL_WRITE; only writes to
      // the shared backing object are forbidden.  This makes a published
      // generation immutable while preserving per-session COW.
      if (fcntl(fd, F_ADD_SEALS, F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_WRITE | F_SEAL_SEAL) != 0)
        THROW(, "cannot seal lexicon generation: " << std::strerror(errno))
#endif
      return std::shared_ptr<const LexiconGeneration>(new LexiconGeneration(id, fd, used, capacity));
    } catch (...) {
      close(fd);
      throw;
    }
  }

  void *LexiconGeneration::mapPrivate() const {
    void *memory = mmap(nullptr, capacity_, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd_, 0);
    if (memory == MAP_FAILED) THROW(, "cannot map lexicon generation: " << std::strerror(errno))
    return memory;
  }

  void LexiconGeneration::unmap(void *memory) const noexcept {
    if (memory != nullptr && memory != MAP_FAILED) munmap(memory, capacity_);
  }

  JitMemory ContextGeneration::mapJitMemory(Size size, const char *name) {
    const int fd = createMemfd(name, size);
    void *writable = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (writable == MAP_FAILED) {
      const int error = errno;
      close(fd);
      THROW(, "cannot map writable JIT memory: " << std::strerror(error))
    }
    void *executable = mmap(nullptr, size, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
    if (executable == MAP_FAILED) {
      const int error = errno;
      munmap(writable, size);
      close(fd);
      THROW(, "cannot map executable JIT memory: " << std::strerror(error))
    }
    close(fd);
    return JitMemory(writable, executable, size).clear();
  }

  ContextGeneration::ContextGeneration(std::shared_ptr<const LexiconGeneration> lexicon,
                                       const context::Config &config, const ActionEntries &actions,
                                       const std::vector<std::string> &arguments, GenerationId projectId,
                                       GenerationId contextId, GenerationId sessionId)
      : lexicon_(std::move(lexicon)), arguments_(arguments) {
    try {
      if (!lexicon_) THROW(, "context generation requires a lexicon generation")

      context_.config = config;
      lexiconMemory_ = lexicon_->mapPrivate();
      context_.lexicon = lexicon::Lexicon(lexiconMemory_, lexicon_->capacity());

      context_.runtime = mapJitMemory(config.runtime.memory.size, "recurloop_session_runtime");
      context_.actionRuntime = mapJitMemory(config.runtime.memory.size, "recurloop_session_actions");

      void *key = malloc(config.workspace.key.memory.size);
      if (!key) THROW(, "cannot allocate session workspace key memory")
      context_.workspace.key = Appender(key, config.workspace.key.memory.size).clear();
      void *code = malloc(config.workspace.code.memory.size);
      if (!code) {
        free(key);
        context_.workspace.key = {};
        THROW(, "cannot allocate session workspace code memory")
      }
      context_.workspace.code = Appender(code, config.workspace.code.memory.size).clear();

      context_.actionRegistry.entries = actions;
      initializeArguments();
      context_.exec.status = 0;
      context_.exec.start = std::chrono::high_resolution_clock::now();
      context_.io = {nullptr, &std::cout, &std::cerr};
      context_.source = {"", 1, 1, false, {}};
      generations_ = {projectId, lexicon_->id(), contextId, sessionId, 0};

      Debugger::initialize(context_);
      debuggerInitialized_ = true;
      context_.lookup = {};
      context_.staging = {};
      context_.reference = {};
      lexicon::Phrase root = context_.lexicon.phrase();
      context::Lookup::enter(context_, root);
      context::Staging::push(context_, root);
      context::Reference::in(context_, root);
    } catch (...) {
      release();
      throw;
    }
  }

  void ContextGeneration::initializeArguments() {
    argv_.clear();
    argv_.reserve(arguments_.size());
    for (std::string &argument : arguments_) argv_.push_back(argument.data());
    const int count = static_cast<int>(argv_.size());
    context_.exec.args = {count, count, argv_.empty() ? nullptr : argv_.data(), true};
  }

  void ContextGeneration::release() noexcept {
    if (debuggerInitialized_) {
      Debugger::release(context_);
      debuggerInitialized_ = false;
    }
    EngineImage::releaseNativeState(context_);

    if (!context_.workspace.key.getMemory().isNull()) {
      free(context_.workspace.key.getMemory().toPtr());
      context_.workspace.key = {};
    }
    if (!context_.workspace.code.getMemory().isNull()) {
      free(context_.workspace.code.getMemory().toPtr());
      context_.workspace.code = {};
    }

    if (!context_.runtime.getMemory().isNull()) {
      munmap(context_.runtime.getMemory().toPtr(), context_.runtime.getCapacity());
      munmap(context_.runtime.getExecutable().toPtr(), context_.runtime.getCapacity());
      context_.runtime = {};
    }
    if (!context_.actionRuntime.getMemory().isNull()) {
      munmap(context_.actionRuntime.getMemory().toPtr(), context_.actionRuntime.getCapacity());
      munmap(context_.actionRuntime.getExecutable().toPtr(), context_.actionRuntime.getCapacity());
      context_.actionRuntime = {};
    }
    if (lexicon_ && lexiconMemory_ != nullptr) {
      lexicon_->unmap(lexiconMemory_);
      lexiconMemory_ = nullptr;
      context_.lexicon = {};
    }
  }

  ContextGeneration::~ContextGeneration() {
    release();
  }

  RequestGeneration::RequestGeneration(context::Context &context, Generations &generations, GenerationId requestId,
                                       std::vector<std::uint8_t> &rollbackBuffer)
      : context_(&context), rollbackBuffer_(&rollbackBuffer), lexiconUsed_(context.lexicon.memoryUsed()),
        runtimeBits_(context.runtime.bits()), actionRuntimeBits_(context.actionRuntime.bits()),
        workspaceKeyBits_(context.workspace.key.bits()), workspaceCodeBits_(context.workspace.code.bits()),
        readOnlyDataSize_(context.workspace.readOnlyData.size()), dataSize_(context.workspace.data.size()),
        bssBytes_(context.workspace.bssBytes), customSectionsSize_(context.workspace.customSections.size()),
        lookup_(context.lookup), staging_(context.staging), reference_(context.reference), source_(context.source),
        io_(context.io), valueScopes_(context.exec.valueScopes), argumentIndex_(context.exec.args.index),
        argumentOptions_(context.exec.args.options) {
    rollbackBuffer.resize(lexiconUsed_);
    if (lexiconUsed_ != 0)
      std::memcpy(rollbackBuffer.data(), context.lexicon.getMemory().toPtr(), lexiconUsed_);
    customSections_.reserve(context.workspace.customSections.size());
    for (const context::Workspace::NativeSection &section : context.workspace.customSections)
      customSections_.push_back({section.bytes.size(), section.memorySize});
    generations.request = requestId;
  }

  RequestGeneration::~RequestGeneration() {
    if (!committed_) rollback();
  }

  void RequestGeneration::rollback() noexcept {
    if (committed_ || context_ == nullptr) return;
    try {
      const Size currentLexiconUsed = context_->lexicon.memoryUsed();
      if (rollbackBuffer_ != nullptr && rollbackBuffer_->size() >= lexiconUsed_ && lexiconUsed_ != 0)
        std::memcpy(context_->lexicon.getMemory().toPtr(), rollbackBuffer_->data(), lexiconUsed_);
      discardPrivateTail(*context_, lexiconUsed_, currentLexiconUsed);
      if (context_->runtime.bits() >= runtimeBits_) context_->runtime.truncate(runtimeBits_);
      if (context_->actionRuntime.bits() >= actionRuntimeBits_) context_->actionRuntime.truncate(actionRuntimeBits_);
      if (context_->workspace.key.bits() >= workspaceKeyBits_) context_->workspace.key.truncate(workspaceKeyBits_);
      if (context_->workspace.code.bits() >= workspaceCodeBits_) context_->workspace.code.truncate(workspaceCodeBits_);
      if (context_->workspace.readOnlyData.size() >= readOnlyDataSize_)
        context_->workspace.readOnlyData.resize(readOnlyDataSize_);
      if (context_->workspace.data.size() >= dataSize_) context_->workspace.data.resize(dataSize_);
      context_->workspace.bssBytes = bssBytes_;
      if (context_->workspace.customSections.size() >= customSectionsSize_) {
        context_->workspace.customSections.resize(customSectionsSize_);
        for (std::size_t i = 0; i < customSections_.size(); ++i) {
          auto &section = context_->workspace.customSections[i];
          if (section.bytes.size() >= customSections_[i].bytes) section.bytes.resize(customSections_[i].bytes);
          section.memorySize = customSections_[i].memorySize;
        }
      }
      context_->lookup = lookup_;
      context_->staging = staging_;
      context_->reference = reference_;
      context_->source = source_;
      context_->io = io_;
      context_->exec.valueScopes = valueScopes_;
      context_->exec.args.index = argumentIndex_;
      context_->exec.args.options = argumentOptions_;
      context_->exec.pendingException = nullptr;
      context_->exec.pendingNativeEntry = 0;
      context_->exec.pendingNativeSymbol.clear();
      context_->exec.definitionSymbolOverride.clear();
      context_->exec.pendingFunctionVariant.clear();
      context_->exec.pendingPhrasePayload.clear();
      context_->exec.hasPendingPhraseSerializable = false;
      context_->exec.hasPendingPhrasePermanent = false;
      context_->exec.hasPendingPhraseRewritable = false;
      context_->exec.pendingPhraseKind.clear();
      context_->exec.pendingPhraseColor.clear();
      context_->exec.pendingPhraseDocs.clear();
      context_->exec.hasPendingPhraseKind = false;
      context_->exec.hasPendingPhraseColor = false;
      context_->exec.hasPendingPhraseDocs = false;
      context_->exec.invoked = nullptr;
    } catch (...) {
      // Rollback is used from error/destructor paths and must never obscure the
      // original request failure.
    }
    committed_ = true;
  }
} // namespace recurloop
