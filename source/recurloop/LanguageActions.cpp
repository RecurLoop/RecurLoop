#include "LanguageInternal.hpp"

#include <recurloop/NameInterpolation.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/PhraseDefinition.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/TranslationUnits.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <utilities/Byte.hpp>

#include <cctype>
#include <cstdint>
#include <span>
#include <algorithm>

namespace recurloop {
  namespace internal {

    void action_ignore(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(Ignore);
      DEBUG_LOG(IGNORE, invoked.getKeyEscaped());
    }

    void action_ping(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(Ping);
      DEBUG_LOG(Ping, "Pong");

      *context.io.out << "pong" << std::endl;
    }

    void elaborate_scoped_callable(context::Context &context, lexicon::Phrase &invoked) {
      lexicon::phrase::type::action(context, invoked);
      // An action can replace the lexicon and invalidate the invoked phrase.
      // A null invocation is the existing signal that no epilogue may touch it.
      if (context.exec.invoked != nullptr) context::Lookup::leave(context, invoked);
    }

    void action_exit(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(Return);
      DEBUG_LOG(RETURN, "");

      SourceLocation origin;
      const std::string expression = Blocks::captureExpression(context, &origin);
      std::int64_t status = 0;
      if (!expression.empty()) {
        const context::Value value = Expressions::evaluate(context, expression, origin);
        if (!value.isInteger()) THROW_AT(origin, "exit status must be an integer")
        status = value.asInteger();
        if (status < 0 || status > 255) THROW_AT(origin, "exit status must be between 0 and 255")
      }

      context.exec.status = static_cast<int>(status);
      context.source.buffer.str.clear();
      context.source.buffer.offset = 0;
      context.source.buffer.bits = 0;

      context.source.more = false;
    }

    void action_continue(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(Continue);
      DEBUG_LOG(CONTINUE, "");
      context.source.buffer.str.clear();
      context.source.buffer.offset = 0;
      context.source.buffer.bits = 0;

      context.io.in = nullptr;
    }

    void action_progress_byte(context::Context &context, lexicon::Phrase &invoked) {
      context::Source::progress(context, Byte::length);
    }

    void action_debug_stats(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(Stats);

      auto end = std::chrono::high_resolution_clock::now();
      auto duration = duration_cast<std::chrono::microseconds>(end - context.exec.start);
      context.exec.start = end;

      double seconds = duration.count() / 1000000.0;
      const double elaborateSeconds = context.exec.timing.elaborate.count() / 1000000000.0;
      const double invokeSeconds = context.exec.timing.invoke.count() / 1000000000.0;

      *context.io.out << BOLD NEWLINE << "▶ Execution time: " << RESET << BRIGHT_YELLOW_TEXT << std::fixed
                      << std::setprecision(6) << seconds << " s" << RESET << NEWLINE;
      *context.io.out << BOLD << "▶ Elaborate time:  " << RESET << BRIGHT_YELLOW_TEXT << std::fixed
                      << std::setprecision(6) << elaborateSeconds << " s" << RESET << " ("
                      << context.exec.timing.elaborateCount << " calls)" << NEWLINE;
      *context.io.out << BOLD << "▶ Invoke time:    " << RESET << BRIGHT_YELLOW_TEXT << std::fixed
                      << std::setprecision(6) << invokeSeconds << " s" << RESET << " ("
                      << context.exec.timing.invokeCount << " calls)" << NEWLINE;

      Size used = context.lexicon.memoryUsed();
      Size unused = context.lexicon.memoryUnused();
      Size total = context.lexicon.memorySize();

      constexpr int barWidth = 40;
      double usageRatio = static_cast<double>(used) / total;

      int usedWidth = static_cast<int>(barWidth * usageRatio);
      int freeWidth = barWidth - usedWidth;

      *context.io.out << BOLD << "▶ Lexicon memory usage:   " << RESET;

      *context.io.out << BRIGHT_GREEN_BACKGROUND;
      for (int i = 0; i < usedWidth; ++i) *context.io.out << " ";
      *context.io.out << BRIGHT_BLACK_BACKGROUND;
      for (int i = 0; i < freeWidth; ++i) *context.io.out << " ";
      *context.io.out << RESET << " ";

      *context.io.out << BRIGHT_GREEN_TEXT << used << RESET << " used, " << BRIGHT_BLACK_TEXT << unused << RESET
                      << " free, " << BRIGHT_WHITE_TEXT << total << RESET << " total" << NEWLINE;

      DEBUG_LOG(STATS, "time: " << seconds << ", used: " << used << ", free: " << unused);
      DEBUG_LOG(STATS, "elaborate-time: " << elaborateSeconds << ", elaborate-calls: "
                                          << context.exec.timing.elaborateCount << ", invoke-time: " << invokeSeconds
                                          << ", invoke-calls: " << context.exec.timing.invokeCount);
      context.exec.timing.clear();
    }

