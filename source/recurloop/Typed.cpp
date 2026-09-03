#include <recurloop/Typed.hpp>

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/Assembler.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/SyntaxCursor.hpp>
#include <recurloop/TypeSyntax.hpp>

#include <charconv>
#include <cctype>
#include <cstring>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace recurloop {
  namespace {
    constexpr std::string_view TypedGrammarName{"\0typed-grammar", 14};

    struct TypedPhraseData {
      compiler::TypeId type = compiler::InvalidType;
      std::size_t storageBytes = 0;
    };

    struct TypedFieldData {
      compiler::TypeId type = compiler::InvalidType;
      std::size_t offset = 0;
    };

    char peek(context::Context &context) {
      while (context.source.buffer.bits == 0 && context.source.more) context::Source::load(context, false);
      if (context.source.buffer.bits == 0) return '\0';
      return context.source.buffer.str[context.source.buffer.offset / Byte::length];
    }

    std::string readLine(context::Context &context, SourceLocation *origin = nullptr) {
      if (origin != nullptr)
        *origin = {context.source.path, context.source.line, context.source.position};
      std::string result;
      while (peek(context) != '\0' && peek(context) != '\n') {
        result.push_back(peek(context));
        context::Source::progress(context, Byte::length);
      }
      return result;
    }

    std::string qualify(context::Context &context, std::string name) {
      if (name.find(':') != std::string::npos) return name;
      const std::string owner = Assembler::dictionarySymbol(context);
      return owner.empty() ? name : owner + ":" + name;
    }

    class Parser : public TypeSyntax::Cursor {
    public:
      Parser(context::Context &context, std::string source, SourceLocation origin)
          : context(context), source(std::move(source)), origin(std::move(origin)),
            cursor(
                context, this->source,
                {LanguageGrammar::find(LanguageGrammar::find(context.lexicon.phrase(), TypedGrammarName), "symbols"),
                 LanguageGrammar::find(
                     LanguageGrammar::find(context.lexicon.phrase(), std::string_view{"\0type-syntax", 12}), "prefix"),
                 LanguageGrammar::find(
                     LanguageGrammar::find(context.lexicon.phrase(), std::string_view{"\0type-syntax", 12}), "suffix")},
                [this](const context::Context &, std::size_t offset, const std::string &message) {
                  this->fail(offset, message);
                },
                {.bareWords = true}) {}
      bool done() const {
        return cursor.current().kind == SyntaxTokenKind::End;
      }
      bool accept(std::string_view token) {
        return !done() && cursor.accept(token);
      }
      std::string take(std::string_view description) {
        if (done()) fail(cursor.current().offset, "expected " + std::string(description));
        return cursor.take().text;
      }
      std::string qualified(std::string_view description) {
        std::string result = take(description);
        while (accept(":")) result += ":" + take("a qualified name component");
        return result;
      }
      std::string remaining() const {
        return std::string(source.substr(cursor.current().offset));
      }
      void expect(std::string_view token) {
        if (!accept(token)) fail(cursor.current().offset, "expected '" + std::string(token) + "'");
      }
      std::vector<std::string> list(std::string_view description) {
        expect("(");
        std::vector<std::string> result;
        if (accept(")")) return result;
        while (true) {
          result.push_back(take(description));
          if (accept(")")) break;
          expect(",");
        }
        return result;
      }
      std::size_t number(std::string_view description) {
        const std::string text = take(description);
        std::size_t result = 0;
        const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), result);
        if (error != std::errc() || end != text.data() + text.size())
          fail(cursor.current().offset, "invalid " + std::string(description) + " '" + text + "'");
        return result;
      }
      compiler::TypeId type() {
        return TypeSyntax::parse(context, *this, Assembler::dictionarySymbol(context));
      }

      std::string_view typeCurrent() const override {
        return done() ? std::string_view{} : std::string_view(cursor.current().text);
      }
      bool typeAccept(std::string_view token) override {
        return accept(token);
      }
      void typeExpect(std::string_view token) override {
        expect(token);
      }
      std::string typeIdentifier(std::string_view description) override {
        return take(description);
      }
      std::size_t typeNumber(std::string_view description) override {
        return number(description);
      }
      [[noreturn]] void typeError(const std::string &message) override {
        fail(cursor.current().offset, message);
      }

    private:
      context::Context &context;
      std::string source;
      SourceLocation origin;
      SyntaxCursor cursor;

      [[noreturn]] void fail(std::size_t offset, const std::string &message) const {
        const SourceLocation location = sourceLocationAt(origin, source, offset);
        THROW_AT(location, "typed declaration: " << message)
      }
    };

    thread_local Parser *currentCommandParser = nullptr;
    thread_local compiler::CallingConvention *currentConvention = nullptr;

    Parser &commandParser() {
      if (currentCommandParser == nullptr) THROW(, "typed command phrase invoked without a parser")
      return *currentCommandParser;
    }

    compiler::CallingConvention &convention() {
      if (currentConvention == nullptr) THROW(, "ABI property phrase invoked without a convention")
      return *currentConvention;
    }

    void invokeCommand(context::Context &context, Parser &parser, lexicon::Phrase phrase) {
      Parser *previous = currentCommandParser;
      currentCommandParser = &parser;
      try {
        phrase.invoke(context);
      } catch (...) {
        currentCommandParser = previous;
        throw;
      }
      currentCommandParser = previous;
    }

    void dispatchCommand(context::Context &context, lexicon::Phrase grammar, std::string_view kind) {
      SourceLocation origin;
      std::string source = readLine(context, &origin);
      Parser parser(context, std::move(source), std::move(origin));
      const std::string command = parser.take(std::string("a ") + std::string(kind) + " command");
      lexicon::Phrase phrase = LanguageGrammar::resolve(context, grammar, command);
      if (phrase.isNull()) THROW(, "typed declaration: unknown " << kind << " command '" << command << "'")
      invokeCommand(context, parser, phrase);
      if (!parser.done()) THROW(, "typed declaration: unexpected token after " << kind << " command")
    }

    void abiInteger(context::Context &, lexicon::Phrase &) {
      convention().integerRegisters = commandParser().list("an integer argument register");
    }
    void abiFloating(context::Context &, lexicon::Phrase &) {
      convention().floatingRegisters = commandParser().list("a floating-point argument register");
    }
    void abiResult(context::Context &, lexicon::Phrase &) {
      const auto value = commandParser().list("a result register");
      if (value.size() != 1) THROW(, "typed declaration: result requires exactly one register")
      convention().resultRegister = value.front();
    }
    void abiFloatingResult(context::Context &, lexicon::Phrase &) {
      const auto value = commandParser().list("a floating-point result register");
      if (value.size() != 1) THROW(, "typed declaration: floating-result requires exactly one register")
      convention().floatingResultRegister = value.front();
    }
    void abiAlign(context::Context &, lexicon::Phrase &) {
      commandParser().expect("(");
      convention().stackAlignment = commandParser().number("stack alignment");
      commandParser().expect(")");
    }
    void abiShadow(context::Context &, lexicon::Phrase &) {
      commandParser().expect("(");
      convention().shadowSpace = commandParser().number("shadow-space size");
      commandParser().expect(")");
    }
    bool booleanValue(context::Context &context, lexicon::Phrase grammar, const std::string &spelling,
                      std::string_view description) {
      lexicon::Phrase value = LanguageGrammar::resolve(context, grammar, spelling);
      lexicon::Phrase metadata = LanguageGrammar::metadata(value, sizeof(std::uint8_t));
      if (metadata.isNull()) THROW(, "typed declaration: " << description << " has unknown value '" << spelling << "'")
      std::uint8_t result = 0;
      metadata.fetch(0, result);
      return result != 0;
    }

    void abiStack(context::Context &context, lexicon::Phrase &invoked) {
      const auto value = commandParser().list("a stack direction");
      if (value.size() != 1) THROW(, "typed declaration: stack requires exactly one direction")
      convention().stackGrowsDown = booleanValue(context, invoked, value.front(), "stack direction");
    }
    void abiCleanup(context::Context &context, lexicon::Phrase &invoked) {
      const auto value = commandParser().list("a stack cleanup owner");
      if (value.size() != 1) THROW(, "typed declaration: cleanup requires exactly one owner")
      convention().callerCleansStack = booleanValue(context, invoked, value.front(), "stack cleanup owner");
    }

    void moduleAuto(context::Context &context, lexicon::Phrase &) {
      context.language().setAutomaticModuleLinking(true);
    }
    void moduleManual(context::Context &context, lexicon::Phrase &) {
      context.language().setAutomaticModuleLinking(false);
    }
    void moduleInclude(context::Context &context, lexicon::Phrase &) {
      context.language().includeModule(commandParser().take("a module symbol"));
    }
    void moduleExclude(context::Context &context, lexicon::Phrase &) {
      context.language().excludeModule(commandParser().take("a module symbol"));
    }
    void moduleEntry(context::Context &context, lexicon::Phrase &) {
      context.language().setModuleEntry(commandParser().take("an entry symbol"));
    }
    void moduleEmbed(context::Context &context, lexicon::Phrase &) {
      context.language().setEmbedLanguage(true);
    }
    void moduleStrip(context::Context &context, lexicon::Phrase &) {
      context.language().setEmbedLanguage(false);
    }
    void moduleClear(context::Context &context, lexicon::Phrase &) {
      context.language().clearModuleSelection();
    }

    void linkObject(context::Context &context, lexicon::Phrase &) {
      context.language().linkObject(commandParser().take("an object path"));
    }
    void linkArchive(context::Context &context, lexicon::Phrase &) {
      context.language().linkArchive(commandParser().take("an archive path"));
    }
    void linkPath(context::Context &context, lexicon::Phrase &) {
      context.language().addLinkSearchPath(commandParser().take("a library search path"));
    }
    void linkLibrary(context::Context &context, lexicon::Phrase &) {
      context.language().linkLibrary(commandParser().take("a static library name"));
    }
    void linkShared(context::Context &context, lexicon::Phrase &) {
      context.language().linkSharedLibrary(commandParser().take("a shared library name"));
    }
    void linkClear(context::Context &context, lexicon::Phrase &) {
      context.language().clearLinkInputs();
    }

    void externalUnavailable(context::Context &, lexicon::Phrase &invoked){
        THROW(, "external typed phrase '" << invoked.getKeyEscaped() << "' requires a native linker")}

    lexicon::Phrase qualifiedExact(lexicon::Phrase dictionary, const std::string &name) {
      std::size_t begin = 0;
      while (begin < name.size()) {
        const std::size_t end = name.find(':', begin);
        const std::string segment = name.substr(begin, end - begin);
        dictionary = LanguageGrammar::find(dictionary, segment);
        if (dictionary.isNull() || end == std::string::npos) return dictionary;
        begin = end + 1;
      }
      return dictionary;
    }

    void instantiateTyped(context::Context &context, lexicon::Phrase &invoked) {
      SourceLocation origin;
      std::string source = readLine(context, &origin);
      Parser parser(context, std::move(source), std::move(origin));
      const std::string name = parser.take("an instance name");
      if (!parser.done()) THROW(, "typed declaration: unexpected token after instance name")
      TypedPhraseData prototype;
      invoked.fetch(0, prototype);
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase instance = root.append(name)
                                     .make()
                                     .setPrototype(invoked)
                                     .setType(lexicon::phrase::type::getData(root))
                                     .save()
                                     .store(prototype);
      if (prototype.storageBytes != 0) {
        Byte storage = instance.allocate(prototype.storageBytes);
        std::memset(storage.toPtr(), 0, prototype.storageBytes);
      }
    }

    void defineTypedPhrase(context::Context &context, const compiler::TypeDescriptor &type,
                           const std::string &declaredName) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase owner = context.staging.dictionary;
      std::string localName = declaredName;
      const std::size_t separator = declaredName.rfind(':');
      if (separator != std::string::npos) {
        owner = root;
        std::size_t begin = 0;
        while (begin < separator) {
          const std::size_t end = declaredName.find(':', begin);
          const std::string segment = declaredName.substr(begin, end - begin);
          owner = LanguageGrammar::find(owner, segment);
          if (owner.isNull() || !owner.containsSubdictionary())
            THROW(, "typed declaration: undefined dictionary in '" << declaredName << "'")
          begin = end + 1;
        }
        localName = declaredName.substr(separator + 1);
      }
      if (localName.empty()) THROW(, "typed declaration: empty type name")
      if (!LanguageGrammar::find(owner, localName).isNull())
        THROW(, "typed declaration: phrase already exists: '" << type.name << "'")
      lexicon::Phrase structure = owner.append(localName)
                                      .make(instantiateTyped)
                                      .setType(lexicon::phrase::type::getElaborate(root))
                                      .enableSubdictionary()
                                      .save()
                                      .store(TypedPhraseData{type.id, type.size});
      for (const compiler::TypeField &field : type.fields)
        structure.append(field.name)
            .make()
            .setType(lexicon::phrase::type::getData(root))
            .save()
            .store(TypedFieldData{field.type, field.offset});
    }
  } // namespace

  void Typed::declareConvention(context::Context &context, lexicon::Phrase &invoked) {
    SourceLocation origin;
    std::string source = readLine(context, &origin);
    Parser parser(context, std::move(source), std::move(origin));
    compiler::CallingConvention convention;
    convention.name = parser.take("an ABI name");
    convention.integerRegisters.clear();
    convention.floatingRegisters.clear();
    parser.expect("(");
    if (!parser.accept(")")) {
      while (true) {
        const std::string property = parser.take("an ABI property");
        lexicon::Phrase phrase = LanguageGrammar::resolve(context, invoked, property);
        if (phrase.isNull()) THROW(, "typed declaration: unknown ABI property '" << property << "'")
        Parser *previousParser = currentCommandParser;
        compiler::CallingConvention *previousConvention = currentConvention;
        currentCommandParser = &parser;
        currentConvention = &convention;
        try {
          phrase.invoke(context);
        } catch (...) {
          currentCommandParser = previousParser;
          currentConvention = previousConvention;
          throw;
        }
        currentCommandParser = previousParser;
        currentConvention = previousConvention;
        if (parser.accept(")")) break;
        parser.expect(",");
      }
    }
    if (!parser.done()) THROW(, "typed declaration: unexpected token after ABI")
    context.language().defineConvention(std::move(convention));
  }

  void Typed::configureModule(context::Context &context, lexicon::Phrase &invoked) {
    dispatchCommand(context, invoked, "module");
  }

  void Typed::configureLink(context::Context &context, lexicon::Phrase &invoked) {
    dispatchCommand(context, invoked, "link");
  }

  void Typed::declareExternal(context::Context &context, lexicon::Phrase &) {
    compiler::TypedFunction function = Functions::parseDeclaration(context, readLine(context), true);

    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase overloads = LanguageGrammar::find(root, function.name);
    if (overloads.isNull())
      overloads = root.append(function.name)
                      .make(externalUnavailable)
                      .enableSubdictionary()
                      .setType(lexicon::phrase::type::getCallable(root))
                      .save();
    if (!overloads.containsSubdictionary()) THROW(, "external function phrase is not an overload dictionary")
    const std::string key = context.language().functionKey(function.parameterTypes, function.signature.variadic);
    overloads.append(key)
        .make(externalUnavailable)
        .enableSubdictionary()
        .setType(lexicon::phrase::type::getCallable(root))
        .save();
    context.language().declareFunction(std::move(function));
  }

  void Typed::declareFunction(context::Context &context, lexicon::Phrase &) {
    compiler::TypedFunction function = Functions::parseDeclaration(context, readLine(context), false);
    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase phrase = LanguageGrammar::find(root, function.signature.symbol);
    if (phrase.isNull() || !phrase.isInvokable())
      THROW(, "typed declaration: function phrase is not invokable: '" << function.signature.symbol << "'")
    if (!context.language().findModule(function.signature.symbol))
      THROW(, "typed declaration: function phrase has no native module: '" << function.signature.symbol << "'")
    context.language().declareFunction(std::move(function));
  }

  void Typed::declareRecord(context::Context &context, lexicon::Phrase &) {
    std::vector<compiler::FieldDeclaration> fields;
    std::string declaredName;
    bool packed = false;
    std::size_t alignment = 0;

    const auto options = [&](Parser &parser) {
      packed = parser.accept("packed");
      if (parser.accept("align")) {
        parser.expect("(");
        const std::string text = parser.take("an alignment");
        const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), alignment);
        if (error != std::errc() || end != text.data() + text.size()) THROW(, "typed declaration: invalid alignment")
        parser.expect(")");
      }
      if (!parser.done()) THROW(, "typed declaration: unexpected token after record")
    };

    if (Blocks::hasOpeningBrace(context)) {
      SourceBlock block = Blocks::capture(context);
      Parser header(context, block.header, {block.path, block.headerLine, block.headerPosition});
      declaredName = header.qualified("a record name");
      options(header);

      const std::string name = qualify(context, declaredName);
      const compiler::TypeId type = context.language().types.declareStructure(name);

      Parser body(context, block.body, {block.path, block.line, block.position});
      while (!body.done()) {
        const std::string field = body.take("a field name");
        body.expect(":");
        fields.push_back({field, body.type()});
        if (!body.done()) body.accept(",");
      }
      context.language().types.completeStructure(type, fields, packed, alignment);
      defineTypedPhrase(context, context.language().types.get(type), declaredName);
      return;
    } else {
      SourceLocation origin;
      std::string source = readLine(context, &origin);
      Parser parser(context, std::move(source), std::move(origin));
      declaredName = parser.qualified("a record name");
      const std::string name = qualify(context, declaredName);
      const compiler::TypeId type = context.language().types.declareStructure(name);
      parser.expect("(");
      if (!parser.accept(")")) {
        while (true) {
          const std::string field = parser.take("a field name");
          parser.expect(":");
          fields.push_back({field, parser.type()});
          if (parser.accept(")")) break;
          parser.expect(",");
        }
      }
      options(parser);
      context.language().types.completeStructure(type, fields, packed, alignment);
      defineTypedPhrase(context, context.language().types.get(type), declaredName);
      return;
    }
  }

  void Typed::declareMethod(context::Context &context, lexicon::Phrase &) {
    SourceLocation origin;
    std::string source = readLine(context, &origin);
    Parser parser(context, std::move(source), std::move(origin));
    const std::string structureName = parser.qualified("a structure type");
    const compiler::TypeId structure = context.language().types.find(structureName);
    if (structure == compiler::InvalidType ||
        context.language().types.get(structure).kind != compiler::TypeKind::Structure)
      THROW(, "typed declaration: method owner is not a structure: '" << structureName << "'")
    compiler::TypedFunction function = Functions::parseDeclaration(context, parser.remaining(), true);
    const std::string methodName = function.signature.symbol;
    function.signature.symbol = structureName + ":" + methodName;
    function.name = function.signature.symbol;

    context.language().types.addMethod(structure, methodName, function.signature);
    context.language().declareFunction(function);
    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase owner = qualifiedExact(root, structureName);
    if (owner.isNull()) THROW(, "typed declaration: structure phrase is unavailable: '" << structureName << "'")
    lexicon::Phrase overloads = LanguageGrammar::find(owner, methodName);
    if (overloads.isNull())
      overloads = owner.append(methodName)
                      .make(externalUnavailable)
                      .enableSubdictionary()
                      .setType(lexicon::phrase::type::getCallable(root))
                      .save();
    const std::string key = context.language().functionKey(function.parameterTypes, function.signature.variadic);
    overloads.append(key)
        .make(externalUnavailable)
        .enableSubdictionary()
        .setType(lexicon::phrase::type::getCallable(root))
        .save();
  }

  void Typed::declarePointer(context::Context &context, lexicon::Phrase &) {
    SourceLocation origin;
    std::string source = readLine(context, &origin);
    Parser parser(context, std::move(source), std::move(origin));
    const compiler::TypeId pointer = parser.type();
    if (context.language().types.get(pointer).kind != compiler::TypeKind::Pointer)
      THROW(, "typed declaration: pointer requires at least one '*'")
    const std::string name = parser.take("a pointer instance name");
    if (!parser.done()) THROW(, "typed declaration: unexpected token after pointer instance")

    compiler::TypeId pointee = pointer;
    while (context.language().types.get(pointee).kind == compiler::TypeKind::Pointer)
      pointee = context.language().types.get(pointee).element;
    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase prototype = qualifiedExact(root, context.language().types.get(pointee).name);
    if (prototype.isNull()) prototype = root;
    lexicon::Phrase instance = root.append(name)
                                   .make()
                                   .setPrototype(prototype)
                                   .setType(lexicon::phrase::type::getData(root))
                                   .save()
                                   .store(TypedPhraseData{pointer, sizeof(std::uintptr_t)});
    Byte storage = instance.allocate(sizeof(std::uintptr_t));
    std::memset(storage.toPtr(), 0, sizeof(std::uintptr_t));
  }

  void Typed::setup(context::Context &context) {
    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase grammar =
        root.append(Byte(const_cast<char *>(TypedGrammarName.data())), 0, TypedGrammarName.size() * Byte::length)
            .make()
            .enableSubdictionary()
            .setType(lexicon::phrase::type::getData(root))
            .save();
    lexicon::Phrase symbols =
        grammar.append("symbols").make().enableSubdictionary().setType(lexicon::phrase::type::getData(root)).save();
    for (std::string_view symbol : {"...", "->", "(", ")", ",", ":", "]", "="})
      symbols.append(std::string(symbol))
          .make()
          .setPrototype(LanguageGrammar::ensureMarker(root, symbol))
          .setType(lexicon::phrase::type::getData(root))
          .save();
    for (std::string_view keyword : {"abi", "packed", "align", "down", "up", "caller", "callee"})
      LanguageGrammar::ensureMarker(root, keyword);

    context.actions().define("typed.abi", declareConvention);
    context.actions().define("typed.module", configureModule);
    context.actions().define("typed.link", configureLink);
    context.actions().define("typed.extern", declareExternal);
    context.actions().define("typed.function", declareFunction);
    context.actions().define("typed.record", declareRecord);
    context.actions().define("typed.method", declareMethod);
    context.actions().define("typed.pointer", declarePointer);
    context.actions().define("typed.external-unavailable", externalUnavailable);
    context.actions().define("typed.instantiate", instantiateTyped);
    context.actions().define("typed.abi.integer", abiInteger);
    context.actions().define("typed.abi.floating", abiFloating);
    context.actions().define("typed.abi.result", abiResult);
    context.actions().define("typed.abi.floating-result", abiFloatingResult);
    context.actions().define("typed.abi.align", abiAlign);
    context.actions().define("typed.abi.shadow", abiShadow);
    context.actions().define("typed.abi.stack", abiStack);
    context.actions().define("typed.abi.cleanup", abiCleanup);
    context.actions().define("typed.module.auto", moduleAuto);
    context.actions().define("typed.module.manual", moduleManual);
    context.actions().define("typed.module.include", moduleInclude);
    context.actions().define("typed.module.exclude", moduleExclude);
    context.actions().define("typed.module.entry", moduleEntry);
    context.actions().define("typed.module.embed", moduleEmbed);
    context.actions().define("typed.module.strip", moduleStrip);
    context.actions().define("typed.module.clear", moduleClear);
    context.actions().define("typed.link.object", linkObject);
    context.actions().define("typed.link.archive", linkArchive);
    context.actions().define("typed.link.path", linkPath);
    context.actions().define("typed.link.library", linkLibrary);
    context.actions().define("typed.link.shared", linkShared);
    context.actions().define("typed.link.clear", linkClear);
    const auto bind = [&](std::string key, lexicon::Phrase::Action action, bool dictionary = false) {
      lexicon::Draft draft =
          root.append(std::move(key)).make(action).setType(lexicon::phrase::type::getElaborate(root));
      if (dictionary) draft.enableSubdictionary();
      lexicon::Phrase phrase = draft.save();
      compiler::LanguageState::bind(phrase);
      return phrase;
    };
    lexicon::Phrase abi = bind("abi", declareConvention, true);
    lexicon::Phrase module = bind("module", configureModule, true);
    lexicon::Phrase link = bind("link", configureLink, true);
    const auto command = [&](lexicon::Phrase &owner, std::string key, lexicon::Phrase::Action action,
                             bool dictionary = false) {
      lexicon::Phrase marker = LanguageGrammar::ensureMarker(root, key);
      lexicon::Draft draft = owner.append(std::move(key))
                                 .make(action)
                                 .setType(lexicon::phrase::type::getCallable(root))
                                 .setPrototype(marker);
      if (dictionary) draft.enableSubdictionary();
      return draft.save();
    };
    command(abi, "integer", abiInteger);
    command(abi, "floating", abiFloating);
    command(abi, "result", abiResult);
    command(abi, "floating-result", abiFloatingResult);
    command(abi, "align", abiAlign);
    command(abi, "shadow", abiShadow);
    lexicon::Phrase stack = command(abi, "stack", abiStack, true);
    lexicon::Phrase cleanup = command(abi, "cleanup", abiCleanup, true);
    const auto boolean = [&](lexicon::Phrase owner, std::string key, bool value) {
      owner.append(key)
          .make()
          .setType(lexicon::phrase::type::getData(root))
          .setPrototype(LanguageGrammar::ensureMarker(root, key))
          .save()
          .store(static_cast<std::uint8_t>(value));
    };
    boolean(stack, "down", true);
    boolean(stack, "up", false);
    boolean(cleanup, "caller", true);
    boolean(cleanup, "callee", false);
    command(module, "auto", moduleAuto);
    command(module, "manual", moduleManual);
    command(module, "include", moduleInclude);
    command(module, "exclude", moduleExclude);
    command(module, "dynamic", moduleExclude);
    command(module, "entry", moduleEntry);
    command(module, "embed", moduleEmbed);
    command(module, "strip", moduleStrip);
    command(module, "clear", moduleClear);
    command(link, "object", linkObject);
    command(link, "archive", linkArchive);
    command(link, "path", linkPath);
    command(link, "library", linkLibrary);
    command(link, "shared", linkShared);
    command(link, "clear", linkClear);
    bind("extern", declareExternal);
    bind("function", declareFunction);
    bind("record", declareRecord);
    bind("method", declareMethod);
    bind("pointer", declarePointer);
  }
} // namespace recurloop
