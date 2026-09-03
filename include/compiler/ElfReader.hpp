#pragma once

#include <compiler/Module.hpp>

#include <cstdint>
#include <span>
#include <string_view>
#include <string>
#include <vector>

namespace compiler {
  class ElfReader {
  public:
    ElfReader() = delete;

    static Module read(std::span<const std::uint8_t> bytes, std::string_view origin = "<memory>");
    static std::vector<std::string> definitions(std::span<const std::uint8_t> bytes,
                                                std::string_view origin = "<memory>");
  };
} // namespace compiler
