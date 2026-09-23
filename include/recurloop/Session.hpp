#pragma once

#include <recurloop/Generation.hpp>
#include <recurloop/Project.hpp>

#include <functional>
#include <iosfwd>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace recurloop {

  struct SessionResponse {
    int status = 0;
    bool quit = false;
    std::string output;
    std::string error;
    Generations generations;
  };

  // One client-local mutable language state.  Sessions never share Context;
  // only their immutable project lexicon pages are shared through MAP_PRIVATE.
  class Session : public std::enable_shared_from_this<Session> {
  public:
    Session(std::shared_ptr<Project> project, std::shared_ptr<const ProjectGeneration> base, GenerationId sessionId);
    Session(const Session &) = delete;
    Session &operator=(const Session &) = delete;

    GenerationId id() const {
      return id_;
    }
    SessionResponse evaluate(std::string_view source, std::string_view path = {});
    // Elaborate source for editor semantics and always roll the request back.
    // Syntax errors are returned as diagnostics together with any spans that
    // were discovered before the error.
    SessionResponse inspect(std::string_view source, std::string_view path = {});
    SessionResponse executeFile(const std::string &path);
    SessionResponse executeArguments(int startIndex, std::ostream *out = nullptr, std::ostream *err = nullptr);
    Generations generations() const;

    void refresh();
    std::shared_ptr<const ProjectGeneration> publish();

  private:
    using Operation = std::function<void(context::Context &)>;

    void attach(std::shared_ptr<const ProjectGeneration> generation);
    SessionResponse runRequest(const Operation &operation, std::ostream *out = nullptr, std::ostream *err = nullptr);
    SessionResponse failure(int status, std::string error) const;

    std::shared_ptr<Project> project_;
    GenerationId id_ = 0;
    mutable std::mutex mutex_;
    std::shared_ptr<const ProjectGeneration> projectGeneration_;
    std::shared_ptr<const ProjectGeneration> preparedPublication_;
    std::unique_ptr<ContextGeneration> contextGeneration_;
    std::vector<std::uint8_t> rollbackBuffer_;
    bool cacheEnabled_ = false;
    ProjectCacheState cacheState_;
  };
} // namespace recurloop
