#pragma once

#include "_module_classes.hpp"
#include "Config.hpp"
#include "Actions.hpp"
#include "Exec.hpp"
#include "IOStreams.hpp"
#include "Lookup.hpp"
#include "Reference.hpp"
#include "Source.hpp"
#include "Staging.hpp"
#include "Workspace.hpp"
#include "Values.hpp"

#include <compiler/LanguageState.hpp>

#include <utilities/Declaration.hpp>

#include <memory>

namespace recurloop {
  class TranslationUnitRegistry;
}

namespace context {
  class Context {
  public:
    static lexicon::Phrase *currentInvoked(Context &context) {
      return context.exec.invoked;
    }

    static void setCurrentInvoked(Context &context, lexicon::Phrase *invoked) {
      context.exec.invoked = invoked;
    }

    Values values() {
      return Values(lexicon);
    }

    compiler::LanguageState language() {
      return compiler::LanguageState::resolve(lexicon, exec.invoked);
    }

    Actions actions() {
      return Actions(lexicon);
    }

    Config config;

    Exec exec;
    IOStreams io;
    Source source;

    lexicon::Lexicon lexicon;

    JitMemory runtime;
    Workspace workspace;

    Lookup lookup;
    Staging staging;
    Reference reference;

    // Process-local futures. The phrase graph and source descriptor remain
    // serializable; only in-flight compilation state lives here.
    std::shared_ptr<recurloop::TranslationUnitRegistry> translationUnits;
  };
} // namespace context

#ifdef INLINE
  #include <context/Lookup.cpp>
  #include <context/Reference.cpp>
  #include <context/Source.cpp>
  #include <context/Staging.cpp>
#endif
