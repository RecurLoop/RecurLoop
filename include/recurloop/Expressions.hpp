#pragma once

#include <context/Values.hpp>
#include <utilities/Exception.hpp>

#include <cstdint>
#include <string_view>

namespace context {
  class Context;
}
namespace lexicon {
  class Phrase;
}

namespace recurloop {
  struct ExpressionOperator {
    enum Flag : std::uint8_t { None = 0, SkipRightWhenTrue = 1, SkipRightWhenFalse = 2 };

    std::uint8_t flags = None;
    std::uint8_t precedence = 0;
  };

  class Expressions {
  public:
    Expressions() = delete;

    static void setup(context::Context &context);
    static context::Value evaluate(context::Context &context, std::string_view source);
    static context::Value evaluate(context::Context &context, std::string_view source, SourceLocation origin);
    static bool isBuiltin(context::Context &context, std::string_view name);
    static lexicon::Phrase prefixOperator(context::Context &context, std::string_view name);
    static lexicon::Phrase infixOperator(context::Context &context, std::string_view name);
    static ExpressionOperator operatorDefinition(lexicon::Phrase &phrase);
    static void bindAssignment(context::Context &context, std::string_view name);

    static void variable(context::Context &context, lexicon::Phrase &invoked);
    static void constant(context::Context &context, lexicon::Phrase &invoked);
    static void assign(context::Context &context, lexicon::Phrase &invoked);
    static void print(context::Context &context, lexicon::Phrase &invoked);
    static void assertTrue(context::Context &context, lexicon::Phrase &invoked);
  };
} // namespace recurloop
