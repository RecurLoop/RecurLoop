#include <utilities/ExecutablePath.hpp>

namespace utilities {
  std::filesystem::path executablePath() {
#ifdef __linux__
    std::error_code error;
    auto path = std::filesystem::read_symlink("/proc/self/exe", error);
    if (!error) return path;
#endif
    return {};
  }
} // namespace utilities
