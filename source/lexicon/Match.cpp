#if !defined(__LEXICON_MATCH_CPP)
  #define __LEXICON_MATCH_CPP
  #include <lexicon/Lexicon.hpp>

namespace lexicon {
  Match::Match(Lexicon *lexicon, Size address, Size bits, bool wantsMore)
      : Dictionary(lexicon, address), bits(bits), more(wantsMore) {}

  Match &Match::setBits(Size bits) {
    this->bits = bits;
    return *this;
  }

  Size Match::getBits() {
    return bits;
  }

  Match &Match::wantsMore(bool more) {
    this->more = more;
    return *this;
  }

  bool Match::wantsMore() {
    return more;
  }
} // namespace lexicon

#endif
