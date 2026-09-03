#pragma once
#include <cstdint>
#include <radix/Radix.hpp>
#include <utilities/Utilities.hpp>

namespace lexicon {
  class Lexicon;
  class Dictionary;
  class Match;
  class Phrase;
  namespace phrase {
    enum Contains : std::uint16_t {
      EMPTY = 0,
      PARENT = 1 << 0,
      SUBDICTIONARY = 1 << 1,
      PROTOTYPE = 1 << 2,
      ACTION = 1 << 3,
      SUCCESSOR = 1 << 4,
      TYPE = 1 << 5,
      UNSERIALIZABLE = 1 << 6,
      PERMANENT = 1 << 7,
      REWRITABLE = 1 << 8
    };

    inline Contains operator|(Contains lhs, Contains rhs) {
      return (Contains)((std::uint16_t)lhs | (std::uint16_t)rhs);
    }

    inline Contains operator&(Contains lhs, Contains rhs) {
      return (Contains)((std::uint16_t)lhs & (std::uint16_t)rhs);
    }

    inline Contains &operator|=(Contains &lhs, Contains rhs) {
      lhs = (Contains)((std::uint16_t)lhs | (std::uint16_t)rhs);
      return lhs;
    }

    inline Contains &operator&=(Contains &lhs, Contains rhs) {
      lhs = (Contains)((std::uint16_t)lhs & (std::uint16_t)rhs);
      return lhs;
    }

    inline Contains &operator~(Contains &lhs) {
      lhs = (Contains)(~(std::uint16_t)lhs);
      return lhs;
    }
  } // namespace phrase

  namespace match {
    using Filter = bool (*)(Dictionary *node, Match *candidate);
  } // namespace match

  class Draft;
} // namespace lexicon

namespace context {
  class Context;
} // namespace context
