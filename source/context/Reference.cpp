#if !defined(__CONTEXT_REFERENCE_CPP)
  #define __CONTEXT_REFERENCE_CPP
  #include <context/Context.hpp>

namespace context {
  lexicon::Phrase &Reference::current(Context &context) {
    return context.reference.dictionary;
  }

  void Reference::in(Context &context, lexicon::Phrase &dictionary) {
    DEBUG_PROFILE_FUNCTION();
    DEBUG_LOG(ALIAS IN, dictionary.getKeyEscaped());
    context.reference.dictionary = dictionary;
  }
} // namespace context

#endif
