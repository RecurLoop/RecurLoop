#pragma once

#include <lexicon/Phrase.hpp>

#include <string>
#include <vector>

namespace context {
  class Context;
}

namespace recurloop {
  struct ParsedPhraseName {
    std::vector<std::string> path;
    std::string name;
    lexicon::Phrase operation;

    std::string qualified() const;
  };

  class PhraseNames {
  public:
    PhraseNames() = delete;

    static void setup(context::Context &context);
    static ParsedPhraseName parseAssignment(context::Context &context, bool allowEmpty = false,
                                            bool allowMissingOperation = false);
  };
} // namespace recurloop
