#include "recurloop/LanguageInternal.hpp"
#include <recurloop/bootstrap/SeedLanguage.hpp>

#include <recurloop/Engine.hpp>
#include <recurloop/LanguageGrammar.hpp>

namespace recurloop {
  using namespace internal;

  void bootstrap::SeedLanguage::setup(context::Context &context) {
    lexicon::Phrase root = context::Lookup::current(context);

    // Register only the action families needed by the seed image itself.
    // The source-core runner registers the complete production Host ABI before
    // loading seed.rli, but seed.rli references only this tiny subset.
    register_language_actions(context);
    Engine::registerActions(context);
    setup_phrase_types(context, root);
    // Blocks::capture recognizes structural braces through the language grammar,
    // so the seed needs canonical markers even though they are consumed as raw
    // source by Engine::define rather than elaborated as ordinary phrases.
    LanguageGrammar::ensureMarker(root, "{");
    LanguageGrammar::ensureMarker(root, "}");
    lexicon::Phrase phrase = root;

    // The checked-in core entrypoint deliberately begins with `engine define`
    // so the seed needs no ordinary language syntax beyond whitespace.
    WHITESPACES(action_ignore);

    PHRASE("engine", context::Lookup::enter, , {
      WHITESPACES(action_ignore)
      PHRASE("define", Engine::define, .setType(lexicon::phrase::type::getCallable(PARENT)));
    });
  }
} // namespace recurloop
