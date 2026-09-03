#include "AssemblerInternal.hpp"

#include <recurloop/Assembler.hpp>
#include <recurloop/LanguageGrammar.hpp>

namespace recurloop {
  void Assembler::sourceEnd(context::Context &context) {
    const SourceLocation location{context.source.path, context.source.line, context.source.position};
    if (assembler_internal::assembler_open(context)) {
      THROW_AT(location, "assembler: unexpected end of input; expected '}'")
    }
    if (assembler_internal::compiled_scope_open(context)) {
      THROW_AT(location, "compiled phrase: unexpected end of input; expected '}'")
    }
    if (assembler_internal::native_output_kind(context) != NativeOutputKind::None) {
      THROW(, "native output: unexpected end of input; expected a definition after the output path")
    }
  }

  void Assembler::scope(context::Context &context, lexicon::Phrase &invoked) {
    if (context.staging.stack.size() > 1 && !assembler_internal::compiled_scope_open(context)) {
      assembler_internal::action_let_scope(context, invoked);
      return;
    }

    lexicon::Phrase fallback = invoked.getPrototype();
    if (fallback.isNull() || fallback.getAction() == nullptr) THROW(, "assembler: compiled scope fallback is missing")
    fallback.getAction()(context, invoked);
  }

  void Assembler::outputBegin(context::Context &context, lexicon::Phrase &invoked) {
    context.workspace.key.clear();
    context::Lookup::enter(context, invoked);
  }

  static char output_peek(context::Context &context, Size relative = 0) {
    while (relative >= context.source.buffer.bits / Byte::length && context.source.more)
      context::Source::load(context, false);
    if (relative >= context.source.buffer.bits / Byte::length) return '\0';
    return context.source.buffer.str[context.source.buffer.offset / Byte::length + relative];
  }

  static void enter_output_definition(context::Context &context) {
    while (std::isspace(static_cast<unsigned char>(assembler_internal::assembler_peek(context))))
      context::Source::progress(context, Byte::length);

    lexicon::Phrase root = context.lexicon.phrase();
    const Size offset = context.source.buffer.offset / Byte::length;
    Size available = 0;
    while (output_peek(context, available) != '\0' && output_peek(context, available) != '\n') ++available;
    lexicon::Phrase definition =
        LanguageGrammar::matchLongest(root, std::string_view(context.source.buffer.str).substr(offset, available));
    if (!definition.isNull()) {
      const std::string key = definition.getKey();
      const char boundary = output_peek(context, key.size());
      if (key.empty() || (assembler_internal::assembler_identifier_character(key.back()) &&
                          assembler_internal::assembler_identifier_character(boundary)))
        definition = lexicon::Phrase(&context.lexicon);
    }
    bool consumeDefinition = !definition.isNull() && definition.isElaboratable();
    if (!consumeDefinition) definition = LanguageGrammar::find(root, "let");
    if (definition.isNull() || !definition.isElaboratable())
      THROW(, "native output: the definition grammar is unavailable")
    if (consumeDefinition) context::Source::progress(context, definition.getKey().size() * Byte::length);
    definition.elaborate(context);
  }

  static void finish_native_output(context::Context &context, NativeOutputKind kind) {
    const char *path = reinterpret_cast<const char *>(context.workspace.key.getMemory().toPtr());
    assembler_internal::set_native_output(context, std::string(path, context.workspace.key.size()), kind);
    context.workspace.key.clear();
    if (context.lookup.stack.size() < 3) THROW(, "native output: lookup stack is incomplete")
    lexicon::Phrase destination = context.lookup.stack[context.lookup.stack.size() - 3];
    context.lookup.stack.resize(context.lookup.stack.size() - 3);
    context::Lookup::in(context, destination);
    enter_output_definition(context);
  }

  void Assembler::objectEnd(context::Context &context, lexicon::Phrase &invoked) {
    finish_native_output(context, NativeOutputKind::Object);
  }

