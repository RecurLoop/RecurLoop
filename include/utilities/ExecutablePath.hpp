#pragma once

#include <filesystem>

namespace utilities {
  // Resolve the actual executable, including invocations through PATH/symlinks.
  // Platform-specific discovery is confined here for future host ports.
  std::filesystem::path executablePath();
} // namespace utilities
