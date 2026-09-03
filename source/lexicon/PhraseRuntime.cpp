#include <context/Context.hpp>
#include <lexicon/Phrase.hpp>

#include <exception>
#include <utility>

namespace lexicon::detail {
  void rethrowPendingPhraseException(context::Context &context) {
    if (!context.exec.pendingException) return;

    std::exception_ptr pending = std::exchange(context.exec.pendingException, {});
    std::rethrow_exception(pending);
  }
} // namespace lexicon::detail