  void Assembler::executableEnd(context::Context &context, lexicon::Phrase &invoked) {
    finish_native_output(context, NativeOutputKind::Executable);
  }

  void Assembler::rawEnd(context::Context &context, lexicon::Phrase &invoked) {
    finish_native_output(context, NativeOutputKind::Raw);
  }

  std::string Assembler::prepareDefinitionName(context::Context &context, std::string name) {
    lexicon::Phrase directive = assembler_internal::native_output(context);
    if (directive.isNull()) {
      if (name.empty() && context.staging.dictionary.getAddress() == context.lexicon.phrase().getAddress())
        THROW(, "let: root phrase name cannot be empty")
      return name;
    }

    NativeOutputData outputData;
    directive.fetch(0, outputData);
    if (outputData.kind == NativeOutputKind::None) {
      if (name.empty() && context.staging.dictionary.getAddress() == context.lexicon.phrase().getAddress())
        THROW(, "let: root phrase name cannot be empty")
      return name;
    }
    if (outputData.kind == NativeOutputKind::Raw && !name.empty())
      THROW(, "emit raw: a definition name is not allowed because raw output has no symbols")
    if (!name.empty()) return name;

    outputData.anonymous = true;
    directive.update(0, outputData);
    return std::string("\1emit.", 6) + std::to_string(context.lexicon.checkpoint().getAddress());
  }

  std::string Assembler::dictionarySymbol(context::Context &context) {
    std::vector<std::string> segments;
    std::vector<Size> visited;
    const Size target = context.staging.dictionary.getAddress();
    const auto find = [&](lexicon::Phrase dictionary, std::size_t depth, const auto &self) -> bool {
      if (dictionary.getAddress() == target) return true;
      if (depth >= 1024 || !dictionary.containsSubdictionary()) return false;
      const Size address = dictionary.getSubdictionary().getAddress();
      if (std::find(visited.begin(), visited.end(), address) != visited.end()) return false;
      visited.push_back(address);
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      for (lexicon::Dictionary cursor = dictionary.fore(populated); !cursor.isNull(); cursor = cursor.next(populated)) {
        lexicon::Phrase child = cursor.getPhrase();
        if (child.isNull()) continue;
        const std::string key = child.getKey();
        if (key.empty() || key.front() == '\0') continue;
        segments.push_back(key);
        if (self(child, depth + 1, self)) return true;
        segments.pop_back();
      }
      return false;
    };
    if (!find(context.lexicon.phrase(), 0, find)) segments.clear();

    std::string result;
    for (const std::string &segment : segments) {
      if (!result.empty()) result.push_back(':');
      result += segment;
    }
    return result;
  }

  std::string Assembler::definitionSymbol(context::Context &context) {
    if (!context.exec.definitionSymbolOverride.empty()) return context.exec.definitionSymbolOverride;
    const std::string leaf = context.staging.phrase.getKey();
    if (leaf.empty()) return std::string("\1entry", 6);

    std::string result = dictionarySymbol(context);
    if (!result.empty()) result.push_back(':');
    result += leaf;
    return result;
  }

  bool Assembler::hasNativeOutput(context::Context &context) {
    return assembler_internal::native_output_kind(context) != NativeOutputKind::None;
  }

  std::optional<NativeFileRequest> Assembler::nativeFileRequest(context::Context &context) {
    lexicon::Phrase directive = assembler_internal::native_output(context);
    if (directive.isNull()) return std::nullopt;
    NativeOutputData data;
    directive.fetch(0, data);
    if (data.kind == NativeOutputKind::None) return std::nullopt;
    const char *bytes = reinterpret_cast<const char *>(directive.content(sizeof(data), data.pathBytes).toPtr());
    NativeFileRequest request;
    request.path.assign(bytes, data.pathBytes);
    request.entry = context.language().moduleEntry().value_or(context.staging.phrase.getKey());
    request.anonymous = data.anonymous;
    switch (data.kind) {
    case NativeOutputKind::Object: request.kind = NativeFileKind::Object; break;
    case NativeOutputKind::Executable: request.kind = NativeFileKind::Executable; break;
    case NativeOutputKind::Raw: request.kind = NativeFileKind::Raw; break;
    case NativeOutputKind::None: return std::nullopt;
    }
    return request;
  }

