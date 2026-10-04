#pragma once

#include <recurloop/Generation.hpp>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace recurloop {
  class Session;

  struct ProjectGeneration {
    GenerationId id = 0;
    std::shared_ptr<const LexiconGeneration> lexicon;
  };

  struct ProjectCacheStamp {
    std::uintmax_t size = 0;
    std::int64_t mtime = 0;
  };

  // One project cache walk. Cached project sources are ordinary linked .rli
  // modules: one source path maps to one image path and images depend on other
  // source images/imported libraries instead of embedding cumulative project
  // checkpoints. A small source stack is kept only while a cache miss is being
  // evaluated so nested includes can be compiled into their own modules.
  struct ProjectCacheState {
    struct Module {
      std::string source;
      ProjectCacheStamp sourceStamp;
      std::unordered_map<std::string, ProjectCacheStamp> dependencies;
      // Engine images that were already materialized when this source module
      // started. They are the exact semantic input of the source and are kept
      // separate from dependencies introduced by the source itself.
      std::vector<std::pair<std::string, ProjectCacheStamp>> inputImages;
      Size segmentUsed = 0;
      std::uint64_t semanticPrefix = 0;
      bool linked = true;
      bool directEntry = true;
    };

    bool enabled = false;
    bool exactRestore = false;
    bool active = false;
    std::size_t step = 0;
    std::unordered_map<std::string, ProjectCacheStamp> observed;
    std::vector<Module> modules;
  };

  // Long-lived project state shared by every transport and session. Published
  // generations are immutable; readers only take a shared_ptr and never block
  // each other while executing against an older generation.
  class Project : public std::enable_shared_from_this<Project> {
  public:
    using ActionEntries = ContextGeneration::ActionEntries;

    static std::shared_ptr<Project> create(context::Context &source, std::vector<std::string> arguments = {});

    std::shared_ptr<const ProjectGeneration> current() const;
    std::shared_ptr<const ProjectGeneration> baseline() const;
    std::shared_ptr<Session> openSession();

    // Publish a portable semantic snapshot of a session. EngineImage encoding
    // rejects live process-local payloads, so a project generation can never
    // accidentally depend on a client's heap/JIT lifetime.
    std::shared_ptr<const ProjectGeneration> publish(context::Context &source);

    // Persistent project source modules. Every .rl file has one cache image and
    // one manifest under <cache>/modules. The image uses normal EngineImage
    // dependency links, so included source modules and imported libraries are
    // loaded transitively rather than copied into cumulative step snapshots.
    void configureCache(std::string directory);
    bool cacheEnabled() const {
      return !cacheModulesDirectory_.empty();
    }
    const std::string &cacheDirectory() const {
      return cacheDirectory_;
    }
    const std::string &cacheModulesDirectory() const {
      return cacheModulesDirectory_;
    }
    // Compatibility for status/output callers that used the old step name.
    const std::string &cacheStepsDirectory() const {
      return cacheModulesDirectory_;
    }
    void beginCache(ProjectCacheState &state, bool exactRestore = false) const;
    bool restoreCacheStep(ProjectCacheState &state, context::Context &context, std::string_view source) noexcept;
    void beginCacheStep(ProjectCacheState &state, std::string_view source, context::Context &context) noexcept;
    void observeCacheSource(ProjectCacheState &state, std::string_view source) noexcept;
    bool restoreCacheNestedModule(ProjectCacheState &state, context::Context &context,
                              std::string_view source) noexcept;
    void beginCacheNestedModule(ProjectCacheState &state, std::string_view source, context::Context &context) noexcept;
    bool commitCacheNestedModule(ProjectCacheState &state, context::Context &context, std::string_view source) noexcept;
    void commitCacheStep(ProjectCacheState &state, context::Context &context) noexcept;
    void beginCacheImageDependency(ProjectCacheState &state, context::Context &context,
                                   std::string_view path) noexcept;
    void completeCacheImageDependency(ProjectCacheState &state, context::Context &context,
                                      std::string_view path) noexcept;
    void abortCacheStep(ProjectCacheState &state) noexcept;

    // Source inspection replays the same root source graph as a normal project
    // build. Cached source images are transparent accelerators: an unchanged
    // branch can be restored from its .rli, while the branch that contains the
    // currently edited source is replayed until that source is reached.
    bool inspectionRoot(std::string_view source, std::string &root) const noexcept;
    bool inspectionModuleContains(std::string_view module, std::string_view source) const noexcept;
    bool restoreInspectionModule(context::Context &context, std::string_view source) const noexcept;
    // Fast inspection entry: restore exactly the engine-image state that was
    // materialized before this source started. Returns false when the module
    // requires source-prefix replay; callers then use the deterministic graph
    // replay fallback instead.
    bool restoreInspectionEntry(context::Context &context, std::string_view source) const noexcept;
    std::uint64_t cacheRevision() const {
      return cacheRevision_.load(std::memory_order_acquire);
    }

    std::uint64_t cacheHits() const {
      return cacheHits_.load(std::memory_order_relaxed);
    }
    std::uint64_t cacheMisses() const {
      return cacheMisses_.load(std::memory_order_relaxed);
    }
    std::uint64_t cacheWrites() const {
      return cacheWrites_.load(std::memory_order_relaxed);
    }

    GenerationId nextId() {
      return nextId_.fetch_add(1, std::memory_order_relaxed);
    }
    const context::Config &config() const {
      return config_;
    }
    const ActionEntries &actions() const {
      return actions_;
    }
    const std::vector<std::string> &arguments() const {
      return arguments_;
    }

  private:
    friend class Session;

    Project(context::Config config, ActionEntries actions, std::vector<std::string> arguments)
        : config_(std::move(config)), actions_(std::move(actions)), arguments_(std::move(arguments)) {}

    std::shared_ptr<const LexiconGeneration> portableLexicon(context::Context &source, GenerationId lexiconId);
    std::shared_ptr<const ProjectGeneration> preparePublication(context::Context &source);
    bool commitPublication(const std::shared_ptr<const ProjectGeneration> &generation);
    std::uint64_t baselineHash() const;

    bool restoreCacheModule(ProjectCacheState &state, context::Context &context, std::string_view source,
                            bool nested) noexcept;
    void beginCacheModule(ProjectCacheState &state, context::Context &context, std::string_view source) noexcept;
    bool commitCacheModule(ProjectCacheState &state, context::Context &context, std::string_view source,
                           bool nested) noexcept;
    void beforeCacheDependency(ProjectCacheState &state, context::Context &context) noexcept;
    void afterCacheDependency(ProjectCacheState &state, context::Context &context) noexcept;
    std::string cacheModuleImagePath(std::string_view source) const;
    std::string cacheModuleManifestPath(std::string_view source) const;
    void rememberCacheEntrySource(std::string_view source) noexcept;

    context::Config config_;
    ActionEntries actions_;
    std::vector<std::string> arguments_;
    mutable std::shared_mutex generationMutex_;
    std::mutex publishMutex_;
    std::shared_ptr<const ProjectGeneration> baseline_;
    std::shared_ptr<const ProjectGeneration> current_;

    std::atomic<GenerationId> nextId_{1};
    std::string cacheDirectory_;
    std::string cacheModulesDirectory_;
    std::string cacheSourceRoot_;
    mutable std::mutex cacheGraphMutex_;
    std::string cacheEntrySource_;
    mutable std::uint64_t cacheBaselineHash_ = 0;
    mutable std::mutex cacheBaselineMutex_;
    std::atomic<std::uint64_t> cacheHits_{0};
    std::atomic<std::uint64_t> cacheMisses_{0};
    std::atomic<std::uint64_t> cacheWrites_{0};
    std::atomic<std::uint64_t> cacheTemporaryId_{1};
    std::atomic<std::uint64_t> cacheRevision_{1};
  };
} // namespace recurloop