    void render_phrase_recursive(std::ostream *out, lexicon::Phrase dictionary, int level) {
      auto filter = [](radix::Node *item, radix::Node *candidate) -> bool { return !candidate->isEmpty(); };

      for (lexicon::Dictionary cursor = dictionary.fore(filter); !cursor.isNull(); cursor = cursor.next(filter)) {
        lexicon::Phrase phrase = cursor.getPhrase();
        lexicon::Dictionary subdictionary = phrase.getSubdictionary();
        lexicon::Phrase prototype = phrase.getPrototype();
        lexicon::Phrase successor = phrase.getSuccessor();
        lexicon::Phrase type = phrase.getType();

        *out << std::string(level, ' ') << BRIGHT_YELLOW_TEXT << phrase.getKeyEscaped() << RESET << " [";

        *out << (subdictionary.isNull() ? " " : "D");

        if (!type.isNull()) *out << " type: " << BRIGHT_MAGENTA_TEXT << type.getKeyEscaped() << RESET;

        if (!prototype.isNull()) *out << " prototype: " << BRIGHT_BLUE_TEXT << prototype.getKeyEscaped() << RESET;

        if (!successor.isNull()) *out << " successor: " << BRIGHT_GREEN_TEXT << successor.getKeyEscaped() << RESET;

        *out << " ]" << NEWLINE;

        if (phrase.containsSubdictionary()) {
          level += 1;
          render_phrase_recursive(out, phrase, level);
          level -= 1;
        }
      }
    }

    void action_debug_dictionary_dump(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(Dump);
      DEBUG_LOG(DICTIONARYDUMP, invoked.getKeyEscaped());

      lexicon::Phrase root = context.lexicon.phrase();

      *context.io.out << NEWLINE BRIGHT_YELLOW_TEXT "▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼" NEWLINE;
      render_phrase_recursive(context.io.out, root, 0);
      *context.io.out << BRIGHT_YELLOW_TEXT "▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲" NEWLINE RESET;
    }

    void action_debug_workspace_print(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(WorkspacePrint);
      std::cout << context.workspace.key.c_str() << std::endl;
    }

    void action_pass_byte(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(PassByte);

      while (context.source.buffer.bits < Byte::length) {
        if (!context.source.more) {
          return;
        }

        context::Source::load(context, false);
      }

      char character = context.source.buffer.str.data()[context.source.buffer.offset / Byte::length];

      DEBUG_LOG(PASS, character);

      context.workspace.key.append(character);
      context::Source::progress(context, Byte::length);
    }

    void action_pass_carriage_return(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(PassCarriageReturn);
      unsigned char character = '\r';
      DEBUG_LOG(PASS, character);
      context.workspace.key.append(character);
    }

    void action_pass_line_feed(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(PassLineFeed);
      unsigned char character = '\n';
      DEBUG_LOG(PASS, character);
      context.workspace.key.append(character);
    }

    void action_pass_horizontal_tab(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(PassHorizontalTab);
      unsigned char character = '\t';
      DEBUG_LOG(PASS, character);
      context.workspace.key.append(character);
    }

    void action_pass_vertical_tab(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(PassVerticalTab);
      unsigned char character = '\v';
      DEBUG_LOG(PASS, character);
      context.workspace.key.append(character);
    }

