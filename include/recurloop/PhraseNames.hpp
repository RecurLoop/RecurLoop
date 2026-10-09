#pragma once

#include <lexicon/Phrase.hpp>
#include <utilities/Exception.hpp>

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
    // Source range of the consumed name during semantic inspection.
    SourceLocation start;
    SourceLocation end;

    std::string qualified() const;
  };

  class PhraseNames {
  public:
    PhraseNames() = delete;

    static void registerActions(context::Context &context);
    static void setup(context::Context &context);
    static ParsedPhraseName parseAssignment(context::Context &context, bool allowEmpty = false,
                                            bool allowMissingOperation = false);
  };
} // namespace recurloop
