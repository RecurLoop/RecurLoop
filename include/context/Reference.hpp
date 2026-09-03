#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace context {
  class Reference {
  public:
    lexicon::Phrase dictionary;

    DECLARATION static lexicon::Phrase& current(Context &context);

    DECLARATION static void in(Context &context, lexicon::Phrase &dictionary);
  };
} // namespace context
