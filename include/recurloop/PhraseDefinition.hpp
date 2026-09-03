#pragma once

namespace context {
  class Context;
}
namespace lexicon {
  class Phrase;
}

namespace recurloop {
  class PhraseDefinition {
  public:
    PhraseDefinition() = delete;
    static void setup(context::Context &context);
    static void define(context::Context &context, lexicon::Phrase &invoked);
    static bool mutate(context::Context &context);
  };
} // namespace recurloop
