#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace context {
  class Staging {
  public:
    std::vector<lexicon::Phrase> stack;
    lexicon::Phrase dictionary;
    lexicon::Draft phrase;

    DECLARATION static void push(Context &context, lexicon::Phrase &phrase);
    DECLARATION static void pop(Context &context, Size count);
  };
} // namespace context
