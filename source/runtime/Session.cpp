#include <recurloop/Session.hpp>

#include <recurloop/Execution.hpp>
#include <recurloop/Project.hpp>
#include <recurloop/SessionRequest.hpp>
#include <recurloop/Semantic.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace recurloop {
  namespace {
    std::string describe(const Exception &error) {
      std::ostringstream stream;
      if (!error.hasSourceLocation()) stream << "<session>:1:1: ";
      stream << error.description();
      return stream.str();
    }

    std::string generationText(const Generations &generation) {
      std::ostringstream output;
      output << "project=" << generation.project << " lexicon=" << generation.lexicon
             << " context=" << generation.context << " session=" << generation.session
             << " request=" << generation.request;
      return output.str();
    }
  } // namespace

  Session::Session(std::shared_ptr<Project> project, std::shared_ptr<const ProjectGeneration> base,
                   GenerationId sessionId)
      : project_(std::move(project)), id_(sessionId) {
    attach(std::move(base));
  }

  void Session::attach(std::shared_ptr<const ProjectGeneration> generation) {
    if (!generation || !generation->lexicon) THROW(, "session requires a published project generation")
    projectGeneration_ = std::move(generation);
    preparedPublication_.reset();
    const GenerationId contextId = project_->nextId();
    const GenerationId sessionGeneration = project_->nextId();
    contextGeneration_ = std::make_unique<ContextGeneration>(projectGeneration_->lexicon, project_->config(),
                                                             project_->actions(), project_->arguments(),
                                                             projectGeneration_->id, contextId, sessionGeneration);
  }

  SessionResponse Session::failure(int status, std::string error) const {
    SessionResponse response;
    response.status = status;
    response.error = std::move(error);
    if (contextGeneration_) response.generations = contextGeneration_->generations();
    return response;
  }

  SessionResponse Session::runRequest(const Operation &operation, std::ostream *out, std::ostream *err) {
    std::lock_guard lock(mutex_);
    std::ostringstream capturedOutput;
    std::ostringstream capturedErrors;
    std::ostream *const requestOut = out != nullptr ? out : &capturedOutput;
    std::ostream *const requestErr = err != nullptr ? err : &capturedErrors;
    SessionRequestState sessionRequest;
    SessionResponse response;

    {
      context::Context &context = contextGeneration_->context();
      const GenerationId requestId = project_->nextId();
      Generations &generations = contextGeneration_->generations();
      RequestGeneration request(context, generations, requestId, rollbackBuffer_);
      SessionRequestScope requestScope(sessionRequest);
      const context::IOStreams previousIo = context.io;
      context.io = {nullptr, requestOut, requestErr};
      context.exec.status = 0;

      try {
        operation(context);
        request.commit();
        generations.lexicon = project_->nextId();
        generations.session = project_->nextId();
        context.exec.pendingException = nullptr;
        context.exec.invoked = nullptr;
        response.status = context.exec.status;
        context.io = previousIo;
      } catch (const Exception &error) {
        const int status = error.status();
        request.rollback();
        context.io = previousIo;
        requestOut->flush();
        requestErr->flush();
        std::string text = err == nullptr ? capturedErrors.str() : std::string{};
        if (!text.empty() && text.back() != '\n') text.push_back('\n');
        text += describe(error);
        return failure(status, std::move(text));
      } catch (const std::exception &error) {
        request.rollback();
        context.io = previousIo;
        requestOut->flush();
        requestErr->flush();
        std::string text = err == nullptr ? capturedErrors.str() : std::string{};
        if (!text.empty() && text.back() != '\n') text.push_back('\n');
        text += std::string("<session>:1:1: ") + error.what();
        return failure(1, std::move(text));
      } catch (...) {
        request.rollback();
        context.io = previousIo;
        requestOut->flush();
        requestErr->flush();
        return failure(1, "<session>:1:1: unknown internal error");
      }
    }

    try {
      for (const SessionCommand command : sessionRequest.commands) {
        switch (command) {
        case SessionCommand::Generations:
          *requestOut << generationText(contextGeneration_->generations()) << '\n';
          break;
        case SessionCommand::Publish: {
          auto generation = project_->publish(contextGeneration_->context());
          attach(generation);
          *requestOut << "published project=" << generation->id << " lexicon=" << generation->lexicon->id() << '\n';
          break;
        }
        case SessionCommand::PreparePublish: {
          preparedPublication_ = project_->preparePublication(contextGeneration_->context());
          *requestOut << "prepared project=" << preparedPublication_->id
                      << " lexicon=" << preparedPublication_->lexicon->id() << '\n';
          break;
        }
        case SessionCommand::CommitPublish: {
          auto generation = preparedPublication_;
          if (!generation) THROW(, "no prepared project generation is available")
          if (!project_->commitPublication(generation)) {
            preparedPublication_.reset();
            THROW(, "a newer project generation was published before the prepared generation")
          }
          attach(generation);
          *requestOut << "published project=" << generation->id << " lexicon=" << generation->lexicon->id() << '\n';
          break;
        }
        case SessionCommand::Refresh:
          attach(project_->current());
          *requestOut << "refreshed " << generationText(contextGeneration_->generations()) << '\n';
          break;
        case SessionCommand::Baseline:
          attach(project_->baseline());
          *requestOut << "baseline " << generationText(contextGeneration_->generations()) << '\n';
          break;
        case SessionCommand::Cache:
          cacheEnabled_ = project_->cacheEnabled();
          contextGeneration_->context().exec.quickCompile = cacheEnabled_;
          if (cacheEnabled_) project_->beginCache(cacheState_);
          *requestOut << "cache=" << (cacheEnabled_ ? "enabled" : "disabled") << '\n';
          break;
        case SessionCommand::CacheExact:
          cacheEnabled_ = project_->cacheEnabled();
          contextGeneration_->context().exec.quickCompile = cacheEnabled_;
          if (cacheEnabled_) project_->beginCache(cacheState_, true);
          *requestOut << "cache=" << (cacheEnabled_ ? "exact" : "disabled") << '\n';
          break;
        case SessionCommand::CacheStatus:
          *requestOut << "cache=" << (project_->cacheEnabled() ? "enabled" : "disabled")
                      << " active=" << (cacheEnabled_ ? "yes" : "no")
                      << " mode=modules files=" << cacheState_.step
                      << " hits=" << project_->cacheHits() << " misses=" << project_->cacheMisses()
                      << " writes=" << project_->cacheWrites();
          if (project_->cacheEnabled()) *requestOut << " directory=" << project_->cacheModulesDirectory();
          *requestOut << '\n';
          break;
        case SessionCommand::CacheDependencies: {
          std::vector<std::string> dependencies;
          dependencies.reserve(cacheState_.observed.size());
          for (const auto &[path, stamp] : cacheState_.observed) {
            (void)stamp;
            dependencies.push_back(path);
          }
          std::sort(dependencies.begin(), dependencies.end());
          for (const std::string &path : dependencies) *requestOut << path << '\n';
          break;
        }
        case SessionCommand::Help:
          *requestOut << "phrases: :generations, :publish, :publish-prepare, :publish-commit, :refresh, :baseline, "
                         ":cache, :cache-exact, :cache-status, "
                         ":cache-dependencies, :load \"<path>\", :quit, :exit\n";
          break;
        case SessionCommand::Quit: response.quit = true; break;
        }
      }
    } catch (const Exception &error) {
      requestOut->flush();
      requestErr->flush();
      std::string text = err == nullptr ? capturedErrors.str() : std::string{};
      if (!text.empty() && text.back() != '\n') text.push_back('\n');
      text += describe(error);
      return failure(error.status(), std::move(text));
    } catch (const std::exception &error) {
      requestOut->flush();
      requestErr->flush();
      std::string text = err == nullptr ? capturedErrors.str() : std::string{};
      if (!text.empty() && text.back() != '\n') text.push_back('\n');
      text += std::string("<session>:1:1: ") + error.what();
      return failure(1, std::move(text));
    }

    requestOut->flush();
    requestErr->flush();
    if (out == nullptr) response.output = capturedOutput.str();
    if (err == nullptr) response.error = capturedErrors.str();
    response.generations = contextGeneration_->generations();
    return response;
  }

  SessionResponse Session::evaluate(std::string_view source, std::string_view path) {
    const std::string sourceCopy(source);
    const std::string pathCopy(path.empty() ? "<session>" : path);
    return runRequest([&](context::Context &context) { executeSource(context, sourceCopy, pathCopy, 1, 1); });
  }

  SessionResponse Session::inspect(std::string_view source, std::string_view path) {
    std::lock_guard lock(mutex_);
    const std::string sourceCopy(source);
    const std::string pathCopy(path.empty() ? "<ide>" : path);

    // Source intelligence follows the newest published project generation
    // without depending on an IDE-side :refresh race. Reattach only when the
    // project actually changed; ordinary keystrokes reuse the same private COW
    // context and RequestGeneration restores it after every inspection.
    std::shared_ptr<const ProjectGeneration> current = project_->current();
    if (!projectGeneration_ || !current || projectGeneration_->id != current->id) attach(std::move(current));
    context::Context &context = contextGeneration_->context();
    const GenerationId requestId = project_->nextId();
    Generations &generations = contextGeneration_->generations();
    RequestGeneration request(context, generations, requestId, rollbackBuffer_);
    SessionRequestState sessionRequest;
    SessionRequestScope requestScope(sessionRequest);
    std::ostringstream discardedOutput;
    std::ostringstream discardedErrors;
    const context::IOStreams previousIo = context.io;
    context.io = {nullptr, &discardedOutput, &discardedErrors};
    context.exec.status = 0;

    Semantic::InspectionScope inspection(context, sourceCopy, pathCopy);
    std::string diagnostic;
    try {
      executeSource(context, sourceCopy, pathCopy, 1, 1);
    } catch (const Exception &error) {
      diagnostic = describe(error);
    } catch (const std::exception &error) {
      diagnostic = std::string("<ide>:1:1: ") + error.what();
    } catch (...) {
      diagnostic = "<ide>:1:1: unknown internal error";
    }

    SessionResponse response;
    response.output = inspection.encode(diagnostic);
    request.rollback();
    context.io = previousIo;
    context.exec.status = 0;
    response.status = 0;
    response.generations = contextGeneration_->generations();
    return response;
  }

  SessionResponse Session::executeFile(const std::string &path) {
    const std::string absolute = std::filesystem::absolute(path).lexically_normal().string();
    bool restored = false;
    bool started = false;
    SessionResponse response = runRequest([&](context::Context &context) {
      if (cacheEnabled_ && project_->restoreCacheStep(cacheState_, context, absolute)) {
        restored = true;
        return;
      }

      std::ifstream input(absolute, std::ios::binary);
      if (!input.is_open()) THROW(, "cannot open file '" << absolute << "'")
      if (!cacheEnabled_) {
        executeStream(context, input, absolute, 1, 1);
        return;
      }

      project_->beginCacheStep(cacheState_, absolute, context);
      started = cacheState_.active;
      struct CacheObserverBridge {
        Session *session;
      } bridge{this};
      SourceObserverScope observer(
          &bridge,
          [](void *user, context::Context &context, std::string_view source) {
            auto *bridge = static_cast<CacheObserverBridge *>(user);
            if (!bridge->session->project_->commitCacheNestedModule(bridge->session->cacheState_, context, source))
              bridge->session->project_->observeCacheSource(bridge->session->cacheState_, source);
          },
          [](void *user, context::Context &context, std::string_view source) {
            auto *bridge = static_cast<CacheObserverBridge *>(user);
            if (bridge->session->project_->restoreCacheNestedModule(bridge->session->cacheState_, context, source))
              return true;
            bridge->session->project_->beginCacheNestedModule(bridge->session->cacheState_, source, context);
            return false;
          },
          [](void *user, context::Context &context, std::string_view path, bool complete) {
            auto *bridge = static_cast<CacheObserverBridge *>(user);
            if (complete)
              bridge->session->project_->completeCacheImageDependency(bridge->session->cacheState_, context, path);
            else
              bridge->session->project_->beginCacheImageDependency(bridge->session->cacheState_, context, path);
          });
      executeStream(context, input, absolute, 1, 1);
    });

    if (restored) return response;
    if (!started) return response;
    if (response.status == 0)
      project_->commitCacheStep(cacheState_, contextGeneration_->context());
    else
      project_->abortCacheStep(cacheState_);
    return response;
  }

  SessionResponse Session::executeArguments(int startIndex, std::ostream *out, std::ostream *err) {
    return runRequest(
        [&](context::Context &context) {
          if (startIndex < 0 || startIndex > context.exec.args.count)
            THROW(, "invalid source argument index " << startIndex)
          context.exec.args.index = startIndex;
          context.exec.args.options = true;
          context.io.in = nullptr;
          context.source = {"", 1, 1, true, {}};
          executeInputs(context);
        },
        out, err);
  }

  Generations Session::generations() const {
    std::lock_guard lock(mutex_);
    return contextGeneration_->generations();
  }

  void Session::refresh() {
    std::lock_guard lock(mutex_);
    attach(project_->current());
  }

  std::shared_ptr<const ProjectGeneration> Session::publish() {
    std::lock_guard lock(mutex_);
    auto generation = project_->publish(contextGeneration_->context());
    // Reattach to the sanitized published image.  This intentionally drops
    // session-local JIT/native caches so the publishing client observes exactly
    // the same portable state that new clients receive.
    attach(generation);
    return generation;
  }
} // namespace recurloop
