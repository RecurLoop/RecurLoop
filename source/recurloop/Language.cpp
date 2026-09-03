#if !defined(__RECURLOOP_LANGUAGE_CPP)
  #define __RECURLOOP_LANGUAGE_CPP
  #include "LanguageInternal.hpp"

  #include <recurloop/BitString.hpp>
  #include <recurloop/Blocks.hpp>
  #include <recurloop/ControlFlow.hpp>
  #include <recurloop/ContextApi.hpp>
  #include <recurloop/Engine.hpp>
  #include <recurloop/Expressions.hpp>
  #include <recurloop/NameInterpolation.hpp>
  #include <recurloop/PhraseDefinition.hpp>
  #include <recurloop/PhraseAction.hpp>
  #include <recurloop/Functions.hpp>
  #include <recurloop/LanguageGrammar.hpp>
  #include <recurloop/PhraseNames.hpp>
  #include <recurloop/Typed.hpp>
  #include <recurloop/TypeSyntax.hpp>

  #include <compiler/Assembler.hpp>
  #include <compiler/Module.hpp>

  #include <cstddef>
  #include <cstdint>
  #include <span>
  #include <string>
  #include <vector>

namespace recurloop {
  using namespace internal;

  namespace {
    template <typename Owner, typename Member> std::size_t memberOffset(Owner &owner, Member &member) {
      return static_cast<std::size_t>(reinterpret_cast<std::byte *>(&member) - reinterpret_cast<std::byte *>(&owner));
    }

