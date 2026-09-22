#pragma once

#include <cstddef>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace compiler {
  class LanguageState;

  class DynamicLinker {
  public:
    struct LibraryEntry {
      void *handle;
      std::string name;
    };

    static DynamicLinker &instance();

    void loadLibrary(std::string_view name, const std::vector<std::string> &searchPaths = {});
    static std::optional<std::string> libraryPath(std::string_view name,
                                                  const std::vector<std::string> &searchPaths = {});
    void registerSymbol(std::string name, std::uintptr_t address);

    std::optional<std::uintptr_t> resolve(std::string_view symbol, const std::vector<std::string> &libNames = {},
                                          const std::vector<std::string> &searchPaths = {});
    std::optional<std::uintptr_t> resolve(std::string_view symbol, const LanguageState &language);

    void clear();

  public:
    DynamicLinker() = default;

    std::optional<std::uintptr_t> resolveFromDefault(std::string_view symbol);

    std::mutex mutex_;
    // A logical library name is scoped by its ordered search path. Different
    // languages/sessions may deliberately bind the same -l name to different
    // files, so neither handles nor resolved symbols can be cached by name alone.
    std::unordered_map<std::string, LibraryEntry> libraries_;
    std::unordered_map<std::string, std::uintptr_t> librarySymbolCache_;
    std::unordered_map<std::string, std::uintptr_t> registeredSymbols_;
    std::unordered_map<std::string, std::uintptr_t> symbolCache_;
  };
} // namespace compiler
