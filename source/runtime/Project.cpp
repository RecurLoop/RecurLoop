#include <recurloop/Project.hpp>

#include <recurloop/ContextApi.hpp>
#include <recurloop/EmbeddedCore.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/LexiconTransaction.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Session.hpp>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace recurloop {
  namespace {
    constexpr std::string_view CacheMagic{"recurloop-project-step-cache-v2"};
    constexpr std::uint64_t FnvOffset = 1469598103934665603ULL;
    constexpr std::uint64_t FnvPrime = 1099511628211ULL;

    bool sourceStamp(const std::string &path, ProjectCacheStamp &stamp) {
      namespace fs = std::filesystem;
      std::error_code error;
      const fs::path file(path);
      if (!fs::is_regular_file(file, error) || error) return false;
      stamp.size = fs::file_size(file, error);
      if (error) return false;
      const auto time = fs::last_write_time(file, error);
      if (error) return false;
      stamp.mtime = static_cast<std::int64_t>(time.time_since_epoch().count());
      return true;
    }

    bool sameStamp(const std::string &path, const ProjectCacheStamp &expected) {
      ProjectCacheStamp actual;
      return sourceStamp(path, actual) && actual.size == expected.size && actual.mtime == expected.mtime;
    }

    bool endsWith(std::string_view value, std::string_view suffix) {
      return value.size() >= suffix.size() && value.substr(value.size() - suffix.size()) == suffix;
    }

    void hashBytes(std::uint64_t &hash, const void *data, std::size_t bytes) {
      const auto *cursor = static_cast<const std::uint8_t *>(data);
      for (std::size_t index = 0; index < bytes; ++index) {
        hash ^= cursor[index];
        hash *= FnvPrime;
      }
    }

    void hashText(std::uint64_t &hash, std::string_view value) {
      hashBytes(hash, value.data(), value.size());
      const std::uint8_t separator = 0xff;
      hashBytes(hash, &separator, sizeof(separator));
    }

    template <typename Value> void hashValue(std::uint64_t &hash, const Value &value) {
      hashBytes(hash, &value, sizeof(value));
    }

    std::uint64_t nextChain(std::uint64_t input, const std::string &source,
                            const std::unordered_map<std::string, ProjectCacheStamp> &dependencies) {
      std::uint64_t hash = input == 0 ? FnvOffset : input;
      hashText(hash, source);
      std::vector<std::pair<std::string, ProjectCacheStamp>> ordered(dependencies.begin(), dependencies.end());
      std::sort(ordered.begin(), ordered.end(),
                [](const auto &left, const auto &right) { return left.first < right.first; });
      for (const auto &[path, stamp] : ordered) {
        hashText(hash, path);
        hashValue(hash, stamp.size);
        hashValue(hash, stamp.mtime);
      }
      return hash == 0 ? 1 : hash;
    }

    std::string stepName(std::size_t step) {
      std::ostringstream stream;
      stream << std::setfill('0') << std::setw(6) << step;
      return stream.str();
    }

    struct Manifest {
      std::uint64_t baseline = 0;
      std::uint64_t input = 0;
      std::uint64_t output = 0;
      std::string source;
      ProjectCacheStamp sourceStamp;
      std::unordered_map<std::string, ProjectCacheStamp> dependencies;
    };

    bool readManifest(const std::filesystem::path &path, Manifest &manifest) {
      std::ifstream input(path);
      if (!input.is_open()) return false;
      std::string magic;
      std::size_t dependencyCount = 0;
      if (!(input >> magic >> std::hex >> manifest.baseline >> manifest.input >> manifest.output >> std::dec >>
            manifest.sourceStamp.size >> manifest.sourceStamp.mtime >> std::quoted(manifest.source) >> dependencyCount))
        return false;
      if (magic != CacheMagic || dependencyCount == 0) return false;
      for (std::size_t index = 0; index < dependencyCount; ++index) {
        ProjectCacheStamp stamp;
        std::string dependency;
        if (!(input >> stamp.size >> stamp.mtime >> std::quoted(dependency))) return false;
        manifest.dependencies.emplace(std::move(dependency), stamp);
      }
      input >> std::ws;
      return input.eof();
    }

    bool writeManifest(const std::filesystem::path &path, std::uint64_t baseline, std::uint64_t input,
                       std::uint64_t output, const std::string &source, const ProjectCacheStamp &sourceStamp,
                       const std::unordered_map<std::string, ProjectCacheStamp> &dependencies) {
      std::vector<std::pair<std::string, ProjectCacheStamp>> ordered(dependencies.begin(), dependencies.end());
      std::sort(ordered.begin(), ordered.end(),
                [](const auto &left, const auto &right) { return left.first < right.first; });
      std::ofstream file(path, std::ios::trunc);
      if (!file.is_open()) return false;
      file << CacheMagic << ' ' << std::hex << baseline << ' ' << input << ' ' << output << std::dec << ' '
           << sourceStamp.size << ' ' << sourceStamp.mtime << ' ' << std::quoted(source) << ' ' << ordered.size()
           << '\n';
      for (const auto &[dependency, stamp] : ordered)
        file << stamp.size << ' ' << stamp.mtime << ' ' << std::quoted(dependency) << '\n';
      file.close();
      return static_cast<bool>(file);
    }

    std::string fragmentName(std::uint64_t input, std::string_view source) {
      std::uint64_t hash = input == 0 ? FnvOffset : input;
      hashText(hash, source);
      std::ostringstream stream;
      stream << std::hex << std::setfill('0') << std::setw(16) << hash;
      return stream.str();
    }
  } // namespace

  std::shared_ptr<Project> Project::create(context::Context &source, std::vector<std::string> arguments) {
    if (arguments.empty() && source.exec.args.ptr != nullptr) {
      arguments.reserve(source.exec.args.count);
      for (int i = 0; i < source.exec.args.count; ++i)
        arguments.emplace_back(source.exec.args.ptr[i] != nullptr ? source.exec.args.ptr[i] : "");
    }
    auto project =
        std::shared_ptr<Project>(new Project(source.config, source.actions().snapshot(), std::move(arguments)));
    const GenerationId projectId = project->nextId();
    const GenerationId lexiconId = project->nextId();
    auto lexicon = project->portableLexicon(source, lexiconId);
    project->current_ = std::make_shared<ProjectGeneration>(ProjectGeneration{projectId, std::move(lexicon)});
    project->baseline_ = project->current_;
    return project;
  }

  std::shared_ptr<const ProjectGeneration> Project::current() const {
    std::shared_lock lock(generationMutex_);
    return current_;
  }

  std::shared_ptr<const ProjectGeneration> Project::baseline() const {
    std::shared_lock lock(generationMutex_);
    return baseline_;
  }

  std::shared_ptr<Session> Project::openSession() {
    return std::make_shared<Session>(shared_from_this(), current(), nextId());
  }

  std::shared_ptr<const LexiconGeneration> Project::portableLexicon(context::Context &source, GenerationId lexiconId) {
    const std::vector<std::uint8_t> image = EngineImage::encode(source);

    char program[] = "recurloop-generation";
    char reset[] = "--reset";
    char *argv[] = {program, reset};
    Recurloop clean;
    clean.initializeEmbedded(2, argv, embedded::coreImage());
    context::Context &context = clean.getContext();

    const bool hasLanguage = !source.lexicon.phrase().getType().isNull();
    EngineImage::decodeExact(context, image);
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

  std::uint64_t Project::baselineHash() const {
    std::lock_guard lock(cacheBaselineMutex_);
    if (cacheBaselineHash_ != 0) return cacheBaselineHash_;
    auto baseGeneration = baseline();
    if (!baseGeneration || !baseGeneration->lexicon) return 0;

    ContextGeneration snapshot(baseGeneration->lexicon, config_, actions_, arguments_, baseGeneration->id, 0, 0);
    const std::vector<std::uint8_t> image = EngineImage::encode(snapshot.context());
    std::uint64_t hash = FnvOffset;
    for (const std::uint8_t byte : image) {
      hash ^= byte;
      hash *= FnvPrime;
    }
    cacheBaselineHash_ = hash == 0 ? 1 : hash;
    return cacheBaselineHash_;
  }

  void Project::configureCache(std::string directory) {
    namespace fs = std::filesystem;
    cacheDirectory_ = fs::absolute(std::move(directory)).lexically_normal().string();
    cacheStepsDirectory_ = (fs::path(cacheDirectory_) / "steps").string();
    cacheFragmentsDirectory_ = (fs::path(cacheDirectory_) / "fragments").string();
    std::error_code error;
    fs::create_directories(cacheStepsDirectory_, error);
    error.clear();
    fs::create_directories(cacheFragmentsDirectory_, error);

    // Remove obsolete cache formats. The only persistent state now is a chain
    // of real .rli checkpoints plus tiny manifests under steps/.
    const fs::path root(cacheDirectory_);
    for (const char *legacy :
         {"project.rli", "project.manifest", "checkpoint.rli", "checkpoint.manifest", "project-bootstrap.rl"}) {
      error.clear();
      fs::remove(root / legacy, error);
    }
  }

  void Project::beginCache(ProjectCacheState &state) const {
    state.enabled = cacheEnabled();
    state.active = false;
    state.step = 0;
    state.chain = state.enabled ? baselineHash() : 0;
    state.inputChain = 0;
    state.source.clear();
    state.dependencies.clear();
    state.observed.clear();
    state.fragmentChain = state.chain;
    state.fragments.clear();
  }

  bool Project::restoreCacheStep(ProjectCacheState &state, context::Context &context,
                                 std::string_view source) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || cacheStepsDirectory_.empty() || !endsWith(source, ".rl")) return false;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error) return false;
      ProjectCacheStamp stamp;
      if (!sourceStamp(absolute, stamp)) return false;

      const fs::path base = fs::path(cacheStepsDirectory_) / stepName(state.step);
      const fs::path imagePath = base.string() + ".rli";
      const fs::path manifestPath = base.string() + ".manifest";
      Manifest manifest;
      if (!readManifest(manifestPath, manifest) || manifest.baseline != baselineHash() ||
          manifest.input != state.chain || manifest.source != absolute || manifest.sourceStamp.size != stamp.size ||
          manifest.sourceStamp.mtime != stamp.mtime) {
        cacheMisses_.fetch_add(1, std::memory_order_relaxed);
        return false;
      }
      for (const auto &[dependency, dependencyStamp] : manifest.dependencies)
        if (!sameStamp(dependency, dependencyStamp)) {
          cacheMisses_.fetch_add(1, std::memory_order_relaxed);
          return false;
        }
      if (!fs::is_regular_file(imagePath, error) || error || fs::file_size(imagePath, error) == 0 || error) {
        cacheMisses_.fetch_add(1, std::memory_order_relaxed);
        return false;
      }

      // A step image is a normal importable .rli delta. The export base is
      // advanced after every successful step, so restoring the chain is just
      // the normal sequence of EngineImage imports; earlier source never needs
      // to be parsed again.
      LexiconTransaction transaction(context.lexicon);
      EngineImage::load(context, imagePath.string());
      EngineImage::markExportBase(context);
      transaction.commit();
      state.chain = manifest.output;
      state.fragmentChain = manifest.output;
      state.observed.insert(manifest.dependencies.begin(), manifest.dependencies.end());
      if (state.active) state.dependencies.insert(manifest.dependencies.begin(), manifest.dependencies.end());
      ++state.step;
      cacheHits_.fetch_add(1, std::memory_order_relaxed);
      return true;
    } catch (...) {
      cacheMisses_.fetch_add(1, std::memory_order_relaxed);
      state.enabled = false;
      return false;
    }
  }

  void Project::beginCacheStep(ProjectCacheState &state, std::string_view source) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || state.active || cacheStepsDirectory_.empty() || !endsWith(source, ".rl")) return;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error) return;
      ProjectCacheStamp stamp;
      if (!sourceStamp(absolute, stamp)) return;
      state.active = true;
      state.inputChain = state.chain;
      state.source = absolute;
      state.sourceStamp = stamp;
      state.dependencies.clear();
      state.dependencies.emplace(absolute, stamp);
      state.observed.emplace(absolute, stamp);
      state.fragmentChain = nextChain(state.fragmentChain, absolute, {{absolute, stamp}});
    } catch (...) {
    }
  }

  void Project::observeCacheSource(ProjectCacheState &state, std::string_view source) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || !state.active || !endsWith(source, ".rl")) return;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error) return;
      ProjectCacheStamp stamp;
      if (sourceStamp(absolute, stamp)) {
        state.dependencies[absolute] = stamp;
        state.observed[absolute] = stamp;
        for (auto &fragment : state.fragments) fragment.dependencies[absolute] = stamp;
      }
    } catch (...) {
    }
  }

  bool Project::restoreCacheFragment(ProjectCacheState &state, context::Context &context,
                                     std::string_view source) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || cacheFragmentsDirectory_.empty() || !endsWith(source, ".rl")) return false;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error) return false;
      ProjectCacheStamp stamp;
      if (!sourceStamp(absolute, stamp)) return false;
      const std::uint64_t input = state.fragmentChain;
      const fs::path base = fs::path(cacheFragmentsDirectory_) / fragmentName(input, absolute);
      const fs::path imagePath = base.string() + ".rli";
      Manifest manifest;
      if (!readManifest(base.string() + ".manifest", manifest) || manifest.baseline != baselineHash() ||
          manifest.input != input || manifest.source != absolute || manifest.sourceStamp.size != stamp.size ||
          manifest.sourceStamp.mtime != stamp.mtime)
        return false;
      for (const auto &[dependency, dependencyStamp] : manifest.dependencies)
        if (!sameStamp(dependency, dependencyStamp)) return false;
      if (!fs::is_regular_file(imagePath, error) || error || fs::file_size(imagePath, error) == 0 || error)
        return false;

      LexiconTransaction transaction(context.lexicon);
      EngineImage::load(context, imagePath.string());
      EngineImage::markExportBase(context);
      transaction.commit();
      state.fragmentChain = manifest.output;
      state.observed.insert(manifest.dependencies.begin(), manifest.dependencies.end());
      if (!state.fragments.empty())
        state.fragments.back().dependencies.insert(manifest.dependencies.begin(), manifest.dependencies.end());
      cacheHits_.fetch_add(1, std::memory_order_relaxed);
      return true;
    } catch (...) {
      return false;
    }
  }

  void Project::beginCacheFragment(ProjectCacheState &state, std::string_view source) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || cacheFragmentsDirectory_.empty() || !endsWith(source, ".rl")) return;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error) return;
      ProjectCacheStamp stamp;
      if (!sourceStamp(absolute, stamp)) return;
      ProjectCacheState::Fragment fragment;
      fragment.inputChain = state.fragmentChain;
      fragment.source = absolute;
      fragment.sourceStamp = stamp;
      fragment.dependencies.emplace(absolute, stamp);
      state.observed[absolute] = stamp;
      if (state.active) state.dependencies[absolute] = stamp;
      state.fragmentChain = nextChain(fragment.inputChain, absolute, fragment.dependencies);
      state.fragments.push_back(std::move(fragment));
    } catch (...) {
    }
  }

  bool Project::commitCacheFragment(ProjectCacheState &state, context::Context &context,
                                    std::string_view source) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || state.fragments.empty()) return false;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error || state.fragments.back().source != absolute) return false;
      ProjectCacheState::Fragment fragment = std::move(state.fragments.back());
      state.fragments.pop_back();
      const std::uint64_t output = nextChain(fragment.inputChain, fragment.source, fragment.dependencies);
      const fs::path base = fs::path(cacheFragmentsDirectory_) / fragmentName(fragment.inputChain, fragment.source);
      const fs::path imagePath = base.string() + ".rli";
      const fs::path manifestPath = base.string() + ".manifest";
      const std::uint64_t temporaryId = cacheTemporaryId_.fetch_add(1, std::memory_order_relaxed);
      const fs::path imageTemporary = imagePath.string() + "." + std::to_string(temporaryId) + ".tmp";
      const fs::path manifestTemporary = manifestPath.string() + "." + std::to_string(temporaryId) + ".tmp";
      EngineImage::saveFull(context, imageTemporary.string());
      if (!writeManifest(manifestTemporary, baselineHash(), fragment.inputChain, output, fragment.source,
                         fragment.sourceStamp, fragment.dependencies)) {
        fs::remove(imageTemporary, error);
        return false;
      }
      fs::rename(imageTemporary, imagePath, error);
      if (error) {
        fs::remove(imageTemporary, error);
        fs::remove(manifestTemporary, error);
        return false;
      }
      fs::rename(manifestTemporary, manifestPath, error);
      if (error) {
        fs::remove(manifestTemporary, error);
        return false;
      }
      EngineImage::markExportBase(context);
      state.fragmentChain = output;
      state.observed.insert(fragment.dependencies.begin(), fragment.dependencies.end());
      if (state.active) state.dependencies.insert(fragment.dependencies.begin(), fragment.dependencies.end());
      if (!state.fragments.empty())
        state.fragments.back().dependencies.insert(fragment.dependencies.begin(), fragment.dependencies.end());
      cacheWrites_.fetch_add(1, std::memory_order_relaxed);
      return true;
    } catch (...) {
      return false;
    }
  }

  void Project::commitCacheStep(ProjectCacheState &state, context::Context &context) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || !state.active || cacheStepsDirectory_.empty()) return;
    try {
      const std::uint64_t outputChain = nextChain(state.inputChain, state.source, state.dependencies);
      const fs::path base = fs::path(cacheStepsDirectory_) / stepName(state.step);
      const fs::path imagePath = base.string() + ".rli";
      const fs::path manifestPath = base.string() + ".manifest";
      const std::uint64_t temporaryId = cacheTemporaryId_.fetch_add(1, std::memory_order_relaxed);
      const fs::path imageTemporary = imagePath.string() + "." + std::to_string(temporaryId) + ".tmp";
      const fs::path manifestTemporary = manifestPath.string() + "." + std::to_string(temporaryId) + ".tmp";
      std::error_code error;

      // Cache a complete semantic checkpoint at each direct source boundary.
      // A source file may assign to a mutable value that was created by the
      // immutable baseline (for example an IDE override). Such an assignment
      // changes an existing phrase in place and therefore cannot be represented
      // by an append-only EngineImage delta. Full checkpoints preserve both
      // appended definitions and those pre-existing mutable values while still
      // avoiding source parsing/compilation on a cache hit.
      EngineImage::saveFull(context, imageTemporary.string());
      if (!writeManifest(manifestTemporary, baselineHash(), state.inputChain, outputChain, state.source,
                         state.sourceStamp, state.dependencies)) {
        fs::remove(imageTemporary, error);
        state.enabled = false;
        state.active = false;
        return;
      }

      error.clear();
      fs::rename(imageTemporary, imagePath, error);
      if (error) {
        fs::remove(imageTemporary, error);
        fs::remove(manifestTemporary, error);
        state.enabled = false;
        state.active = false;
        return;
      }
      error.clear();
      fs::rename(manifestTemporary, manifestPath, error);
      if (error) {
        fs::remove(manifestTemporary, error);
        state.enabled = false;
        state.active = false;
        return;
      }

      EngineImage::markExportBase(context);
      state.chain = outputChain;
      state.active = false;
      state.source.clear();
      state.dependencies.clear();
      ++state.step;
      cacheWrites_.fetch_add(1, std::memory_order_relaxed);
    } catch (...) {
      state.enabled = false;
      state.active = false;
    }
  }

  void Project::abortCacheStep(ProjectCacheState &state) noexcept {
    if (!state.active) return;
    state.chain = state.inputChain;
    state.active = false;
    state.source.clear();
    state.dependencies.clear();
    state.fragments.clear();
  }

} // namespace recurloop
