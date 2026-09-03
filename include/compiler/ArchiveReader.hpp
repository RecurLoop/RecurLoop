#pragma once

#include <compiler/Module.hpp>

#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace compiler {
  struct ArchiveMember {
    std::string name;
    std::string origin;
    std::vector<std::uint8_t> bytes;
    std::vector<std::string> definitions;

    Module load() const;
  };

  class ArchiveReader {
  public:
    ArchiveReader() = delete;

    static std::vector<ArchiveMember> read(std::span<const std::uint8_t> bytes,
                                           std::string_view origin = "<memory>");
  };
} // namespace compiler
