#include "AssemblerInternal.hpp"

#include <recurloop/Expressions.hpp>

namespace recurloop {
  namespace assembler_internal {
    compiler::Assembler::Location assembler_location(context::Context &context, Size keyBytes) {
      compiler::Assembler::Location location;
      location.path = context.source.path;
      location.line = context.source.line;
      location.column = context.source.position > keyBytes ? context.source.position - keyBytes : 1;
      return location;
    }
    std::string assembler_internal_key(unsigned char kind) {
      if (kind == ASSEMBLER_SESSION) {
        static constexpr char key[] = "\0assembler-session";
        return std::string(key, sizeof(key) - 1);
      }
      return std::string(1, static_cast<char>(kind));
    }

    std::string assembler_operand_key(Size index) {
      std::string key(1 + sizeof(index), '\0');
      key[0] = static_cast<char>(ASSEMBLER_OPERAND);
      Byte::copy(Byte(&index), Byte(key.data() + 1), sizeof(index));
      return key;
    }

    std::string compiled_invocation_key(Size index) {
      std::string key(1 + sizeof(index), '\0');
      key[0] = static_cast<char>(COMPILED_INVOCATION);
      Byte::copy(Byte(&index), Byte(key.data() + 1), sizeof(index));
      return key;
    }

    lexicon::Phrase assembler_match_phrase(lexicon::Phrase &dictionary, const std::string &key) {
      auto filter = [](radix::Node *node, radix::Match *candidate) -> bool {
        return !lexicon::Dictionary(*candidate).getPhrase().isNull();
      };
      lexicon::Match matched =
          dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length, filter);
      return matched.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : matched.getPhrase();
    }

    lexicon::Phrase native_output(context::Context &context) {
      lexicon::Phrase root = context.lexicon.phrase();
      return assembler_match_phrase(root, std::string(NATIVE_OUTPUT_KEY, sizeof(NATIVE_OUTPUT_KEY) - 1));
    }

    NativeOutputKind native_output_kind(context::Context &context) {
      lexicon::Phrase directive = native_output(context);
      if (directive.isNull()) return NativeOutputKind::None;
      NativeOutputData data;
      directive.fetch(0, data);
      return data.kind;
    }

    bool linked_native_output(context::Context &context) {
      const NativeOutputKind kind = native_output_kind(context);
      return kind == NativeOutputKind::Object || kind == NativeOutputKind::Executable;
    }

    void set_native_output(context::Context &context, const std::string &path, NativeOutputKind kind) {
      if (path.empty()) THROW(, "native output: path cannot be empty")
      if (path.find('\0') != std::string::npos) THROW(, "native output: path contains a NUL byte")
      if (kind == NativeOutputKind::None) THROW(, "native output: missing output kind")

      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase directive =
          root.append(Byte((unsigned char *)NATIVE_OUTPUT_KEY), 0, (sizeof(NATIVE_OUTPUT_KEY) - 1) * Byte::length)
              .make()
              .setType(lexicon::phrase::type::getData(root))
              .save()
              .store(NativeOutputData{path.size(), kind, false});
      Byte destination = directive.allocate(path.size());
      Byte::copy(Byte(const_cast<char *>(path.data())), destination, path.size());
    }

    std::string compiled_scope_session_key() {
      return std::string(phrases::COMPILED_SCOPE_SESSION, sizeof(phrases::COMPILED_SCOPE_SESSION) - 1);
    }

