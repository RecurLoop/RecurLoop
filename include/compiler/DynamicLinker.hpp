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
  class DynamicLinker {
  public:
    struct LibraryEntry {
      void *handle;
      std::string name;
    };

    static DynamicLinker &instance();

    void loadLibrary(std::string_view name, const std::vector<std::string> &searchPaths = {});
    void registerSymbol(std::string name, std::uintptr_t address);

    std::optional<std::uintptr_t> resolve(std::string_view symbol, const std::vector<std::string> &libNames = {});

    void clear();

  public:
    DynamicLinker() = default;

    std::optional<std::uintptr_t> resolveFromDefault(std::string_view symbol);

    std::mutex mutex_;
    std::unordered_map<std::string, LibraryEntry> libraries_;
    std::unordered_map<std::string, std::uintptr_t> registeredSymbols_;
    std::unordered_map<std::string, std::uintptr_t> symbolCache_;
  };
} // namespace compiler
