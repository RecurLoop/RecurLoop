#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>
#include <utilities/Exception.hpp>
#include <unordered_map>

namespace context {
  class Staging {
  public:
    std::vector<lexicon::Phrase> stack;
    lexicon::Phrase dictionary;
    lexicon::Draft phrase;
    std::unordered_map<std::size_t, std::pair<SourceLocation, SourceLocation>> definitions;

    DECLARATION static void push(Context &context, lexicon::Phrase &phrase);
    DECLARATION static void pop(Context &context, Size count);
  };
} // namespace context