    void action_lexicon(context::Context &context, lexicon::Phrase &invoked) {
      SourceBlock block = Blocks::capture(context);
      const bool headerIsEmpty = std::all_of(block.header.begin(), block.header.end(),
                                             [](unsigned char character) { return std::isspace(character); });
      if (!headerIsEmpty) THROW(, "lexicon expects '{' immediately after the phrase")

      context.exec.pendingPhrasePayload = TranslationUnitRegistry::descriptor(block.body);
      context::Lookup::leave(context, invoked, 1);
    }

    void action_merge(context::Context &context, lexicon::Phrase &invoked) {
      TranslationUnitRegistry::merge(context, invoked);
    }

    void action_let_equals(context::Context &context, lexicon::Phrase &invoked);

    void select_let_dictionary(context::Context &context, const std::string &name) {
      auto filter = [](radix::Node *dictionary, radix::Match *candidate) -> bool {
        return !lexicon::Dictionary(*candidate).getPhrase().getSubdictionary().isNull();
      };

      lexicon::Match matched = context.staging.dictionary.matchExact(Byte(const_cast<char *>(name.data())), 0,
                                                                     name.size() * Byte::length, filter);

      if (matched.isNull()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "undefined dictionary \"" << helper::string::escape(name) << "\"")
      }

      context.staging.dictionary = matched.getPhrase();
    }

    lexicon::Phrase let_equals(lexicon::Phrase phrase) {
      while (!phrase.isNull()) {
        if (phrase.containsSubdictionary()) {
          lexicon::Match matched = phrase.matchExact(Byte(const_cast<char *>("=")), 0, Byte::length,
                                                     [](radix::Node *, radix::Match *candidate) {
                                                       return !lexicon::Dictionary(*candidate).getPhrase().isNull();
                                                     });
          if (!matched.isNull()) return matched.getPhrase();
        }
        if (!phrase.containsPrototype()) break;
        phrase = phrase.getPrototype();
      }
      return lexicon::Phrase(phrase.getLexicon());
    }

    void action_let_enter(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(LetEnter);
      context.workspace.key.clear();
      context::Staging::push(context, context.staging.dictionary);
      context::Lookup::enter(context, invoked);

      ParsedPhraseName parsed = PhraseNames::parseAssignment(context, true, true);
      if (parsed.operation.isNull()) return;
      if (parsed.operation.getKey() != "=") THROW(, "phrase definition requires '='")
      for (const std::string &segment : parsed.path) select_let_dictionary(context, segment);
      context.workspace.key.clear();
      context.workspace.key.append(parsed.name);

      lexicon::Phrase equals = let_equals(invoked);
      if (equals.isNull()) THROW(, "let phrase has no '=' continuation")
      action_let_equals(context, equals);
    }

    void action_let_equals(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(LetEquals);
      const std::string name = Assembler::prepareDefinitionName(context, context.workspace.key.c_str());
      context.staging.phrase =
          context.staging.dictionary.make().append(Byte((unsigned char *)name.data()), 0, name.size() * Byte::length);
      context::Lookup::enter(context, invoked);
    }

    void finalize_staged_code(context::Context &context, lexicon::Phrase &invoked) {
      if (context.workspace.code.empty()) return;

      compiler::Module module;
      const std::span<const std::uint8_t> code(context.workspace.code.getMemory().toPtr(),
                                               context.workspace.code.size());
      const std::size_t entryOffset = module.append(compiler::SectionKind::Text, code, 16);
      if (!context.workspace.readOnlyData.empty())
        module.append(compiler::SectionKind::ReadOnlyData, context.workspace.readOnlyData, 1);
      if (!context.workspace.data.empty()) module.append(compiler::SectionKind::Data, context.workspace.data, 1);
      if (context.workspace.bssBytes != 0) module.reserve(compiler::SectionKind::Bss, context.workspace.bssBytes, 1);
      Assembler::defineEntry(context, module, entryOffset);

      Assembler::finalize(context, invoked, module);
    }

