#include <recurloop/Functions.hpp>

#include "FunctionsInternal.hpp"
#ifdef RECURLOOP_ENABLE_LLVM
  #include "LlvmBackend.hpp"
#endif

#include <compiler/DynamicLinker.hpp>
#include <compiler/JitLinker.hpp>
#include <compiler/LanguageState.hpp>
#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace recurloop {
  namespace {
    constexpr std::string_view ActionRegistryName{"\0inline-actions", 15};
    constexpr std::uint64_t SignaturePhraseMagic = 0x524C464E53494731ull;

    struct SignaturePhraseHeader {
      std::uint64_t magic = SignaturePhraseMagic;
      compiler::TypeId type = compiler::InvalidType;
      std::uint32_t parameterCount = 0;
    };

    struct SignaturePhrase {
      compiler::TypeId type = compiler::InvalidType;
      std::vector<std::string> names;
    };

    bool validSymbol(std::string_view value) {
      std::size_t begin = 0;
      while (begin < value.size()) {
        const std::size_t end = value.find(':', begin);
        const std::string_view component = value.substr(begin, end - begin);
        if (component.empty() ||
            (!std::isalpha(static_cast<unsigned char>(component.front())) && component.front() != '_') ||
            !std::all_of(component.begin() + 1, component.end(),
                         [](unsigned char character) { return std::isalnum(character) || character == '_'; }))
          return false;
        if (end == std::string_view::npos) return true;
        begin = end + 1;
      }
      return false;
    }

    struct DefinitionHeader {
      std::string name;
      std::string signature;
      std::size_t signatureOffset = 0;
    };

    std::size_t signatureOpening(context::Context &context, std::string_view header) {
      lexicon::Phrase grammar = LanguageGrammar::find(context.lexicon.phrase(), function_internal::FunctionGrammarName);
      lexicon::Phrase symbols = LanguageGrammar::find(grammar, "symbols");
      lexicon::Phrase canonical = LanguageGrammar::find(symbols, "(");
      for (std::size_t offset = 0; offset < header.size(); ++offset) {
        lexicon::Phrase spelling = LanguageGrammar::matchLongest(context, {symbols}, header.substr(offset));
        if (spelling.isNull()) continue;
        const std::string key = spelling.getKey();
        const bool word = !key.empty() && (std::isalnum(static_cast<unsigned char>(key.front())) || key.front() == '_');
        if (word && ((offset != 0 &&
                      (std::isalnum(static_cast<unsigned char>(header[offset - 1])) || header[offset - 1] == '_')) ||
                     (offset + key.size() < header.size() &&
                      (std::isalnum(static_cast<unsigned char>(header[offset + key.size()])) ||
                       header[offset + key.size()] == '_'))))
          continue;
        lexicon::Phrase resolved = LanguageGrammar::resolve(context, symbols, key);
        if (!resolved.isNull() && resolved.getAddress() == canonical.getAddress()) return offset;
      }
      return std::string::npos;
    }

    DefinitionHeader definitionHeader(context::Context &context, std::string header) {
      const std::size_t opening = signatureOpening(context, header);
      if (opening == std::string::npos) THROW(, "fn expects '[name](parameters) -> result' before '{'")
      DefinitionHeader result{function_internal::trim(header.substr(0, opening)), header.substr(opening), opening};
      if (!result.name.empty() && !validSymbol(result.name))
        THROW(, "fn: invalid function name '" << result.name << "'")
      return result;
    }

    lexicon::Phrase qualified(lexicon::Phrase phrase, std::string_view name) {
      while (!name.empty()) {
        const std::size_t separator = name.find(':');
        phrase = LanguageGrammar::find(phrase, name.substr(0, separator));
        if (phrase.isNull() || separator == std::string_view::npos) return phrase;
        name.remove_prefix(separator + 1);
      }
      return lexicon::Phrase(phrase.getLexicon());
    }

    std::optional<SignaturePhrase> signaturePhrase(lexicon::Phrase phrase) {
      for (std::size_t depth = 0; !phrase.isNull() && depth < 1024; ++depth) {
        if (phrase.payloadSize() >= sizeof(SignaturePhraseHeader)) {
          SignaturePhraseHeader header;
          std::memcpy(&header, phrase.content(0, sizeof(header)).toPtr(), sizeof(header));
          if (header.magic == SignaturePhraseMagic) {
            if (header.type == compiler::InvalidType) THROW(, "function signature phrase has invalid payload")
            SignaturePhrase result;
            result.type = header.type;
            std::size_t offset = sizeof(header);
            result.names.reserve(header.parameterCount);
            for (std::size_t index = 0; index < header.parameterCount; ++index) {
              if (offset > phrase.payloadSize() || phrase.payloadSize() - offset < sizeof(std::uint32_t))
                THROW(, "function signature phrase has invalid payload")
              std::uint32_t bytes = 0;
              std::memcpy(&bytes, phrase.content(offset, sizeof(bytes)).toPtr(), sizeof(bytes));
              offset += sizeof(bytes);
              if (bytes > phrase.payloadSize() - offset) THROW(, "function signature phrase has invalid payload")
              std::string name(bytes, '\0');
              if (bytes != 0) std::memcpy(name.data(), phrase.content(offset, bytes).toPtr(), bytes);
              offset += bytes;
              result.names.push_back(std::move(name));
            }
            if (offset != phrase.payloadSize()) THROW(, "function signature phrase has invalid payload")
            return result;
          }
        }
        if (!phrase.containsPrototype()) break;
        phrase = phrase.getPrototype();
      }
      return std::nullopt;
    }

    std::vector<std::uint8_t> signaturePayload(compiler::TypeId type, const std::vector<std::string> &names) {
      if (names.size() > std::numeric_limits<std::uint32_t>::max())
        THROW(, "function signature phrase has too many parameters")
      const SignaturePhraseHeader header{SignaturePhraseMagic, type, static_cast<std::uint32_t>(names.size())};
      std::size_t size = sizeof(header);
      for (const std::string &name : names) {
        if (name.size() > std::numeric_limits<std::uint32_t>::max() ||
            size > std::numeric_limits<std::size_t>::max() - sizeof(std::uint32_t) ||
            name.size() > std::numeric_limits<std::size_t>::max() - size - sizeof(std::uint32_t))
          THROW(, "function signature phrase is too large")
        size += sizeof(std::uint32_t) + name.size();
      }
      std::vector<std::uint8_t> result(size);
      std::memcpy(result.data(), &header, sizeof(header));
      std::size_t offset = sizeof(header);
      for (const std::string &name : names) {
        const auto bytes = static_cast<std::uint32_t>(name.size());
        std::memcpy(result.data() + offset, &bytes, sizeof(bytes));
        offset += sizeof(bytes);
        if (bytes != 0) std::memcpy(result.data() + offset, name.data(), bytes);
        offset += bytes;
      }
      return result;
    }

    function_internal::FunctionDefinition
        signatureDefinition(context::Context &context, const SignaturePhrase &signature, const std::string &symbol) {
      const compiler::TypeDescriptor type = context.language().types.get(signature.type);
      if (type.kind != compiler::TypeKind::Function || type.parameterTypes.size() != signature.names.size())
        THROW(, "function signature phrase does not describe a function")
      function_internal::FunctionDefinition result;
      result.names = signature.names;
      result.function.signature = context.language().functionSignature(signature.type, symbol);
      result.function.parameterTypes = type.parameterTypes;
      result.function.resultType = type.resultType;
      return result;
    }

    bool pointerTo(context::Context &context, compiler::TypeId type, std::string_view pointee) {
      const compiler::TypeDescriptor pointer = context.language().types.get(type);
      return pointer.kind == compiler::TypeKind::Pointer &&
             context.language().types.get(pointer.element).name == pointee;
    }

    void requireActionSignature(context::Context &context, const compiler::TypedFunction &function) {
      const bool valid = !function.signature.variadic && function.signature.convention.name == "sysv-amd64" &&
                         function.parameterTypes.size() == 2 &&
                         pointerTo(context, function.parameterTypes[0], "Context") &&
                         pointerTo(context, function.parameterTypes[1], "Phrase") &&
                         context.language().types.get(function.resultType).kind == compiler::TypeKind::Void;
      if (!valid) THROW(, "phrase action requires fn (context:Context*, phrase:Phrase*) -> void")
    }

    void rememberFunctionSource(context::Context &context, const function_internal::FunctionDefinition &definition) {
      compiler::FunctionSource source;
      source.parameterNames = definition.names;
      source.scope = definition.scope;
      source.path = definition.sourcePath;
      source.body = definition.sourceText;
      source.line = definition.sourceLine;
      source.column = definition.sourceColumn;
      context.language().rememberFunctionSource(definition.function.signature.symbol, std::move(source));
    }
  } // namespace

  lexicon::Phrase Functions::action(context::Context &context, std::string_view symbol) {
    if (symbol.empty()) THROW(, "inline phrase action requires a stable symbol")
    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase registry = LanguageGrammar::find(root, ActionRegistryName);
    if (registry.isNull())
      registry =
          root.append(Byte(const_cast<char *>(ActionRegistryName.data())), 0, ActionRegistryName.size() * Byte::length)
              .make()
              .enableSubdictionary()
              .setType(lexicon::phrase::type::getData(root))
              .save();
    lexicon::Phrase implementation = LanguageGrammar::find(registry, symbol);
    if (!implementation.isNull()) return implementation;
    return registry.append(Byte(const_cast<char *>(symbol.data())), 0, symbol.size() * Byte::length)
        .make()
        .setType(lexicon::phrase::type::getData(root))
        .save();
  }

  void Functions::bindAction(lexicon::Draft &draft, lexicon::Phrase implementation) {
    draft.setAction(invokeBoundAction).setActionImplementation(implementation);
  }

  void Functions::bindAction(lexicon::Phrase &phrase, lexicon::Phrase implementation) {
    phrase.setAction(invokeBoundAction).setActionImplementation(implementation).save();
  }

  void Functions::invokeBoundAction(context::Context &context, lexicon::Phrase &invoked) {
    lexicon::Phrase binding = invoked;
    for (std::size_t depth = 0; !binding.containsAction() && depth < 64; ++depth) {
      lexicon::Phrase prototype = binding.getPrototype();
      if (prototype.isNull() || prototype.getAddress() == binding.getAddress()) break;
      binding = prototype;
    }
    if (!binding.containsAction()) THROW(, "bound phrase action has no allocated action slot")
    lexicon::Phrase implementation = binding.getActionImplementation();
    if (implementation.isNull()) THROW(, "bound phrase action has no implementation")
    const std::string symbol = implementation.getKey();
    const std::optional<compiler::TypedFunction> function = context.language().findFunction(symbol);
    if (!function) THROW(, "bound phrase action function is unavailable: '" << symbol << "'")
    requireActionSignature(context, *function);

    std::uintptr_t entry = binding.getActionEntry();
    if (entry == 0) {
      const std::optional<compiler::Module> module = context.language().findModule(symbol);
      if (!module) THROW(, "bound phrase action module is unavailable: '" << symbol << "'")
      const compiler::Module linked = context.language().composeModule(*module);
      const compiler::JitImage image = compiler::JitLinker::link(
          linked, context.runtime, [&](std::string_view dependency) -> std::optional<std::uintptr_t> {
            return compiler::DynamicLinker::instance().resolveFromDefault(dependency);
          });
      entry = image.address(symbol);
      binding.setActionEntry(entry).save();
    }
    reinterpret_cast<void (*)(context::Context *, lexicon::Phrase *)>(entry)(&context, &invoked);
  }

  void Functions::forward(context::Context &context, lexicon::Phrase &) {
    const SourceLocation origin{context.source.path, context.source.line, context.source.position};
    const std::string declaration = function_internal::trim(function_internal::readLine(context));
    const std::size_t opening = declaration.find('(');
    if (opening == std::string::npos) THROW(, "forward expects name(parameters) -> result")
    const std::string symbol = function_internal::trim(declaration.substr(0, opening));
    if (!validSymbol(symbol)) THROW(, "forward: invalid function name '" << symbol << "'")

    const std::string signatureSource = declaration.substr(opening);
    const SourceLocation signatureLocation = sourceLocationAt(origin, declaration, opening);
    function_internal::FunctionDefinition signature =
        function_internal::parseSignature(context, signatureSource, symbol, false, signatureLocation.path,
                                          signatureLocation.line, signatureLocation.column);
    signature.function.name = symbol;
    signature.function.signature.symbol = context.language().functionSymbol(symbol, signature.function.parameterTypes,
                                                                            signature.function.signature.variadic);
    signature.function.imported = true;
    context.language().declareFunction(std::move(signature.function));
  }

  lexicon::Phrase Functions::compileAction(context::Context &context, std::string_view signatureSource,
                                           std::string_view bodySource, std::string hint,
                                           SourceLocation signatureOrigin, SourceLocation bodyOrigin) {
    const std::string scope = Assembler::definitionSymbol(context);
    if (hint.empty()) hint = "__recurloop_action_" + std::to_string(context.lexicon.checkpoint().getAddress());
    if (signatureOrigin.path.empty())
      signatureOrigin = {context.source.path, context.source.line, context.source.position};
    if (bodyOrigin.path.empty()) bodyOrigin = signatureOrigin;
    function_internal::FunctionDefinition definition = function_internal::parseSignature(
        context, signatureSource, hint, false, signatureOrigin.path, signatureOrigin.line, signatureOrigin.column);
    definition.scope = scope;
    std::vector<function_internal::Statement> statements =
        function_internal::parseBody(context, bodySource, scope, bodyOrigin.path, bodyOrigin.line, bodyOrigin.column);
    definition.sourcePath = bodyOrigin.path;
    definition.sourceText = std::string(bodySource);
    definition.sourceLine = bodyOrigin.line;
    definition.sourceColumn = bodyOrigin.column;
    return function_internal::compileActionDefinition(context, std::move(definition), statements, hint);
  }

  void Functions::define(context::Context &context, lexicon::Phrase &invoked) {
    const bool stagedByLet = !context.staging.phrase.getKey().empty();
    const bool openingBrace = Blocks::hasOpeningBrace(context, true);
    const bool indented = !openingBrace && Blocks::hasIndentedBody(context);
    if (!openingBrace && !indented) {
      if (!stagedByLet) THROW(, "fn signature aliases require 'let name = fn ...'")
      if (signaturePhrase(invoked)) THROW(, "a function signature alias requires '<alias>' or a new 'fn' signature")
      const SourceLocation origin{context.source.path, context.source.line, context.source.position};
      const std::string source = function_internal::trim(function_internal::readLine(context));
      const std::string symbol = Assembler::definitionSymbol(context);
      function_internal::FunctionDefinition signature =
          function_internal::parseSignature(context, source, symbol, false, origin.path, origin.line, origin.column);
      const compiler::TypeId type = context.language().functionType(signature.function);
      context.staging.phrase.setPrototype(invoked);
      context.exec.pendingPhrasePayload = signaturePayload(type, signature.names);
      context::Lookup::leave(context, invoked);
      return;
    }

    SourceBlock block = indented ? Blocks::captureIndented(context) : Blocks::capture(context);
    const std::optional<SignaturePhrase> inheritedSignature = signaturePhrase(invoked);
    const std::string headerSource = block.header;
    DefinitionHeader header;
    if (inheritedSignature) {
      header.name = function_internal::trim(std::move(block.header));
      if (!header.name.empty() && !validSymbol(header.name))
        THROW(, "fn: invalid function name '" << header.name << "'")
    } else {
      header = definitionHeader(context, std::move(block.header));
    }

    context.workspace.key.clear();
    if (header.name.empty()) {
      if (!stagedByLet) THROW(, "fn requires a name unless it is the right-hand side of let")
      context.workspace.key.append(context.staging.phrase.getKey());
    } else {
      context.workspace.key.append(header.name);
      context.staging.phrase =
          context.staging.dictionary
              .append(Byte(reinterpret_cast<unsigned char *>(header.name.data())), 0, header.name.size() * Byte::length)
              .make();
    }

    const std::string symbol = Assembler::definitionSymbol(context);
    if (symbol.empty()) THROW(, "fn requires a phrase name")

    const SourceLocation headerLocation{block.path, block.headerLine, block.headerPosition};
    const SourceLocation signatureLocation = sourceLocationAt(headerLocation, headerSource, header.signatureOffset);
    function_internal::FunctionDefinition signature =
        inheritedSignature
            ? signatureDefinition(context, *inheritedSignature, symbol)
            : function_internal::parseSignature(context, header.signature, symbol, false, signatureLocation.path,
                                                signatureLocation.line, signatureLocation.column);
    signature.function.name = symbol;
    signature.scope = symbol;
    signature.sourcePath = block.path;
    signature.sourceText = block.body;
    signature.sourceLine = block.line;
    signature.sourceColumn = block.position;
    if (!Assembler::hasNativeOutput(context))
      signature.function.signature.symbol = context.language().functionSymbol(symbol, signature.function.parameterTypes,
                                                                              signature.function.signature.variadic);
    context.language().declareFunction(signature.function);
    const std::size_t separator = symbol.rfind(':');
    if (separator != std::string::npos && !signature.function.parameterTypes.empty()) {
      compiler::TypeDescriptor receiver = context.language().types.get(signature.function.parameterTypes.front());
      if (receiver.kind == compiler::TypeKind::Pointer) receiver = context.language().types.get(receiver.element);
      const std::string owner = symbol.substr(0, separator);
      const std::string method = symbol.substr(separator + 1);
      if (receiver.kind == compiler::TypeKind::Structure && receiver.name == owner &&
          std::none_of(receiver.methods.begin(), receiver.methods.end(), [&](const compiler::TypeMethod &candidate) {
            return candidate.name == method &&
                   candidate.signature.parameters == signature.function.signature.parameters &&
                   candidate.signature.variadic == signature.function.signature.variadic;
          }))
        context.language().types.addMethod(receiver.id, method, signature.function.signature);
    }

    std::vector<function_internal::Statement> statements =
        function_internal::parseBody(context, block.body, symbol, block.path, block.line, block.position);
    rememberFunctionSource(context, signature);
    context.exec.definitionSymbolOverride = signature.function.signature.symbol;
    compiler::Module module;
    try {
#ifdef RECURLOOP_ENABLE_LLVM
      const std::optional<NativeFileRequest> output = Assembler::nativeFileRequest(context);
      if (output && output->kind != NativeFileKind::Raw) {
        function_internal::LlvmProgram program = function_internal::generateLlvmProgram(
            context, signature, statements,
            output->kind == NativeFileKind::Executable ? std::string_view(output->entry) : std::string_view{});
        Assembler::finalizeLlvm(context, invoked, program.objects, program.providedSymbols, program.imports);
      } else {
        module = function_internal::generateLlvmModule(context, signature, statements);
        Assembler::finalize(context, invoked, module);
      }
#else
      module = function_internal::generateModule(context, signature, statements);
      Assembler::finalize(context, invoked, module);
#endif
    } catch (...) {
      context.exec.definitionSymbolOverride.clear();
      throw;
    }
    context.exec.definitionSymbolOverride.clear();
    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase previous = LanguageGrammar::find(context.staging.dictionary, context.staging.phrase.getKey());
    if (!previous.isNull()) context.staging.phrase.setPrototype(previous);
    context.staging.phrase.enableSubdictionary();
    context.staging.phrase.setType(lexicon::phrase::type::getCallable(root));
    context.exec.pendingFunctionVariant =
        context.language().functionKey(signature.function.parameterTypes, signature.function.signature.variadic);
    if (stagedByLet) {
      context::Lookup::leave(context, invoked);
      return;
    }

    lexicon::Phrase &saved = context.staging.phrase.save();
    Assembler::commitNative(context, saved);
    commitVariant(context, saved);
    context.staging.phrase = context.staging.dictionary.append("");
    context.workspace.key.clear();
  }

  compiler::TypeId Functions::signatureType(context::Context &context, std::string_view name) {
    const std::optional<SignaturePhrase> signature = signaturePhrase(qualified(context.lexicon.phrase(), name));
    return signature ? signature->type : compiler::InvalidType;
  }

  compiler::TypedFunction Functions::parseDeclaration(context::Context &context, std::string_view source,
                                                      bool imported) {
    DefinitionHeader header = definitionHeader(context, std::string(source));
    if (header.name.empty()) THROW(, "typed function declaration requires a symbol")
    function_internal::FunctionDefinition definition =
        function_internal::parseSignature(context, header.signature, header.name, true);
    definition.function.imported = imported;
    definition.function.name = header.name;
    return std::move(definition.function);
  }

  void Functions::commitVariant(context::Context &context, lexicon::Phrase &function) {
    if (context.exec.pendingFunctionVariant.empty()) return;
    lexicon::Phrase previous =
        function.containsPrototype() ? function.getPrototype() : lexicon::Phrase(&context.lexicon);
    if (!function.containsSubdictionary()) {
      lexicon::Phrase implementation = function;
      lexicon::Phrase owner = context.staging.dictionary;
      function = owner.append(function.getKey())
                     .make()
                     .enableSubdictionary()
                     .setPrototype(implementation)
                     .setType(implementation.getType())
                     .setAction(implementation.getAction())
                     .save();
    }
    if (!previous.isNull() && previous.containsSubdictionary() &&
        previous.getSubdictionary().getAddress() != function.getSubdictionary().getAddress()) {
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      for (lexicon::Dictionary cursor = previous.fore(populated); !cursor.isNull(); cursor = cursor.next(populated)) {
        lexicon::Phrase variant = cursor.getPhrase();
        if (variant.isNull()) continue;
        function.append(variant.getKey())
            .make()
            .enableSubdictionary()
            .setPrototype(variant)
            .setType(variant.getType())
            .setAction(variant.getAction())
            .save();
      }
    }
    function.append(context.exec.pendingFunctionVariant)
        .make()
        .enableSubdictionary()
        .setPrototype(function)
        .setType(function.getType())
        .setAction(function.getAction())
        .save();
    context.exec.pendingFunctionVariant.clear();
  }

  void Functions::setup(context::Context &context) {
    context.actions().define("fn.forward", forward);
    context.actions().define("fn.define", define);
    context.actions().define("fn.bound-action", invokeBoundAction);
    lexicon::Phrase root = context.lexicon.phrase();
    LanguageGrammar::ensureMarker(context, "else");
    LanguageGrammar::ensureMarker(context, "cast");
    lexicon::Phrase grammar = root.append(Byte(const_cast<char *>(function_internal::FunctionGrammarName.data())), 0,
                                          function_internal::FunctionGrammarName.size() * Byte::length)
                                  .make()
                                  .enableSubdictionary()
                                  .setType(lexicon::phrase::type::getData(root))
                                  .save();
    lexicon::Phrase symbols =
        grammar.append("symbols").make().enableSubdictionary().setType(lexicon::phrase::type::getData(root)).save();
    for (std::string_view symbol : {"...", "->", "(", ")", "{", "}", "]", ",", ":", ";", ".", "&", "?"})
      symbols.append(std::string(symbol))
          .make()
          .setPrototype(LanguageGrammar::ensureMarker(root, symbol))
          .setType(lexicon::phrase::type::getData(root))
          .save();
    function_internal::setupStatementSyntax(context, grammar);
    lexicon::Phrase forwardPhrase =
        root.append("forward").make(forward).setType(lexicon::phrase::type::getElaborate(root)).save();
    compiler::LanguageState::bind(forwardPhrase);
    lexicon::Phrase fnMarker = LanguageGrammar::find(root, "fn");
    lexicon::Draft fnDraft = root.append("fn").make(define).setType(lexicon::phrase::type::getElaborate(root));
    if (!fnMarker.isNull()) fnDraft.setPrototype(fnMarker);
    lexicon::Phrase fn = fnDraft.save();
    compiler::LanguageState::bind(fn);
    function_internal::setupCompilerSyntax(context);
  }

  void Functions::finalizeSyntax(context::Context &context) {
    function_internal::bindSyntaxPrototypes(context);
  }

  namespace function_internal {
    compiler::TypedFunction compileFunctionDefinition(context::Context &context, FunctionDefinition definition,
                                                      const std::vector<Statement> &body, std::string hint) {
      if (hint.empty()) hint = definition.function.signature.symbol;
      if (definition.scope.empty()) definition.scope = hint;
      definition.function.name = hint;
      definition.function.signature.symbol = hint;
      definition.function.imported = false;
      context.language().declareFunction(definition.function);
      rememberFunctionSource(context, definition);

      const std::string previousOverride = context.exec.definitionSymbolOverride;
      context.exec.definitionSymbolOverride = hint;
      compiler::Module module;
      try {
#ifdef RECURLOOP_ENABLE_LLVM
        module = generateLlvmModule(context, definition, body);
#else
        module = generateModule(context, definition, body);
#endif
      } catch (...) {
        context.exec.definitionSymbolOverride = previousOverride;
        throw;
      }
      context.exec.definitionSymbolOverride = previousOverride;
      context.language().rememberModule(hint, std::move(module));
      return definition.function;
    }

    lexicon::Phrase compileActionDefinition(context::Context &context, FunctionDefinition definition,
                                            const std::vector<Statement> &body, std::string hint) {
      requireActionSignature(context, definition.function);
      const compiler::TypedFunction function =
          compileFunctionDefinition(context, std::move(definition), body, std::move(hint));
      const std::string &symbol = function.signature.symbol;
      return Functions::action(context, symbol);
    }
  } // namespace function_internal
} // namespace recurloop
