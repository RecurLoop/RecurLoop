#pragma once

#include <cstdint>
#include <string_view>
#include <string>
#include <vector>
#include <cstddef>

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

    struct Expectation {
      std::size_t start = 0;
      std::string name;
      std::string matcher;
      std::string literal;
    };
    static void validate(std::string_view pattern);
    static std::string pattern(lexicon::Phrase phrase);
    // The ordinary matcher reports continuations at EOF without executing an
    // action or evaluating captures. Optional/choice branches are all retained.
    // An empty name/matcher/literal marks a complete pattern at EOF.
    static std::vector<Expectation> expect(std::string_view pattern, std::string_view prefix);
    static bool accepts(std::string_view matcher, std::string_view value);
    static std::string insertion(std::string_view pattern, std::string_view prefix, const Expectation &item);
  };
} // namespace recurloop
