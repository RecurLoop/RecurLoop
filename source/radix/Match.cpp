#if !defined(__RADIX_MATCH_CPP)
  #define __RADIX_MATCH_CPP
  #include <radix/Radix.hpp>

namespace radix {
  Node Match::node() {
    return *this;
  }

  Size Match::getBits() {
    return bits;
  }

  Match *Match::setBits(Size bits) {
    this->bits = bits;
    return this;
  }

  Match *Match::wantsMore(bool more) {
    this->more = more;
    return this;
  }

  bool Match::wantsMore() {
    return more;
  }
} // namespace radix

#endif
