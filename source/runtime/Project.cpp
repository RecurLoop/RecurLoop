#include <recurloop/Project.hpp>

#include <recurloop/ContextApi.hpp>
#include <recurloop/EmbeddedCore.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/LexiconTransaction.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Session.hpp>
#include <radix/node/Data.hpp>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace recurloop {
  namespace {
    constexpr std::string_view CacheMagic{"recurloop-project-module-cache-v3"};
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

    std::uint64_t pathHash(std::string_view value) {
      std::uint64_t hash = FnvOffset;
      for (const unsigned char byte : value) {
        hash ^= byte;
        hash *= FnvPrime;
      }
      return hash == 0 ? 1 : hash;
    }

    std::string hexadecimal(std::uint64_t value) {
      std::ostringstream stream;
      stream << std::hex << std::setfill('0') << std::setw(16) << value;
      return stream.str();
    }

    bool relativeInside(const std::filesystem::path &path) {
      if (path.empty() || path.is_absolute()) return false;
      for (const auto &part : path)
        if (part == "..") return false;
      return true;
    }

    struct Manifest {
      std::uint64_t baseline = 0;
      bool linked = true;
      std::string source;
      ProjectCacheStamp sourceStamp;
      std::unordered_map<std::string, ProjectCacheStamp> dependencies;
    };

    bool readManifest(const std::filesystem::path &path, Manifest &manifest) {
      std::ifstream input(path);
      if (!input.is_open()) return false;
      std::string magic;
      int linked = 0;
      std::size_t dependencyCount = 0;
      if (!(input >> magic >> std::hex >> manifest.baseline >> std::dec >> linked >> manifest.sourceStamp.size >>
            manifest.sourceStamp.mtime >> std::quoted(manifest.source) >> dependencyCount))
        return false;
      if (magic != CacheMagic || (linked != 0 && linked != 1) || dependencyCount == 0) return false;
      manifest.linked = linked != 0;
      for (std::size_t index = 0; index < dependencyCount; ++index) {
        ProjectCacheStamp stamp;
        std::string dependency;
        if (!(input >> stamp.size >> stamp.mtime >> std::quoted(dependency))) return false;
        manifest.dependencies.emplace(std::move(dependency), stamp);
      }
      input >> std::ws;
      return input.eof();
    }

    bool writeManifest(const std::filesystem::path &path, std::uint64_t baseline, bool linked,
                       const std::string &source, const ProjectCacheStamp &sourceStamp,
                       const std::unordered_map<std::string, ProjectCacheStamp> &dependencies) {
      std::vector<std::pair<std::string, ProjectCacheStamp>> ordered(dependencies.begin(), dependencies.end());
      std::sort(ordered.begin(), ordered.end(),
                [](const auto &left, const auto &right) { return left.first < right.first; });
      std::ofstream file(path, std::ios::trunc);
      if (!file.is_open()) return false;
      file << CacheMagic << ' ' << std::hex << baseline << std::dec << ' ' << (linked ? 1 : 0) << ' '
           << sourceStamp.size << ' ' << sourceStamp.mtime << ' ' << std::quoted(source) << ' ' << ordered.size()
           << '\n';
      for (const auto &[dependency, stamp] : ordered)
        file << stamp.size << ' ' << stamp.mtime << ' ' << std::quoted(dependency) << '\n';
      file.close();
      return static_cast<bool>(file);
    }

    void hashBytes(std::uint64_t &hash, const void *data, std::size_t size) {
      const auto *bytes = static_cast<const std::uint8_t *>(data);
      for (std::size_t index = 0; index < size; ++index) {
        hash ^= bytes[index];
        hash *= FnvPrime;
      }
    }

    template <typename Value> void hashValue(std::uint64_t &hash, const Value &value) {
      hashBytes(hash, &value, sizeof(value));
    }

    std::uint64_t semanticPrefix(context::Context &context, Size before) {
      std::uint64_t hash = FnvOffset;
      for (radix::Item item = context.lexicon.lastItem(); !item.isNull(); item = item.earlier()) {
        const Size address = item.getAddress();
        const Size contentSize = item.contentSize();
        if (address >= before || contentSize < sizeof(lexicon::Phrase::Contains)) continue;

        Size offset = 0;
        lexicon::Phrase::Contains contains;
        std::memcpy(&contains, item.content(offset, sizeof(contains)).toPtr(), sizeof(contains));
        if (contains & lexicon::phrase::Contains::UNSERIALIZABLE) continue;
        hashValue(hash, address);
        hashValue(hash, contains);
        offset += sizeof(contains);

        const auto hashField = [&](std::size_t size) {
          if (offset > contentSize || size > contentSize - offset)
            THROW(, "project cache encountered truncated phrase metadata")
          hashBytes(hash, item.content(offset, size).toPtr(), size);
          offset += size;
        };
        if (contains & lexicon::phrase::Contains::PROTOTYPE) hashField(sizeof(Size));
        if (contains & lexicon::phrase::Contains::PARENT) hashField(sizeof(Size));
        if (contains & lexicon::phrase::Contains::SUBDICTIONARY) offset += sizeof(radix::node::Data);
        if (contains & lexicon::phrase::Contains::TYPE) hashField(sizeof(Size));
        if (contains & lexicon::phrase::Contains::ACTION) {
          lexicon::Phrase::ActionBinding action;
          if (offset > contentSize || sizeof(action) > contentSize - offset)
            THROW(, "project cache encountered truncated phrase action")
          std::memcpy(&action, item.content(offset, sizeof(action)).toPtr(), sizeof(action));
          hashValue(hash, action.dispatch);
          hashValue(hash, action.implementation);
          offset += sizeof(action);
        }
        if (contains & lexicon::phrase::Contains::SUCCESSOR) hashField(sizeof(Size));
        if (offset > contentSize) THROW(, "project cache encountered truncated phrase payload")
        const Size payloadSize = contentSize - offset;
        if (payloadSize != 0) hashBytes(hash, item.content(offset, payloadSize).toPtr(), payloadSize);
      }
      return hash == 0 ? 1 : hash;
    }

    void snapshotSegment(ProjectCacheState::Module &module, context::Context &context) {
      module.segmentUsed = context.lexicon.memoryUsed();
      module.semanticPrefix = semanticPrefix(context, module.segmentUsed);
    }

    bool semanticPrefixChanged(const ProjectCacheState::Module &module, context::Context &context) {
      const Size used = context.lexicon.memoryUsed();
      if (used < module.segmentUsed) return true;
      return module.semanticPrefix != semanticPrefix(context, module.segmentUsed);
    }

    bool segmentChanged(const ProjectCacheState::Module &module, context::Context &context) {
      return context.lexicon.memoryUsed() != module.segmentUsed || semanticPrefixChanged(module, context);
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

  std::shared_ptr<const ProjectGeneration> Project::preparePublication(context::Context &source) {
    const GenerationId projectId = nextId();
    const GenerationId lexiconId = nextId();
    auto lexicon = portableLexicon(source, lexiconId);
    return std::make_shared<ProjectGeneration>(ProjectGeneration{projectId, std::move(lexicon)});
  }

  bool Project::commitPublication(const std::shared_ptr<const ProjectGeneration> &generation) {
    if (!generation || !generation->lexicon) return false;
    std::lock_guard publishLock(publishMutex_);
    std::unique_lock lock(generationMutex_);
    if (current_ && current_->id >= generation->id) return false;
    current_ = generation;
    return true;
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
    cacheModulesDirectory_ = (fs::path(cacheDirectory_) / "modules").string();

    std::error_code error;
    fs::create_directories(cacheModulesDirectory_, error);

    const char *projectRoot = std::getenv("RECURLOOP_PROJECT_ROOT");
    if (projectRoot != nullptr && *projectRoot != '\0')
      cacheSourceRoot_ = fs::absolute(fs::path(projectRoot), error).lexically_normal().string();
    if (cacheSourceRoot_.empty() || error) {
      error.clear();
      cacheSourceRoot_ = fs::current_path(error).lexically_normal().string();
    }

    // Linked modules are append-only deltas instead of flattened snapshots.
    // Old step/fragment trees are not compatible and would only waste space.
    error.clear();
    fs::remove_all(fs::path(cacheDirectory_) / "steps", error);
    error.clear();
    fs::remove_all(fs::path(cacheDirectory_) / "fragments", error);
    for (const char *legacy :
         {"project.rli", "project.manifest", "checkpoint.rli", "checkpoint.manifest", "project-bootstrap.rl"}) {
      error.clear();
      fs::remove(fs::path(cacheDirectory_) / legacy, error);
    }
  }

  std::string Project::cacheModuleImagePath(std::string_view source) const {
    namespace fs = std::filesystem;
    std::error_code error;
    const fs::path absolute = fs::absolute(fs::path(source), error).lexically_normal();
    if (error) return {};

    fs::path relative;
    if (!cacheSourceRoot_.empty()) relative = absolute.lexically_relative(fs::path(cacheSourceRoot_));
    fs::path output;
    if (relativeInside(relative)) {
      output = fs::path(cacheModulesDirectory_) / relative;
    } else {
      output = fs::path(cacheModulesDirectory_) / "external" /
               (hexadecimal(pathHash(absolute.generic_string())) + "-" + absolute.filename().string());
    }
    output.replace_extension(".rli");
    return output.string();
  }

  std::string Project::cacheModuleManifestPath(std::string_view source) const {
    namespace fs = std::filesystem;
    fs::path path(cacheModuleImagePath(source));
    if (path.empty()) return {};
    path.replace_extension(".manifest");
    return path.string();
  }

  void Project::beginCache(ProjectCacheState &state, bool exactRestore) const {
    state.enabled = cacheEnabled();
    state.exactRestore = state.enabled && exactRestore;
    state.active = false;
    state.step = 0;
    state.observed.clear();
    state.modules.clear();
  }

  void Project::beforeCacheDependency(ProjectCacheState &state, context::Context &context) noexcept {
    if (!state.enabled || state.modules.empty()) return;
    try {
      ProjectCacheState::Module &module = state.modules.back();
      // A single linked image can represent one source file only when all
      // dependencies are established before that file contributes semantic
      // state. If source state exists before a later dependency, keep the
      // one-file cache invariant by falling back to a self-contained image for
      // this file rather than creating hidden per-include segments.
      if (segmentChanged(module, context)) module.linked = false;
    } catch (...) {
      state.enabled = false;
    }
  }

  void Project::afterCacheDependency(ProjectCacheState &state, context::Context &context) noexcept {
    if (!state.enabled || state.modules.empty()) return;
    try {
      // Subsequent source-owned state starts after the dependency. The module
      // checkpoint moves forward without turning the dependency into local
      // image contents.
      snapshotSegment(state.modules.back(), context);
    } catch (...) {
      state.enabled = false;
    }
  }

  bool Project::restoreCacheModule(ProjectCacheState &state, context::Context &context, std::string_view source,
                                   bool nested) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || cacheModulesDirectory_.empty() || !endsWith(source, ".rl")) return false;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error) return false;
      ProjectCacheStamp stamp;
      if (!sourceStamp(absolute, stamp)) return false;

      const fs::path imagePath(cacheModuleImagePath(absolute));
      const fs::path manifestPath(cacheModuleManifestPath(absolute));
      Manifest manifest;
      if (!readManifest(manifestPath, manifest) || manifest.baseline != baselineHash() ||
          manifest.source != absolute || manifest.sourceStamp.size != stamp.size ||
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

      if (nested) beforeCacheDependency(state, context);
      LexiconTransaction transaction(context.lexicon);
      // Linked modules always compose like normal imports. A standalone fallback
      // is also loaded as an overlay when nested; at the direct root exact mode
      // may replace the graph because the caller has explicitly requested it.
      if (state.exactRestore && !nested && !manifest.linked) EngineImage::loadFull(context, imagePath.string());
      else EngineImage::load(context, imagePath.string());
      transaction.commit();

      state.observed.insert(manifest.dependencies.begin(), manifest.dependencies.end());
      if (nested && !state.modules.empty()) {
        state.modules.back().dependencies.insert(manifest.dependencies.begin(), manifest.dependencies.end());
        afterCacheDependency(state, context);
      }
      ++state.step;
      cacheHits_.fetch_add(1, std::memory_order_relaxed);
      return true;
    } catch (...) {
      cacheMisses_.fetch_add(1, std::memory_order_relaxed);
      return false;
    }
  }

  void Project::beginCacheModule(ProjectCacheState &state, context::Context &context, std::string_view source) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || cacheModulesDirectory_.empty() || !endsWith(source, ".rl")) return;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error) return;
      ProjectCacheStamp stamp;
      if (!sourceStamp(absolute, stamp)) return;

      ProjectCacheState::Module module;
      module.source = absolute;
      module.sourceStamp = stamp;
      module.dependencies.emplace(absolute, stamp);
      snapshotSegment(module, context);
      state.observed[absolute] = stamp;
      state.modules.push_back(std::move(module));
      state.active = true;
    } catch (...) {
      state.enabled = false;
    }
  }

  bool Project::commitCacheModule(ProjectCacheState &state, context::Context &context, std::string_view source,
                                  bool nested) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || state.modules.empty()) return false;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error || state.modules.back().source != absolute) return false;

      ProjectCacheState::Module module = std::move(state.modules.back());
      state.modules.pop_back();

      // In-place writes to state that existed before the current dependency
      // boundary cannot be represented by an append-only linked image. Keep a
      // correct 1:1 cache entry by making just this source standalone. Normal
      // declaration-only project files stay linked and small.
      if (semanticPrefixChanged(module, context)) module.linked = false;

      const fs::path imagePath(cacheModuleImagePath(absolute));
      const fs::path manifestPath(cacheModuleManifestPath(absolute));
      if (imagePath.empty() || manifestPath.empty()) return false;
      fs::create_directories(imagePath.parent_path(), error);
      if (error) return false;

      const std::uint64_t temporaryId = cacheTemporaryId_.fetch_add(1, std::memory_order_relaxed);
      const fs::path imageTemporary = imagePath.string() + "." + std::to_string(temporaryId) + ".tmp";
      const fs::path manifestTemporary = manifestPath.string() + "." + std::to_string(temporaryId) + ".tmp";

      if (module.linked) EngineImage::saveLinked(context, module.segmentUsed, imageTemporary.string());
      else EngineImage::saveFull(context, imageTemporary.string());
      if (!writeManifest(manifestTemporary, baselineHash(), module.linked, module.source, module.sourceStamp,
                         module.dependencies)) {
        fs::remove(imageTemporary, error);
        return false;
      }

      error.clear();
      fs::rename(imageTemporary, imagePath, error);
      if (error) {
        fs::remove(imageTemporary, error);
        fs::remove(manifestTemporary, error);
        return false;
      }
      error.clear();
      fs::rename(manifestTemporary, manifestPath, error);
      if (error) {
        fs::remove(manifestTemporary, error);
        return false;
      }

      // The source was already executed in this context. Register the new image
      // as a dependency without loading it a second time, so the enclosing
      // source exports a link to this module instead of copying its contents.
      EngineImage::rememberDependency(context, imagePath.string());
      state.observed.insert(module.dependencies.begin(), module.dependencies.end());
      if (!state.modules.empty()) {
        state.modules.back().dependencies.insert(module.dependencies.begin(), module.dependencies.end());
        afterCacheDependency(state, context);
      } else {
        state.active = false;
      }
      ++state.step;
      cacheWrites_.fetch_add(1, std::memory_order_relaxed);
      return true;
    } catch (...) {
      if (!state.modules.empty() && state.modules.back().source == source) state.modules.pop_back();
      if (!nested && state.modules.empty()) state.active = false;
      return false;
    }
  }

  bool Project::restoreCacheStep(ProjectCacheState &state, context::Context &context,
                                 std::string_view source) noexcept {
    return restoreCacheModule(state, context, source, false);
  }

  void Project::beginCacheStep(ProjectCacheState &state, std::string_view source,
                               context::Context &context) noexcept {
    if (!state.modules.empty()) return;
    beginCacheModule(state, context, source);
  }

  void Project::observeCacheSource(ProjectCacheState &state, std::string_view source) noexcept {
    namespace fs = std::filesystem;
    if (!state.enabled || !endsWith(source, ".rl")) return;
    try {
      std::error_code error;
      const std::string absolute = fs::absolute(fs::path(source), error).lexically_normal().string();
      if (error) return;
      ProjectCacheStamp stamp;
      if (!sourceStamp(absolute, stamp)) return;
      state.observed[absolute] = stamp;
      for (auto &module : state.modules) module.dependencies[absolute] = stamp;
    } catch (...) {
    }
  }

  bool Project::restoreCacheNestedModule(ProjectCacheState &state, context::Context &context,
                                     std::string_view source) noexcept {
    return restoreCacheModule(state, context, source, true);
  }

  void Project::beginCacheNestedModule(ProjectCacheState &state, std::string_view source,
                                   context::Context &context) noexcept {
    beforeCacheDependency(state, context);
    beginCacheModule(state, context, source);
  }

  bool Project::commitCacheNestedModule(ProjectCacheState &state, context::Context &context,
                                    std::string_view source) noexcept {
    if (state.modules.size() <= 1) return false;
    return commitCacheModule(state, context, source, true);
  }

  void Project::commitCacheStep(ProjectCacheState &state, context::Context &context) noexcept {
    if (!state.enabled || state.modules.size() != 1) return;
    const std::string source = state.modules.back().source;
    if (!commitCacheModule(state, context, source, false)) {
      state.enabled = false;
      state.active = false;
      state.modules.clear();
    }
  }

  void Project::beginCacheImageDependency(ProjectCacheState &state, context::Context &context,
                                          std::string_view path) noexcept {
    (void)path;
    beforeCacheDependency(state, context);
  }

  void Project::completeCacheImageDependency(ProjectCacheState &state, context::Context &context,
                                             std::string_view path) noexcept {
    (void)path;
    afterCacheDependency(state, context);
  }

  void Project::abortCacheStep(ProjectCacheState &state) noexcept {
    state.active = false;
    state.modules.clear();
  }

} // namespace recurloop
