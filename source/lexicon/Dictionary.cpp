#if !defined(__LEXICON_DICTIONARY_CPP)
  #define __LEXICON_DICTIONARY_CPP
  #include <lexicon/Lexicon.hpp>

namespace lexicon {
  Dictionary::Dictionary(radix::Node node) : radix::Node(node) {}

  Lexicon *Dictionary::getLexicon() {
    return (Lexicon *)getRadix();
  }

  std::string Dictionary::getKey() {
    auto bits = keyBits();

    try {
      std::vector<char> key(Bit::bytes(bits), '\0');
      keyCopy(Bit(key.data(), 0), bits);
      return std::string(key.begin(), key.end());
    } catch (const std::bad_alloc &e) {
      THROW(, "Cannot get phrase key, out of memory.");
    }
  }

  std::string Dictionary::getKeyEscaped() {
    return helper::string::escape(getKey());
  }

  Dictionary Dictionary::append(Byte key, Size keyOffset, Size keyBits) {
    if (isNull()) THROW(, "Append fails, dictionary is null.")
    auto dictionary = Dictionary(radix::Node::append(key, keyOffset, keyBits));
    if (dictionary.isNull()) THROW(, "Append fails, out of memory.")
    return dictionary;
  }

  Draft Dictionary::make() {
    return Draft(*this);
  }

  Draft Dictionary::make(Action action) {
    return Draft(*this, action);
  }

  Draft Dictionary::make(Phrase prototype) {
    return Draft(*this, prototype);
  }

  Phrase Dictionary::push() {
    if (isNull()) THROW(, "Push fails, dictionary is null.")
    auto phrase = Phrase(radix::Node::push());
    if (phrase.isNull()) THROW(, "Push phrase fails, out of memory.")
    return phrase;
  }

  Match Dictionary::matchFirst(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter) {
    auto match = radix::Node::matchFirst(key, keyOffset, keyBits, filter);

    return Match(match.node()).setBits(match.getBits()).wantsMore(match.wantsMore());
  }

  Match Dictionary::matchLongest(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter) {
    auto match = radix::Node::matchLongest(key, keyOffset, keyBits, filter);

    return Match(match.node()).setBits(match.getBits()).wantsMore(match.wantsMore());
  }

  Match Dictionary::matchExact(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter) {
    auto match = radix::Node::matchExact(key, keyOffset, keyBits, filter);

    return Match(match.node()).setBits(match.getBits()).wantsMore(match.wantsMore());
  }

  Dictionary Dictionary::predecessor(radix::node::Filter filter) {
    return Dictionary(radix::Node::predecessor(filter));
  }

  Dictionary Dictionary::fore(radix::node::Filter filter) {
    return Dictionary(radix::Node::fore(filter));
  }

  Dictionary Dictionary::rear(radix::node::Filter filter) {
    return Dictionary(radix::Node::rear(filter));
  }

  Dictionary Dictionary::prev(radix::node::Filter filter) {
    return Dictionary(radix::Node::prev(filter));
  }

  Dictionary Dictionary::next(radix::node::Filter filter) {
    return Dictionary(radix::Node::next(filter));
  }

  Dictionary Dictionary::foreInverse(radix::node::Filter filter) {
    return Dictionary(radix::Node::foreInverse(filter));
  }

  Dictionary Dictionary::rearInverse(radix::node::Filter filter) {
    return Dictionary(radix::Node::rearInverse(filter));
  }

  Dictionary Dictionary::prevInverse(radix::node::Filter filter) {
    return Dictionary(radix::Node::prevInverse(filter));
  }

  Dictionary Dictionary::nextInverse(radix::node::Filter filter) {
    return Dictionary(radix::Node::nextInverse(filter));
  }

  Phrase Dictionary::getPhrase(radix::item::Filter filter) {
    return Phrase(radix::Node::item(filter)).load();
  }

  Phrase Dictionary::older(radix::item::Filter filter) {
    return getPhrase(filter).older(filter);
  }

  Phrase Dictionary::newer(radix::item::Filter filter) {
    return getPhrase(filter).newer(filter);
  }
} // namespace lexicon

#endif
