#pragma once

#include <utilities/Size.hpp>
#include <utilities/Exception.hpp>

#include <string>
#include <string_view>

namespace context {
  class Context;
}

namespace recurloop {
  struct SourceBlock {
    std::string header;
    std::string body;
    std::string path;
    Size headerLine = 1;
    Size headerPosition = 1;
    Size line = 1;
    Size position = 1;
  };

  class Blocks {
  public:
    Blocks() = delete;

    static bool hasOpeningBrace(context::Context &context, bool followingLine = false);
    static bool hasIndentedBody(context::Context &context);
    static SourceBlock capture(context::Context &context);
    static SourceBlock captureIndented(context::Context &context);
    static std::string captureExpression(context::Context &context, SourceLocation *origin = nullptr);
    static bool consume(context::Context &context, std::string_view keyword);
    static void execute(context::Context &context, const SourceBlock &block, bool scoped = true);
  };
} // namespace recurloop