    void setupContextTypes(context::Context &context) {
      compiler::LanguageState language = context.language();
      compiler::TypeRegistry &types = language.types;
      const compiler::TypeId u8 = types.find("u8");
      const compiler::TypeId i32 = types.find("i32");
      const compiler::TypeId u64 = types.find("u64");
      const compiler::TypeId bytePointer = types.pointerTo(u8);
      const compiler::TypeId bytePointerPointer = types.pointerTo(bytePointer);

      const auto opaque = [&](std::string name, std::size_t size, std::size_t alignment) {
        return types.defineStructureLayout(std::move(name), size, alignment);
      };
      const auto layout = [&](std::string name, std::size_t size, std::size_t alignment,
                              std::initializer_list<compiler::TypeField> fields) {
        return types.defineStructureLayout(std::move(name), size, alignment, fields);
      };

      const compiler::TypeId stringType = opaque("CxxString", sizeof(std::string), alignof(std::string));
      const compiler::TypeId bitString =
          layout("BitString", sizeof(BitString), alignof(BitString),
                 {{"data", bytePointer, offsetof(BitString, data)}, {"bits", u64, offsetof(BitString, bits)}});
      types.pointerTo(bitString);
      const compiler::TypeId phraseAction = layout(
          "PhraseAction", sizeof(PhraseAction), alignof(PhraseAction),
          {{"symbol", bytePointer, offsetof(PhraseAction, symbol)}, {"bytes", u64, offsetof(PhraseAction, bytes)}});
      types.pointerTo(phraseAction);
      const compiler::TypeId byteVector =
          opaque("CxxByteVector", sizeof(std::vector<std::uint8_t>), alignof(std::vector<std::uint8_t>));
      const compiler::TypeId phraseVector =
          opaque("CxxPhraseVector", sizeof(std::vector<lexicon::Phrase>), alignof(std::vector<lexicon::Phrase>));
      const compiler::TypeId nativeSectionVector =
          opaque("CxxNativeSectionVector", sizeof(std::vector<context::Workspace::NativeSection>),
                 alignof(std::vector<context::Workspace::NativeSection>));
      const compiler::TypeId timePoint =
          opaque("CxxTimePoint", sizeof(decltype(context.exec.start)), alignof(decltype(context.exec.start)));
      const compiler::TypeId exceptionPointer =
          opaque("CxxExceptionPointer", sizeof(std::exception_ptr), alignof(std::exception_ptr));
      const compiler::TypeId appender = opaque("Appender", sizeof(Appender), alignof(Appender));
      const compiler::TypeId lexicon = opaque("Lexicon", sizeof(lexicon::Lexicon), alignof(lexicon::Lexicon));
      const compiler::TypeId runtime = opaque("JitMemory", sizeof(JitMemory), alignof(JitMemory));
      const compiler::TypeId phrase = opaque("Phrase", sizeof(lexicon::Phrase), alignof(lexicon::Phrase));
      const compiler::TypeId draft = opaque("Draft", sizeof(lexicon::Draft), alignof(lexicon::Draft));
      const compiler::TypeId sourceBlock = opaque("SourceBlock", sizeof(SourceBlock), alignof(SourceBlock));
      types.pointerTo(sourceBlock);

      context::Config config;
      using ConfigSource = decltype(config.source);
      using ConfigSourceBuffer = decltype(config.source.buffer);
      using ConfigMemory = context::Config::Memory;
      using ConfigLexicon = decltype(config.lexicon);
      using ConfigRuntime = decltype(config.runtime);
      using ConfigWorkspace = decltype(config.workspace);
      using ConfigWorkspaceKey = decltype(config.workspace.key);
      using ConfigWorkspaceCode = decltype(config.workspace.code);
      using ConfigException = decltype(config.exception);
      const compiler::TypeId configMemory = layout("ContextMemory", sizeof(ConfigMemory), alignof(ConfigMemory),
                                                   {{"size", u64, offsetof(ConfigMemory, size)}});
      const compiler::TypeId configSourceBuffer =
          layout("ContextConfigSourceBuffer", sizeof(ConfigSourceBuffer), alignof(ConfigSourceBuffer),
                 {{"size", u64, offsetof(ConfigSourceBuffer, size)}});
      const compiler::TypeId configSource = layout("ContextConfigSource", sizeof(ConfigSource), alignof(ConfigSource),
                                                   {{"buffer", configSourceBuffer, offsetof(ConfigSource, buffer)}});
      const compiler::TypeId configLexicon =
          layout("ContextConfigLexicon", sizeof(ConfigLexicon), alignof(ConfigLexicon),
                 {{"memory", configMemory, offsetof(ConfigLexicon, memory)}});
      const compiler::TypeId configRuntime =
          layout("ContextConfigRuntime", sizeof(ConfigRuntime), alignof(ConfigRuntime),
                 {{"memory", configMemory, offsetof(ConfigRuntime, memory)}});
      const compiler::TypeId configWorkspaceKey =
          layout("ContextConfigWorkspaceKey", sizeof(ConfigWorkspaceKey), alignof(ConfigWorkspaceKey),
                 {{"memory", configMemory, offsetof(ConfigWorkspaceKey, memory)}});
      const compiler::TypeId configWorkspaceCode =
          layout("ContextConfigWorkspaceCode", sizeof(ConfigWorkspaceCode), alignof(ConfigWorkspaceCode),
                 {{"memory", configMemory, offsetof(ConfigWorkspaceCode, memory)}});
      const compiler::TypeId configWorkspace =
          layout("ContextConfigWorkspace", sizeof(ConfigWorkspace), alignof(ConfigWorkspace),
                 {{"key", configWorkspaceKey, offsetof(ConfigWorkspace, key)},
                  {"code", configWorkspaceCode, offsetof(ConfigWorkspace, code)}});
      const compiler::TypeId configException =
          layout("ContextConfigException", sizeof(ConfigException), alignof(ConfigException),
                 {{"continues", u8, offsetof(ConfigException, continues)}});
      const compiler::TypeId configType =
          layout("ContextConfig", sizeof(context::Config), alignof(context::Config),
                 {{"source", configSource, offsetof(context::Config, source)},
                  {"lexicon", configLexicon, offsetof(context::Config, lexicon)},
                  {"runtime", configRuntime, offsetof(context::Config, runtime)},
                  {"workspace", configWorkspace, offsetof(context::Config, workspace)},
                  {"exception", configException, offsetof(context::Config, exception)}});

      using Arguments = context::Exec::Args;
      const compiler::TypeId arguments = layout("ContextArguments", sizeof(Arguments), alignof(Arguments),
                                                {{"index", i32, offsetof(Arguments, index)},
                                                 {"count", i32, offsetof(Arguments, count)},
                                                 {"values", bytePointerPointer, offsetof(Arguments, ptr)},
                                                 {"options", u8, offsetof(Arguments, options)}});
      const compiler::TypeId phrasePointer = types.pointerTo(phrase);
      const compiler::TypeId execType =
          layout("ContextExec", sizeof(context::Exec), alignof(context::Exec),
                 {{"status", i32, offsetof(context::Exec, status)},
                  {"invoked", phrasePointer, offsetof(context::Exec, invoked)},
                  {"start", timePoint, offsetof(context::Exec, start)},
                  {"args", arguments, offsetof(context::Exec, args)},
                  {"pendingException", exceptionPointer, offsetof(context::Exec, pendingException)},
                  {"pendingNativeEntry", u64, offsetof(context::Exec, pendingNativeEntry)},
                  {"pendingNativeSymbol", stringType, offsetof(context::Exec, pendingNativeSymbol)}});

      context::IOStreams streams;
      const compiler::TypeId streamsType =
          layout("ContextIOStreams", sizeof(context::IOStreams), alignof(context::IOStreams),
                 {{"in", bytePointer, memberOffset(streams, streams.in)},
                  {"out", bytePointer, memberOffset(streams, streams.out)},
                  {"err", bytePointer, memberOffset(streams, streams.err)}});

      context::Source source;
      using SourceBuffer = context::Source::Buffer;
      const compiler::TypeId sourceBuffer = layout("ContextSourceBuffer", sizeof(SourceBuffer), alignof(SourceBuffer),
                                                   {{"text", stringType, offsetof(SourceBuffer, str)},
                                                    {"match", u64, offsetof(SourceBuffer, match)},
                                                    {"offset", u64, offsetof(SourceBuffer, offset)},
                                                    {"bits", u64, offsetof(SourceBuffer, bits)}});
      const compiler::TypeId sourceType = layout("ContextSource", sizeof(context::Source), alignof(context::Source),
                                                 {{"path", stringType, memberOffset(source, source.path)},
                                                  {"line", u64, memberOffset(source, source.line)},
                                                  {"position", u64, memberOffset(source, source.position)},
                                                  {"more", u8, memberOffset(source, source.more)},
                                                  {"buffer", sourceBuffer, memberOffset(source, source.buffer)}});

      context::Workspace workspace;
      const compiler::TypeId workspaceType =
          layout("ContextWorkspace", sizeof(context::Workspace), alignof(context::Workspace),
                 {{"key", appender, memberOffset(workspace, workspace.key)},
                  {"code", appender, memberOffset(workspace, workspace.code)},
                  {"readOnlyData", byteVector, memberOffset(workspace, workspace.readOnlyData)},
                  {"data", byteVector, memberOffset(workspace, workspace.data)},
                  {"bssBytes", u64, memberOffset(workspace, workspace.bssBytes)},
                  {"customSections", nativeSectionVector, memberOffset(workspace, workspace.customSections)}});

      context::Lookup lookupValue;
      const compiler::TypeId lookup =
          layout("ContextLookup", sizeof(context::Lookup), alignof(context::Lookup),
                 {{"stack", phraseVector, memberOffset(lookupValue, lookupValue.stack)},
                  {"dictionary", phrase, memberOffset(lookupValue, lookupValue.dictionary)}});
      context::Staging stagingValue;
      const compiler::TypeId staging =
          layout("ContextStaging", sizeof(context::Staging), alignof(context::Staging),
                 {{"stack", phraseVector, memberOffset(stagingValue, stagingValue.stack)},
                  {"dictionary", phrase, memberOffset(stagingValue, stagingValue.dictionary)},
                  {"phrase", draft, memberOffset(stagingValue, stagingValue.phrase)}});
      context::Reference referenceValue;
      const compiler::TypeId reference =
          layout("ContextReference", sizeof(context::Reference), alignof(context::Reference),
                 {{"dictionary", phrase, memberOffset(referenceValue, referenceValue.dictionary)}});

      context::Context value;
      const compiler::TypeId contextType = layout("Context", sizeof(context::Context), alignof(context::Context),
                                                  {{"config", configType, memberOffset(value, value.config)},
                                                   {"exec", execType, memberOffset(value, value.exec)},
                                                   {"io", streamsType, memberOffset(value, value.io)},
                                                   {"source", sourceType, memberOffset(value, value.source)},
                                                   {"lexicon", lexicon, memberOffset(value, value.lexicon)},
                                                   {"runtime", runtime, memberOffset(value, value.runtime)},
                                                   {"workspace", workspaceType, memberOffset(value, value.workspace)},
                                                   {"lookup", lookup, memberOffset(value, value.lookup)},
                                                   {"staging", staging, memberOffset(value, value.staging)},
                                                   {"reference", reference, memberOffset(value, value.reference)}});
      types.pointerTo(contextType);
    }
  } // namespace

