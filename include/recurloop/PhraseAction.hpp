#pragma once

#include <cstdint>

namespace recurloop {
  // Stable descriptor emitted for an inline phrase action. The symbol names a
  // relocatable language module; no process-local entry address crosses the
  // typed Context API boundary.
  struct PhraseAction {
    const std::uint8_t *symbol = nullptr;
    std::uint64_t bytes = 0;
  };
} // namespace recurloop
