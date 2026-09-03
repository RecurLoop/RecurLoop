#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace lexicon {
  class Lexicon : public radix::Radix {
  public:
    using radix::Radix::Radix;
    using Action = void (*)(context::Context &context, Phrase &phrase);

    DECLARATION Byte allocate(Size size);

    DECLARATION Lexicon &clear();

  public:
    DECLARATION Dictionary dictionary();
    DECLARATION Phrase phrase(radix::item::Filter filter = nullptr);

    DECLARATION Dictionary append(Byte key, Size keyOffset, Size keyBits);
    DECLARATION Draft make(Action action = nullptr);
    DECLARATION Phrase push();

    DECLARATION Match matchFirst(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter = nullptr);
    DECLARATION Match matchLongest(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter = nullptr);
    DECLARATION Match matchExact(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter = nullptr);

    DECLARATION Dictionary predecessor(radix::node::Filter filter = nullptr);

    DECLARATION Dictionary fore(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary rear(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary prev(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary next(radix::node::Filter filter = nullptr);

    DECLARATION Dictionary foreInverse(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary rearInverse(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary prevInverse(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary nextInverse(radix::node::Filter filter = nullptr);

  public:
    template <Size N> DECLARATION Dictionary append(const char (&str)[N]);
  };
} // namespace lexicon

#include "Dictionary.hpp"
#include "Phrase.hpp"
#include "Draft.hpp"
#include "Match.hpp"

namespace lexicon {
  template <Size N> Dictionary Lexicon::append(const char (&str)[N]) {
    return append(Byte((unsigned char *)str), 0, (N - 1) * Byte::length);
  }
} // namespace lexicon

#ifdef INLINE
  #include <lexicon/Lexicon.cpp>
  #include <lexicon/Dictionary.cpp>
  #include <lexicon/Phrase.cpp>
  #include <lexicon/Draft.cpp>
  #include <lexicon/Match.cpp>
#endif
