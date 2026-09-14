#pragma once

#include <string_view>

namespace context { class Context; }

namespace recurloop::internal {
  class CoreDefinition {
  public:
    CoreDefinition() = delete;
    static void apply(context::Context &context, std::string_view source, std::string_view sourcePath);
  };
}
