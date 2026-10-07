#pragma once

#include <context/Actions.hpp>
#include <context/Config.hpp>
#include <context/Context.hpp>

#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace recurloop {
  using GenerationId = std::uint64_t;

  struct Generations {
    GenerationId project = 0;
    GenerationId lexicon = 0;
    GenerationId context = 0;
    GenerationId session = 0;
    GenerationId request = 0;
  };

  // Immutable lexicon snapshot backed by a sealed memfd.  Contexts map it with
  // MAP_PRIVATE, so unchanged pages are physically shared by all sessions while
  // writes become session-local through the kernel's copy-on-write mechanism.
  class LexiconGeneration {
  public:
    LexiconGeneration(const LexiconGeneration &) = delete;
    LexiconGeneration &operator=(const LexiconGeneration &) = delete;
    ~LexiconGeneration();

    static std::shared_ptr<const LexiconGeneration> capture(context::Context &context, GenerationId id);

    GenerationId id() const { return id_; }
    Size used() const { return used_; }
    Size capacity() const { return capacity_; }

    void *mapPrivate() const;
    void unmap(void *memory) const noexcept;

  private:
    LexiconGeneration(GenerationId id, int fd, Size used, Size capacity)
        : id_(id), fd_(fd), used_(used), capacity_(capacity) {}

    GenerationId id_ = 0;
    int fd_ = -1;
    Size used_ = 0;
    Size capacity_ = 0;
  };

  // One mutable execution context attached to an immutable lexicon generation.
  // The lexicon mapping is COW; JIT/workspace/native state is private to this
  // context and is released with it.
  class ContextGeneration {
  public:
    using ActionEntries = std::vector<std::pair<std::string, context::Action>>;

    ContextGeneration(std::shared_ptr<const LexiconGeneration> lexicon, const context::Config &config,
                      const ActionEntries &actions, const std::vector<std::string> &arguments,
                      GenerationId projectId, GenerationId contextId, GenerationId sessionId);
    ContextGeneration(const ContextGeneration &) = delete;
    ContextGeneration &operator=(const ContextGeneration &) = delete;
    ~ContextGeneration();

    context::Context &context() { return context_; }
    const context::Context &context() const { return context_; }
    Generations &generations() { return generations_; }
    const Generations &generations() const { return generations_; }
    std::shared_ptr<const LexiconGeneration> lexiconGeneration() const { return lexicon_; }

  private:
    context::Context context_;
    Generations generations_;
    std::shared_ptr<const LexiconGeneration> lexicon_;
    void *lexiconMemory_ = nullptr;
    std::vector<std::string> arguments_;
    std::vector<char *> argv_;
    bool debuggerInitialized_ = false;

    static JitMemory mapJitMemory(Size size, const char *name);
    void initializeArguments();
    void release() noexcept;
  };

  // A request is a cheap generation nested inside a session context.  The
  // lexicon snapshot is limited to the actually used bytes (not the 64 MiB
  // arena), while JIT/workspace appenders are restored by watermarks.  Commit
  // is explicit; an exception therefore leaves the previous session generation
  // intact, including in-place lexicon payload writes.
  class RequestGeneration {
  public:
    RequestGeneration(context::Context &context, Generations &generations, GenerationId requestId,
                      std::vector<std::uint8_t> &rollbackBuffer);
    RequestGeneration(const RequestGeneration &) = delete;
    RequestGeneration &operator=(const RequestGeneration &) = delete;
    ~RequestGeneration();

    void commit() noexcept { committed_ = true; }
    void rollback() noexcept;

  private:
    context::Context *context_ = nullptr;
    std::vector<std::uint8_t> *rollbackBuffer_ = nullptr;
    Size lexiconUsed_ = 0;
    Size runtimeBits_ = 0;
    Size actionRuntimeBits_ = 0;
    Size workspaceKeyBits_ = 0;
    Size workspaceCodeBits_ = 0;
    std::size_t readOnlyDataSize_ = 0;
    std::size_t dataSize_ = 0;
    Size bssBytes_ = 0;
    struct NativeSectionCheckpoint {
      std::size_t bytes = 0;
      Size memorySize = 0;
    };

    std::size_t customSectionsSize_ = 0;
    std::vector<NativeSectionCheckpoint> customSections_;
    context::Lookup lookup_;
    context::Staging staging_;
    context::Reference reference_;
    context::Source source_;
    context::IOStreams io_;
    std::vector<context::Values::ScopeFrame> valueScopes_;
    int argumentIndex_ = 0;
    bool argumentOptions_ = true;
    bool committed_ = false;
  };
} // namespace recurloop
