#include <compiler/DynamicLinker.hpp>
#include <compiler/LanguageState.hpp>

#include <utilities/Exception.hpp>

#ifndef _WIN32
  #include <dlfcn.h>
  #include <glob.h>
#endif

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <set>

namespace compiler {
  namespace {
    std::string toFilename(std::string_view name) {
      if (name.find('/') != std::string::npos || name.find('\\') != std::string::npos) return std::string(name);
#ifndef _WIN32
      std::string filename(name);
      if (!filename.starts_with("lib")) filename.insert(0, "lib");
      if (!filename.ends_with(".so") && filename.find(".so.") == std::string::npos) filename += ".so";
      return filename;
#else
      if (name.starts_with("lib")) return std::string(name.substr(3)) + (name.ends_with(".dll") ? "" : ".dll");
      return std::string(name) + (name.ends_with(".dll") ? "" : ".dll");
#endif
    }

    std::string libraryKey(std::string_view name, const std::vector<std::string> &searchPaths) {
      std::string result;
      const auto append = [&](std::string_view value) {
        result += std::to_string(value.size());
        result.push_back(':');
        result.append(value);
        result.push_back(';');
      };
      append(name);
      for (const std::string &path : searchPaths) append(path);
      return result;
    }

    std::string symbolKey(std::string_view library, std::string_view symbol) {
      std::string result;
      result.reserve(library.size() + symbol.size() + 1);
      result.append(library);
      result.push_back('\0');
      result.append(symbol);
      return result;
    }

    void *tryLoad(const std::string &path) {
#ifndef _WIN32
      return dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL);
#else
      return LoadLibraryA(path.c_str());
#endif
    }

#ifndef _WIN32
    void addPath(std::vector<std::string> &paths, std::set<std::string> &seen, std::string path) {
      if (path.empty()) path = ".";
      std::error_code ec;
      if (!std::filesystem::is_directory(path, ec)) return;
      std::filesystem::path normalized = std::filesystem::path(path).lexically_normal();
      std::string value = normalized.string();
      if (seen.insert(value).second) paths.push_back(std::move(value));
    }

    void addColonPaths(std::vector<std::string> &paths, std::set<std::string> &seen, const char *value) {
      if (value == nullptr) return;
      std::string_view list(value);
      std::size_t begin = 0;
      while (begin <= list.size()) {
        const std::size_t end = list.find(':', begin);
        addPath(paths, seen, std::string(list.substr(begin, end - begin)));
        if (end == std::string_view::npos) break;
        begin = end + 1;
      }
    }

    void addLoaderConfig(std::vector<std::string> &paths, std::set<std::string> &seen, const std::string &file,
                         std::set<std::string> &visited, std::size_t depth = 0) {
      if (depth > 8 || !visited.insert(file).second) return;
      std::ifstream input(file);
      if (!input.is_open()) return;
      std::string line;
      while (std::getline(input, line)) {
        const std::size_t comment = line.find('#');
        if (comment != std::string::npos) line.resize(comment);
        const auto first = std::find_if_not(line.begin(), line.end(), [](unsigned char c) { return std::isspace(c); });
        const auto last =
            std::find_if_not(line.rbegin(), line.rend(), [](unsigned char c) { return std::isspace(c); }).base();
        if (first >= last) continue;
        std::string value(first, last);
        if (value.starts_with("include")) {
          std::string pattern = value.substr(7);
          const auto start = std::find_if_not(pattern.begin(), pattern.end(),
                                                [](unsigned char c) { return std::isspace(c); });
          pattern.erase(pattern.begin(), start);
          if (pattern.empty()) continue;
          glob_t matches{};
          if (glob(pattern.c_str(), 0, nullptr, &matches) == 0) {
            for (std::size_t index = 0; index < matches.gl_pathc; ++index)
              addLoaderConfig(paths, seen, matches.gl_pathv[index], visited, depth + 1);
          }
          globfree(&matches);
        } else {
          addPath(paths, seen, std::move(value));
        }
      }
    }