    void commit_let(context::Context &context, lexicon::Phrase &invoked, Size lookupLevels) {
      DEBUG_PROFILE_SCOPE(LetCommit);

      finalize_staged_code(context, invoked);

      if (!context.staging.phrase.containsType() && !context.staging.phrase.containsPrototype())
        context.staging.phrase.setType(lexicon::phrase::type::getData(invoked));

      lexicon::Phrase &saved = context.staging.phrase.save();
      Assembler::commitNative(context, saved);
      Functions::commitVariant(context, saved);
      if (!context.exec.pendingPhrasePayload.empty()) {
        Byte output = saved.allocate(context.exec.pendingPhrasePayload.size());
        std::memcpy(output.toPtr(), context.exec.pendingPhrasePayload.data(), context.exec.pendingPhrasePayload.size());
        context.exec.pendingPhrasePayload.clear();
      }
      if (context.exec.hasPendingPhraseSerializable) {
        saved.setSerializable(context.exec.pendingPhraseSerializable).save();
        context.exec.hasPendingPhraseSerializable = false;
      }
      if (context.exec.hasPendingPhraseRewritable) {
        saved.setRewritable(context.exec.pendingPhraseRewritable).save();
        context.exec.hasPendingPhraseRewritable = false;
      }
      if (context.exec.hasPendingPhrasePermanent) {
        saved.setPermanent(context.exec.pendingPhrasePermanent).save();
        context.exec.hasPendingPhrasePermanent = false;
      }

      if (TranslationUnitRegistry::isDescriptor(saved)) {
        if (!context.translationUnits) context.translationUnits = std::make_shared<TranslationUnitRegistry>(context);
        context.translationUnits->start(saved);
      }

      context::Staging::pop(context, 1);

      context::Lookup::leave(context, invoked, lookupLevels);
    }

    void action_anonymous_let_commit(context::Context &context, lexicon::Phrase &invoked) {
      commit_let(context, invoked, 1);
    }

    void action_reference_enter(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(ReferenceEnter);
      context::Reference::in(context, context::Lookup::current(context));
      context::Lookup::enter(context, invoked);
      context.workspace.key.clear();
    }

    void action_reference_colon(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(ReferenceColon);

      auto filter = [](radix::Node *dictionary, radix::Match *candidate) -> bool {
        return !lexicon::Dictionary(*candidate).getPhrase().getSubdictionary().isNull();
      };

      lexicon::Match matched = context::Reference::current(context).matchExact(context.workspace.key.getMemory(), 0,
                                                                               context.workspace.key.bits(), filter);

      if (matched.isNull()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "undefined dictionary \"" << helper::string::escape(context.workspace.key.c_str()) << "\"")
      }

      lexicon::Phrase phrase = matched.getPhrase();

      context::Reference::current(context) = phrase;
      context.workspace.key.clear();

