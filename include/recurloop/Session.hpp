#pragma once

#include <recurloop/Generation.hpp>
#include <recurloop/Project.hpp>
#include <recurloop/Semantic.hpp>
#include <utilities/Completion.hpp>

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
    SessionResponse evaluate(std::string_view source, std::string_view path = {}, std::ostream *out = nullptr,
                             std::ostream *err = nullptr);
    // Elaborate source for inspection and always roll the request back.
    // Syntax errors are returned as diagnostics together with any spans that
    // were discovered before the error.
    // Standalone targets start at the immutable baseline rather than replaying
    // the published project's processing graph.
    SessionResponse inspect(std::string_view source, std::string_view path = {}, bool trace = false,
                            bool standalone = false);
    SessionResponse executeFile(const std::string &path, std::ostream *out = nullptr, std::ostream *err = nullptr);
    SessionResponse executeArguments(int startIndex, std::ostream *out = nullptr, std::ostream *err = nullptr);
    SessionResponse projectTargets();
    SessionResponse runTarget(std::string_view name, bool prepareDebug = false, std::ostream *out = nullptr,
                              std::ostream *err = nullptr);
    SessionResponse debugTarget(std::string_view name, std::ostream *out = nullptr, std::ostream *err = nullptr);
    utilities::Completion complete(std::string_view line, std::size_t cursor);
    // Color console input from this session's metadata without elaborating it.
    std::string highlight(std::string_view line);
    Generations generations() const;

    void refresh();
    std::shared_ptr<const ProjectGeneration> publish();

  private:
    using Operation = std::function<void(context::Context &)>;

    void attach(std::shared_ptr<const ProjectGeneration> generation);
    bool prepareInspectionReplay(std::string_view path, std::string &root, bool &direct);
    SessionResponse runRequest(const Operation &operation, std::ostream *out = nullptr, std::ostream *err = nullptr);
    SessionResponse failure(int status, std::string error) const;

    std::shared_ptr<Project> project_;
    GenerationId id_ = 0;
    mutable std::mutex mutex_;
    std::shared_ptr<const ProjectGeneration> projectGeneration_;
    std::shared_ptr<const ProjectGeneration> preparedPublication_;
    std::unique_ptr<ContextGeneration> contextGeneration_;
    std::shared_ptr<const ProjectGeneration> inspectionProjectGeneration_;
    std::unique_ptr<ContextGeneration> inspectionContextGeneration_;
    std::unique_ptr<ContextGeneration> standaloneInspectionContextGeneration_;
    std::vector<std::uint8_t> rollbackBuffer_;
    std::unique_ptr<Semantic::ConsoleHighlighter> consoleHighlighter_;
    GenerationId consolePaletteGeneration_ = 0;
    bool cacheEnabled_ = false;
    ProjectCacheState cacheState_;
    std::string inspectionPreparedPath_;
    std::string inspectionPreparedRoot_;
    std::uint64_t inspectionPreparedRevision_ = 0;
    bool inspectionPreparedDirect_ = false;
  };
} // namespace recurloop
