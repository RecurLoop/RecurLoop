#pragma once

#include <cstdint>
#include <span>

namespace recurloop::embedded {
  std::span<const std::uint8_t> coreImage();
}
