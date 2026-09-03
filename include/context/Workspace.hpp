#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

#include <cstdint>
#include <string>
#include <vector>

namespace context {
  class Workspace {
  public:
    struct NativeSection {
      std::string name;
      std::vector<std::uint8_t> bytes;
      Size memorySize = 0;
      Size alignment = 1;
      std::uint8_t type = 0;
      std::uint16_t flags = 0;
    };

    Appender key;
    Appender code;
    std::vector<std::uint8_t> readOnlyData;
    std::vector<std::uint8_t> data;
    Size bssBytes = 0;
    std::vector<NativeSection> customSections;
  };
} // namespace context