  void Language::setup(context::Context &context) {
    // clang-format off
    lexicon::Phrase root = context::Lookup::current(context);
    lexicon::Phrase undefined(root.getLexicon());

    register_language_actions(context);
    Debugger::registerActions(context);
    Engine::registerActions(context);
    setup_phrase_types(context, root);
    context.actions().typePhrases();
    compiler::LanguageState::setup(root);
    setupContextTypes(context);
    ContextApi::setup(context);
    TypeSyntax::setup(context);
    Typed::setup(context);
    Expressions::setup(context);
    ControlFlow::setup(context);
    Functions::setup(context);
    PhraseDefinition::setup(context);
    lexicon::Phrase phrase = root;

    WHITESPACES(action_ignore);

    PHRASE("exit", action_exit);
    PHRASE("continue", action_continue);
    PHRASE("include", Engine::includeSource);

    PHRASE("//", context::Lookup::enter, .setSuccessor(PARENT), {
      PHRASE("", action_progress_byte);
      PHRASE("\\\n", action_ignore);
      PHRASE("\n", context::Lookup::leave);
    });

    PHRASE("/*", context::Lookup::enter, .setSuccessor(PARENT), {
      PHRASE("", action_progress_byte);
      PHRASE("\\*", action_ignore);
      PHRASE("*/", context::Lookup::leave);
    });

    lexicon::Phrase debug = PHRASE("debug", context::Lookup::enter, , { WHITESPACES(action_ignore) PHRASE(":", action_ignore);
      PHRASE("ping", action_ping, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("stats", action_debug_stats, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("trace", Debugger::trace, .setType(lexicon::phrase::type::getScopedCallable(PARENT)), {
        PHRASE("on", nullptr, .setPrototype(LanguageGrammar::ensureMarker(root, "on"))).store(std::uint8_t{1});
        PHRASE("off", nullptr, .setPrototype(LanguageGrammar::ensureMarker(root, "off"))).store(std::uint8_t{0});
      });
      PHRASE("run", Debugger::run, .setType(lexicon::phrase::type::getCallable(PARENT)));
      PHRASE("continue", Debugger::resume, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("step", Debugger::step, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("next", Debugger::next, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("finish", Debugger::finish, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("where", Debugger::where, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("eval", Debugger::evaluate, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("locals", Debugger::locals, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("registers", Debugger::registers, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("delete", Debugger::deleteBreakpoint, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("breakpoints", Debugger::listBreakpoints,
             .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      PHRASE("break", context::Lookup::enter, , { WHITESPACES(action_ignore) PHRASE(":", action_ignore);
        PHRASE("phrase", Debugger::breakPhrase, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
        PHRASE("line", Debugger::breakLine, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
        PHRASE("function", Debugger::breakFunction, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      });
      PHRASE("executable", context::Lookup::enter, , { WHITESPACES(action_ignore) PHRASE(":", action_ignore);
        PHRASE("run", Debugger::runExecutable, .setType(lexicon::phrase::type::getCallable(PARENT)));
      });
      PHRASE("dictionary", context::Lookup::enter, , { WHITESPACES(action_ignore) PHRASE(":", action_ignore);
        PHRASE("dump", action_debug_dictionary_dump, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      });
      PHRASE("workspace", context::Lookup::enter, , { WHITESPACES(action_ignore) PHRASE(":", action_ignore);
        PHRASE("print", action_debug_workspace_print, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      });
    });
    Debugger::setup(context, debug);

    PHRASE("engine", context::Lookup::enter, , { WHITESPACES(action_ignore) PHRASE(":", action_ignore);
      PHRASE("export", Engine::exportImage, .setType(lexicon::phrase::type::getScopedCallable(PARENT)));
      // Restoring an engine replaces the lookup lexicon, so there must be no
      // scoped-callable epilogue that touches the old invoked phrase.
      PHRASE("import", Engine::importImage, .setType(lexicon::phrase::type::getCallable(PARENT)));
      PHRASE("define", Engine::define, .setType(lexicon::phrase::type::getCallable(PARENT)));
    });

    lexicon::Phrase emit = PHRASE("emit", context::Lookup::enter, , {
      WHITESPACES(action_ignore)
      PHRASE("object", Assembler::outputBegin, , {
        WHITESPACES(action_ignore)
        PHRASE("\"", context::Lookup::enter, , {
          PHRASE("", action_pass_byte);
          PHRASE("\\", action_pass_byte);
          PHRASE("\\r", action_pass_carriage_return);
          PHRASE("\\n", action_pass_line_feed);
          PHRASE("\\t", action_pass_horizontal_tab);
          PHRASE("\\v", action_pass_vertical_tab);
          PHRASE("\"", Assembler::objectEnd);
        });
      });
      PHRASE("executable", Assembler::outputBegin, , {
        WHITESPACES(action_ignore)
        PHRASE("\"", context::Lookup::enter, , {
          PHRASE("", action_pass_byte);
          PHRASE("\\", action_pass_byte);
          PHRASE("\\r", action_pass_carriage_return);
          PHRASE("\\n", action_pass_line_feed);
          PHRASE("\\t", action_pass_horizontal_tab);
          PHRASE("\\v", action_pass_vertical_tab);
          PHRASE("\"", Assembler::executableEnd);
        });
      });
      PHRASE("raw", Assembler::outputBegin, , {
        WHITESPACES(action_ignore)
        PHRASE("\"", context::Lookup::enter, , {
          PHRASE("", action_pass_byte);
          PHRASE("\\", action_pass_byte);
          PHRASE("\\r", action_pass_carriage_return);
          PHRASE("\\n", action_pass_line_feed);
          PHRASE("\\t", action_pass_horizontal_tab);
          PHRASE("\\v", action_pass_vertical_tab);
          PHRASE("\"", Assembler::rawEnd);
        });
      });
    });
    compiler::LanguageState::bind(emit);

    // The language-level invoke is the canonical compiler phrase. Specialized
    // syntaxes, including asm, inherit its action through a prototype.
    lexicon::Phrase invoke = PHRASE("invoke", Assembler::invoke);
    compiler::LanguageState::bind(invoke);

    lexicon::Phrase let = PHRASE("let", action_let_enter, , {
      PHRASE("=", action_let_equals, , {
        WHITESPACES(action_ignore)

        lexicon::Phrase let_commit = PHRASE("", context::Lookup::enter, , {
          PHRASE("", action_anonymous_let_commit);
        });

        PHRASE("", context::Lookup::enter, .setPrototype(root).setSuccessor(let_commit));
      });
    });
    compiler::LanguageState::bind(let);
    PHRASE("lexicon", action_lexicon);
    PHRASE("merge", action_merge);
    PHRASE("phrase", PhraseDefinition::define);
    // `struct` deliberately reuses the ordinary phrase-definition parser.
    // Its fields and methods are a subdictionary, while `<Template>` creates
    // an instance through the normal prototype chain. Repeating references
    // gives pointer-like indirection without a second object model.
    PHRASE("struct", let);

    PHRASE("<", action_reference_enter, , {
      WHITESPACES(action_ignore);

      lexicon::Phrase colon = PHRASE(":", action_reference_colon, .setSuccessor(PARENT));

      lexicon::Phrase apostrophe = PHRASE("'", context::Lookup::enter, .setSuccessor(PARENT), {
        PHRASE("", action_pass_byte);

        PHRASE("${", NameInterpolation::append);

        PHRASE("\\", action_pass_byte);

        PHRASE("\\r", action_pass_carriage_return);
        PHRASE("\\n", action_pass_line_feed);
        PHRASE("\\t", action_pass_horizontal_tab);
        PHRASE("\\v", action_pass_vertical_tab);

        PHRASE("'", context::Lookup::leave);
      });

      lexicon::Phrase quotation = PHRASE("\"", context::Lookup::enter, .setSuccessor(PARENT), {
        PHRASE("", action_pass_byte);

        PHRASE("${", NameInterpolation::append);

        PHRASE("\\", action_pass_byte);

        PHRASE("\\r", action_pass_carriage_return);
        PHRASE("\\n", action_pass_line_feed);
        PHRASE("\\t", action_pass_horizontal_tab);
        PHRASE("\\v", action_pass_vertical_tab);

        PHRASE("\"", context::Lookup::leave);
      });

      PHRASE("", context::Lookup::enter, .setSuccessor(PARENT), {
        WHITESPACES(action_reference_whitespaces);

        PHRASE("", action_pass_byte);

        PHRASE("${", NameInterpolation::append);

        PHRASE("\\", action_pass_byte);

        PHRASE(">", action_reference_commit);
        PHRASE(":", colon, .setSuccessor(undefined));
        PHRASE("\"", quotation, .setSuccessor(undefined));
        PHRASE("'", apostrophe, .setSuccessor(undefined));
        PHRASE("\\r", action_pass_carriage_return);
        PHRASE("\\n", action_pass_line_feed);
        PHRASE("\\t", action_pass_horizontal_tab);
        PHRASE("\\v", action_pass_vertical_tab);
      });
    });

    PHRASE("[", action_dictionary_enter, , {
      WHITESPACES(action_ignore);

      lexicon::Phrase apostrophe = PHRASE("'", context::Lookup::enter, .setSuccessor(PARENT), {
        PHRASE("", action_pass_byte);

        PHRASE("${", NameInterpolation::append);

        PHRASE("\\", action_pass_byte);

        PHRASE("\\r", action_pass_carriage_return);
        PHRASE("\\n", action_pass_line_feed);
        PHRASE("\\t", action_pass_horizontal_tab);
        PHRASE("\\v", action_pass_vertical_tab);

        PHRASE("'", context::Lookup::leave);
      });

      lexicon::Phrase quotation = PHRASE("\"", context::Lookup::enter, .setSuccessor(PARENT), {
        PHRASE("", action_pass_byte);

        PHRASE("${", NameInterpolation::append);

        PHRASE("\\", action_pass_byte);

        PHRASE("\\r", action_pass_carriage_return);
        PHRASE("\\n", action_pass_line_feed);
        PHRASE("\\t", action_pass_horizontal_tab);
        PHRASE("\\v", action_pass_vertical_tab);

        PHRASE("\"", context::Lookup::leave);
      });

      PHRASE("", context::Lookup::enter, .setSuccessor(PARENT), {
          WHITESPACES(action_dictionary_whitespaces);

          // A merge is a dictionary operation, not a key/value entry. It is
          // deliberately registered in the same grammar so the target is the
          // dictionary currently being staged.
          PHRASE("merge", action_merge);
          PHRASE("", action_pass_byte);
          PHRASE("${", NameInterpolation::append);
          PHRASE("\\", action_pass_byte);

          PHRASE("=", action_dictionary_equals, , {
            WHITESPACES(action_ignore)

            lexicon::Phrase dictionary_commit = PHRASE("", context::Lookup::enter, , {
              PHRASE("", action_dictionary_commit);
            });

            PHRASE("", context::Lookup::enter, .setPrototype(root).setSuccessor(dictionary_commit));
          });

          PHRASE("\"", quotation, .setSuccessor(undefined));
          PHRASE("'", apostrophe, .setSuccessor(undefined));
          PHRASE("\\r", action_pass_carriage_return);
          PHRASE("\\n", action_pass_line_feed);
          PHRASE("\\t", action_pass_horizontal_tab);
          PHRASE("\\v", action_pass_vertical_tab);
      });

      PHRASE("]", action_dictionary_leave);
    });

    lexicon::Phrase scopeFallback = PHRASE("\0scope-fallback", action_scope);
    PHRASE("{", Assembler::scope, .setPrototype(scopeFallback), {
      lexicon::Phrase scope = PHRASE("", context::Lookup::enter, .setPrototype(root).setSuccessor(root));
      scope.setSuccessor(scope).save();
    });

    PHRASE("hex", context::Lookup::enter, , {
      WHITESPACES(action_ignore)
      PHRASE("{", context::Lookup::enter, , {
        WHITESPACES(action_ignore)
        PHRASE("", action_hex);
        PHRASE("}", context::Lookup::leave);
      });
    });

#define ASSEMBLER_REGISTER(Key, Code, Bits, High, RequiresRex)                                                        \
  PHRASE(Key, Assembler::operand, .setPrototype(LanguageGrammar::ensureMarker(root, Key)))                           \
      .store(compiler::Assembler::Register{Code, Bits, High, RequiresRex});
#define ASSEMBLER_REGISTER_FAMILY(Code, Byte, Word, Dword, Qword)                                                     \
  ASSEMBLER_REGISTER(Byte, Code, 8, false, Code >= 4)                                                                \
  ASSEMBLER_REGISTER(Word, Code, 16, false, false)                                                                   \
  ASSEMBLER_REGISTER(Dword, Code, 32, false, false)                                                                  \
  ASSEMBLER_REGISTER(Qword, Code, 64, false, false)
#define ASSEMBLER_EXTENDED_REGISTER_FAMILY(Code, Prefix)                                                             \
  ASSEMBLER_REGISTER(Prefix "b", Code, 8, false, true)                                                              \
  ASSEMBLER_REGISTER(Prefix "w", Code, 16, false, false)                                                            \
  ASSEMBLER_REGISTER(Prefix "d", Code, 32, false, false)                                                            \
  ASSEMBLER_REGISTER(Prefix, Code, 64, false, false)
#define ASSEMBLER_REGISTERS()                                                                                         \
  ASSEMBLER_REGISTER_FAMILY(0, "al", "ax", "eax", "rax")                                                          \
  ASSEMBLER_REGISTER_FAMILY(1, "cl", "cx", "ecx", "rcx")                                                          \
  ASSEMBLER_REGISTER_FAMILY(2, "dl", "dx", "edx", "rdx")                                                          \
  ASSEMBLER_REGISTER_FAMILY(3, "bl", "bx", "ebx", "rbx")                                                          \
  ASSEMBLER_REGISTER_FAMILY(4, "spl", "sp", "esp", "rsp")                                                         \
  ASSEMBLER_REGISTER_FAMILY(5, "bpl", "bp", "ebp", "rbp")                                                         \
  ASSEMBLER_REGISTER_FAMILY(6, "sil", "si", "esi", "rsi")                                                         \
  ASSEMBLER_REGISTER_FAMILY(7, "dil", "di", "edi", "rdi")                                                         \
  ASSEMBLER_REGISTER("ah", 4, 8, true, false) ASSEMBLER_REGISTER("ch", 5, 8, true, false)                            \
  ASSEMBLER_REGISTER("dh", 6, 8, true, false) ASSEMBLER_REGISTER("bh", 7, 8, true, false)                            \
  ASSEMBLER_EXTENDED_REGISTER_FAMILY(8, "r8") ASSEMBLER_EXTENDED_REGISTER_FAMILY(9, "r9")                           \
  ASSEMBLER_EXTENDED_REGISTER_FAMILY(10, "r10") ASSEMBLER_EXTENDED_REGISTER_FAMILY(11, "r11")                       \
  ASSEMBLER_EXTENDED_REGISTER_FAMILY(12, "r12") ASSEMBLER_EXTENDED_REGISTER_FAMILY(13, "r13")                       \
  ASSEMBLER_EXTENDED_REGISTER_FAMILY(14, "r14") ASSEMBLER_EXTENDED_REGISTER_FAMILY(15, "r15")
#define ASSEMBLER_SYNTAX(Key, Action)                                                                                 \
  PHRASE(Key, Action, .setPrototype(LanguageGrammar::ensureMarker(root, Key)));
#define ASSEMBLER_MEMORY_TOKENS()                                                                                     \
  ASSEMBLER_SYNTAX("+", Assembler::operandMemoryOperator)                                                            \
  ASSEMBLER_SYNTAX("-", Assembler::operandMemoryOperator)                                                            \
  ASSEMBLER_SYNTAX("*", Assembler::operandMemoryOperator)                                                            \
  ASSEMBLER_SYNTAX("]", Assembler::operandMemoryEnd)                                                                 \
  ASSEMBLER_SYNTAX(",", Assembler::operandSeparator)
#define ASSEMBLER_SECTION_QUALIFIER(Key, Category, Value)                                                             \
  PHRASE(Key, nullptr, .setPrototype(LanguageGrammar::ensureMarker(root, Key)))                                      \
      .store(                                                                                                         \
          AssemblerSectionQualifier{AssemblerSectionQualifier::Kind::Category, static_cast<std::uint16_t>(Value)});
#define ASSEMBLER_REGISTER_INSTRUCTION(Mnemonic, Name)                                                                 \
  PHRASE(#Mnemonic, Assembler::instruction,                                                                            \
         .setPrototype(LanguageGrammar::ensureMarker(root, #Mnemonic)))                                                \
      .store(AssemblerInstruction{#Mnemonic});
    lexicon::Phrase assembler = PHRASE("asm", context::Lookup::enter, , {
      WHITESPACES(action_ignore)
      PHRASE("{", Assembler::begin, , {
        WHITESPACES(action_ignore)
        PHRASE(";", action_ignore, .setPrototype(LanguageGrammar::ensureMarker(root, ";")));
        PHRASE("//", Assembler::comment);

        PHRASE(assembler::phrases::OPERANDS, nullptr, , {
          WHITESPACES_EXCEPT_NEWLINE(Assembler::operandWhitespace)
          PHRASE("byte", Assembler::operandSize, .setPrototype(LanguageGrammar::ensureMarker(root, "byte")))
              .store(std::uint8_t{8});
          PHRASE("word", Assembler::operandSize, .setPrototype(LanguageGrammar::ensureMarker(root, "word")))
              .store(std::uint8_t{16});
          PHRASE("dword", Assembler::operandSize, .setPrototype(LanguageGrammar::ensureMarker(root, "dword")))
              .store(std::uint8_t{32});
          PHRASE("qword", Assembler::operandSize, .setPrototype(LanguageGrammar::ensureMarker(root, "qword")))
              .store(std::uint8_t{64});
          ASSEMBLER_REGISTERS()
          ASSEMBLER_SYNTAX("[", Assembler::operandMemoryBegin)
          ASSEMBLER_SYNTAX(",", Assembler::operandSeparator)
          PHRASE("//", Assembler::operandComment);
          PHRASE("", Assembler::operandDynamic);
        });

        PHRASE(assembler::phrases::OPERAND_COMPLETE, nullptr, , {
          WHITESPACES_EXCEPT_NEWLINE(Assembler::operandWhitespace)
          ASSEMBLER_SYNTAX(",", Assembler::operandSeparator)
          PHRASE("//", Assembler::operandComment);
          PHRASE("", Assembler::operandDynamic);
        });

        PHRASE(assembler::phrases::OPERAND_SIZE_WHITESPACE, nullptr, , {
          WHITESPACES_EXCEPT_NEWLINE(Assembler::operandWhitespace)
          ASSEMBLER_SYNTAX(",", Assembler::operandSeparator)
          PHRASE("//", Assembler::operandComment);
          PHRASE("", Assembler::operandDynamic);
        });

        PHRASE(assembler::phrases::OPERAND_SIZE_BRACKET, nullptr, , {
          WHITESPACES_EXCEPT_NEWLINE(Assembler::operandWhitespace)
          ASSEMBLER_SYNTAX("[", Assembler::operandMemoryBegin)
          ASSEMBLER_SYNTAX(",", Assembler::operandSeparator)
          PHRASE("//", Assembler::operandComment);
          PHRASE("", Assembler::operandDynamic);
        });

        PHRASE(assembler::phrases::MEMORY_EXPECT, nullptr, , {
          WHITESPACES_EXCEPT_NEWLINE(Assembler::operandWhitespace)
          ASSEMBLER_REGISTERS()
          ASSEMBLER_MEMORY_TOKENS()
          PHRASE("//", Assembler::operandComment);
          PHRASE("", Assembler::operandDynamic);
        });

        PHRASE(assembler::phrases::MEMORY_REGISTER, nullptr, , {
          WHITESPACES_EXCEPT_NEWLINE(Assembler::operandWhitespace)
          ASSEMBLER_MEMORY_TOKENS()
          PHRASE("//", Assembler::operandComment);
          PHRASE("", Assembler::operandDynamic);
        });

        PHRASE(assembler::phrases::MEMORY_TERM, nullptr, , {
          WHITESPACES_EXCEPT_NEWLINE(Assembler::operandWhitespace)
          ASSEMBLER_MEMORY_TOKENS()
          PHRASE("//", Assembler::operandComment);
          PHRASE("", Assembler::operandDynamic);
        });

        PHRASE(assembler::phrases::MEMORY_SCALE, nullptr, , {
          WHITESPACES_EXCEPT_NEWLINE(Assembler::operandWhitespace)
          ASSEMBLER_MEMORY_TOKENS()
          PHRASE("//", Assembler::operandComment);
          PHRASE("", Assembler::operandDynamic);
        });

        ASSEMBLER_INSTRUCTIONS(ASSEMBLER_REGISTER_INSTRUCTION)
        PHRASE("invoke", invoke, .setPrototype(LanguageGrammar::ensureMarker(root, "invoke")));
        PHRASE(".text", Assembler::section, .setPrototype(LanguageGrammar::ensureMarker(root, ".text")))
            .store(compiler::SectionKind::Text);
        PHRASE(".rodata", Assembler::section, .setPrototype(LanguageGrammar::ensureMarker(root, ".rodata")))
            .store(compiler::SectionKind::ReadOnlyData);
        PHRASE(".data", Assembler::section, .setPrototype(LanguageGrammar::ensureMarker(root, ".data")))
            .store(compiler::SectionKind::Data);
        PHRASE(".bss", Assembler::section, .setPrototype(LanguageGrammar::ensureMarker(root, ".bss")))
            .store(compiler::SectionKind::Bss);
        PHRASE(".section", Assembler::customSection,
               .setPrototype(LanguageGrammar::ensureMarker(root, ".section")), {
          ASSEMBLER_SECTION_QUALIFIER("alloc", Flag, compiler::SectionFlag::Alloc)
          ASSEMBLER_SECTION_QUALIFIER("write", Flag, compiler::SectionFlag::Write)
          ASSEMBLER_SECTION_QUALIFIER("exec", Flag, compiler::SectionFlag::Execute)
          ASSEMBLER_SECTION_QUALIFIER("merge", Flag, compiler::SectionFlag::Merge)
          ASSEMBLER_SECTION_QUALIFIER("strings", Flag, compiler::SectionFlag::Strings)
          ASSEMBLER_SECTION_QUALIFIER("tls", Flag, compiler::SectionFlag::ThreadLocal)
          ASSEMBLER_SECTION_QUALIFIER("note", Type, compiler::SectionType::Note)
          ASSEMBLER_SECTION_QUALIFIER("nobits", Type, compiler::SectionType::NoBits)
          ASSEMBLER_SECTION_QUALIFIER("dynamic", Type, compiler::SectionType::Dynamic)
          ASSEMBLER_SECTION_QUALIFIER("init-array", Type, compiler::SectionType::InitArray)
          ASSEMBLER_SECTION_QUALIFIER("fini-array", Type, compiler::SectionType::FiniArray)
          ASSEMBLER_SECTION_QUALIFIER("preinit-array", Type, compiler::SectionType::PreinitArray)
          ASSEMBLER_SECTION_QUALIFIER("align", Alignment, 0)
        });
        PHRASE("db", Assembler::bytes, .setPrototype(LanguageGrammar::ensureMarker(root, "db")))
            .store(std::uint8_t{1});
        PHRASE("dw", Assembler::bytes, .setPrototype(LanguageGrammar::ensureMarker(root, "dw")))
            .store(std::uint8_t{2});
        PHRASE("dd", Assembler::bytes, .setPrototype(LanguageGrammar::ensureMarker(root, "dd")))
            .store(std::uint8_t{4});
        PHRASE("dq", Assembler::bytes, .setPrototype(LanguageGrammar::ensureMarker(root, "dq")))
            .store(std::uint8_t{8});
        PHRASE("resb", Assembler::reserve, .setPrototype(LanguageGrammar::ensureMarker(root, "resb")));

        PHRASE("}", Assembler::end, .setPrototype(LanguageGrammar::ensureMarker(root, "}")));
        PHRASE("", Assembler::unknown);
      });
    });
    compiler::LanguageState::bind(assembler);
#undef ASSEMBLER_REGISTERS
#undef ASSEMBLER_MEMORY_TOKENS
#undef ASSEMBLER_SECTION_QUALIFIER
#undef ASSEMBLER_SYNTAX
#undef ASSEMBLER_EXTENDED_REGISTER_FAMILY
#undef ASSEMBLER_REGISTER_FAMILY
#undef ASSEMBLER_REGISTER
#undef ASSEMBLER_REGISTER_INSTRUCTION
    PHRASE("assembler", assembler);
    Functions::finalizeSyntax(context);
    // clang-format on
  }
} // namespace recurloop

#endif
