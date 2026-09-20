#pragma once

#include <recurloop/Generation.hpp>

#include <atomic>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <vector>

namespace recurloop {
  class Session;

  struct ProjectGeneration {
    GenerationId id = 0;
    std::shared_ptr<const LexiconGeneration> lexicon;
  };

  // Long-lived project state shared by every transport and session.  Published
  // generations are immutable; readers only take a shared_ptr and never block
  // each other while executing against an older generation.
  class Project : public std::enable_shared_from_this<Project> {
  public:
    using ActionEntries = ContextGeneration::ActionEntries;

    static std::shared_ptr<Project> create(context::Context &source, std::vector<std::string> arguments = {});

    std::shared_ptr<const ProjectGeneration> current() const;
    std::shared_ptr<Session> openSession();

    // Publish a portable semantic snapshot of a session.  EngineImage encoding
    // rejects live process-local payloads, so a project generation can never
    // accidentally depend on a client's heap/JIT lifetime.
    std::shared_ptr<const ProjectGeneration> publish(context::Context &source);

    GenerationId nextId() { return nextId_.fetch_add(1, std::memory_order_relaxed); }
    const context::Config &config() const { return config_; }
    const ActionEntries &actions() const { return actions_; }
    const std::vector<std::string> &arguments() const { return arguments_; }

  private:
    Project(context::Config config, ActionEntries actions, std::vector<std::string> arguments)
        : config_(std::move(config)), actions_(std::move(actions)), arguments_(std::move(arguments)) {}

    std::shared_ptr<const LexiconGeneration> portableLexicon(context::Context &source, GenerationId lexiconId);

    context::Config config_;
    ActionEntries actions_;
    std::vector<std::string> arguments_;
    mutable std::shared_mutex generationMutex_;
    std::mutex publishMutex_;
    std::shared_ptr<const ProjectGeneration> current_;
    std::atomic<GenerationId> nextId_{1};
  };
} // namespace recurloop
