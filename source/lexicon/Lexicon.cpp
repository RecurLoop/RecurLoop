#if !defined(__LEXICON_LEXICON_CPP)
  #define __LEXICON_LEXICON_CPP
  #include <lexicon/Lexicon.hpp>

namespace lexicon {
  Byte Lexicon::allocate(Size size) {
    auto allocated = radix::Radix::Radix::allocate(size);

    if (allocated.isNull()) THROW(, "Cannot allocate " << size << "bytes memory for lexicon.")

    return allocated;
  }

  Lexicon &Lexicon::clear() {
    if (!radix::Radix::clear()) THROW(, "Cannot clear lexicon.")

    return *this;
  }

  Dictionary Lexicon::dictionary() {
    return Dictionary(radix::Radix::Radix::node());
  }

  Phrase Lexicon::phrase(radix::item::Filter filter) {
    return dictionary().getPhrase(filter);
  }

  Dictionary Lexicon::append(Byte key, Size keyOffset, Size keyBits) {
    return dictionary().append(key, keyOffset, keyBits);
  }

  Draft Lexicon::make(Action action) {
    return Draft(dictionary(), action);
  }

  Phrase Lexicon::push() {
    return dictionary().push();
  }

  Dictionary Lexicon::predecessor(radix::node::Filter filter) {
    return dictionary().predecessor(filter);
  }

  Dictionary Lexicon::fore(radix::node::Filter filter) {
    return dictionary().fore(filter);
  }

  Dictionary Lexicon::rear(radix::node::Filter filter) {
    return dictionary().rear(filter);
  }

  Dictionary Lexicon::prev(radix::node::Filter filter) {
    return dictionary().prev(filter);
  }

  Dictionary Lexicon::next(radix::node::Filter filter) {
    return dictionary().next(filter);
  }

  Dictionary Lexicon::foreInverse(radix::node::Filter filter) {
    return dictionary().foreInverse(filter);
  }

  Dictionary Lexicon::rearInverse(radix::node::Filter filter) {
    return dictionary().rearInverse(filter);
  }

  Dictionary Lexicon::prevInverse(radix::node::Filter filter) {
    return dictionary().prevInverse(filter);
  }

  Dictionary Lexicon::nextInverse(radix::node::Filter filter) {
    return dictionary().nextInverse(filter);
  }
} // namespace lexicon
#endif