    lexicon::Phrase compiled_scope_session(context::Context &context, bool required) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase session = assembler_match_phrase(root, compiled_scope_session_key());
      if (required && session.isNull()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "compiled phrase: internal session phrase is missing")
      }
      return session;
    }

    bool compiled_scope_open(context::Context &context) {
      return !compiled_scope_session(context, false).isNull();
    }

    void compiled_scope_restore_key(context::Context &context, lexicon::Phrase &session,
                                    const CompiledScopeSessionData &data) {
      const Size keyBytes = Bit::bytes(data.keyStartBits);
      context.workspace.key.clear();
      if (keyBytes != 0)
        context.workspace.key.append(Bit(session.content(sizeof(data), keyBytes), 0), data.keyStartBits);
    }

    lexicon::Phrase assembler_body(context::Context &context, bool required) {
      const std::string key = assembler_internal_key(ASSEMBLER_SESSION);
      lexicon::Phrase body = context::Lookup::current(context);
      lexicon::Phrase session = assembler_match_phrase(body, key);
      for (auto cursor = context.lookup.stack.rbegin(); session.isNull() && cursor != context.lookup.stack.rend();
           ++cursor) {
        body = *cursor;
        session = assembler_match_phrase(body, key);
      }
      if (required && session.isNull()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "assembler: internal session phrase is missing")
      }
      return session.isNull() ? lexicon::Phrase(&context.lexicon) : body;
    }

    lexicon::Phrase assembler_session(context::Context &context, bool required) {
      lexicon::Phrase body = assembler_body(context, required);
      return body.isNull() ? lexicon::Phrase(&context.lexicon)
                           : assembler_match_phrase(body, assembler_internal_key(ASSEMBLER_SESSION));
    }

    void assembler_enter_operand_state(context::Context &context, const char *key) {
      lexicon::Phrase body = assembler_body(context);
      lexicon::Phrase state = assembler_match_phrase(body, key);
      if (state.isNull()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "assembler: internal operand state '" << key << "' is missing")
      }
      context::Lookup::in(context, state);
    }

    bool assembler_open(context::Context &context) {
      return !assembler_session(context, false).isNull();
    }

    void assembler_restore_key(context::Context &context, lexicon::Phrase &session, const AssemblerSessionData &data) {
      const Size keyBytes = Bit::bytes(data.keyStartBits);
      context.workspace.key.clear();
      if (keyBytes != 0)
        context.workspace.key.append(Bit(session.content(sizeof(data), keyBytes), 0), data.keyStartBits);
    }

    void action_compiled_scope_end(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(CompiledScopeEnd);
      lexicon::Phrase session = compiled_scope_session(context);
      CompiledScopeSessionData data;
      session.fetch(0, data);

      const bool tailCall = data.tailCallEligible && data.tailCallEnd == context.workspace.code.size() &&
                            data.tailCallOpcodeOffset < context.workspace.code.size() &&
                            context.workspace.code.getMemory().toPtr()[data.tailCallOpcodeOffset] == 0xe8;
      if (!tailCall && context.workspace.code.size() + 2 > context.workspace.code.getCapacity()) {
        const SourceLocation location{context.source.path, context.source.line, context.source.position};
        THROW_AT(location, "compiled phrase: generated return exceeds workspace.code capacity")
      }

      // A final native call is a proper tail call: change CALL rel32 to JMP rel32
      // and omit RET. Otherwise close the sequence as an ordinary void function.
      if (tailCall)
        context.workspace.code.getMemory().toPtr()[data.tailCallOpcodeOffset] = 0xe9;
      else
        context.workspace.code.append(static_cast<char>(0xc3));
      NativeDefinition definition = link_compiled_scope_definition(context, invoked, session, data);
      compiled_scope_restore_key(context, session, data);
      context::Lookup::leave(context, invoked, 2);
      radix::Checkpoint(&context.lexicon, data.lexiconCheckpoint).restore();
      context.exec.invoked = nullptr;
      finalize_native_definition(context, invoked, definition.module, definition.imports);
    }

    void action_let_scope(context::Context &context, lexicon::Phrase &invoked) {
      DEBUG_PROFILE_SCOPE(CompiledScopeBegin);

      const CompiledScopeSessionData data{context.lexicon.checkpoint().getAddress(), context.workspace.code.bits(),
                                          context.workspace.key.bits(), context.staging.dictionary.getAddress(), 0};

      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase session = root.append(Byte((unsigned char *)phrases::COMPILED_SCOPE_SESSION), 0,
                                            (sizeof(phrases::COMPILED_SCOPE_SESSION) - 1) * Byte::length)
                                    .make()
                                    .setType(lexicon::phrase::type::getData(invoked))
                                    .enableSubdictionary()
                                    .save()
                                    .store(data);

      const Size keyBytes = Bit::bytes(data.keyStartBits);
      if (keyBytes != 0) {
        Byte savedKey = session.allocate(keyBytes);
        Bit::copy(Bit(context.workspace.key.getMemory(), 0), Bit(savedKey, 0), data.keyStartBits);
      }

      root.append("}").make(action_compiled_scope_end).setType(lexicon::phrase::type::getElaborate(invoked)).save();
      context::Lookup::enter(context, invoked);
    }

    char assembler_peek(context::Context &context, Size relative) {
      while (relative >= context.source.buffer.bits / Byte::length && context.source.more)
        context::Source::load(context, false);
      if (relative >= context.source.buffer.bits / Byte::length) return '\0';
      return context.source.buffer.str[context.source.buffer.offset / Byte::length + relative];
    }

    void assembler_skip_horizontal_whitespace(context::Context &context) {
      while (true) {
        const char character = assembler_peek(context);
        if (character != ' ' && character != '\t' && character != '\r' && character != '\v') return;
        context::Source::progress(context, Byte::length);
      }
    }

    [[noreturn]] void assembler_fail(const compiler::Assembler::Location &location, const std::string &message) {
      const SourceLocation sourceLocation{location.path, location.line, location.column};
      THROW_AT(sourceLocation, "assembler: " << message)
    }

    [[noreturn]] void invocation_fail(const compiler::Assembler::Location &location, bool assemblerContext,
                                      const std::string &message) {
      if (assemblerContext) assembler_fail(location, message);
      const SourceLocation sourceLocation{location.path, location.line, location.column};
      THROW_AT(sourceLocation, "invoke: " << message)
    }

    int invoke_phrase(context::Context *context, Size phraseAddress, Size line, Size column) noexcept {
      std::string targetName = "<unknown>";
      try {
        if (context == nullptr) THROW(, "generated phrase invocation received a null context")
        if (context->exec.pendingException) return 1;

        lexicon::Phrase target(&context->lexicon, phraseAddress);
        const SourceLocation location{context->source.path, line, column};
        if (target.isNull()) THROW_AT(location, "invoke: invoked phrase address is null")
        target.load();
        targetName = target.getKeyEscaped();
        if (!target.isInvokable()) THROW_AT(location, "invoke: phrase '" << targetName << "' is not invokable")

        target.invoke(*context);
        return 0;
      } catch (const Exception &error) {
        if (context != nullptr) {
          if (error.hasSourceLocation()) {
            context->exec.pendingException = std::current_exception();
            return 1;
          }
          try {
            const SourceLocation location{context->source.path, line, column};
            THROW_AT(location, "invoke: invoked phrase '" << targetName << "' failed: " << error.description())
          } catch (...) {
            context->exec.pendingException = std::current_exception();
          }
        }
        return 1;
      } catch (...) {
        if (context != nullptr) context->exec.pendingException = std::current_exception();
        return 1;
      }
    }

    namespace {
      bool pointerTo(context::Context &context, compiler::TypeId type, std::string_view pointee) {
        const compiler::TypeDescriptor pointer = context.language().types.get(type);
        return pointer.kind == compiler::TypeKind::Pointer &&
               context.language().types.get(pointer.element).name == pointee;
      }

      bool actionSignature(context::Context &context, const compiler::TypedFunction &function) {
        return !function.signature.variadic && function.signature.convention.name == "sysv-amd64" &&
               function.parameterTypes.size() == 2 && pointerTo(context, function.parameterTypes[0], "Context") &&
               pointerTo(context, function.parameterTypes[1], "Phrase") &&
               context.language().types.get(function.resultType).kind == compiler::TypeKind::Void;
      }

      std::string remainingLine(context::Context &context) {
        std::string result;
        while (true) {
          while (context.source.buffer.bits == 0 && context.source.more) context::Source::load(context, false);
          if (context.source.buffer.bits == 0) break;
          const char character = context.source.buffer.str[context.source.buffer.offset / Byte::length];
          if (character == '\n' || character == '\r') break;
          result.push_back(character);
          context::Source::progress(context, Byte::length);
        }
        const auto begin = std::find_if_not(result.begin(), result.end(),
                                            [](unsigned char character) { return std::isspace(character); });
        const auto end = std::find_if_not(result.rbegin(), result.rend(), [](unsigned char character) {
                           return std::isspace(character);
                         }).base();
        return begin < end ? std::string(begin, end) : std::string{};
      }

      bool invocationArgumentsFollow(context::Context &context) {
        while (true) {
          while (context.source.buffer.bits == 0 && context.source.more) context::Source::load(context, false);
          if (context.source.buffer.bits == 0) return false;
          const char character = context.source.buffer.str[context.source.buffer.offset / Byte::length];
          if (character == '\n' || character == '\r') return false;
          if (!std::isspace(static_cast<unsigned char>(character))) return character == '(';
          context::Source::progress(context, Byte::length);
        }
      }
    } // namespace

    lexicon::Phrase native_action_implementation(lexicon::Phrase phrase, Size minimumPayload) {
      for (std::size_t depth = 0; depth < 64; ++depth) {
        if (phrase.payloadSize() >= minimumPayload) return phrase;
        if (!phrase.containsPrototype()) break;
        lexicon::Phrase prototype = phrase.getPrototype();
        if (prototype.isNull() || prototype.getAddress() == phrase.getAddress()) break;
        phrase = prototype;
      }
      THROW(, "compiled phrase implementation payload is unavailable for '" << phrase.getKeyEscaped() << "'")
    }

    void invoke_native_entry(context::Context &context, lexicon::Phrase &invoked, std::uintptr_t entry,
                             const std::string &symbol) {
      if (entry == 0) THROW(, "compiled phrase entrypoint is null for '" << invoked.getKeyEscaped() << "'")
      const std::optional<compiler::TypedFunction> function =
          symbol.empty() ? std::nullopt : context.language().findFunction(symbol);
      if (function && actionSignature(context, *function)) {
        reinterpret_cast<void (*)(context::Context *, lexicon::Phrase *)>(entry)(&context, &invoked);
        return;
      }

      if (!function) {
        reinterpret_cast<void (*)()>(entry)();
        return;
      }
      if (invocationArgumentsFollow(context)) {
        const std::string arguments = remainingLine(context);
        (void)Expressions::evaluate(context, function->name + arguments);
        return;
      }
      if (!function->parameterTypes.empty())
        THROW(, "function phrase '" << invoked.getKeyEscaped() << "' requires " << function->parameterTypes.size()
                                    << " typed argument(s)")
      reinterpret_cast<void (*)()>(entry)();
    }

    void invoke_native_action(context::Context &context, lexicon::Phrase &invoked) {
      lexicon::Phrase implementation = native_action_implementation(invoked, sizeof(NativeActionData));
      NativeActionData data;
      implementation.fetch(0, data);
      const std::size_t symbolBytes = implementation.payloadSize() - sizeof(data);
      const std::string symbol =
          symbolBytes == 0
              ? std::string{}
              : std::string(reinterpret_cast<const char *>(implementation.content(sizeof(data), symbolBytes).toPtr()),
                            symbolBytes);
      invoke_native_entry(context, invoked, data.entry, symbol);
    }

    void invoke_deferred_native_action(context::Context &context, lexicon::Phrase &invoked) {
      lexicon::Phrase implementation = native_action_implementation(invoked, sizeof(DeferredNativeActionData));
      DeferredNativeActionData data;
      implementation.fetch(0, data);
      const Byte symbolBytes = implementation.content(sizeof(data), data.symbolBytes);
      const std::string symbol(reinterpret_cast<const char *>(symbolBytes.toPtr()), data.symbolBytes);
      std::uintptr_t entry = implementation.getActionEntry();
      if (entry == 0) {
        const std::optional<compiler::Module> module = context.language().findModule(symbol);
        if (!module) THROW(, "deferred native module is unavailable for symbol: '" << symbol << "'")

        const compiler::Module linked = context.language().composeModule(*module);
        const compiler::JitImage image = compiler::JitLinker::link(
            linked, context.runtime, [&](std::string_view sym) -> std::optional<std::uintptr_t> {
              return compiler::DynamicLinker::instance().resolveFromDefault(sym);
            });
        entry = image.address(symbol);
        // The process-local address is only a cache. Engine images intentionally
        // omit ActionBinding::entry and reconstruct it from the persisted module.
        implementation.setActionEntry(entry).save();
      }
      invoke_native_entry(context, invoked, entry, symbol);
    }

    void assembler_store_path(lexicon::Phrase &phrase, const std::string &path) {
      if (path.empty()) return;
      Byte destination = phrase.allocate(path.size());
      Byte::copy(Byte(const_cast<char *>(path.data())), destination, path.size());
    }

    compiler::Assembler::Location assembler_load_location(lexicon::Phrase &phrase, Size offset) {
      AssemblerSourceData source;
      phrase.fetch(offset, source);
      compiler::Assembler::Location location;
      location.line = source.line;
      location.column = source.column;
      if (source.pathBytes != 0) {
        const char *path =
            reinterpret_cast<const char *>(phrase.content(offset + sizeof(source), source.pathBytes).toPtr());
        location.path.assign(path, source.pathBytes);
      }
      return location;
    }

    lexicon::Phrase assembler_find_label(context::Context &context, const std::string &name) {
      lexicon::Phrase session = assembler_session(context);
      return assembler_match_phrase(session, name);
    }

    bool assembler_label_conflicts_with_builtin(context::Context &context, const std::string &name) {
      lexicon::Phrase body = assembler_body(context);
      if (!assembler_match_phrase(body, name).isNull()) return true;

      lexicon::Phrase operands = assembler_match_phrase(body, phrases::OPERANDS);
      return !operands.isNull() && !assembler_match_phrase(operands, name).isNull();
    }
  } // namespace assembler_internal
} // namespace recurloop
