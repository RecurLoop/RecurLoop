#pragma once

namespace context { class Context; }
namespace lexicon { class Phrase; }

namespace recurloop {
  class Typed {
  public:
    Typed() = delete;
    static void setup(context::Context &context);
    static void declareConvention(context::Context &context, lexicon::Phrase &invoked);
    static void configureModule(context::Context &context, lexicon::Phrase &invoked);
    static void configureLink(context::Context &context, lexicon::Phrase &invoked);
    static void declareExternal(context::Context &context, lexicon::Phrase &invoked);
    static void declareFunction(context::Context &context, lexicon::Phrase &invoked);
    static void declareRecord(context::Context &context, lexicon::Phrase &invoked);
    static void declareMethod(context::Context &context, lexicon::Phrase &invoked);
    static void declarePointer(context::Context &context, lexicon::Phrase &invoked);
  };
} // namespace recurloop