  void Assembler::defineEntry(context::Context &context, compiler::Module &module, std::size_t offset) {
    const std::string entrySymbol = definitionSymbol(context);
    if (entrySymbol.empty()) THROW(, "native definition: symbol name cannot be empty")

    lexicon::Phrase directive = assembler_internal::native_output(context);
    NativeOutputData outputData;
    if (!directive.isNull()) directive.fetch(0, outputData);
    const bool requiresEntry = outputData.kind == NativeOutputKind::None || !outputData.anonymous ||
                               outputData.kind == NativeOutputKind::Executable;
    if (requiresEntry) module.define(entrySymbol, compiler::SectionKind::Text, offset);
  }

  void Assembler::finalize(context::Context &context, lexicon::Phrase &invoked, compiler::Module &module) {
    assembler_internal::finalize_native_definition(context, invoked, module, {});
  }

  std::uintptr_t Assembler::nativeEntry(lexicon::Phrase &phrase) {
    // Callers can retain a Phrase value while invocation updates the persisted
    // action cache through another handle. Reload from the radix storage so the
    // process-local entry is never read from a stale Phrase cache.
    lexicon::Phrase current(phrase.getLexicon(), phrase.getAddress());
    lexicon::Phrase implementation =
        assembler_internal::native_action_implementation(current, sizeof(NativeActionData));
    if (implementation.getAction() == assembler_internal::invoke_deferred_native_action) {
      const std::uintptr_t entry = implementation.getActionEntry();
      if (entry == 0)
        THROW(, "phrase has not resolved its native ABI entrypoint yet: '" << phrase.getKeyEscaped() << "'")
      return entry;
    }
    if (implementation.getAction() != assembler_internal::invoke_native_action)
      THROW(, "phrase is not backed by a native ABI entrypoint: '" << phrase.getKeyEscaped() << "'")
    NativeActionData data;
    implementation.fetch(0, data);
    return data.entry;
  }

  void Assembler::commitNative(context::Context &context, lexicon::Phrase &phrase) {
    if (context.exec.pendingNativeEntry != 0) {
      if (phrase.getAction() == assembler_internal::invoke_deferred_native_action &&
          !context.exec.pendingNativeSymbol.empty()) {
        phrase.store(DeferredNativeActionData{context.exec.pendingNativeSymbol.size()});
        Byte destination = phrase.allocate(context.exec.pendingNativeSymbol.size());
        Byte::copy(Byte(reinterpret_cast<unsigned char *>(context.exec.pendingNativeSymbol.data())), destination,
                   context.exec.pendingNativeSymbol.size());
        compiler::LanguageState::bind(phrase);
        phrase.setActionEntry(context.exec.pendingNativeEntry).save();
        context.exec.pendingNativeEntry = 0;
        context.exec.pendingNativeSymbol.clear();
        return;
      }
      phrase.store(NativeActionData{context.exec.pendingNativeEntry});
      if (!context.exec.pendingNativeSymbol.empty()) {
        Byte destination = phrase.allocate(context.exec.pendingNativeSymbol.size());
        Byte::copy(Byte(reinterpret_cast<unsigned char *>(context.exec.pendingNativeSymbol.data())), destination,
                   context.exec.pendingNativeSymbol.size());
      }
      phrase.setSerializable(false).save();
      context.exec.pendingNativeEntry = 0;
      context.exec.pendingNativeSymbol.clear();
      return;
    }
    if (context.exec.pendingNativeSymbol.empty()) return;
    phrase.store(DeferredNativeActionData{context.exec.pendingNativeSymbol.size()});
    Byte destination = phrase.allocate(context.exec.pendingNativeSymbol.size());
    Byte::copy(Byte(reinterpret_cast<unsigned char *>(context.exec.pendingNativeSymbol.data())), destination,
               context.exec.pendingNativeSymbol.size());
    compiler::LanguageState::bind(phrase);
    context.exec.pendingNativeSymbol.clear();
  }

