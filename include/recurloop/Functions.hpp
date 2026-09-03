#pragma once

#include <compiler/TypeSystem.hpp>
#include <utilities/Exception.hpp>

#include <string>
#include <string_view>

namespace context {
  class Context;
}
namespace compiler {
  struct TypedFunction;
}
namespace lexicon {
  class Draft;
  class Phrase;
} // namespace lexicon

namespace recurloop {
  // RecurLoop functions use the ordinary expression and control-flow
  // vocabulary and always compile to a relocatable machine-code module.
  class Functions {
  public:
    Functions() = delete;

    static void setup(context::Context &context);
    static void finalizeSyntax(context::Context &context);
    static void forward(context::Context &context, lexicon::Phrase &invoked);
    static void define(context::Context &context, lexicon::Phrase &invoked);
    static compiler::TypeId signatureType(context::Context &context, std::string_view name);
    static compiler::TypedFunction parseDeclaration(context::Context &context, std::string_view source, bool imported);
    static void commitVariant(context::Context &context, lexicon::Phrase &function);
    static lexicon::Phrase compileAction(context::Context &context, std::string_view signature, std::string_view body,
                                         std::string hint = {}, SourceLocation signatureOrigin = {},
                                         SourceLocation bodyOrigin = {});
    static lexicon::Phrase action(context::Context &context, std::string_view symbol);
    static void bindAction(lexicon::Draft &draft, lexicon::Phrase implementation);
    static void bindAction(lexicon::Phrase &phrase, lexicon::Phrase implementation);
    static void invokeBoundAction(context::Context &context, lexicon::Phrase &invoked);
  };
} // namespace recurloop
