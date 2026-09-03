#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace context {
  class Lookup {
  public:
    std::vector<lexicon::Phrase> stack;
    lexicon::Phrase dictionary;

    DECLARATION static lexicon::Phrase& current(Context &context);

    DECLARATION static void in(Context &context, lexicon::Phrase &dictionary);

    DECLARATION static void enter(Context &context, lexicon::Phrase &dictionary);

    DECLARATION static void leave(Context &context, lexicon::Phrase &dictionary);
    DECLARATION static void leave(Context &context, lexicon::Phrase &dictionary, Size level);
  };
} // namespace context
