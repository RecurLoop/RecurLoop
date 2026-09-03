#pragma once

#include "_module_classes.hpp"
#include "Dictionary.hpp"
#include <utilities/Declaration.hpp>

namespace lexicon {
  class Match : public Dictionary {
  protected:
    Size bits = 0;
    bool more = false;

  public:
    using Dictionary::Dictionary;

    DECLARATION Match(Lexicon *lexicon = nullptr, Size address = 0, Size bits = 0, bool wantsMore = false);

    DECLARATION Match &setBits(Size bits);
    DECLARATION Size getBits();
    DECLARATION Match &wantsMore(bool more);
    DECLARATION bool wantsMore();

    friend Dictionary;
  };
} // namespace lexicon
