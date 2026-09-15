#include <recurloop/LexiconTransaction.hpp>

#include <context/Context.hpp>
#include <recurloop/EngineImage.hpp>

namespace recurloop {
  void LexiconTransaction::promote(context::Context &context, std::span<const lexicon::Phrase> roots) {
    if (!active) return;
    if (lexicon != &context.lexicon) return;
    EngineImage::promote(context, checkpointAddress, roots);
    active = false;
  }
} // namespace recurloop
