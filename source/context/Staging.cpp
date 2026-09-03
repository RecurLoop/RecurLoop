#if !defined(__CONTEXT_STAGING_CPP)
  #define __CONTEXT_STAGING_CPP
  #include <context/Context.hpp>
  #include <unistd.h>

namespace context {
  void Staging::push(Context &context, lexicon::Phrase &phrase) {
    DEBUG_PROFILE_FUNCTION();
    context.staging.stack.push_back(phrase);
    context.staging.dictionary = phrase;
    context.staging.phrase = context.staging.dictionary.append("");
  }

  void Staging::pop(Context &context, Size count) {
    DEBUG_PROFILE_FUNCTION();
    for (Size i = 0; i < count; i++) {
      if (context.staging.stack.empty()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "cannot pop an empty staging stack")
      }

      context.staging.stack.pop_back();
    }

    if (context.staging.stack.empty()) {
      const SourceLocation location{context.source.path, context.source.line, context.source.position};
      THROW_AT(location, "cannot leave the staging stack empty")
    }

    context.staging.dictionary = context.staging.stack.back();
    context.staging.phrase = context.staging.dictionary.append("");
  }
} // namespace context

#endif