      context::Lookup::leave(context, invoked);
    }

    void action_reference_whitespaces(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(ReferenceWhitespaces);

      auto record = [](context::Context &context, lexicon::Phrase &invoked) {
        DEBUG_PROFILE_SCOPE(ReferenceWhitespacesRecord);

        context::Source::Buffer &buffer = context.source.buffer;
        context.workspace.key.append(Bit(buffer.str.data(), buffer.match), buffer.offset - buffer.match);
      };

      auto apply = [](context::Context &context, lexicon::Phrase &invoked) {
        DEBUG_PROFILE_SCOPE(ReferenceWhitespacesApply);

        Size lexiconCheckpoint;
        invoked.fetch(0, lexiconCheckpoint);

        radix::Checkpoint(&context.lexicon, lexiconCheckpoint).restore();
      };

      auto discard = [](context::Context &context, lexicon::Phrase &invoked) {
        DEBUG_PROFILE_SCOPE(ReferenceWhitespacesDiscard);

        Size lexiconCheckpoint;
        Size workspaceCheckpoint;
        invoked.fetch(0, lexiconCheckpoint, workspaceCheckpoint);

        context.workspace.key.truncate(workspaceCheckpoint);
        radix::Checkpoint(&context.lexicon, lexiconCheckpoint).restore();

        invoked.older().elaborate(context);
      };

      auto end = [](context::Context &context, lexicon::Phrase &invoked) {
        DEBUG_PROFILE_SCOPE(ReferenceWhitespacesEnd);

        Size lexiconCheckpoint;
        invoked.fetch(0, lexiconCheckpoint);
        radix::Checkpoint(&context.lexicon, lexiconCheckpoint).restore();

        context::Lookup::leave(context, invoked);
      };

      lexicon::Phrase &phrase = context::Lookup::current(context);

      // Retrieve lexicon and workspace status
      Size lexiconCheckpoint = context.lexicon.checkpoint().getAddress();
      Size workspaceKeyCheckpoint = context.workspace.key.bits();

      // RECORD (a procedure that does not ignore but appends whitespace to the workspace)
      WHITESPACES(record);
      // APPLY (restores the lexicon checkpoint to exit the whitespace saving procedure, but does not restore it in the
      // workspace because the whitespace is supposed to be)
      PHRASE("", apply).store(lexiconCheckpoint);
      // DISCARD (restores the lexicon checkpoint to exit the whitespace saving procedure, restores the workspace
      // checkpoint to remove saved whitespace)
      PHRASE(">", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE(":", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("'", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\"", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\\r", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\\n", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\\t", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\\v", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      // END (applies whitespace and continues the append procedure, but restores its parent dictionaryal behavior)
      PHRASE("\\", end).store(lexiconCheckpoint);

      context::Source::Buffer &buffer = context.source.buffer;
      context.workspace.key.append(Bit(buffer.str.data(), buffer.match), buffer.offset - buffer.match);
    }

    void action_reference_commit(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(ReferenceCommit);
      auto filter = [](radix::Node *dictionary, radix::Match *candidate) -> bool {
        return !lexicon::Dictionary(*candidate).getPhrase().isNull();
      };

      lexicon::Match matched = context::Reference::current(context).matchExact(context.workspace.key.getMemory(), 0,
                                                                               context.workspace.key.bits(), filter);

      if (matched.isNull()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "undefined phrase \"" << helper::string::escape(context.workspace.key.c_str()) << "\"")
      }

      lexicon::Phrase phrase = matched.getPhrase();

      context.staging.phrase.setPrototype(phrase).setType(phrase.getType()).setAction(phrase.getAction());
      lexicon::Phrase implementation = phrase.getActionImplementation();
      if (!implementation.isNull()) context.staging.phrase.setActionImplementation(implementation);

      context::Lookup::leave(context, invoked, 2);

      // context.workspace.key.clear();
    }

    void action_dictionary_enter(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(DictionaryEnter);

      lexicon::Phrase phrase = context.staging.phrase.setType(lexicon::phrase::type::getElaborate(invoked))
                                   .setAction(context::Lookup::enter)
                                   .enableSubdictionary()
                                   .save();

      PHRASE(":", action_ignore);
      WHITESPACES(action_ignore);

      context::Staging::push(context, phrase);
      context::Lookup::enter(context, invoked);
      context.workspace.key.clear();
    }

    void action_dictionary_whitespaces(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(DictionaryWhitespaces);

      auto record = [](context::Context &context, lexicon::Phrase &invoked) {
        DEBUG_PROFILE_SCOPE(DictionaryWhitespacesRecord);

        context::Source::Buffer &buffer = context.source.buffer;
        context.workspace.key.append(Bit(buffer.str.data(), buffer.match), buffer.offset - buffer.match);
      };

      auto apply = [](context::Context &context, lexicon::Phrase &invoked) {
        DEBUG_PROFILE_SCOPE(DictionaryWhitespacesApply);

        Size lexiconCheckpoint;
        invoked.fetch(0, lexiconCheckpoint);

        radix::Checkpoint(&context.lexicon, lexiconCheckpoint).restore();
      };

      auto discard = [](context::Context &context, lexicon::Phrase &invoked) {
        DEBUG_PROFILE_SCOPE(DictionaryWhitespacesDiscard);

        Size lexiconCheckpoint;
        Size workspaceCheckpoint;
        invoked.fetch(0, lexiconCheckpoint, workspaceCheckpoint);

        context.workspace.key.truncate(workspaceCheckpoint);
        radix::Checkpoint(&context.lexicon, lexiconCheckpoint).restore();

        invoked.older().elaborate(context);
      };

      auto end = [](context::Context &context, lexicon::Phrase &invoked) {
        DEBUG_PROFILE_SCOPE(DictionaryWhitespacesEnd);

        Size lexiconCheckpoint;
        invoked.fetch(0, lexiconCheckpoint);
        radix::Checkpoint(&context.lexicon, lexiconCheckpoint).restore();

        context::Lookup::leave(context, invoked);
      };

      lexicon::Phrase &phrase = context::Lookup::current(context);

      // Retrieve lexicon and workspace status
      Size lexiconCheckpoint = context.lexicon.checkpoint().getAddress();
      Size workspaceKeyCheckpoint = context.workspace.key.bits();

      // RECORD (a procedure that does not ignore but appends whitespace to the workspace)
      WHITESPACES(record);
      // APPLY (restores the lexicon checkpoint to exit the whitespace saving procedure, but does not restore it in the
      // workspace because the whitespace is supposed to be)
      PHRASE("", apply).store(lexiconCheckpoint);
      // DISCARD (restores the lexicon checkpoint to exit the whitespace saving procedure, restores the workspace
      // checkpoint to remove saved whitespace)
      PHRASE("=", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE(":", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("'", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\"", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\\r", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\\n", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\\t", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      PHRASE("\\v", discard).store(lexiconCheckpoint, workspaceKeyCheckpoint);
      // END (applies whitespace and continues the append procedure, but restores its parent dictionaryal behavior)
      PHRASE("\\", end).store(lexiconCheckpoint);

      context::Source::Buffer &buffer = context.source.buffer;
      context.workspace.key.append(Bit(buffer.str.data(), buffer.match), buffer.offset - buffer.match);
    }

    void action_dictionary_leave(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(DictionaryLeave);
      context::Lookup::leave(context, invoked, 1);
      context::Staging::pop(context, 1);
      context.workspace.key.clear();
    }

    void action_dictionary_equals(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(DictionaryEquals);
      context.staging.phrase =
          context.staging.phrase.append(context.workspace.key.getMemory(), 0, context.workspace.key.bits())
              .make(nullptr);
      context::Lookup::enter(context, invoked);
    }

    void action_dictionary_commit(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(DictionaryCommit);

      finalize_staged_code(context, invoked);

      if (!context.staging.phrase.containsType())
        context.staging.phrase.setType(lexicon::phrase::type::getData(invoked));

      lexicon::Phrase &saved = context.staging.phrase.save();
      Assembler::commitNative(context, saved);

      context::Staging::pop(context, 0);

      context::Lookup::leave(context, invoked, 1);

      context.workspace.key.clear();
    }

    void action_scope(context::Context &context, lexicon::Phrase &invoked) {
      auto action_scope_end = [](context::Context &context, lexicon::Phrase &invoked) {
        DEBUG_PROFILE_SCOPE(ScopeEnd);
        context::Lookup::leave(context, invoked, 2);

        Size address;
        invoked.fetch(0, address);

        DEBUG_LOG(SCOPE : END, address);

        radix::Checkpoint(&context.lexicon, address).restore();
      };

      DEBUG_PROFILE_SCOPE(ScopeStart);
      lexicon::Phrase &phrase = context::Lookup::current(context);

      Size address = context.lexicon.checkpoint().getAddress();

      DEBUG_LOG(SCOPE : START, address);

      PHRASE("}", action_scope_end).store(address);

      context::Lookup::enter(context, invoked);
    }

    void action_hex(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(Hex);

      while (context.source.buffer.bits < 2 * Byte::length) {
        if (!context.source.more) return;

        context::Source::load(context, false);
      }

      char *hexCode = &context.source.buffer.str.data()[context.source.buffer.offset / Byte::length];

      char high = hexCode[0];
      char low = hexCode[1];
      DEBUG_LOG(HEX, high << low);

      if ('0' <= high && high <= '9') {
        high -= '0';
      } else if ('A' <= high && high <= 'F') {
        high -= 'A' - 10;
      } else if ('a' <= high && high <= 'f') {
        high -= 'a' - 10;
      } else {
        THROW(, "Hex: high invalid code")
      }

      if ('0' <= low && low <= '9') {
        low -= '0';
      } else if ('A' <= low && low <= 'F') {
        low -= 'A' - 10;
      } else if ('a' <= low && low <= 'f') {
        low -= 'a' - 10;
      } else {
        THROW(, "Hex: low invalid code")
      }

      char binaryCode = (high << 4) | low;

      context.workspace.code.append(binaryCode);
      context::Source::progress(context, 2 * Byte::length);
    }

    void setup_phrase_types(context::Context &context, lexicon::Phrase &root) {
      lexicon::Phrase undefined(root.getLexicon());

      lexicon::Phrase types =
          root.append(language::phrases::TYPES).make().setType(undefined).enableSubdictionary().save();

      lexicon::Phrase data = types.append(language::phrases::TYPE_DATA)
                                 .make()
                                 .setType(undefined)
                                 .save()
                                 .store(lexicon::phrase::type::Behavior{}, lexicon::phrase::type::Core{});
      data.setType(data).save();

      types.setType(data).save();

      lexicon::Phrase elaborate = types.append(language::phrases::TYPE_ELABORATE)
                                      .make()
                                      .setType(data)
                                      .save()
                                      .store(lexicon::phrase::type::Behavior{lexicon::phrase::type::action, nullptr});
      lexicon::Phrase callable =
          types.append(language::phrases::TYPE_CALLABLE)
              .make()
              .setType(data)
              .save()
              .store(lexicon::phrase::type::Behavior{lexicon::phrase::type::action, lexicon::phrase::type::action});
      lexicon::Phrase scopedCallable =
          types.append(language::phrases::TYPE_SCOPED_CALLABLE)
              .make()
              .setType(data)
              .save()
              .store(lexicon::phrase::type::Behavior{elaborate_scoped_callable, lexicon::phrase::type::action});

      data.update(
          sizeof(lexicon::phrase::type::Behavior),
          lexicon::phrase::type::Core{elaborate.getAddress(), callable.getAddress(), scopedCallable.getAddress()});
      root.setType(elaborate).save();
    }

    void register_language_actions(context::Context &context) {
      context::Actions actions = context.actions();
      actions.define("phrase.dispatch", lexicon::phrase::type::action);
      actions.define("lookup.enter", context::Lookup::enter);
      actions.define("lookup.leave",
                     static_cast<void (*)(context::Context &, lexicon::Phrase &)>(context::Lookup::leave));
      actions.define("language.ignore", action_ignore);
      actions.define("language.ping", action_ping);
      actions.define("language.scoped-callable", elaborate_scoped_callable);
      actions.define("language.exit", action_exit);
      actions.define("language.continue", action_continue);
      actions.define("source.progress-byte", action_progress_byte);
      actions.define("debug.stats", action_debug_stats);
      actions.define("debug.dictionary-dump", action_debug_dictionary_dump);
      actions.define("debug.workspace-print", action_debug_workspace_print);
      actions.define("workspace.pass-byte", action_pass_byte);
      actions.define("workspace.pass-cr", action_pass_carriage_return);
      actions.define("workspace.pass-lf", action_pass_line_feed);
      actions.define("workspace.pass-tab", action_pass_horizontal_tab);
      actions.define("workspace.pass-vtab", action_pass_vertical_tab);
      actions.define("let.enter", action_let_enter);
      actions.define("let.equals", action_let_equals);
      actions.define("let.commit-anonymous", action_anonymous_let_commit);
      actions.define("lexicon.create", action_lexicon);
      actions.define("lexicon.merge", action_merge);
      actions.define("phrase.define", PhraseDefinition::define);
      actions.define("reference.enter", action_reference_enter);
      actions.define("reference.colon", action_reference_colon);
      actions.define("reference.whitespace", action_reference_whitespaces);
      actions.define("reference.commit", action_reference_commit);
      actions.define("dictionary.enter", action_dictionary_enter);
      actions.define("dictionary.whitespace", action_dictionary_whitespaces);
      actions.define("dictionary.leave", action_dictionary_leave);
      actions.define("dictionary.equals", action_dictionary_equals);
      actions.define("dictionary.commit", action_dictionary_commit);
      actions.define("scope.enter", action_scope);
      actions.define("hex.byte", action_hex);
      actions.define("name.interpolate", NameInterpolation::append);
      Assembler::registerActions(context);
    }

  } // namespace internal
} // namespace recurloop
