#pragma once

#include <utilities/Size.hpp>

#include <iosfwd>
#include <string_view>

namespace context { class Context; }

namespace recurloop {
  void executeSource(context::Context &context, std::string_view source, std::string_view path, Size line,
                     Size position = 1);
  void executeStream(context::Context &context, std::istream &source, std::string_view path, Size line = 1,
                     Size position = 1);
  void executeCurrentBlock(context::Context &context, bool scoped = true);
} // namespace recurloop
