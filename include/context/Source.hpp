#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace context {
  class Source {
  public:
    std::string path = "";
    Size line = 1;
    Size position = 1;
    bool more = true;

    struct Buffer {
      std::string str = "";
      Size match = 0;
      Size offset = 0;
      Size bits = 0;
    } buffer;

    DECLARATION static void load(Context &context, bool slide = false);
    DECLARATION static void progress(Context &context, Size bits);

    DECLARATION static lexicon::Phrase matchFirst(Context &context, lexicon::Dictionary &dictionary, lexicon::match::Filter filter, bool slide);
    DECLARATION static lexicon::Phrase matchLongest(Context &context, lexicon::Dictionary &dictionary, lexicon::match::Filter filter, bool slide);
    DECLARATION static lexicon::Phrase matchExact(Context &context, lexicon::Dictionary &dictionary, lexicon::match::Filter filter, bool slide);
  };
} // namespace context
