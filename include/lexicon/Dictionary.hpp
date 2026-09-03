#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace lexicon {
  class Dictionary : public radix::Node {
  public:
    using radix::Node::Node;
    using Action = void (*)(context::Context &context, Phrase &phrase);

    DECLARATION Dictionary(radix::Node node);

    DECLARATION Lexicon *getLexicon();
    DECLARATION std::string getKey();
    DECLARATION std::string getKeyEscaped();

    DECLARATION Dictionary append(Byte key, Size keyOffset, Size keyBits);
    DECLARATION Draft make();
    DECLARATION Draft make(Action action);
    DECLARATION Draft make(Phrase prototype);
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

    DECLARATION Phrase getPhrase(radix::item::Filter filter = nullptr);

    DECLARATION Phrase older(radix::item::Filter filter = nullptr);
    DECLARATION Phrase newer(radix::item::Filter filter = nullptr);

  public:
    template <Size N> DECLARATION Dictionary append(const char (&str)[N]);
  };

  template <Size N> Dictionary Dictionary::append(const char (&str)[N]) {
    return append(Byte((unsigned char *)str), 0, (N - 1) * Byte::length);
  }
} // namespace lexicon
