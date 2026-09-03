#pragma once

#include <utilities/Size.hpp>

#include <string_view>

namespace context { class Context; }

namespace recurloop {
  void executeSource(context::Context &context, std::string_view source, std::string_view path, Size line,
                     Size position = 1);
} // namespace recurloop
