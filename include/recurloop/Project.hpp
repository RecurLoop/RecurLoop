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

  // One deterministic cache walk belongs to one build session. Direct project
  // loads are full fast-path checkpoints; nested includes add graph-fragment
  // resume boundaries and contribute their transitive dependency stamps.
  struct ProjectCacheState {
    struct Fragment {
      std::uint64_t inputChain = 0;
      std::string source;
      ProjectCacheStamp sourceStamp;
      std::unordered_map<std::string, ProjectCacheStamp> dependencies;
    };

    bool enabled = false;
    bool active = false;
    std::size_t step = 0;
    std::uint64_t chain = 0;
    std::uint64_t inputChain = 0;
    std::string source;
    ProjectCacheStamp sourceStamp;
    std::unordered_map<std::string, ProjectCacheStamp> dependencies;
    std::unordered_map<std::string, ProjectCacheStamp> observed;
    std::uint64_t fragmentChain = 0;
    std::vector<Fragment> fragments;
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

    // Persistent project source checkpoints. The shared project.rli remains the
    // immutable baseline; the workspace cache stores cumulative, self-contained
    // semantic .rli checkpoints after each direct project source file. A later
    // build restores the longest still-valid prefix and only evaluates files
    // from the first invalid step.
    void configureCache(std::string directory);
    bool cacheEnabled() const {
      return !cacheStepsDirectory_.empty();
    }
    const std::string &cacheDirectory() const {
      return cacheDirectory_;
    }
    const std::string &cacheStepsDirectory() const {
      return cacheStepsDirectory_;
    }
    void beginCache(ProjectCacheState &state) const;
    bool restoreCacheStep(ProjectCacheState &state, context::Context &context, std::string_view source) noexcept;
    void beginCacheStep(ProjectCacheState &state, std::string_view source) noexcept;
    void observeCacheSource(ProjectCacheState &state, std::string_view source) noexcept;
    bool restoreCacheFragment(ProjectCacheState &state, context::Context &context, std::string_view source) noexcept;
    void beginCacheFragment(ProjectCacheState &state, std::string_view source) noexcept;
    bool commitCacheFragment(ProjectCacheState &state, context::Context &context, std::string_view source) noexcept;
    void commitCacheStep(ProjectCacheState &state, context::Context &context) noexcept;
    void abortCacheStep(ProjectCacheState &state) noexcept;

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

    context::Config config_;
    ActionEntries actions_;
    std::vector<std::string> arguments_;
    mutable std::shared_mutex generationMutex_;
    std::mutex publishMutex_;
    std::shared_ptr<const ProjectGeneration> baseline_;
    std::shared_ptr<const ProjectGeneration> current_;

    std::atomic<GenerationId> nextId_{1};
    std::string cacheDirectory_;
    std::string cacheStepsDirectory_;
    std::string cacheFragmentsDirectory_;
    mutable std::uint64_t cacheBaselineHash_ = 0;
    mutable std::mutex cacheBaselineMutex_;
    std::atomic<std::uint64_t> cacheHits_{0};
    std::atomic<std::uint64_t> cacheMisses_{0};
    std::atomic<std::uint64_t> cacheWrites_{0};
    std::atomic<std::uint64_t> cacheTemporaryId_{1};
  };
} // namespace recurloop
