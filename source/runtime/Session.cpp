#include <recurloop/Session.hpp>

#include <recurloop/Execution.hpp>
#include <recurloop/NativeIO.hpp>
#include <recurloop/Project.hpp>
#include <recurloop/SessionRequest.hpp>
#include <recurloop/Semantic.hpp>
#include <recurloop/Targets.hpp>
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

    std::string hexText(std::string_view value) {
      static constexpr char digits[] = "0123456789abcdef";
      std::string result;
      result.reserve(value.size() * 2);
      for (const unsigned char byte : value) {
        result.push_back(digits[byte >> 4]);
        result.push_back(digits[byte & 0x0f]);
      }
      return result;
    }

    void stopCurrentSource(context::Context &context) noexcept {
      context.source.buffer.bits = 0;
      context.source.more = false;
    }

    struct InspectionReplayState {
      std::shared_ptr<Project> project;
      std::string targetPath;
      std::string targetSource;
      bool cacheBacked = false;
      bool insideTarget = false;
      bool reached = false;
      std::string diagnostic;
      std::unique_ptr<Semantic::InspectionScope> inspection;
    };

    std::string absolutePath(std::string_view path) {
      if (path.empty() || path.front() == '<') return std::string(path);
      namespace fs = std::filesystem;
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(path), error).lexically_normal().string();
      return error ? std::string(path) : absolute;
    }

    bool replayInspectionSource(context::Context &context, InspectionReplayState &state, std::string_view root, bool direct) {
      const auto executeTarget = [&](context::Context &targetContext) {
        state.inspection = std::make_unique<Semantic::InspectionScope>(targetContext, state.targetSource, state.targetPath);
        state.insideTarget = true;
        try {
          executeSource(targetContext, state.targetSource, state.targetPath, 1, 1);
        } catch (const Exception &error) {
          state.diagnostic = describe(error);
        } catch (const std::exception &error) {
          state.diagnostic = std::string("<inspection>:1:1: ") + error.what();
        } catch (...) {
          state.diagnostic = "<inspection>:1:1: unknown internal error";
        }
        state.insideTarget = false;
        state.reached = true;
      };

      if (!state.cacheBacked) {
        // Standalone inspection processes includes/imports against the current
        // session state, using the same rollback boundary as other source.
        executeTarget(context);
        return true;
      }

      // Includes inside the inspected buffer still use the ordinary .rl -> .rli
      // cache. This matters especially for root files with many dependencies: replaying
      // every included source on every request would throw away most of the
      // project cache benefit even though the target entry itself is prepared.
      SourceObserverScope observer(
          &state,
          [](void *user, context::Context &sourceContext, std::string_view) {
            auto *state = static_cast<InspectionReplayState *>(user);
            if (state->reached && !state->insideTarget) stopCurrentSource(sourceContext);
          },
          [](void *user, context::Context &nestedContext, std::string_view nestedSource) {
            auto *state = static_cast<InspectionReplayState *>(user);
            const std::string nestedPath = absolutePath(nestedSource);

            if (state->insideTarget) {
              if (state->project->restoreInspectionModule(nestedContext, nestedPath)) {
                Semantic::markInspectionMetadataDirty(nestedContext);
                return true;
              }
              return false;
            }
            if (state->reached) return true;
            if (nestedPath == state->targetPath) {
              state->inspection = std::make_unique<Semantic::InspectionScope>(nestedContext, state->targetSource,
                                                                               state->targetPath);
              state->insideTarget = true;
              try {
                executeSource(nestedContext, state->targetSource, state->targetPath, 1, 1);
              } catch (const Exception &error) {
                state->diagnostic = describe(error);
              } catch (const std::exception &error) {
                state->diagnostic = std::string("<inspection>:1:1: ") + error.what();
              } catch (...) {
                state->diagnostic = "<inspection>:1:1: unknown internal error";
              }
              state->insideTarget = false;
              state->reached = true;
              stopCurrentSource(nestedContext);
              return true;
            }

            // Only replay branches that lead to the target. Every other
            // unchanged include is restored from its ordinary module .rli.
            if (state->project->inspectionModuleContains(nestedPath, state->targetPath)) return false;
            if (state->project->restoreInspectionModule(nestedContext, nestedPath)) return true;
            return false;
          },
          nullptr);

      // Fast path: Project restored the exact state at source entry from the
      // ordinary .rl -> .rli cache. The target buffer is the only source that
      // must be elaborated; nested includes are handled by the observer above
      // and normally become cheap image loads. RequestGeneration rolls all of
      // this back to the prepared entry state after the request.
      if (direct) {
        executeTarget(context);
        return true;
      }

      const std::string rootPath = absolutePath(root);
      if (rootPath == state.targetPath) {
        executeTarget(context);
        return true;
      }

      std::ifstream input(rootPath, std::ios::binary);
      if (!input.is_open()) return false;
      try {
        executeStream(context, input, rootPath, 1, 1);
      } catch (const Exception &error) {
        if (!state.reached) state.diagnostic = std::string("project replay failed before source: ") + describe(error);
      } catch (const std::exception &error) {
        if (!state.reached) state.diagnostic = std::string("project replay failed before source: ") + error.what();
      } catch (...) {
        if (!state.reached) state.diagnostic = "project replay failed before source";
      }
      return state.reached && state.inspection != nullptr;
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
    consoleHighlighter_.reset();
    contextGeneration_ = std::make_unique<ContextGeneration>(projectGeneration_->lexicon, project_->config(),
                                                             project_->actions(), project_->arguments(),
                                                             projectGeneration_->id, contextId, sessionGeneration);
    inspectionContextGeneration_.reset();
    standaloneInspectionContextGeneration_.reset();
    inspectionProjectGeneration_.reset();
    inspectionPreparedPath_.clear();
    inspectionPreparedRoot_.clear();
    inspectionPreparedRevision_ = 0;
    inspectionPreparedDirect_ = false;
  }

  bool Session::prepareInspectionReplay(std::string_view path, std::string &root, bool &direct) {
    root.clear();
    direct = false;
    if (!project_->cacheEnabled()) return true;

    const std::string pathCopy = absolutePath(path);
    const std::uint64_t revision = project_->cacheRevision();
    if (!project_->inspectionRoot(pathCopy, root)) return false;
    if (inspectionPreparedRevision_ == revision && inspectionPreparedPath_ == pathCopy &&
        inspectionPreparedRoot_ == root) {
      root = inspectionPreparedRoot_;
      direct = inspectionPreparedDirect_;
      return true;
    }

    auto base = project_->baseline();
    if (!base || !base->lexicon) return false;
    inspectionProjectGeneration_ = base;
    inspectionContextGeneration_ =
        std::make_unique<ContextGeneration>(base->lexicon, project_->config(), project_->actions(),
                                            project_->arguments(), base->id, project_->nextId(), project_->nextId());

    direct = project_->restoreInspectionEntry(inspectionContextGeneration_->context(), pathCopy);
    inspectionPreparedPath_ = pathCopy;
    inspectionPreparedRoot_ = root;
    inspectionPreparedRevision_ = revision;
    inspectionPreparedDirect_ = direct;
    return true;
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
    NativeIO::Scope nativeIo({nullptr, requestOut, requestErr});
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
          if (dependencies.empty()) dependencies = project_->processingSources();
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

  SessionResponse Session::evaluate(std::string_view source, std::string_view path, std::ostream *out, std::ostream *err) {
    const std::string sourceCopy(source);
    const std::string pathCopy(path.empty() ? "<session>" : path);
    return runRequest([&](context::Context &context) { executeSource(context, sourceCopy, pathCopy, 1, 1); }, out, err);
  }

  SessionResponse Session::inspect(std::string_view source, std::string_view path, bool trace, bool standalone) {
    std::lock_guard lock(mutex_);
    const std::string sourceCopy(source);
    const std::string pathCopy = absolutePath(path.empty() ? "<inspection>" : path);
    std::string root;
    bool direct = false;

    if (!standalone && !prepareInspectionReplay(pathCopy, root, direct)) {
      SessionResponse response;
      response.status = 0;
      response.output = "O\t\nE\t" + hexText("source is outside the current project processing graph; semantic analysis is unavailable") + "\n";
      response.generations = contextGeneration_->generations();
      return response;
    }

    if (standalone) {
      const auto base = project_->baseline();
      // RequestGeneration restores this context after every inspection. Keep
      // its mappings/workspace across keystrokes, but recreate it whenever the
      // immutable baseline changes; no analyzed buffer becomes cached state.
      if (!standaloneInspectionContextGeneration_ ||
          standaloneInspectionContextGeneration_->lexiconGeneration() != base->lexicon) {
        standaloneInspectionContextGeneration_ = std::make_unique<ContextGeneration>(
            base->lexicon, project_->config(), project_->actions(), project_->arguments(),
            base->id, project_->nextId(), project_->nextId());
      }
    }
    ContextGeneration &inspectionGeneration =
        standalone ? *standaloneInspectionContextGeneration_
                   : (project_->cacheEnabled() ? *inspectionContextGeneration_ : *contextGeneration_);
    context::Context &context = inspectionGeneration.context();
    const GenerationId requestId = project_->nextId();
    Generations &generations = inspectionGeneration.generations();
    RequestGeneration request(context, generations, requestId, rollbackBuffer_);
    SessionRequestState sessionRequest;
    SessionRequestScope requestScope(sessionRequest);
    std::ostringstream discardedOutput;
    std::ostringstream discardedErrors;
    const context::IOStreams previousIo = context.io;
    context.io = {nullptr, &discardedOutput, &discardedErrors};
    NativeIO::Scope nativeIo(context.io);
    context.exec.status = 0;
    struct RestoreRequestIO {
      context::Context &context;
      context::IOStreams previous;
      ~RestoreRequestIO() {
        context.io = previous;
        context.exec.status = 0;
      }
    } restoreIO{context, previousIo};

    InspectionReplayState replay{project_, pathCopy, sourceCopy, !standalone && project_->cacheEnabled()};
    const bool available = replayInspectionSource(context, replay, root, direct);

    SessionResponse response;
    if (!available || !replay.inspection) {
      const std::string message = replay.diagnostic.empty()
                                      ? "source is outside the current project processing graph; semantic analysis is unavailable"
                                      : replay.diagnostic;
      response.output = "O\t\nE\t" + hexText(message) + "\n";
    } else {
      response.output = replay.inspection->encode(replay.diagnostic);
      if (trace) response.output += replay.inspection->trace();
    }
    replay.inspection.reset();
    request.rollback();
    context.io = previousIo;
    context.exec.status = 0;
    response.status = 0;
    response.generations = inspectionGeneration.generations();
    return response;
  }

  std::string Session::highlight(std::string_view line) {
    std::lock_guard lock(mutex_);
    if (line.empty() || line.size() > 8192) return {};
    const auto generation = contextGeneration_->generations().session;
    if (!consoleHighlighter_ || consolePaletteGeneration_ != generation) {
      consoleHighlighter_ = std::make_unique<Semantic::ConsoleHighlighter>(contextGeneration_->context());
      consolePaletteGeneration_ = generation;
    }
    return consoleHighlighter_->highlight(line);
  }

  SessionResponse Session::executeFile(const std::string &path, std::ostream *out, std::ostream *err) {
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
    }, out, err);

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

  SessionResponse Session::projectTargets() {
    return runRequest([](context::Context &context) { *context.io.out << Targets::describe(Targets::read(context)); });
  }

  SessionResponse Session::runTarget(std::string_view name, bool prepareDebug, std::ostream *out, std::ostream *err) {
    return runRequest(
        [&](context::Context &context) {
          const auto target = Targets::run(context, name, prepareDebug);
          if (prepareDebug) *context.io.out << Targets::describe({target});
        },
        out, err);
  }

  SessionResponse Session::debugTarget(std::string_view name, std::ostream *out, std::ostream *err) {
    return runRequest(
        [&](context::Context &context) {
          const auto target = Targets::run(context, name, true);
          const bool native = !target.debugExecutable.empty();
          const auto &entry = native ? target.debugExecutable : target.debugProgram;
          // Paths are data. Encode them as a source literal without allowing code injection.
          std::string literal = "\"";
          for (const char ch : entry) {
            if (ch == '\\' || ch == '"') literal += '\\';
            if (ch == '\n')
              literal += "\\n";
            else if (ch == '\r')
              literal += "\\r";
            else if (ch == '\t')
              literal += "\\t";
            else
              literal += ch;
          }
          literal += '"';
          executeSource(context, std::string(native ? "debug:executable run " : "debug:run ") + literal + '\n',
                        "<project-debug>", 1, 1);
        },
        out, err);
  }

  utilities::Completion Session::complete(std::string_view line, std::size_t cursor) {
    std::lock_guard lock(mutex_);
    // User-defined completion providers can change language metadata.
    consoleHighlighter_.reset();
    return context::Source::complete(contextGeneration_->context(), line, cursor);
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