  void Assembler::registerActions(context::Context &context) {
    context::Actions actions = context.actions();
    actions.define("assembler.scope", scope);
    actions.define("assembler.output-begin", outputBegin);
    actions.define("assembler.object-end", objectEnd);
    actions.define("assembler.executable-end", executableEnd);
    actions.define("assembler.raw-end", rawEnd);
    actions.define("assembler.begin", begin);
    actions.define("assembler.instruction", instruction);
    // Keep old image bindings readable while all new phrases serialize the
    // single descriptor-driven action name.
#define ASSEMBLER_INSTRUCTION(Mnemonic, Name) actions.define("assembler.instruction." #Mnemonic, instruction);
    ASSEMBLER_INSTRUCTIONS(ASSEMBLER_INSTRUCTION)
#undef ASSEMBLER_INSTRUCTION
    actions.define("assembler.operand", operand);
    actions.define("assembler.operand-size", operandSize);
    actions.define("assembler.operand-whitespace", operandWhitespace);
    actions.define("assembler.memory-begin", operandMemoryBegin);
    actions.define("assembler.memory-operator", operandMemoryOperator);
    actions.define("assembler.memory-end", operandMemoryEnd);
    actions.define("assembler.operand-separator", operandSeparator);
    actions.define("assembler.operand-comment", operandComment);
    actions.define("assembler.operand-dynamic", operandDynamic);
    actions.define("assembler.invoke", invoke);
    actions.define("assembler.section", section);
    actions.define("assembler.custom-section", customSection);
    actions.define("assembler.bytes", bytes);
    actions.define("assembler.reserve", reserve);
    actions.define("assembler.comment", comment);
    actions.define("assembler.end", end);
    actions.define("assembler.unknown", unknown);
    actions.define("assembler.native-entry", assembler_internal::invoke_native_action);
    actions.define("assembler.deferred-native-entry", assembler_internal::invoke_deferred_native_action);
  }

  void Assembler::begin(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_begin(context, invoked);
  }

  void Assembler::instruction(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_instruction(context, invoked,
                                                     assembler_internal::assembler_instruction_name(invoked));
  }

  void Assembler::operand(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_operand(context, invoked);
  }

  void Assembler::operandSize(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_operand_size(context, invoked);
  }

  void Assembler::operandWhitespace(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_operand_whitespace(context, invoked);
  }

  void Assembler::operandMemoryBegin(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_operand_memory_begin(context, invoked);
  }

  void Assembler::operandMemoryOperator(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_operand_memory_operator(context, invoked);
  }

  void Assembler::operandMemoryEnd(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_operand_memory_end(context, invoked);
  }

  void Assembler::operandSeparator(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_operand_separator(context, invoked);
  }

  void Assembler::operandComment(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_operand_comment(context, invoked);
  }

  void Assembler::operandDynamic(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_operand_dynamic(context, invoked);
  }

  void Assembler::invoke(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_invoke(context, invoked);
  }

  void Assembler::section(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_section(context, invoked);
  }

  void Assembler::customSection(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_custom_section(context, invoked);
  }

  void Assembler::bytes(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_bytes(context, invoked);
  }

  void Assembler::reserve(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_reserve(context, invoked);
  }

  void Assembler::comment(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_comment(context, invoked);
  }

  void Assembler::end(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_end(context, invoked);
  }

  void Assembler::unknown(context::Context &context, lexicon::Phrase &invoked) {
    assembler_internal::action_assembler_unknown(context, invoked);
  }
} // namespace recurloop
