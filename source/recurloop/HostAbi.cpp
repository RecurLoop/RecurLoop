#include <recurloop/HostAbi.hpp>

#include <recurloop/Debugger.hpp>
#include <recurloop/Engine.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/PhraseDefinition.hpp>
#include <recurloop/PhraseNames.hpp>
#include <recurloop/SyntaxPattern.hpp>
#include <recurloop/TypeSyntax.hpp>
#include <recurloop/Typed.hpp>

#include "LanguageInternal.hpp"

namespace recurloop {
  void HostAbi::registerActions(context::Context &context) {
    internal::register_language_actions(context);
    Debugger::registerActions(context);
    Engine::registerActions(context);
    TypeSyntax::registerActions(context);
    Typed::registerActions(context);
    Expressions::registerActions(context);
    Functions::registerActions(context);
    PhraseDefinition::registerActions(context);
    PhraseNames::registerActions(context);
    SyntaxPattern::registerActions(context);
  }
} // namespace recurloop
