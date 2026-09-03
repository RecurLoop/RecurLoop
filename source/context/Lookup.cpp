#if !defined(__CONTEXT_LOOKUP_CPP)
  #define __CONTEXT_LOOKUP_CPP
  #include <context/Context.hpp>

namespace context {
  lexicon::Phrase &Lookup::current(Context &context) {
    return context.lookup.dictionary;
  }

  void Lookup::in(Context &context, lexicon::Phrase &dictionary) {
    DEBUG_PROFILE_FUNCTION();
    DEBUG_LOG(LOOKUP IN, dictionary.getKeyEscaped());

    context.lookup.dictionary = dictionary;
  }

  void Lookup::enter(Context &context, lexicon::Phrase &dictionary) {
    DEBUG_PROFILE_FUNCTION();
    DEBUG_LOG(LOOKUP ENTER, dictionary.getKeyEscaped());

    context.lookup.stack.push_back(context.lookup.dictionary);
    context.lookup.dictionary = dictionary;
  }

  void Lookup::leave(Context &context, lexicon::Phrase &dictionary) {
    DEBUG_PROFILE_FUNCTION();
    DEBUG_LOG(LOOKUP LEAVE, dictionary.getKeyEscaped());

    lexicon::Phrase ancestor = dictionary.getSuccessor();
    if (ancestor.isNull()) {
      for (lexicon::Phrase phrase = context.lookup.dictionary; !phrase.isNull();) {
        lexicon::Phrase candidate = phrase.getSuccessor();

        if (!candidate.isNull()) {
          ancestor = candidate;
          break;
        }

        if (context.lookup.stack.empty()) break;

        phrase = context.lookup.stack.back();
        context.lookup.stack.pop_back();
      }

      if (ancestor.isNull()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "cannot leave phrase '" << dictionary.getKeyEscaped() << "' because it has no ancestor")
      }
    }

    context.lookup.dictionary = ancestor;
  }

  void Lookup::leave(Context &context, lexicon::Phrase &dictionary, Size level) {
    DEBUG_PROFILE_FUNCTION();
    DEBUG_LOG(LOOKUP LEAVE, dictionary.getKeyEscaped());

    lexicon::Phrase ancestor = dictionary.getSuccessor();
    if (ancestor.isNull()) {
      for (lexicon::Phrase phrase = context.lookup.dictionary; !phrase.isNull();) {
        lexicon::Phrase candidate = phrase.getSuccessor();

        if (!candidate.isNull() && level-- <= 1) {
          ancestor = candidate;
          break;
        }

        if (context.lookup.stack.empty()) break;

        phrase = context.lookup.stack.back();
        context.lookup.stack.pop_back();
      }

      if (ancestor.isNull()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "cannot leave phrase '" << dictionary.getKeyEscaped() << "' because it has no ancestor")
      }
    }

    context.lookup.dictionary = ancestor;
  }
} // namespace context

#endif
