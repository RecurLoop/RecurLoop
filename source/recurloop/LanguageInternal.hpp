#pragma once

#include <recurloop/Language.hpp>
#include <recurloop/Assembler.hpp>
#include <recurloop/Debugger.hpp>
#include <recurloop/PhraseNames.hpp>
#include <compiler/Module.hpp>
#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <utilities/Console.hpp>
#include <utilities/Exception.hpp>
#include <utilities/Size.hpp>
#include <utilities/debug/Logger.hpp>
#include <utilities/debug/Profiler.hpp>
#include <utilities/helper/string.hpp>

#include <chrono>
#include <iomanip>
#include <ostream>
#include <string>

namespace recurloop {
namespace internal {

  void action_ignore(context::Context &context, lexicon::Phrase &invoked);
  void action_ping(context::Context &context, lexicon::Phrase &invoked);
  void elaborate_scoped_callable(context::Context &context, lexicon::Phrase &invoked);
  void action_exit(context::Context &context, lexicon::Phrase &invoked);
  void action_continue(context::Context &context, lexicon::Phrase &invoked);
  void action_progress_byte(context::Context &context, lexicon::Phrase &invoked);
  void action_debug_stats(context::Context &context, lexicon::Phrase &invoked);
  void action_debug_dictionary_dump(context::Context &context, lexicon::Phrase &invoked);
  void action_debug_workspace_print(context::Context &context, lexicon::Phrase &invoked);
  void action_pass_byte(context::Context &context, lexicon::Phrase &invoked);
  void action_pass_carriage_return(context::Context &context, lexicon::Phrase &invoked);
  void action_pass_line_feed(context::Context &context, lexicon::Phrase &invoked);
  void action_pass_horizontal_tab(context::Context &context, lexicon::Phrase &invoked);
  void action_pass_vertical_tab(context::Context &context, lexicon::Phrase &invoked);
  void action_let_enter(context::Context &context, lexicon::Phrase &invoked);
  void action_let_equals(context::Context &context, lexicon::Phrase &invoked);
  void action_anonymous_let_commit(context::Context &context, lexicon::Phrase &invoked);
  void action_reference_enter(context::Context &context, lexicon::Phrase &invoked);
  void action_reference_colon(context::Context &context, lexicon::Phrase &invoked);
  void action_reference_whitespaces(context::Context &context, lexicon::Phrase &invoked);
  void action_reference_commit(context::Context &context, lexicon::Phrase &invoked);
  void action_dictionary_enter(context::Context &context, lexicon::Phrase &invoked);
  void action_dictionary_whitespaces(context::Context &context, lexicon::Phrase &invoked);
  void action_dictionary_leave(context::Context &context, lexicon::Phrase &invoked);
  void action_dictionary_equals(context::Context &context, lexicon::Phrase &invoked);
  void action_dictionary_commit(context::Context &context, lexicon::Phrase &invoked);
  void action_lexicon(context::Context &context, lexicon::Phrase &invoked);
  void action_merge(context::Context &context, lexicon::Phrase &invoked);
  void action_scope(context::Context &context, lexicon::Phrase &invoked);
  void action_hex(context::Context &context, lexicon::Phrase &invoked);
  void setup_phrase_types(context::Context &context, lexicon::Phrase &root);
  void register_language_actions(context::Context &context);

} // namespace internal
} // namespace recurloop
