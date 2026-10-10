#pragma once

#include <filesystem>
#include <span>
#include <string_view>

namespace context {
  class Context;
}

namespace recurloop {
  class Library {
  public:
    Library() = delete;
    // Shared by CLI startup and source imports. Explicit paths precede the
    // environment, installed prefix, build prefix and local libraries directory.
    static std::filesystem::path resolve(context::Context &context, std::string_view name,
                                         std::span<const std::filesystem::path> paths = {});
  };
} // namespace recurloop
