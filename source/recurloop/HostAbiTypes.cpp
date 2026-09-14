#include <recurloop/HostAbi.hpp>

#include <recurloop/BitString.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/PhraseAction.hpp>

#include <compiler/LanguageState.hpp>
#include <compiler/Module.hpp>

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <cstddef>
#include <cstdint>
#include <exception>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace recurloop {
  namespace {
    struct PhysicalLayout {
      std::size_t size = 0;
      std::size_t alignment = 1;
      std::vector<std::pair<std::string, std::size_t>> fields;
    };

    template <typename Owner, typename Member> std::size_t memberOffset(Owner &owner, Member &member) {
      return static_cast<std::size_t>(reinterpret_cast<std::byte *>(&member) - reinterpret_cast<std::byte *>(&owner));
    }

    PhysicalLayout physicalLayout(std::string_view name) {
      if (name == "CxxString") return {sizeof(std::string), alignof(std::string), {}};
      if (name == "BitString")
        return {sizeof(BitString), alignof(BitString), {{"data", offsetof(BitString, data)}, {"bits", offsetof(BitString, bits)}}};
      if (name == "PhraseAction")
        return {sizeof(PhraseAction), alignof(PhraseAction),
                {{"symbol", offsetof(PhraseAction, symbol)}, {"bytes", offsetof(PhraseAction, bytes)}}};
      if (name == "CxxByteVector")
        return {sizeof(std::vector<std::uint8_t>), alignof(std::vector<std::uint8_t>), {}};
      if (name == "CxxPhraseVector")
        return {sizeof(std::vector<lexicon::Phrase>), alignof(std::vector<lexicon::Phrase>), {}};
      if (name == "CxxNativeSectionVector")
        return {sizeof(std::vector<context::Workspace::NativeSection>), alignof(std::vector<context::Workspace::NativeSection>), {}};
      if (name == "CxxTimePoint") {
        using TimePoint = decltype(context::Context{}.exec.start);
        return {sizeof(TimePoint), alignof(TimePoint), {}};
      }
      if (name == "CxxExceptionPointer") return {sizeof(std::exception_ptr), alignof(std::exception_ptr), {}};
      if (name == "Appender") return {sizeof(Appender), alignof(Appender), {}};
      if (name == "Lexicon") return {sizeof(lexicon::Lexicon), alignof(lexicon::Lexicon), {}};
      if (name == "JitMemory") return {sizeof(JitMemory), alignof(JitMemory), {}};
      if (name == "Phrase") return {sizeof(lexicon::Phrase), alignof(lexicon::Phrase), {}};
      if (name == "Draft") return {sizeof(lexicon::Draft), alignof(lexicon::Draft), {}};
      if (name == "SourceBlock") return {sizeof(SourceBlock), alignof(SourceBlock), {}};

      using ConfigMemory = context::Config::Memory;
      if (name == "ContextMemory")
        return {sizeof(ConfigMemory), alignof(ConfigMemory), {{"size", offsetof(ConfigMemory, size)}}};

      context::Config config;
      using ConfigSource = decltype(config.source);
      using ConfigSourceBuffer = decltype(config.source.buffer);
      using ConfigLexicon = decltype(config.lexicon);
      using ConfigRuntime = decltype(config.runtime);
      using ConfigWorkspace = decltype(config.workspace);
      using ConfigWorkspaceKey = decltype(config.workspace.key);
      using ConfigWorkspaceCode = decltype(config.workspace.code);
      using ConfigException = decltype(config.exception);
      if (name == "ContextConfigSourceBuffer")
        return {sizeof(ConfigSourceBuffer), alignof(ConfigSourceBuffer), {{"size", offsetof(ConfigSourceBuffer, size)}}};
      if (name == "ContextConfigSource")
        return {sizeof(ConfigSource), alignof(ConfigSource), {{"buffer", offsetof(ConfigSource, buffer)}}};
      if (name == "ContextConfigLexicon")
        return {sizeof(ConfigLexicon), alignof(ConfigLexicon), {{"memory", offsetof(ConfigLexicon, memory)}}};
      if (name == "ContextConfigRuntime")
        return {sizeof(ConfigRuntime), alignof(ConfigRuntime), {{"memory", offsetof(ConfigRuntime, memory)}}};
      if (name == "ContextConfigWorkspaceKey")
        return {sizeof(ConfigWorkspaceKey), alignof(ConfigWorkspaceKey), {{"memory", offsetof(ConfigWorkspaceKey, memory)}}};
      if (name == "ContextConfigWorkspaceCode")
        return {sizeof(ConfigWorkspaceCode), alignof(ConfigWorkspaceCode), {{"memory", offsetof(ConfigWorkspaceCode, memory)}}};
      if (name == "ContextConfigWorkspace")
        return {sizeof(ConfigWorkspace), alignof(ConfigWorkspace),
                {{"key", offsetof(ConfigWorkspace, key)}, {"code", offsetof(ConfigWorkspace, code)}}};
      if (name == "ContextConfigException")
        return {sizeof(ConfigException), alignof(ConfigException), {{"continues", offsetof(ConfigException, continues)}}};
      if (name == "ContextConfig")
        return {sizeof(context::Config), alignof(context::Config),
                {{"source", offsetof(context::Config, source)},
                 {"lexicon", offsetof(context::Config, lexicon)},
                 {"runtime", offsetof(context::Config, runtime)},
                 {"workspace", offsetof(context::Config, workspace)},
                 {"exception", offsetof(context::Config, exception)}}};

      using Arguments = context::Exec::Args;
      if (name == "ContextArguments")
        return {sizeof(Arguments), alignof(Arguments),
                {{"index", offsetof(Arguments, index)}, {"count", offsetof(Arguments, count)},
                 {"values", offsetof(Arguments, ptr)}, {"options", offsetof(Arguments, options)}}};
      if (name == "ContextExec")
        return {sizeof(context::Exec), alignof(context::Exec),
                {{"status", offsetof(context::Exec, status)}, {"invoked", offsetof(context::Exec, invoked)},
                 {"start", offsetof(context::Exec, start)}, {"args", offsetof(context::Exec, args)},
                 {"pendingException", offsetof(context::Exec, pendingException)},
                 {"pendingNativeEntry", offsetof(context::Exec, pendingNativeEntry)},
                 {"pendingNativeSymbol", offsetof(context::Exec, pendingNativeSymbol)}}};

      context::IOStreams streams;
      if (name == "ContextIOStreams")
        return {sizeof(context::IOStreams), alignof(context::IOStreams),
                {{"in", memberOffset(streams, streams.in)}, {"out", memberOffset(streams, streams.out)},
                 {"err", memberOffset(streams, streams.err)}}};

      context::Source source;
      using SourceBuffer = context::Source::Buffer;
      if (name == "ContextSourceBuffer")
        return {sizeof(SourceBuffer), alignof(SourceBuffer),
                {{"text", offsetof(SourceBuffer, str)}, {"match", offsetof(SourceBuffer, match)},
                 {"offset", offsetof(SourceBuffer, offset)}, {"bits", offsetof(SourceBuffer, bits)}}};
      if (name == "ContextSource")
        return {sizeof(context::Source), alignof(context::Source),
                {{"path", memberOffset(source, source.path)}, {"line", memberOffset(source, source.line)},
                 {"position", memberOffset(source, source.position)}, {"more", memberOffset(source, source.more)},
                 {"buffer", memberOffset(source, source.buffer)}}};

      context::Workspace workspace;
      if (name == "ContextWorkspace")
        return {sizeof(context::Workspace), alignof(context::Workspace),
                {{"key", memberOffset(workspace, workspace.key)}, {"code", memberOffset(workspace, workspace.code)},
                 {"readOnlyData", memberOffset(workspace, workspace.readOnlyData)},
                 {"data", memberOffset(workspace, workspace.data)}, {"bssBytes", memberOffset(workspace, workspace.bssBytes)},
                 {"customSections", memberOffset(workspace, workspace.customSections)}}};

      context::Lookup lookup;
      if (name == "ContextLookup")
        return {sizeof(context::Lookup), alignof(context::Lookup),
                {{"stack", memberOffset(lookup, lookup.stack)}, {"dictionary", memberOffset(lookup, lookup.dictionary)}}};
      context::Staging staging;
      if (name == "ContextStaging")
        return {sizeof(context::Staging), alignof(context::Staging),
                {{"stack", memberOffset(staging, staging.stack)}, {"dictionary", memberOffset(staging, staging.dictionary)},
                 {"phrase", memberOffset(staging, staging.phrase)}}};
      context::Reference reference;
      if (name == "ContextReference")
        return {sizeof(context::Reference), alignof(context::Reference),
                {{"dictionary", memberOffset(reference, reference.dictionary)}}};

      context::Context value;
      if (name == "Context")
        return {sizeof(context::Context), alignof(context::Context),
                {{"config", memberOffset(value, value.config)}, {"exec", memberOffset(value, value.exec)},
                 {"io", memberOffset(value, value.io)}, {"source", memberOffset(value, value.source)},
                 {"lexicon", memberOffset(value, value.lexicon)}, {"runtime", memberOffset(value, value.runtime)},
                 {"workspace", memberOffset(value, value.workspace)}, {"lookup", memberOffset(value, value.lookup)},
                 {"staging", memberOffset(value, value.staging)}, {"reference", memberOffset(value, value.reference)}}};

      THROW(, "unknown Host ABI compiler type '" << name << "'")
    }

    compiler::TypeId defineOpaque(context::Context &context, std::string_view name) {
      const PhysicalLayout layout = physicalLayout(name);
      if (!layout.fields.empty()) THROW(, "Host ABI type '" << name << "' is not opaque")
      return context.language().types.defineStructureLayout(std::string(name), layout.size, layout.alignment);
    }

    compiler::TypeId defineStructure(context::Context &context, std::string_view name,
                                     std::span<const compiler::FieldDeclaration> fields) {
      const PhysicalLayout layout = physicalLayout(name);
      if (layout.fields.size() != fields.size()) THROW(, "Host ABI field count mismatch for '" << name << "'")
      std::vector<compiler::TypeField> materialized;
      materialized.reserve(fields.size());
      for (std::size_t i = 0; i < fields.size(); ++i) {
        if (layout.fields[i].first != fields[i].name)
          THROW(, "Host ABI field mismatch for '" << name << "': expected '" << layout.fields[i].first
                                                    << "', source declared '" << fields[i].name << "'")
        materialized.push_back({fields[i].name, fields[i].type, layout.fields[i].second});
      }
      return context.language().types.defineStructureLayout(std::string(name), layout.size, layout.alignment, materialized);
    }
  } // namespace

  compiler::TypeId HostAbi::defineOpaqueCompilerType(context::Context &context, std::string_view name) {
    return defineOpaque(context, name);
  }

  compiler::TypeId HostAbi::defineStructureCompilerType(context::Context &context, std::string_view name,
                                                        std::span<const compiler::FieldDeclaration> fields) {
    return defineStructure(context, name, fields);
  }

  void HostAbi::setupCompilerTypes(context::Context &context) {
    compiler::LanguageState language = context.language();
    compiler::TypeRegistry &types = language.types;
    const auto id = [&](std::string_view name) {
      const compiler::TypeId result = types.find(name);
      if (result == compiler::InvalidType) THROW(, "bootstrap Host ABI requires compiler type '" << name << "'")
      return result;
    };
    const auto opaque = [&](std::string_view name) { return defineOpaque(context, name); };
    const auto structure = [&](std::string_view name, std::initializer_list<compiler::FieldDeclaration> fields) {
      return defineStructure(context, name, fields);
    };

    const compiler::TypeId u8 = id("u8");
    const compiler::TypeId i32 = id("i32");
    const compiler::TypeId u64 = id("u64");
    const compiler::TypeId bytePointer = types.pointerTo(u8);
    const compiler::TypeId bytePointerPointer = types.pointerTo(bytePointer);

    const compiler::TypeId stringType = opaque("CxxString");
    const compiler::TypeId bitString = structure("BitString", {{"data", bytePointer}, {"bits", u64}});
    types.pointerTo(bitString);
    const compiler::TypeId phraseAction = structure("PhraseAction", {{"symbol", bytePointer}, {"bytes", u64}});
    types.pointerTo(phraseAction);
    const compiler::TypeId byteVector = opaque("CxxByteVector");
    const compiler::TypeId phraseVector = opaque("CxxPhraseVector");
    const compiler::TypeId nativeSectionVector = opaque("CxxNativeSectionVector");
    const compiler::TypeId timePoint = opaque("CxxTimePoint");
    const compiler::TypeId exceptionPointer = opaque("CxxExceptionPointer");
    const compiler::TypeId appender = opaque("Appender");
    const compiler::TypeId lexicon = opaque("Lexicon");
    const compiler::TypeId runtime = opaque("JitMemory");
    const compiler::TypeId phrase = opaque("Phrase");
    const compiler::TypeId draft = opaque("Draft");
    const compiler::TypeId sourceBlock = opaque("SourceBlock");
    types.pointerTo(sourceBlock);

    const compiler::TypeId configMemory = structure("ContextMemory", {{"size", u64}});
    const compiler::TypeId configSourceBuffer = structure("ContextConfigSourceBuffer", {{"size", u64}});
    const compiler::TypeId configSource = structure("ContextConfigSource", {{"buffer", configSourceBuffer}});
    const compiler::TypeId configLexicon = structure("ContextConfigLexicon", {{"memory", configMemory}});
    const compiler::TypeId configRuntime = structure("ContextConfigRuntime", {{"memory", configMemory}});
    const compiler::TypeId configWorkspaceKey = structure("ContextConfigWorkspaceKey", {{"memory", configMemory}});
    const compiler::TypeId configWorkspaceCode = structure("ContextConfigWorkspaceCode", {{"memory", configMemory}});
    const compiler::TypeId configWorkspace = structure(
        "ContextConfigWorkspace", {{"key", configWorkspaceKey}, {"code", configWorkspaceCode}});
    const compiler::TypeId configException = structure("ContextConfigException", {{"continues", u8}});
    const compiler::TypeId configType = structure(
        "ContextConfig", {{"source", configSource}, {"lexicon", configLexicon}, {"runtime", configRuntime},
                          {"workspace", configWorkspace}, {"exception", configException}});

    const compiler::TypeId arguments = structure(
        "ContextArguments", {{"index", i32}, {"count", i32}, {"values", bytePointerPointer}, {"options", u8}});
    const compiler::TypeId phrasePointer = types.pointerTo(phrase);
    const compiler::TypeId execType = structure(
        "ContextExec", {{"status", i32}, {"invoked", phrasePointer}, {"start", timePoint}, {"args", arguments},
                        {"pendingException", exceptionPointer}, {"pendingNativeEntry", u64},
                        {"pendingNativeSymbol", stringType}});
    const compiler::TypeId streamsType =
        structure("ContextIOStreams", {{"in", bytePointer}, {"out", bytePointer}, {"err", bytePointer}});
    const compiler::TypeId sourceBuffer = structure(
        "ContextSourceBuffer", {{"text", stringType}, {"match", u64}, {"offset", u64}, {"bits", u64}});
    const compiler::TypeId sourceType = structure(
        "ContextSource", {{"path", stringType}, {"line", u64}, {"position", u64}, {"more", u8},
                          {"buffer", sourceBuffer}});
    const compiler::TypeId workspaceType = structure(
        "ContextWorkspace", {{"key", appender}, {"code", appender}, {"readOnlyData", byteVector},
                             {"data", byteVector}, {"bssBytes", u64}, {"customSections", nativeSectionVector}});
    const compiler::TypeId lookup = structure("ContextLookup", {{"stack", phraseVector}, {"dictionary", phrase}});
    const compiler::TypeId staging =
        structure("ContextStaging", {{"stack", phraseVector}, {"dictionary", phrase}, {"phrase", draft}});
    const compiler::TypeId reference = structure("ContextReference", {{"dictionary", phrase}});
    const compiler::TypeId contextType = structure(
        "Context", {{"config", configType}, {"exec", execType}, {"io", streamsType}, {"source", sourceType},
                    {"lexicon", lexicon}, {"runtime", runtime}, {"workspace", workspaceType}, {"lookup", lookup},
                    {"staging", staging}, {"reference", reference}});
    types.pointerTo(contextType);
  }
} // namespace recurloop
