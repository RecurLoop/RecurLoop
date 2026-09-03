#include <compiler/DynamicLinker.hpp>

#include <utilities/Exception.hpp>

#ifndef _WIN32
  #include <dlfcn.h>
#endif

#include <filesystem>

namespace compiler {
  namespace {
    std::string toFilename(std::string_view name) {
      if (name.find('/') != std::string::npos || name.find('\\') != std::string::npos) return std::string(name);
      if (name.starts_with("lib")) {
#ifndef _WIN32
        return std::string(name) + ".so";
#else
        return std::string(name.substr(3)) + ".dll";
#endif
      }
#ifndef _WIN32
      return "lib" + std::string(name) + ".so";
#else
      return std::string(name) + ".dll";
#endif
    }

    void *tryLoad(const std::string &path) {
#ifndef _WIN32
      return dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL);
#else
      return LoadLibraryA(path.c_str());
#endif
    }

    void *trySymbol(void *handle, std::string_view sym) {
#ifndef _WIN32
      return dlsym(handle, sym.data());
#else
      return GetProcAddress(handle, sym.data());
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

  void DynamicLinker::loadLibrary(std::string_view name, const std::vector<std::string> &searchPaths) {
    if (name.empty()) return;

    std::string logicalName = std::string(name);
    std::string filename = toFilename(name);

    std::lock_guard<std::mutex> lock(mutex_);
    if (libraries_.count(logicalName)) return;

    void *handle = nullptr;

    for (const std::string &dir : searchPaths) {
      std::filesystem::path candidate = std::filesystem::path(dir) / filename;
      std::error_code ec;
      if (std::filesystem::is_regular_file(candidate, ec)) {
        handle = tryLoad(candidate.string());
        if (handle) break;
      }
    }

    if (!handle) {
      handle = tryLoad(filename);
    }

    if (!handle) {
#ifndef _WIN32
      THROW(, "cannot load shared library '" << logicalName << "': " << dlerror())
#else
      THROW(, "cannot load shared library '" << logicalName << "'")
#endif
    }

    libraries_[logicalName] = {handle, filename};
  }

  void DynamicLinker::registerSymbol(std::string name, std::uintptr_t address) {
    if (name.empty() || address == 0) THROW(, "registered dynamic symbol requires a name and address")
    std::lock_guard<std::mutex> lock(mutex_);
    const auto [found, inserted] = registeredSymbols_.emplace(std::move(name), address);
    if (!inserted && found->second != address)
      THROW(, "registered dynamic symbol has conflicting addresses: '" << found->first << "'")
    symbolCache_[found->first] = address;
  }

  std::optional<std::uintptr_t> DynamicLinker::resolve(std::string_view symbol,
                                                       const std::vector<std::string> &libNames) {
    if (symbol.empty()) return std::nullopt;

    // Fast path: check cache
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto cacheIt = symbolCache_.find(std::string(symbol));
      if (cacheIt != symbolCache_.end()) return cacheIt->second;
    }

    // Try each explicitly linked library
    for (const std::string &libName : libNames) {
      // Ensure the library is loaded (loadLibrary has its own lock — no deadlock)
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!libraries_.count(libName)) {
          // Cannot call loadLibrary here (recursive lock). Inline the load.
          std::string filename = toFilename(libName);
          void *handle = tryLoad(filename);
          if (handle) {
            libraries_[libName] = {handle, filename};
          }
        }
      }

      void *addr = nullptr;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        auto libIt = libraries_.find(libName);
        if (libIt != libraries_.end()) {
          addr = trySymbol(libIt->second.handle, symbol);
        }
      }

      if (addr) {
        std::lock_guard<std::mutex> lock(mutex_);
        symbolCache_[std::string(symbol)] = reinterpret_cast<std::uintptr_t>(addr);
        return reinterpret_cast<std::uintptr_t>(addr);
      }
    }

    // Fallback: search all already-loaded libraries (RTLD_DEFAULT / system DLLs)
    return resolveFromDefault(symbol);
  }

  std::optional<std::uintptr_t> DynamicLinker::resolveFromDefault(std::string_view symbol) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto registered = registeredSymbols_.find(std::string(symbol));
    if (registered != registeredSymbols_.end()) return registered->second;

    auto cacheIt = symbolCache_.find(std::string(symbol));
    if (cacheIt != symbolCache_.end()) return cacheIt->second;

#ifndef _WIN32
    void *addr = dlsym(RTLD_DEFAULT, symbol.data());
    if (addr) {
      symbolCache_[std::string(symbol)] = reinterpret_cast<std::uintptr_t>(addr);
      return reinterpret_cast<std::uintptr_t>(addr);
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
        void *addr = GetProcAddress(libIt->second.handle, symbol.data());
        if (addr) {
          symbolCache_[std::string(symbol)] = reinterpret_cast<std::uintptr_t>(addr);
          return reinterpret_cast<std::uintptr_t>(addr);
        }
      }
    }
#endif
    return std::nullopt;
  }

  void DynamicLinker::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto &entry : libraries_) {
      closeLib(entry.second.handle);
    }
    libraries_.clear();
    symbolCache_.clear();
    symbolCache_.insert(registeredSymbols_.begin(), registeredSymbols_.end());
  }
} // namespace compiler