    std::vector<std::string> runtimeLibraryPaths(const std::vector<std::string> &searchPaths) {
      std::vector<std::string> result;
      std::set<std::string> seen;
      for (const std::string &path : searchPaths) addPath(result, seen, path);
      addColonPaths(result, seen, std::getenv("LD_LIBRARY_PATH"));
      std::set<std::string> visited;
      addLoaderConfig(result, seen, "/etc/ld.so.conf", visited);
      for (const char *path : {"/lib", "/usr/lib", "/lib64", "/usr/lib64", "/usr/local/lib"})
        addPath(result, seen, path);
      return result;
    }

    int naturalCompare(std::string_view left, std::string_view right) {
      std::size_t l = 0;
      std::size_t r = 0;
      while (l < left.size() && r < right.size()) {
        const bool leftDigit = std::isdigit(static_cast<unsigned char>(left[l]));
        const bool rightDigit = std::isdigit(static_cast<unsigned char>(right[r]));
        if (leftDigit && rightDigit) {
          std::size_t lEnd = l;
          std::size_t rEnd = r;
          while (lEnd < left.size() && std::isdigit(static_cast<unsigned char>(left[lEnd]))) ++lEnd;
          while (rEnd < right.size() && std::isdigit(static_cast<unsigned char>(right[rEnd]))) ++rEnd;
          std::size_t lSignificant = l;
          std::size_t rSignificant = r;
          while (lSignificant < lEnd && left[lSignificant] == '0') ++lSignificant;
          while (rSignificant < rEnd && right[rSignificant] == '0') ++rSignificant;
          const std::size_t lDigits = lEnd - lSignificant;
          const std::size_t rDigits = rEnd - rSignificant;
          if (lDigits != rDigits) return lDigits < rDigits ? -1 : 1;
          const int numeric = left.substr(lSignificant, lDigits).compare(right.substr(rSignificant, rDigits));
          if (numeric != 0) return numeric < 0 ? -1 : 1;
          l = lEnd;
          r = rEnd;
          continue;
        }
        if (left[l] != right[r]) return left[l] < right[r] ? -1 : 1;
        ++l;
        ++r;
      }
      if (l == left.size() && r == right.size()) return 0;
      return l == left.size() ? -1 : 1;
    }

    std::vector<std::string> versionedCandidates(const std::string &filename,
                                                  const std::vector<std::string> &paths) {
      if (!filename.ends_with(".so")) return {};
      const std::string prefix = filename + ".";
      std::vector<std::string> result;
      std::set<std::string> seen;
      for (const std::string &directory : paths) {
        std::error_code ec;
        for (std::filesystem::directory_iterator iterator(directory, ec), end; !ec && iterator != end;
             iterator.increment(ec)) {
          const std::string candidateName = iterator->path().filename().string();
          if (!candidateName.starts_with(prefix)) continue;
          std::error_code fileError;
          if (!std::filesystem::is_regular_file(iterator->path(), fileError)) continue;
          const std::string candidate = iterator->path().string();
          if (seen.insert(candidate).second) result.push_back(candidate);
        }
      }
      std::sort(result.begin(), result.end(), [&](const std::string &left, const std::string &right) {
        return naturalCompare(std::filesystem::path(left).filename().string(),
                              std::filesystem::path(right).filename().string()) > 0;
      });
      return result;
    }
#endif

