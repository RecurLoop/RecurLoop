#pragma once

#include <compiler/Module.hpp>

#include <cstdint>
#include <string_view>
#include <vector>

namespace compiler {
  class ElfWriter {
  public:
    ElfWriter() = delete;

    static std::vector<std::uint8_t> write(const Module &module);
    static std::vector<std::uint8_t> writeExecutable(const Module &module, std::string_view entrySymbol);
  };
} // namespace compiler
