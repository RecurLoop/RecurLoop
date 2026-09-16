#pragma once

#include <cstdint>
#include <string_view>

namespace context {
  class Context;
}

namespace lexicon {
  class Phrase;
}

namespace recurloop {
  class SyntaxPattern {
  public:
    SyntaxPattern() = delete;

    static void registerActions(context::Context &context);
    static void define(context::Context &context, lexicon::Phrase &invoked);
    static void invoke(context::Context &context, lexicon::Phrase &invoked);

    static const std::uint8_t *capture(context::Context &context, std::string_view name);
    static bool captureExists(context::Context &context, std::string_view name);
  };
} // namespace recurloop
