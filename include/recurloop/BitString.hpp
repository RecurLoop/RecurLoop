#pragma once

#include <cstdint>

namespace recurloop {
  // A non-owning bit-precise view. Bits are ordered from the most significant
  // bit of data[0], matching Bit and radix key ordering.
  struct BitString {
    const std::uint8_t *data = nullptr;
    std::uint64_t bits = 0;
  };
} // namespace recurloop
