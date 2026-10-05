#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace utilities {
  struct Completion {
    std::size_t start = 0;
    std::vector<std::string> candidates;
  };
} // namespace utilities
