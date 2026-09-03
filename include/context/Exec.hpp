#pragma once

#include "_module_classes.hpp"
#include <exception>
#include <chrono>
#include <cstdint>
#include <string>
#include <vector>
#include <utilities/Declaration.hpp>

namespace lexicon {
  class Phrase;
}

namespace context {
  class Exec {
  public:
    int status = 0;

    // The currently active phrase while a JIT-backed invocation is running. This
    // is intentionally cleared in the host/executable path, where no JIT frame
    // owns an invoked phrase.
    lexicon::Phrase *invoked = nullptr;

    std::chrono::time_point<std::chrono::system_clock> start;

    struct Timing {
      std::chrono::nanoseconds elaborate{};
      std::chrono::nanoseconds invoke{};
      std::uint64_t elaborateCount = 0;
      std::uint64_t invokeCount = 0;
      std::uint64_t generation = 0;

      void clear() {
        elaborate = {};
        invoke = {};
        elaborateCount = 0;
        invokeCount = 0;
        ++generation;
      }
    } timing;

    struct Args {
      int index = 0;
      int count = 0;
      char **ptr = nullptr;

      bool options = true;
    } args;

    // A phrase invoked from generated machine code cannot unwind a C++
    // exception through a JIT frame. The invocation trampoline captures it
    // here and the Phrase elaboration/invocation boundary rethrows it after the
    // JIT function returns.
    std::exception_ptr pendingException;
    std::uintptr_t pendingNativeEntry = 0;
    std::string pendingNativeSymbol;
    std::string definitionSymbolOverride;
    std::string pendingFunctionVariant;
    std::vector<std::uint8_t> pendingPhrasePayload;
    bool pendingPhraseSerializable = true;
    bool hasPendingPhraseSerializable = false;
    bool pendingPhrasePermanent = false;
    bool hasPendingPhrasePermanent = false;
    bool pendingPhraseRewritable = false;
    bool hasPendingPhraseRewritable = false;
  };
} // namespace context
