#include <recurloop/Project.hpp>

#include <recurloop/ContextApi.hpp>
#include <recurloop/EmbeddedCore.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Session.hpp>

namespace recurloop {
  std::shared_ptr<Project> Project::create(context::Context &source, std::vector<std::string> arguments) {
    if (arguments.empty() && source.exec.args.ptr != nullptr) {
      arguments.reserve(source.exec.args.count);
      for (int i = 0; i < source.exec.args.count; ++i)
        arguments.emplace_back(source.exec.args.ptr[i] != nullptr ? source.exec.args.ptr[i] : "");
    }
    auto project = std::shared_ptr<Project>(
        new Project(source.config, source.actions().snapshot(), std::move(arguments)));
    const GenerationId projectId = project->nextId();
    const GenerationId lexiconId = project->nextId();
    auto lexicon = project->portableLexicon(source, lexiconId);
    project->current_ = std::make_shared<ProjectGeneration>(ProjectGeneration{projectId, std::move(lexicon)});
    return project;
  }

  std::shared_ptr<const ProjectGeneration> Project::current() const {
    std::shared_lock lock(generationMutex_);
    return current_;
  }

  std::shared_ptr<Session> Project::openSession() {
    return std::make_shared<Session>(shared_from_this(), current(), nextId());
  }

  std::shared_ptr<const LexiconGeneration> Project::portableLexicon(context::Context &source,
                                                                    GenerationId lexiconId) {
    // Image encode/decode is intentionally only on publication, not on each
    // request.  It strips JIT/process-local state and validates the persistence
    // boundary before the immutable COW generation is exposed to other clients.
    const std::vector<std::uint8_t> image = EngineImage::encode(source);

    // Rebuild the portable snapshot on the kernel only.  Seeding this
    // temporary context with the default embedded language would preserve
    // compiler-schema phrases that are intentionally absent from a custom
    // `--reset --import` language and could make bound actions resolve against
    // the wrong LanguageState.  `--reset` leaves the Host ABI registered while
    // removing the embedded language before the source image is restored.
    char program[] = "recurloop-generation";
    char reset[] = "--reset";
    char *argv[] = {program, reset};
    Recurloop clean;
    clean.initializeEmbedded(2, argv, embedded::coreImage());
    context::Context &context = clean.getContext();

    // Project generations clone an exact runtime state; they are not image
    // imports.  The regular decode path initializes semantic defaults after
    // restore, which is correct for importing a language image but mutates the
    // intentionally empty host kernel produced by `--reset` (Values::setup()
    // needs a typed root).  Exact restore preserves both cases as-is.
    const bool hasLanguage = !source.lexicon.phrase().getType().isNull();
    EngineImage::decodeExact(context, image);

    // Host function addresses are process-local and must be rebound for a real
    // language image.  A reset-only kernel has no typed compiler language and
    // deliberately has no Context API declarations to bind.
    if (hasLanguage) {
      ContextApi::bind(context);
      EngineImage::markExportBase(context);
    }
    return LexiconGeneration::capture(context, lexiconId);
  }

  std::shared_ptr<const ProjectGeneration> Project::publish(context::Context &source) {
    std::lock_guard publishLock(publishMutex_);
    const GenerationId projectId = nextId();
    const GenerationId lexiconId = nextId();
    auto lexicon = portableLexicon(source, lexiconId);
    auto generation = std::make_shared<ProjectGeneration>(ProjectGeneration{projectId, std::move(lexicon)});
    {
      std::unique_lock lock(generationMutex_);
      current_ = generation;
    }
    return generation;
  }
} // namespace recurloop
