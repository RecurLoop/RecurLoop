#pragma once

#include <compiler/Module.hpp>

#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace compiler {
  struct DebugLocal {
    std::string name;
    std::string type;
    std::uint64_t frameOffset = 0;
    std::uint32_t size = 0;
    std::uint8_t kind = 0;
    bool signedValue = false;
  };

  struct DebugPoint {
    std::string symbol;
    std::string path;
    std::string function;
    std::string phrase;
    std::uint64_t offset = 0;
    std::uint64_t address = 0;
    std::uint64_t line = 1;
    std::uint64_t column = 1;
    std::vector<DebugLocal> locals;
  };

  class DebugInfo {
  public:
    using SymbolResolver = std::function<std::optional<std::uint64_t>(std::string_view)>;

    static constexpr std::string_view SectionName = ".recurloop.debug";

    static void add(Module &module, const DebugPoint &point);
    static std::vector<DebugPoint> readModule(const Module &module);
    static void appendExecutable(std::vector<std::uint8_t> &executable, const Module &module,
                                 const SymbolResolver &resolve);
    static std::vector<DebugPoint> readExecutable(std::span<const std::uint8_t> executable);
  };
} // namespace compiler
