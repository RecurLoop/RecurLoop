#pragma once

#include <cstddef>
#include <cstdint>

namespace recurloop {
  bool scalarNativeSysvAvailable() noexcept;
  std::uintptr_t callScalarNativeSysv(std::uintptr_t entry, const std::uintptr_t *args, std::size_t count) noexcept;
} // namespace recurloop