    std::optional<std::string> locateLibrary(std::string_view name, const std::vector<std::string> &searchPaths) {
      const std::string filename = toFilename(name);
      if (filename.empty()) return std::nullopt;

      const bool explicitPath = name.find('/') != std::string_view::npos || name.find('\\') != std::string_view::npos;
      if (explicitPath) {
        std::error_code ec;
        if (std::filesystem::is_regular_file(filename, ec)) return filename;
        return std::nullopt;
      }

#ifndef _WIN32
      const std::vector<std::string> paths = runtimeLibraryPaths(searchPaths);
#else
      const std::vector<std::string> paths = searchPaths;
#endif
      for (const std::string &directory : paths) {
        const std::filesystem::path candidate = std::filesystem::path(directory) / filename;
        std::error_code ec;
        if (std::filesystem::is_regular_file(candidate, ec)) return candidate.string();
      }
#ifndef _WIN32
      const std::vector<std::string> versioned = versionedCandidates(filename, paths);
      if (!versioned.empty()) return versioned.front();
#endif
      return std::nullopt;
    }

    struct LoadResult {
      void *handle = nullptr;
      std::string path;
    };

    LoadResult tryLoadLibrary(std::string_view name, const std::vector<std::string> &searchPaths) {
      const std::string filename = toFilename(name);
      for (const std::string &dir : searchPaths) {
        const std::filesystem::path candidate = std::filesystem::path(dir) / filename;
        std::error_code ec;
        if (!std::filesystem::is_regular_file(candidate, ec)) continue;
        if (void *handle = tryLoad(candidate.string())) return {handle, candidate.string()};
      }
      if (void *handle = tryLoad(filename)) return {handle, filename};
#ifndef _WIN32
      for (const std::string &candidate : versionedCandidates(filename, runtimeLibraryPaths(searchPaths)))
        if (void *handle = tryLoad(candidate)) return {handle, candidate};
#endif
      return {};
    }

    void *trySymbol(void *handle, std::string_view sym) {
      const std::string symbol(sym);
#ifndef _WIN32
      return dlsym(handle, symbol.c_str());
#else
      return GetProcAddress(handle, symbol.c_str());
#endif
    }

