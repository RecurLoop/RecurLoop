#pragma once

namespace context {
  class Context;
}
namespace lexicon {
  class Phrase;
}

namespace recurloop {
  class Engine {
  public:
    Engine() = delete;
    static void registerActions(context::Context &context);
    static void exportImage(context::Context &context, lexicon::Phrase &invoked);
    static void importImage(context::Context &context, lexicon::Phrase &invoked);
    static void define(context::Context &context, lexicon::Phrase &invoked);
    static void includeSource(context::Context &context, lexicon::Phrase &invoked);
  };
} // namespace recurloop
