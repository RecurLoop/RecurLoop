#include "CoreDefinition.hpp"
#include "LanguageInternal.hpp"

#include <recurloop/Assembler.hpp>
#include <recurloop/ContextApi.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/HostAbi.hpp>

#include <compiler/Assembler.hpp>
#include <compiler/LanguageState.hpp>
#include <compiler/RegistrySchema.hpp>
#include <compiler/Module.hpp>

#include <context/Lookup.hpp>
#include <context/Reference.hpp>
#include <context/Staging.hpp>
#include <context/Values.hpp>
#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cctype>
#include <charconv>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace recurloop::internal {
  namespace {
    struct Payload {
      std::string kind;
      std::vector<std::string> args;
    };

    struct PhraseSpec {
      std::string label;
      std::string key;
      std::string parent;
      std::size_t bits = 0;
      bool explicitBits = false;
      bool dictionary = false;
      bool permanent = false;
      bool rewritable = false;
      bool hasPrototype = false;
      bool hasType = false;
      bool hasAction = false;
      bool hasSuccessor = false;
      std::string prototype;
      std::string type;
      std::string action;
      std::string successor;
      Payload payload;
    };

    struct TypeSpec {
      std::string name;
      std::string kind;
      std::vector<std::string> args;
    };

    struct FunctionSpec {
      std::string name;
      std::string symbol;
      std::vector<std::string> parameters;
      std::string result;
      std::string abi;
      bool imported = false;
    };

    struct RegistrySpec {
      compiler::RegistryRole role;
      std::string key;
    };

    struct SlotSpec {
      compiler::SlotRole role;
      std::string key;
      std::optional<std::uint64_t> initial;
    };

    struct AbiKindSpec {
      compiler::TypeKind typeKind;
      compiler::ValueKind valueKind;
    };

    struct CompilerSpec {
      std::optional<std::string> languageKey;
      std::vector<RegistrySpec> registries;
      std::vector<SlotSpec> slots;
      std::vector<AbiKindSpec> abiKinds;
      std::vector<std::string> abis;
      std::vector<TypeSpec> types;
      std::vector<FunctionSpec> functions;
      std::vector<std::string> linkerPaths;
    };

    struct Definition {
      std::vector<PhraseSpec> phrases;
      CompilerSpec compiler;
    };

    std::string trim(std::string value) {
      const auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char c) { return std::isspace(c); });
      const auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char c) { return std::isspace(c); }).base();
      if (first >= last) return {};
      return std::string(first, last);
    }

    unsigned nibble(char c) {
      if (c >= '0' && c <= '9') return static_cast<unsigned>(c - '0');
      if (c >= 'a' && c <= 'f') return static_cast<unsigned>(c - 'a' + 10);
      if (c >= 'A' && c <= 'F') return static_cast<unsigned>(c - 'A' + 10);
      THROW(, "core definition contains an invalid hexadecimal escape")
    }

    std::vector<std::string> tokens(std::string_view line, std::size_t lineNumber) {
      std::vector<std::string> result;
      for (std::size_t cursor = 0; cursor < line.size();) {
        while (cursor < line.size() && std::isspace(static_cast<unsigned char>(line[cursor]))) ++cursor;
        if (cursor == line.size() || line.substr(cursor).starts_with("//")) break;
        if (line[cursor] != '"') {
          const std::size_t begin = cursor;
          while (cursor < line.size() && !std::isspace(static_cast<unsigned char>(line[cursor]))) ++cursor;
          result.emplace_back(line.substr(begin, cursor - begin));
          continue;
        }
        ++cursor;
        std::string value;
        bool closed = false;
        while (cursor < line.size()) {
          char c = line[cursor++];
          if (c == '"') { closed = true; break; }
          if (c != '\\') { value.push_back(c); continue; }
          if (cursor == line.size()) THROW(, "core definition line " << lineNumber << ": unterminated escape")
          c = line[cursor++];
          switch (c) {
          case '\\': value.push_back('\\'); break;
          case '"': value.push_back('"'); break;
          case 'n': value.push_back('\n'); break;
          case 'r': value.push_back('\r'); break;
          case 't': value.push_back('\t'); break;
          case '0': value.push_back('\0'); break;
          case 'x':
            if (cursor + 2 > line.size()) THROW(, "core definition line " << lineNumber << ": truncated hex escape")
            value.push_back(static_cast<char>((nibble(line[cursor]) << 4) | nibble(line[cursor + 1])));
            cursor += 2;
            break;
          default: THROW(, "core definition line " << lineNumber << ": unknown escape")
          }
        }
        if (!closed) THROW(, "core definition line " << lineNumber << ": unterminated string")
        result.push_back(std::move(value));
      }
      return result;
    }

    std::uint64_t integer(std::string_view text, std::size_t line) {
      std::uint64_t value = 0;
      const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value);
      if (error != std::errc() || end != text.data() + text.size())
        THROW(, "core definition line " << line << ": invalid integer '" << text << "'")
      return value;
    }

    bool boolean(std::string_view text, std::size_t line) {
      if (text == "true") return true;
      if (text == "false") return false;
      THROW(, "core definition line " << line << ": expected true or false")
    }

    std::string readFile(const std::filesystem::path &path) {
      std::ifstream input(path, std::ios::binary);
      if (!input.is_open()) THROW(, "core definition cannot open include '" << path.string() << "'")
      std::string result{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
      if (input.bad()) THROW(, "core definition cannot read include '" << path.string() << "'")
      return result;
    }

    std::string expandIncludes(std::string_view source, const std::filesystem::path &base,
                               std::unordered_set<std::string> &active) {
      std::ostringstream output;
      std::istringstream input{std::string(source)};
      std::string line;
      std::size_t lineNumber = 0;
      while (std::getline(input, line)) {
        ++lineNumber;
        const std::string stripped = trim(line);
        const auto fields = tokens(stripped, lineNumber);
        if (fields.size() == 2 && fields[0] == "include") {
          std::filesystem::path path(fields[1]);
          if (path.is_relative()) path = base / path;
          path = std::filesystem::absolute(path).lexically_normal();
          const std::string key = path.string();
          if (!active.insert(key).second) THROW(, "recursive core definition include '" << key << "'")
          output << expandIncludes(readFile(path), path.parent_path(), active);
          active.erase(key);
        } else {
          output << line << '\n';
        }
      }
      return output.str();
    }

    compiler::RegistryRole registryRole(std::string_view name, std::size_t lineNumber) {
      static const std::unordered_map<std::string_view, compiler::RegistryRole> roles{
          {"calling-conventions", compiler::RegistryRole::CallingConventions},
          {"functions", compiler::RegistryRole::Functions},
          {"function-sources", compiler::RegistryRole::FunctionSources},
          {"modules", compiler::RegistryRole::Modules},
          {"settings", compiler::RegistryRole::Settings},
          {"module-selections", compiler::RegistryRole::ModuleSelections},
          {"link-objects", compiler::RegistryRole::LinkObjects},
          {"link-archives", compiler::RegistryRole::LinkArchives},
          {"link-paths", compiler::RegistryRole::LinkPaths},
          {"shared-libraries", compiler::RegistryRole::SharedLibraries},
          {"types", compiler::RegistryRole::Types},
          {"type-ids", compiler::RegistryRole::TypeIds},
          {"abi-kinds", compiler::RegistryRole::AbiKinds},
      };
      const auto found = roles.find(name);
      if (found == roles.end()) THROW(, "core definition line " << lineNumber << ": unknown compiler registry role '" << name << "'")
      return found->second;
    }

    compiler::SlotRole slotRole(std::string_view name, std::size_t lineNumber) {
      static const std::unordered_map<std::string_view, compiler::SlotRole> roles{
          {"type-next-id", compiler::SlotRole::TypeNextId},
          {"automatic-modules", compiler::SlotRole::AutomaticModules},
          {"embed-language", compiler::SlotRole::EmbedLanguage},
          {"selection-generation", compiler::SlotRole::SelectionGeneration},
          {"link-sequence", compiler::SlotRole::LinkSequence},
          {"link-generation", compiler::SlotRole::LinkGeneration},
          {"module-entry", compiler::SlotRole::ModuleEntry},
      };
      const auto found = roles.find(name);
      if (found == roles.end()) THROW(, "core definition line " << lineNumber << ": unknown compiler slot role '" << name << "'")
      return found->second;
    }

    compiler::TypeKind schemaTypeKind(std::string_view name, std::size_t lineNumber) {
      if (name == "void") return compiler::TypeKind::Void;
      if (name == "integer") return compiler::TypeKind::Integer;
      if (name == "floating") return compiler::TypeKind::FloatingPoint;
      if (name == "pointer") return compiler::TypeKind::Pointer;
      if (name == "array") return compiler::TypeKind::Array;
      if (name == "structure") return compiler::TypeKind::Structure;
      if (name == "function") return compiler::TypeKind::Function;
      THROW(, "core definition line " << lineNumber << ": unknown ABI type kind '" << name << "'")
    }

    compiler::ValueKind schemaValueKind(std::string_view name, std::size_t lineNumber) {
      if (name == "void") return compiler::ValueKind::Void;
      if (name == "integer") return compiler::ValueKind::Integer;
      if (name == "floating") return compiler::ValueKind::FloatingPoint;
      if (name == "pointer") return compiler::ValueKind::Pointer;
      if (name == "aggregate") return compiler::ValueKind::Aggregate;
      THROW(, "core definition line " << lineNumber << ": unknown ABI value kind '" << name << "'")
    }

    Definition parse(std::string_view source, std::string_view sourcePath) {
      std::filesystem::path base = std::filesystem::current_path();
      if (!sourcePath.empty() && sourcePath.front() != '<') base = std::filesystem::path(sourcePath).parent_path();
      std::unordered_set<std::string> active;
      const std::string expanded = expandIncludes(source, base, active);

      Definition result;
      PhraseSpec *phrase = nullptr;
      bool compiler = false;
      std::istringstream input(expanded);
      std::string line;
      for (std::size_t lineNumber = 1; std::getline(input, line); ++lineNumber) {
        const std::string stripped = trim(line);
        const std::vector<std::string> f = tokens(stripped, lineNumber);
        if (f.empty()) continue;

        if (phrase) {
          if (f.size() == 1 && f[0] == "}") { phrase = nullptr; continue; }
          if (f[0] == "bits" && f.size() == 2) { phrase->bits = integer(f[1], lineNumber); phrase->explicitBits = true; continue; }
          if (f[0] == "dictionary" && f.size() == 1) { phrase->dictionary = true; continue; }
          if (f[0] == "permanent" && f.size() == 1) { phrase->permanent = true; continue; }
          if (f[0] == "rewritable" && f.size() == 1) { phrase->rewritable = true; continue; }
          if (f[0] == "prototype" && f.size() == 2) { phrase->hasPrototype = true; phrase->prototype = f[1]; continue; }
          if (f[0] == "type" && f.size() == 2) { phrase->hasType = true; phrase->type = f[1]; continue; }
          if (f[0] == "successor" && f.size() == 2) { phrase->hasSuccessor = true; phrase->successor = f[1]; continue; }
          if (f[0] == "action" && f.size() == 3 && f[1] == "host") { phrase->hasAction = true; phrase->action = f[2]; continue; }
          static const std::unordered_set<std::string> payloads{
              "language", "phrase-type", "operator", "intrinsic-behavior", "assignment", "intrinsic",
              "variable", "character", "abi-cleanup", "abi-stack", "section", "byte-width", "operand-size",
              "boolean", "u8", "register", "section-flag", "section-type", "section-alignment", "instruction"};
          if (payloads.contains(f[0])) { phrase->payload.kind = f[0]; phrase->payload.args.assign(f.begin() + 1, f.end()); continue; }
          THROW(, "core definition line " << lineNumber << ": unknown phrase property '" << f[0] << "'")
        }

        if (compiler) {
          if (f.size() == 1 && f[0] == "}") { compiler = false; continue; }
          if (f[0] == "language-root" && f.size() == 2) {
            if (result.compiler.languageKey) THROW(, "core definition line " << lineNumber << ": duplicate compiler language root")
            result.compiler.languageKey = f[1];
            continue;
          }
          if (f[0] == "registry" && f.size() == 3) {
            result.compiler.registries.push_back({registryRole(f[1], lineNumber), f[2]});
            continue;
          }
          if (f[0] == "slot" && (f.size() == 3 || f.size() == 4)) {
            SlotSpec slot{slotRole(f[1], lineNumber), f[2], std::nullopt};
            if (f.size() == 4) {
              if (f[3] == "true" || f[3] == "false") slot.initial = boolean(f[3], lineNumber) ? 1 : 0;
              else slot.initial = integer(f[3], lineNumber);
            }
            result.compiler.slots.push_back(std::move(slot));
            continue;
          }
          if (f[0] == "abi-kind" && f.size() == 3) {
            result.compiler.abiKinds.push_back({schemaTypeKind(f[1], lineNumber), schemaValueKind(f[2], lineNumber)});
            continue;
          }
          if (f[0] == "abi" && f.size() == 2) { result.compiler.abis.push_back(f[1]); continue; }
          if (f[0] == "type" && f.size() >= 3) {
            TypeSpec type{f[1], f[2], {}};
            type.args.assign(f.begin() + 3, f.end());
            result.compiler.types.push_back(std::move(type));
            continue;
          }
          if (f[0] == "extern") {
            FunctionSpec fn;
            if (f.size() < 11 || f[2] != "symbol" || f[4] != "params" || f[5] != "[")
              THROW(, "core definition line " << lineNumber << ": malformed extern declaration")
            fn.name = f[1]; fn.symbol = f[3];
            std::size_t i = 6;
            while (i < f.size() && f[i] != "]") fn.parameters.push_back(f[i++]);
            if (i >= f.size() || ++i >= f.size() || f[i++] != "result" || i >= f.size())
              THROW(, "core definition line " << lineNumber << ": malformed extern result")
            fn.result = f[i++];
            if (i >= f.size() || f[i++] != "abi" || i >= f.size()) THROW(, "core definition line " << lineNumber << ": missing extern ABI")
            fn.abi = f[i++];
            if (i < f.size() && f[i] == "imported") { fn.imported = true; ++i; }
            if (i != f.size()) THROW(, "core definition line " << lineNumber << ": trailing extern fields")
            result.compiler.functions.push_back(std::move(fn));
            continue;
          }
          if (f[0] == "linker-path" && f.size() == 2) { result.compiler.linkerPaths.push_back(f[1]); continue; }
          THROW(, "core definition line " << lineNumber << ": unknown compiler declaration '" << f[0] << "'")
        }

        if (f[0] == "phrase") {
          if (f.size() != 7 || f[2] != "=" || f[4] != "in" || f[6] != "{")
            THROW(, "core definition line " << lineNumber << ": malformed phrase declaration")
          result.phrases.push_back(PhraseSpec{f[1], f[3], f[5]});
          phrase = &result.phrases.back();
          phrase->bits = phrase->key.size() * 8;
          continue;
        }
        if (f.size() == 2 && f[0] == "compiler" && f[1] == "{") { compiler = true; continue; }
        THROW(, "core definition line " << lineNumber << ": expected phrase or compiler block")
      }
      if (phrase || compiler) THROW(, "core definition contains an unterminated block")
      return result;
    }

    lexicon::Phrase exact(lexicon::Phrase parent, std::string_view key) {
      lexicon::Match match = parent.matchExact(Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length,
          [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); });
      return match.isNull() ? lexicon::Phrase(parent.getLexicon()) : match.getPhrase();
    }

    compiler::CallingConvention compilerConvention(std::string_view name) {
      if (name == "sysv-amd64") return compiler::CallingConvention::systemVAMD64();
      if (name == "microsoft-x64") return compiler::CallingConvention::microsoftX64();
      if (name == "cdecl-x86") return compiler::CallingConvention::cdeclX86();
      if (name == "stdcall-x86") return compiler::CallingConvention::stdcallX86();
      if (name == "fastcall-x86") return compiler::CallingConvention::fastcallX86();
      THROW(, "source core declares unsupported ABI convention '" << name << "'")
    }

    compiler::TypeId requireType(compiler::TypeRegistry &types, std::string_view name) {
      const compiler::TypeId result = types.find(name);
      if (result == compiler::InvalidType) THROW(, "source core references unknown compiler type '" << name << "'")
      return result;
    }

    compiler::TypeId materializeFunctionType(compiler::TypeRegistry &types, std::string_view name) {
      if (!name.starts_with("fn(")) THROW(, "malformed source-core function type '" << name << "'")
      const std::size_t close = name.find(")->", 3);
      if (close == std::string_view::npos) THROW(, "malformed source-core function type '" << name << "'")
      const std::size_t abiMarker = name.find(" abi ", close + 3);
      if (abiMarker == std::string_view::npos) THROW(, "source-core function type is missing ABI '" << name << "'")

      std::vector<compiler::TypeId> parameters;
      bool variadic = false;
      const std::string_view parameterText = name.substr(3, close - 3);
      for (std::size_t begin = 0; begin < parameterText.size();) {
        const std::size_t comma = parameterText.find(',', begin);
        const std::size_t end = comma == std::string_view::npos ? parameterText.size() : comma;
        const std::string_view parameter = parameterText.substr(begin, end - begin);
        if (parameter == "...") variadic = true;
        else if (!parameter.empty()) parameters.push_back(requireType(types, parameter));
        if (comma == std::string_view::npos) break;
        begin = comma + 1;
      }
      const std::string_view resultName = name.substr(close + 3, abiMarker - (close + 3));
      const std::string_view abi = name.substr(abiMarker + 5);
      const compiler::TypeId result = types.functionOf(parameters, requireType(types, resultName), abi, variadic);
      if (types.get(result).name != name) THROW(, "source-core function type canonicalization mismatch for '" << name << "'")
      return result;
    }

    std::vector<compiler::FieldDeclaration> sourceFields(compiler::TypeRegistry &types, const TypeSpec &spec) {
      if (spec.args.size() < 2 || spec.args[0] != "fields" || spec.args[1] != "[")
        THROW(, "host structure declaration malformed for '" << spec.name << "'")
      std::vector<compiler::FieldDeclaration> fields;
      std::size_t i = 2;
      while (i < spec.args.size() && spec.args[i] != "]") {
        if (i + 1 >= spec.args.size()) THROW(, "host structure field declaration malformed for '" << spec.name << "'")
        fields.push_back({spec.args[i], requireType(types, spec.args[i + 1])});
        i += 2;
      }
      if (i >= spec.args.size() || spec.args[i] != "]" || i + 1 != spec.args.size())
        THROW(, "host structure field declaration malformed for '" << spec.name << "'")
      return fields;
    }

    lexicon::Phrase materializeCompilerSchema(context::Context &context, lexicon::Phrase root,
                                                   const CompilerSpec &spec) {
      if (!spec.languageKey) THROW(, "source core compiler schema is missing language-root")

      std::unordered_set<compiler::RegistryRole> registryRoles;
      for (const RegistrySpec &entry : spec.registries)
        if (!registryRoles.insert(entry.role).second) THROW(, "source core compiler schema duplicates a registry role")
      for (compiler::RegistryRole required : {
               compiler::RegistryRole::CallingConventions, compiler::RegistryRole::Functions,
               compiler::RegistryRole::FunctionSources, compiler::RegistryRole::Modules,
               compiler::RegistryRole::Settings, compiler::RegistryRole::ModuleSelections,
               compiler::RegistryRole::LinkObjects, compiler::RegistryRole::LinkArchives,
               compiler::RegistryRole::LinkPaths, compiler::RegistryRole::SharedLibraries,
               compiler::RegistryRole::Types, compiler::RegistryRole::TypeIds,
               compiler::RegistryRole::AbiKinds})
        if (!registryRoles.contains(required)) THROW(, "source core compiler schema is missing a required registry role")

      std::unordered_set<compiler::SlotRole> slotRoles;
      for (const SlotSpec &entry : spec.slots)
        if (!slotRoles.insert(entry.role).second) THROW(, "source core compiler schema duplicates a setting slot role")
      for (compiler::SlotRole required : {
               compiler::SlotRole::TypeNextId, compiler::SlotRole::AutomaticModules,
               compiler::SlotRole::EmbedLanguage, compiler::SlotRole::SelectionGeneration,
               compiler::SlotRole::LinkSequence, compiler::SlotRole::LinkGeneration,
               compiler::SlotRole::ModuleEntry})
        if (!slotRoles.contains(required)) THROW(, "source core compiler schema is missing a required setting slot role")

      std::unordered_set<compiler::TypeKind> abiKinds;
      for (const AbiKindSpec &entry : spec.abiKinds)
        if (!abiKinds.insert(entry.typeKind).second) THROW(, "source core compiler schema duplicates an ABI-kind mapping")
      for (compiler::TypeKind required : {compiler::TypeKind::Void, compiler::TypeKind::Integer,
                                          compiler::TypeKind::FloatingPoint, compiler::TypeKind::Pointer,
                                          compiler::TypeKind::Array, compiler::TypeKind::Structure,
                                          compiler::TypeKind::Function})
        if (!abiKinds.contains(required)) THROW(, "source core compiler schema is missing an ABI-kind mapping")

      lexicon::Phrase dataType = lexicon::phrase::type::getData(root);
      lexicon::Phrase language = root.append(*spec.languageKey)
                                     .make()
                                     .enableSubdictionary()
                                     .setType(dataType)
                                     .save();
      compiler::RegistrySchema::initializeLanguage(language);

      for (const RegistrySpec &entry : spec.registries) {
        lexicon::Phrase registry = language.append(entry.key)
                                        .make()
                                        .enableSubdictionary()
                                        .setType(dataType)
                                        .save();
        compiler::RegistrySchema::bindRegistry(registry, entry.role);
      }

      lexicon::Phrase settings = compiler::RegistrySchema::registry(context.lexicon, language.getAddress(),
                                                                    compiler::RegistryRole::Settings);
      for (const SlotSpec &entry : spec.slots) {
        lexicon::Phrase slot = settings.append(entry.key).make().setType(dataType).save();
        if (entry.initial) {
          const std::uint64_t value = *entry.initial;
          compiler::RegistrySchema::bindSlot(
              slot, entry.role,
              std::span<const std::uint8_t>(reinterpret_cast<const std::uint8_t *>(&value), sizeof(value)));
        } else {
          compiler::RegistrySchema::bindSlot(slot, entry.role);
        }
      }

      lexicon::Phrase kinds = compiler::RegistrySchema::registry(context.lexicon, language.getAddress(),
                                                                 compiler::RegistryRole::AbiKinds);
      for (const AbiKindSpec &entry : spec.abiKinds) {
        kinds.append(std::string(1, static_cast<char>(entry.typeKind)))
            .make()
            .setType(dataType)
            .save()
            .store(entry.valueKind)
            .save();
      }
      return language;
    }

    void materializeCompiler(context::Context &context, const CompilerSpec &spec) {
      compiler::LanguageState language = context.language();
      for (const std::string &abi : spec.abis) language.defineConvention(compilerConvention(abi));

      for (const TypeSpec &type : spec.types) {
        compiler::TypeId created = compiler::InvalidType;
        if (type.kind == "void") {
          if (!type.args.empty()) THROW(, "void type declaration has unexpected arguments")
          created = language.types.defineVoid(type.name);
        } else if (type.kind == "integer") {
          if (type.args.size() != 2 || (type.args[0] != "signed" && type.args[0] != "unsigned"))
            THROW(, "integer type declaration malformed for '" << type.name << "'")
          created = language.types.defineInteger(type.name, static_cast<std::size_t>(std::stoull(type.args[1])),
                                                 type.args[0] == "signed");
        } else if (type.kind == "floating") {
          if (type.args.size() != 1) THROW(, "floating type declaration malformed for '" << type.name << "'")
          created = language.types.defineFloatingPoint(type.name, static_cast<std::size_t>(std::stoull(type.args[0])));
        } else if (type.kind == "pointer") {
          if (type.args.size() != 1) THROW(, "pointer type declaration malformed for '" << type.name << "'")
          created = language.types.pointerTo(requireType(language.types, type.args[0]));
        } else if (type.kind == "host-opaque") {
          if (!type.args.empty()) THROW(, "host opaque declaration has unexpected arguments for '" << type.name << "'")
          created = HostAbi::defineOpaqueCompilerType(context, type.name);
        } else if (type.kind == "host-structure") {
          const std::vector<compiler::FieldDeclaration> fields = sourceFields(language.types, type);
          created = HostAbi::defineStructureCompilerType(context, type.name, fields);
        } else if (type.kind == "function") {
          if (!type.args.empty()) THROW(, "function type declaration has unexpected arguments for '" << type.name << "'")
          created = materializeFunctionType(language.types, type.name);
        } else {
          THROW(, "unsupported source-core compiler type kind '" << type.kind << "'")
        }
        if (language.types.get(created).name != type.name)
          THROW(, "source-core compiler type name mismatch: declared '" << type.name << "', materialized '"
                                                                         << language.types.get(created).name << "'")
      }

      for (const FunctionSpec &specFunction : spec.functions) {
        compiler::TypedFunction function;
        function.name = specFunction.name;
        function.signature.symbol = specFunction.symbol;
        function.signature.convention = language.convention(specFunction.abi);
        for (const std::string &parameter : specFunction.parameters) {
          const compiler::TypeId type = requireType(language.types, parameter);
          function.parameterTypes.push_back(type);
          function.signature.parameters.push_back(language.types.abiType(type));
        }
        function.resultType = requireType(language.types, specFunction.result);
        function.signature.result = language.types.abiType(function.resultType);
        function.imported = specFunction.imported;

        const std::size_t separator = function.name.rfind(':');
        if (separator != std::string::npos && !function.parameterTypes.empty()) {
          compiler::TypeDescriptor receiver = language.types.get(function.parameterTypes.front());
          if (receiver.kind == compiler::TypeKind::Pointer) receiver = language.types.get(receiver.element);
          if (receiver.kind == compiler::TypeKind::Structure && receiver.name == function.name.substr(0, separator))
            language.types.addMethod(receiver.id, function.name.substr(separator + 1), function.signature);
        }
        language.declareFunction(std::move(function));
      }

      for (const std::string &path : spec.linkerPaths) language.addLinkSearchPath(path);

      // Native addresses are process-local and deliberately absent from the
      // image. The source declarations above must already be complete here.
      ContextApi::bind(context);
    }

    std::string typeKind(compiler::TypeKind kind) {
      switch (kind) {
      case compiler::TypeKind::Void: return "void";
      case compiler::TypeKind::Integer: return "integer";
      case compiler::TypeKind::FloatingPoint: return "floating";
      case compiler::TypeKind::Pointer: return "pointer";
      case compiler::TypeKind::Array: return "array";
      case compiler::TypeKind::Structure: return "structure";
      case compiler::TypeKind::Function: return "function";
      }
      return "unknown";
    }

    void verifyCompiler(context::Context &context, const CompilerSpec &spec) {
      compiler::LanguageState language = context.language();
      if (spec.abis.size() != 5) THROW(, "source core must declare exactly five ABI conventions")
      for (const std::string &abi : spec.abis) (void)language.convention(abi);

      const std::vector<compiler::TypeDescriptor> actualTypes = language.types.types();
      if (spec.types.size() + 1 != actualTypes.size())
        THROW(, "source core compiler type contract mismatch: expected " << spec.types.size() << ", host materialized " << (actualTypes.size() - 1))
      for (const TypeSpec &expected : spec.types) {
        const compiler::TypeDescriptor actual = language.types.get(expected.name);
        if (expected.kind == "void" && actual.kind != compiler::TypeKind::Void) THROW(, "type kind mismatch for '" << expected.name << "'")
        if (expected.kind == "integer") {
          if (actual.kind != compiler::TypeKind::Integer || expected.args.size() != 2) THROW(, "integer type mismatch for '" << expected.name << "'")
          const bool signedExpected = expected.args[0] == "signed";
          const std::size_t bits = static_cast<std::size_t>(std::stoull(expected.args[1]));
          if (actual.isSigned != signedExpected || actual.size * 8 != bits) THROW(, "integer layout mismatch for '" << expected.name << "'")
        } else if (expected.kind == "floating") {
          if (actual.kind != compiler::TypeKind::FloatingPoint || expected.args.size() != 1 || actual.size * 8 != std::stoull(expected.args[0]))
            THROW(, "floating type mismatch for '" << expected.name << "'")
        } else if (expected.kind == "pointer") {
          if (actual.kind != compiler::TypeKind::Pointer || expected.args.size() != 1 || language.types.get(actual.element).name != expected.args[0])
            THROW(, "pointer type mismatch for '" << expected.name << "'")
        } else if (expected.kind == "host-opaque") {
          if (actual.kind != compiler::TypeKind::Structure || !actual.fields.empty()) THROW(, "host opaque type mismatch for '" << expected.name << "'")
        } else if (expected.kind == "host-structure") {
          if (actual.kind != compiler::TypeKind::Structure || expected.args.size() < 2 || expected.args[0] != "fields" || expected.args[1] != "[")
            THROW(, "host structure contract malformed for '" << expected.name << "'")
          std::vector<std::pair<std::string, std::string>> fields;
          for (std::size_t i = 2; i < expected.args.size() && expected.args[i] != "]";) {
            if (i + 1 >= expected.args.size()) THROW(, "host structure field contract malformed")
            fields.emplace_back(expected.args[i], expected.args[i + 1]); i += 2;
          }
          if (fields.size() != actual.fields.size()) THROW(, "host structure field count mismatch for '" << expected.name << "'")
          for (std::size_t i = 0; i < fields.size(); ++i)
            if (actual.fields[i].name != fields[i].first || language.types.get(actual.fields[i].type).name != fields[i].second)
              THROW(, "host structure field mismatch for '" << expected.name << "'")
        } else if (expected.kind == "function") {
          if (actual.kind != compiler::TypeKind::Function) THROW(, "function type mismatch for '" << expected.name << "'")
        }
      }

      const auto actualFunctions = language.functions();
      if (actualFunctions.size() != spec.functions.size())
        THROW(, "source core host function contract mismatch: expected " << spec.functions.size() << ", host materialized " << actualFunctions.size())
      for (const FunctionSpec &expected : spec.functions) {
        bool matched = false;
        for (const compiler::TypedFunction &actual : language.findFunctions(expected.name)) {
          if (actual.signature.symbol != expected.symbol) continue;
          std::vector<std::string> parameters;
          for (compiler::TypeId type : actual.parameterTypes) parameters.push_back(language.types.get(type).name);
          if (parameters != expected.parameters || language.types.get(actual.resultType).name != expected.result ||
              actual.signature.convention.name != expected.abi || actual.imported != expected.imported)
            THROW(, "host function contract mismatch for '" << expected.symbol << "'")
          matched = true; break;
        }
        if (!matched) THROW(, "source core declares unavailable host function '" << expected.symbol << "'")
      }

      auto actualPaths = language.linkerSearchPaths();
      auto expectedPaths = spec.linkerPaths;
      std::sort(actualPaths.begin(), actualPaths.end());
      std::sort(expectedPaths.begin(), expectedPaths.end());
      if (actualPaths != expectedPaths) THROW(, "source core linker path contract mismatch")
    }

    std::uint8_t sectionTypeValue(std::string_view name) {
      if (name == "nobits") return static_cast<std::uint8_t>(compiler::SectionType::NoBits);
      if (name == "note") return static_cast<std::uint8_t>(compiler::SectionType::Note);
      if (name == "dynamic") return static_cast<std::uint8_t>(compiler::SectionType::Dynamic);
      if (name == "init-array") return static_cast<std::uint8_t>(compiler::SectionType::InitArray);
      if (name == "fini-array") return static_cast<std::uint8_t>(compiler::SectionType::FiniArray);
      if (name == "preinit-array") return static_cast<std::uint8_t>(compiler::SectionType::PreinitArray);
      THROW(, "unknown assembler section type '" << name << "'")
    }

    std::uint16_t sectionFlagValue(std::string_view name) {
      if (name == "alloc") return static_cast<std::uint16_t>(compiler::SectionFlag::Alloc);
      if (name == "write") return static_cast<std::uint16_t>(compiler::SectionFlag::Write);
      if (name == "exec") return static_cast<std::uint16_t>(compiler::SectionFlag::Execute);
      if (name == "merge") return static_cast<std::uint16_t>(compiler::SectionFlag::Merge);
      if (name == "strings") return static_cast<std::uint16_t>(compiler::SectionFlag::Strings);
      if (name == "tls") return static_cast<std::uint16_t>(compiler::SectionFlag::ThreadLocal);
      THROW(, "unknown assembler section flag '" << name << "'")
    }

    template <typename T> void storeValue(lexicon::Phrase &phrase, const T &value) { phrase.store(value); }

    void applyPayload(context::Context &context, lexicon::Phrase phrase, const PhraseSpec &spec) {
      if (spec.payload.kind.empty()) return;
      const auto &a = spec.payload.args;
      if (spec.payload.kind == "language") {
        if (a != std::vector<std::string>{"compiler"}) THROW(, "unknown language binding payload")
        compiler::LanguageState::bind(phrase); return;
      }
      if (spec.payload.kind == "phrase-type") return; // materialized by the kernel phrase-type bootstrap
      if (spec.payload.kind == "operator") {
        if (a.size() < 3 || a[1] != "precedence") THROW(, "malformed operator payload")
        ExpressionOperator value;
        value.precedence = static_cast<std::uint8_t>(std::stoul(a[2]));
        if (a.size() == 5 && a[3] == "short-circuit")
          value.flags = a[4] == "true" ? ExpressionOperator::SkipRightWhenTrue : ExpressionOperator::SkipRightWhenFalse;
        storeValue(phrase, value); return;
      }
      if (spec.payload.kind == "intrinsic-behavior") {
        if (a.size() != 2) THROW(, "malformed intrinsic behavior")
        const std::uint8_t kind = a[0] == "cast" ? 0 : a[0] == "address" ? 1 : a[0] == "dereference" ? 2 : 255;
        const std::uint8_t phase = a[1] == "infer" ? 0 : a[1] == "emit" ? 1 : a[1] == "lvalue" ? 2 : 255;
        if (kind == 255 || phase == 255) THROW(, "unknown intrinsic behavior")
        struct Behavior { std::uint8_t kind; std::uint8_t phase; } value{kind, phase};
        storeValue(phrase, value); return;
      }
      if (spec.payload.kind == "assignment") { storeValue(phrase, static_cast<std::uint8_t>(a.at(0) == "direct")); return; }
      if (spec.payload.kind == "intrinsic") {
        const std::uint8_t value = a.at(0) == "cast" ? 0 : a.at(0) == "address" ? 1 : a.at(0) == "dereference" ? 2 : 255;
        if (value == 255) THROW(, "unknown intrinsic kind")
        storeValue(phrase, value); return;
      }
      if (spec.payload.kind == "variable") { storeValue(phrase, static_cast<std::uint8_t>(a.at(0) == "mutable")); return; }
      if (spec.payload.kind == "character") {
        std::uint8_t value = a.at(0) == "newline" ? 10 : a.at(0) == "carriage-return" ? 13 : a.at(0) == "tab" ? 9 : 11;
        storeValue(phrase, value); return;
      }
      if (spec.payload.kind == "abi-cleanup") { storeValue(phrase, static_cast<std::uint8_t>(a.at(0) == "caller")); return; }
      if (spec.payload.kind == "abi-stack") { storeValue(phrase, static_cast<std::uint8_t>(a.at(0) == "down")); return; }
      if (spec.payload.kind == "section") {
        const std::uint8_t value = a.at(0) == "text" ? 0 : a.at(0) == "rodata" ? 1 : a.at(0) == "data" ? 2 : a.at(0) == "bss" ? 3 : 255;
        if (value == 255) THROW(, "unknown section kind")
        storeValue(phrase, value); return;
      }
      if (spec.payload.kind == "byte-width" || spec.payload.kind == "operand-size" || spec.payload.kind == "u8") {
        storeValue(phrase, static_cast<std::uint8_t>(std::stoul(a.at(0)))); return;
      }
      if (spec.payload.kind == "boolean") { storeValue(phrase, static_cast<std::uint8_t>(a.at(0) == "true")); return; }
      if (spec.payload.kind == "register") {
        if (a.size() != 9 || a[1] != "code" || a[3] != "bits" || a[5] != "high" || a[7] != "rex") THROW(, "malformed register payload")
        compiler::Assembler::Register value{static_cast<std::uint8_t>(std::stoul(a[2])), static_cast<std::uint8_t>(std::stoul(a[4])), a[6] == "true", a[8] == "true"};
        storeValue(phrase, value); return;
      }
      if (spec.payload.kind == "section-flag") { storeValue(phrase, AssemblerSectionQualifier{AssemblerSectionQualifier::Kind::Flag, sectionFlagValue(a.at(0))}); return; }
      if (spec.payload.kind == "section-type") { storeValue(phrase, AssemblerSectionQualifier{AssemblerSectionQualifier::Kind::Type, sectionTypeValue(a.at(0))}); return; }
      if (spec.payload.kind == "section-alignment") { storeValue(phrase, AssemblerSectionQualifier{AssemblerSectionQualifier::Kind::Alignment}); return; }
      if (spec.payload.kind == "instruction") {
        AssemblerInstruction value;
        const std::string &name = a.at(0);
        if (name.size() >= sizeof(value.mnemonic)) THROW(, "assembler instruction mnemonic too long")
        std::memcpy(value.mnemonic, name.data(), name.size());
        storeValue(phrase, value); return;
      }
      THROW(, "unsupported semantic phrase payload '" << spec.payload.kind << "'")
    }

    void verifyKernelPhrase(const PhraseSpec &spec, lexicon::Phrase phrase) {
      if (phrase.isNull() || phrase.getKey() != spec.key) THROW(, "kernel phrase contract mismatch for '" << spec.label << "'")
    }
  } // namespace

  void CoreDefinition::apply(context::Context &context, std::string_view source, std::string_view sourcePath) {
    const Definition definition = parse(source, sourcePath);
    std::unordered_map<std::string, const PhraseSpec *> specs;
    for (const PhraseSpec &spec : definition.phrases)
      if (!specs.emplace(spec.label, &spec).second) THROW(, "duplicate source-core phrase label '" << spec.label << "'")
    if (!specs.contains("root") || !specs.contains("phrase_types") || !specs.contains("phrase_types_data") ||
        !specs.contains("phrase_types_elaborate") || !specs.contains("phrase_types_callable") || !specs.contains("phrase_types_scoped_callable"))
      THROW(, "source core is missing the kernel phrase-type contract")

    const auto registeredActions = context.actions().snapshot();
    context.lexicon.clear();
    context.actions().restore(registeredActions);
    lexicon::Phrase undefined(&context.lexicon);
    const PhraseSpec &rootSpec = *specs.at("root");
    lexicon::Draft rootDraft = context.lexicon.make(rootSpec.action.empty() ? nullptr : context.actions().get(rootSpec.action));
    rootDraft.setType(undefined).setSuccessor(undefined);
    if (rootSpec.dictionary) rootDraft.enableSubdictionary();
    lexicon::Phrase root = rootDraft.save();
    root.setSuccessor(root).save();

    setup_phrase_types(context, root);
    materializeCompilerSchema(context, root, definition.compiler);
    materializeCompiler(context, definition.compiler);

    std::unordered_map<std::string, lexicon::Phrase> phrases;
    phrases.emplace("root", root);
    lexicon::Phrase phraseTypes = exact(root, "phrase-types");
    phrases.emplace("phrase_types", phraseTypes);
    phrases.emplace("phrase_types_data", exact(phraseTypes, "data"));
    phrases.emplace("phrase_types_elaborate", exact(phraseTypes, "elaborate"));
    phrases.emplace("phrase_types_callable", exact(phraseTypes, "callable"));
    phrases.emplace("phrase_types_scoped_callable", exact(phraseTypes, "scoped-callable"));
    for (const std::string &label : {"root", "phrase_types", "phrase_types_data", "phrase_types_elaborate", "phrase_types_callable", "phrase_types_scoped_callable"})
      verifyKernelPhrase(*specs.at(label), phrases.at(label));

    for (const PhraseSpec &spec : definition.phrases) {
      if (phrases.contains(spec.label)) continue;
      const auto parent = phrases.find(spec.parent);
      if (parent == phrases.end()) THROW(, "source core phrase '" << spec.label << "' references unavailable parent '" << spec.parent << "'")
      lexicon::Draft draft = parent->second.append(Byte(const_cast<char *>(spec.key.data())), 0, spec.bits).make();
      if (spec.dictionary) draft.enableSubdictionary();
      if (spec.hasPrototype) draft.setPrototype(undefined);
      if (spec.hasType) draft.setType(undefined);
      if (spec.hasAction) draft.setAction(spec.action.empty() ? nullptr : context.actions().get(spec.action));
      if (spec.hasSuccessor) draft.setSuccessor(undefined);
      lexicon::Phrase saved = draft.save();
      phrases.emplace(spec.label, saved);
      // Payloads are attached while the phrase is still the newest lexicon item.
      // This matters for LanguageBinding: a leaf can carry the binding directly
      // only before later phrases close over the allocation frontier.
      applyPayload(context, saved, spec);
    }

    const auto resolve = [&](const std::string &label) {
      if (label == "none") return undefined;
      const auto found = phrases.find(label);
      if (found == phrases.end()) THROW(, "source core references unknown phrase '" << label << "'")
      return found->second;
    };
    for (const PhraseSpec &spec : definition.phrases) {
      lexicon::Phrase phrase = phrases.at(spec.label);
      if (spec.hasPrototype) phrase.setPrototype(resolve(spec.prototype));
      if (spec.hasType) phrase.setType(resolve(spec.type));
      if (spec.hasSuccessor) phrase.setSuccessor(resolve(spec.successor));
      if (spec.rewritable) phrase.setRewritable(true);
      if (spec.permanent) phrase.setPermanent(true);
      phrase.save();
    }

    verifyCompiler(context, definition.compiler);
    context::Values::setup(root);
    context.lookup = {};
    context.staging = {};
    context.reference = {};
    context::Lookup::in(context, root);
    context::Staging::push(context, root);
    context::Reference::in(context, root);
    context.workspace.key.clear();
  }
} // namespace recurloop::internal