    void closeLib(void *handle) {
#ifndef _WIN32
      if (handle) dlclose(handle);
#else
      if (handle) FreeLibrary(handle);
#endif
    }
  } // namespace

  DynamicLinker &DynamicLinker::instance() {
    static DynamicLinker instance;
    return instance;
  }

  std::optional<std::string> DynamicLinker::libraryPath(std::string_view name,
                                                        const std::vector<std::string> &searchPaths) {
    if (name.empty()) return std::nullopt;
    return locateLibrary(name, searchPaths);
  }

  void DynamicLinker::loadLibrary(std::string_view name, const std::vector<std::string> &searchPaths) {
    if (name.empty()) return;

    const std::string logicalName(name);
    const std::string key = libraryKey(name, searchPaths);

    std::lock_guard<std::mutex> lock(mutex_);
    if (libraries_.count(key)) return;

    LoadResult loaded = tryLoadLibrary(name, searchPaths);
    if (!loaded.handle) {
#ifndef _WIN32
      const char *message = dlerror();
      THROW(, "cannot load shared library '" << logicalName << "': " << (message == nullptr ? "not found" : message))
#else
      THROW(, "cannot load shared library '" << logicalName << "'")
#endif
    }

    libraries_[key] = {loaded.handle, std::move(loaded.path)};
  }

  void DynamicLinker::registerSymbol(std::string name, std::uintptr_t address) {
    if (name.empty() || address == 0) THROW(, "registered dynamic symbol requires a name and address")
    std::lock_guard<std::mutex> lock(mutex_);
    const auto [found, inserted] = registeredSymbols_.emplace(std::move(name), address);
    if (!inserted && found->second != address)
      THROW(, "registered dynamic symbol has conflicting addresses: '" << found->first << "'")
    symbolCache_[found->first] = address;
  }

  void DynamicLinker::redirectSymbol(std::uintptr_t original, std::uintptr_t replacement) {
    if (original == 0 || replacement == 0) THROW(, "dynamic symbol redirection requires non-zero addresses")
    std::lock_guard<std::mutex> lock(mutex_);
    const auto [found, inserted] = redirects_.emplace(original, replacement);
    if (!inserted && found->second != replacement) THROW(, "conflicting dynamic symbol redirection")
    if (inserted) {
      for (auto *cache : {&symbolCache_, &librarySymbolCache_})
        for (auto &[key, address] : *cache)
          if (address == original) address = replacement;
    }
  }

  std::optional<std::uintptr_t> DynamicLinker::resolve(std::string_view symbol,
                                                       const std::vector<std::string> &libNames,
                                                       const std::vector<std::string> &searchPaths) {
    if (symbol.empty()) return std::nullopt;

    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto registered = registeredSymbols_.find(std::string(symbol));
      if (registered != registeredSymbols_.end()) return registered->second;
    }

    for (const std::string &libName : libNames) {
      const std::string key = libraryKey(libName, searchPaths);
      const std::string cacheKey = symbolKey(key, symbol);
      {
        std::lock_guard<std::mutex> lock(mutex_);
        auto cached = librarySymbolCache_.find(cacheKey);
        if (cached != librarySymbolCache_.end()) return cached->second;
        if (!libraries_.count(key)) {
          LoadResult loaded = tryLoadLibrary(libName, searchPaths);
          if (loaded.handle) libraries_[key] = {loaded.handle, std::move(loaded.path)};
        }
        auto library = libraries_.find(key);
        if (library != libraries_.end()) {
          if (void *address = trySymbol(library->second.handle, symbol)) {
            std::uintptr_t value = reinterpret_cast<std::uintptr_t>(address);
            if (auto redirected = redirects_.find(value); redirected != redirects_.end()) value = redirected->second;
            librarySymbolCache_[cacheKey] = value;
            return value;
          }
        }
      }
    }

    return resolveFromDefault(symbol);
  }

  std::optional<std::uintptr_t> DynamicLinker::resolve(std::string_view symbol, const LanguageState &language) {
    return resolve(symbol, language.sharedLibraries(), language.linkerSearchPaths());
  }

  std::optional<std::uintptr_t> DynamicLinker::resolveFromDefault(std::string_view symbol) {
    std::lock_guard<std::mutex> lock(mutex_);

    const std::string symbolName(symbol);
    auto registered = registeredSymbols_.find(symbolName);
    if (registered != registeredSymbols_.end()) return registered->second;

    auto cacheIt = symbolCache_.find(symbolName);
    if (cacheIt != symbolCache_.end()) return cacheIt->second;

#ifndef _WIN32
    void *addr = dlsym(RTLD_DEFAULT, symbolName.c_str());
    if (addr) {
      std::uintptr_t value = reinterpret_cast<std::uintptr_t>(addr);
      if (auto redirected = redirects_.find(value); redirected != redirects_.end()) value = redirected->second;
      symbolCache_[symbolName] = value;
      return value;
    }
#else
    static const char *knownDlls[] = {"kernel32.dll", "msvcrt.dll", "ucrtbase.dll"};
    for (const char *dll : knownDlls) {
      std::string key(dll);
      if (!libraries_.count(key)) {
        void *h = LoadLibraryA(dll);
        if (h) libraries_[key] = {h, key};
      }
      auto libIt = libraries_.find(key);
      if (libIt != libraries_.end()) {
        void *addr = GetProcAddress(libIt->second.handle, symbolName.c_str());
        if (addr) {
          symbolCache_[symbolName] = reinterpret_cast<std::uintptr_t>(addr);
          return reinterpret_cast<std::uintptr_t>(addr);
        }
      }
    }
#endif
    return std::nullopt;
  }

  void DynamicLinker::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto &entry : libraries_) closeLib(entry.second.handle);
    libraries_.clear();
    librarySymbolCache_.clear();
    symbolCache_.clear();
    symbolCache_.insert(registeredSymbols_.begin(), registeredSymbols_.end());
  }
} // namespace compiler
