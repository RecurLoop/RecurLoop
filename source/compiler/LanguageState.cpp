#include <compiler/LanguageState.hpp>

#include <compiler/ArchiveReader.hpp>
#include <compiler/ElfReader.hpp>
#include <compiler/ElfWriter.hpp>
#include <compiler/StaticLinker.hpp>

#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cstring>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <limits>
#include <span>
#include <unordered_set>

namespace compiler {
  namespace {
    constexpr std::string_view LanguageDictionaryName{"\0compiler-language", 18};
    constexpr std::string_view ConventionsName{"calling-conventions"};
    constexpr std::string_view FunctionsName{"functions"};
    constexpr std::string_view FunctionSourcesName{"function-sources"};
    constexpr std::string_view ModulesName{"modules"};
    constexpr std::string_view SettingsName{"settings"};
    constexpr std::string_view SelectionsName{"module-selections"};
    constexpr std::string_view LinkObjectsName{"link-objects"};
    constexpr std::string_view LinkArchivesName{"link-archives"};
    constexpr std::string_view LinkPathsName{"link-paths"};
    constexpr std::string_view SharedLibrariesName{"shared-libraries"};

    lexicon::Phrase exact(lexicon::Phrase dictionary, std::string_view key) {
      lexicon::Match match = dictionary.matchExact(
          Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length,
          [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); });
      return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
    }

    lexicon::Phrase dictionary(lexicon::Phrase parent, std::string_view name) {
      lexicon::Phrase found = exact(parent, name);
      if (!found.isNull()) return found;
      return parent.append(std::string(name))
          .make()
          .enableSubdictionary()
          .setType(lexicon::phrase::type::getData(parent))
          .save();
    }

    lexicon::Phrase languageRoot(lexicon::Lexicon &lexicon, Size address = 0) {
      lexicon::Phrase result =
          address == 0 ? exact(lexicon.phrase(), LanguageDictionaryName) : lexicon::Phrase(&lexicon, address).load();
      if (result.isNull()) THROW(, "compiler language phrase is not initialized")
      return result;
    }

    Language languageData(lexicon::Phrase phrase) {
      if (phrase.payloadSize() != sizeof(Language)) THROW(, "compiler language phrase has invalid metadata")
      Language result;
      phrase.fetch(0, result);
      if (result.magic != Language::Magic || result.version != Language::Version)
        THROW(, "compiler language phrase has an unsupported schema")
      return result;
    }

    lexicon::Phrase registry(lexicon::Lexicon &lexicon, std::string_view name, Size languageAddress = 0) {
      lexicon::Phrase result = exact(languageRoot(lexicon, languageAddress), name);
      if (result.isNull()) THROW(, "compiler phrase registry is not initialized: '" << name << "'")
      return result;
    }

    std::vector<std::string> keys(lexicon::Phrase registry) {
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      std::vector<std::string> result;
      for (lexicon::Dictionary cursor = registry.fore(populated); !cursor.isNull(); cursor = cursor.next(populated)) {
        lexicon::Phrase phrase = cursor.getPhrase();
        if (!phrase.isNull()) result.push_back(phrase.getKey());
      }
      return result;
    }

    class Writer {
    public:
      std::vector<std::uint8_t> bytes;

      template <typename Number> void number(Number value) {
        const std::size_t offset = bytes.size();
        bytes.resize(offset + sizeof(value));
        std::memcpy(bytes.data() + offset, &value, sizeof(value));
      }
      void boolean(bool value) {
        number<std::uint8_t>(value ? 1 : 0);
      }
      void text(std::string_view value) {
        if (value.size() > std::numeric_limits<std::uint32_t>::max()) THROW(, "compiler phrase string is too large")
        number(static_cast<std::uint32_t>(value.size()));
        bytes.insert(bytes.end(), value.begin(), value.end());
      }
      void strings(const std::vector<std::string> &values) {
        number(static_cast<std::uint32_t>(values.size()));
        for (const std::string &value : values) text(value);
      }
      void data(std::span<const std::uint8_t> value) {
        if (value.size() > std::numeric_limits<std::uint32_t>::max()) THROW(, "compiler phrase data is too large")
        number(static_cast<std::uint32_t>(value.size()));
        bytes.insert(bytes.end(), value.begin(), value.end());
      }
    };

    class Reader {
    public:
      explicit Reader(std::span<const std::uint8_t> bytes) : bytes(bytes) {}

      template <typename Number> Number number() {
        if (cursor > bytes.size() || sizeof(Number) > bytes.size() - cursor)
          THROW(, "truncated compiler phrase payload")
        Number result;
        std::memcpy(&result, bytes.data() + cursor, sizeof(result));
        cursor += sizeof(result);
        return result;
      }
      bool boolean() {
        return number<std::uint8_t>() != 0;
      }
      std::string text() {
        const std::size_t size = number<std::uint32_t>();
        if (cursor > bytes.size() || size > bytes.size() - cursor) THROW(, "truncated compiler phrase string")
        std::string result(reinterpret_cast<const char *>(bytes.data() + cursor), size);
        cursor += size;
        return result;
      }
      std::vector<std::string> strings() {
        const std::size_t count = number<std::uint32_t>();
        std::vector<std::string> result;
        result.reserve(count);
        for (std::size_t index = 0; index < count; ++index) result.push_back(text());
        return result;
      }
      std::vector<std::uint8_t> data() {
        const std::size_t size = number<std::uint32_t>();
        if (cursor > bytes.size() || size > bytes.size() - cursor) THROW(, "truncated compiler phrase data")
        std::vector<std::uint8_t> result(bytes.begin() + cursor, bytes.begin() + cursor + size);
        cursor += size;
        return result;
      }
      void finish() const {
        if (cursor != bytes.size()) THROW(, "compiler phrase contains trailing payload")
      }

    private:
      std::span<const std::uint8_t> bytes;
      std::size_t cursor = 0;
    };

    std::vector<std::uint8_t> payload(lexicon::Phrase phrase) {
      std::vector<std::uint8_t> result(phrase.payloadSize());
      if (!result.empty()) std::memcpy(result.data(), phrase.content(0, result.size()).toPtr(), result.size());
      return result;
    }

    void store(lexicon::Phrase registry, std::string_view key, std::span<const std::uint8_t> bytes) {
      lexicon::Phrase phrase =
          registry.append(std::string(key)).make().setType(lexicon::phrase::type::getData(registry)).save();
      if (!bytes.empty()) {
        Byte output = phrase.allocate(bytes.size());
        std::memcpy(output.toPtr(), bytes.data(), bytes.size());
      }
      phrase.save();
    }

    void writeValueType(Writer &writer, const ValueType &type) {
      writer.text(type.name);
      writer.number(static_cast<std::uint8_t>(type.kind));
      writer.number(type.bits);
      writer.number(type.pointerDepth);
    }

    ValueType readValueType(Reader &reader) {
      ValueType result;
      result.name = reader.text();
      result.kind = static_cast<ValueKind>(reader.number<std::uint8_t>());
      result.bits = reader.number<std::uint16_t>();
      result.pointerDepth = reader.number<std::uint16_t>();
      return result;
    }

    void writeConvention(Writer &writer, const CallingConvention &value) {
      writer.text(value.name);
      writer.strings(value.integerRegisters);
      writer.strings(value.floatingRegisters);
      writer.text(value.resultRegister);
      writer.text(value.floatingResultRegister);
      writer.number(static_cast<std::uint64_t>(value.stackAlignment));
      writer.number(static_cast<std::uint64_t>(value.shadowSpace));
      writer.boolean(value.stackGrowsDown);
      writer.boolean(value.callerCleansStack);
    }

    CallingConvention readConvention(Reader &reader) {
      CallingConvention result;
      result.name = reader.text();
      result.integerRegisters = reader.strings();
      result.floatingRegisters = reader.strings();
      result.resultRegister = reader.text();
      result.floatingResultRegister = reader.text();
      result.stackAlignment = reader.number<std::uint64_t>();
      result.shadowSpace = reader.number<std::uint64_t>();
      result.stackGrowsDown = reader.boolean();
      result.callerCleansStack = reader.boolean();
      Abi::validate(result);
      return result;
    }

    void writeSignature(Writer &writer, const FunctionSignature &signature) {
      writer.text(signature.symbol);
      writer.number(static_cast<std::uint32_t>(signature.parameters.size()));
      for (const ValueType &parameter : signature.parameters) writeValueType(writer, parameter);
      writeValueType(writer, signature.result);
      writeConvention(writer, signature.convention);
      writer.boolean(signature.variadic);
    }

    FunctionSignature readSignature(Reader &reader) {
      FunctionSignature result;
      result.symbol = reader.text();
      const std::size_t count = reader.number<std::uint32_t>();
      result.parameters.reserve(count);
      for (std::size_t index = 0; index < count; ++index) result.parameters.push_back(readValueType(reader));
      result.result = readValueType(reader);
      result.convention = readConvention(reader);
      result.variadic = reader.boolean();
      return result;
    }

    std::vector<std::uint8_t> encode(const CallingConvention &value) {
      Writer writer;
      writeConvention(writer, value);
      return writer.bytes;
    }

    CallingConvention decodeConvention(lexicon::Phrase phrase) {
      const std::vector<std::uint8_t> bytes = payload(phrase);
      Reader reader(bytes);
      CallingConvention result = readConvention(reader);
      reader.finish();
      return result;
    }

    std::vector<std::uint8_t> encode(const TypedFunction &function) {
      Writer writer;
      writer.text(function.name);
      writeSignature(writer, function.signature);
      writer.number(static_cast<std::uint32_t>(function.parameterTypes.size()));
      for (TypeId type : function.parameterTypes) writer.number(type);
      writer.number(function.resultType);
      writer.boolean(function.imported);
      return writer.bytes;
    }

    TypedFunction decodeFunction(lexicon::Phrase phrase) {
      const std::vector<std::uint8_t> bytes = payload(phrase);
      Reader reader(bytes);
      TypedFunction result;
      result.name = reader.text();
      result.signature = readSignature(reader);
      const std::size_t count = reader.number<std::uint32_t>();
      result.parameterTypes.reserve(count);
      for (std::size_t index = 0; index < count; ++index) result.parameterTypes.push_back(reader.number<TypeId>());
      result.resultType = reader.number<TypeId>();
      result.imported = reader.boolean();
      reader.finish();
      return result;
    }

    std::uint64_t setting(lexicon::Lexicon &lexicon, Size languageAddress, std::string_view name,
                          std::uint64_t fallback) {
      lexicon::Phrase phrase = exact(registry(lexicon, SettingsName, languageAddress), name);
      if (phrase.isNull()) return fallback;
      if (phrase.payloadSize() != sizeof(std::uint64_t)) THROW(, "invalid compiler setting phrase")
      std::uint64_t result;
      phrase.fetch(0, result);
      return result;
    }

    void setSetting(lexicon::Lexicon &lexicon, Size languageAddress, std::string_view name, std::uint64_t value) {
      lexicon::Phrase settings = registry(lexicon, SettingsName, languageAddress);
      lexicon::Phrase phrase =
          settings.append(std::string(name)).make().setType(lexicon::phrase::type::getData(settings)).save();
      phrase.store(value).save();
    }

    struct Selection {
      std::uint64_t generation = 0;
      std::uint8_t state = 0;
    };

    void select(lexicon::Lexicon &lexicon, Size languageAddress, std::string_view symbol, std::uint8_t state) {
      lexicon::Phrase selections = registry(lexicon, SelectionsName, languageAddress);
      lexicon::Phrase phrase =
          selections.append(std::string(symbol)).make().setType(lexicon::phrase::type::getData(selections)).save();
      phrase.store(Selection{setting(lexicon, languageAddress, "selection-generation", 0), state}).save();
    }

    std::uint8_t selection(lexicon::Lexicon &lexicon, Size languageAddress, std::string_view symbol) {
      lexicon::Phrase phrase = exact(registry(lexicon, SelectionsName, languageAddress), symbol);
      if (phrase.isNull()) return 0;
      if (phrase.payloadSize() != sizeof(Selection)) THROW(, "invalid module selection phrase")
      Selection result;
      phrase.fetch(0, result);
      return result.generation == setting(lexicon, languageAddress, "selection-generation", 0) ? result.state : 0;
    }

    std::vector<std::string> selected(lexicon::Lexicon &lexicon, Size languageAddress, std::uint8_t state) {
      std::vector<std::string> result;
      for (const std::string &key : keys(registry(lexicon, SelectionsName, languageAddress)))
        if (selection(lexicon, languageAddress, key) == state) result.push_back(key);
      return result;
    }

    std::vector<std::uint8_t> readLinkInput(const std::string &path) {
      if (path.empty()) THROW(, "link input path cannot be empty")
      std::ifstream input(path, std::ios::binary);
      if (!input.is_open()) THROW(, "cannot open link input '" << path << "'")
      std::vector<std::uint8_t> bytes{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
      if (input.bad()) THROW(, "cannot read link input '" << path << "'")
      return bytes;
    }

    void storeLinkInput(lexicon::Lexicon &lexicon, Size languageAddress, std::string_view registryName,
                        const std::string &path, std::span<const std::uint8_t> bytes) {
      const std::uint64_t sequence = setting(lexicon, languageAddress, "link-sequence", 0);
      setSetting(lexicon, languageAddress, "link-sequence", sequence + 1);
      Writer writer;
      writer.number(setting(lexicon, languageAddress, "link-generation", 0));
      writer.text(path);
      writer.data(bytes);
      store(registry(lexicon, registryName, languageAddress), std::to_string(sequence), writer.bytes);
    }

    struct LinkInput {
      std::uint64_t generation;
      std::string path;
      std::vector<std::uint8_t> bytes;
    };

    LinkInput decodeLinkInput(lexicon::Phrase phrase) {
      const std::vector<std::uint8_t> bytes = payload(phrase);
      Reader reader(bytes);
      LinkInput result{reader.number<std::uint64_t>(), reader.text(), reader.data()};
      reader.finish();
      return result;
    }

    std::vector<LinkInput> linkInputs(lexicon::Lexicon &lexicon, Size languageAddress, std::string_view registryName) {
      const std::uint64_t generation = setting(lexicon, languageAddress, "link-generation", 0);
      std::vector<LinkInput> result;
      for (const std::string &key : keys(registry(lexicon, registryName, languageAddress))) {
        LinkInput input = decodeLinkInput(exact(registry(lexicon, registryName, languageAddress), key));
        if (input.generation == generation) result.push_back(std::move(input));
      }
      return result;
    }

    bool sameConvention(const CallingConvention &left, const CallingConvention &right) {
      return left.name == right.name && left.integerRegisters == right.integerRegisters &&
             left.floatingRegisters == right.floatingRegisters && left.resultRegister == right.resultRegister &&
             left.floatingResultRegister == right.floatingResultRegister &&
             left.stackAlignment == right.stackAlignment && left.shadowSpace == right.shadowSpace &&
             left.stackGrowsDown == right.stackGrowsDown && left.callerCleansStack == right.callerCleansStack;
    }

    bool sameDeclaration(const TypedFunction &left, const TypedFunction &right) {
      return left.name == right.name && left.signature.symbol == right.signature.symbol &&
             left.parameterTypes == right.parameterTypes && left.resultType == right.resultType &&
             left.signature.parameters == right.signature.parameters &&
             left.signature.result == right.signature.result && left.signature.variadic == right.signature.variadic &&
             sameConvention(left.signature.convention, right.signature.convention);
    }
  } // namespace

  LanguageState::LanguageState(lexicon::Phrase language)
      : types(language), lexicon(language.getLexicon()), languageAddress(language.getAddress()) {
    languageData(language);
  }

  LanguageState LanguageState::locate(lexicon::Lexicon &lexicon) {
    return LanguageState(languageRoot(lexicon));
  }

  LanguageState LanguageState::resolve(lexicon::Lexicon &lexicon, lexicon::Phrase *invoked) {
    if (invoked == nullptr || invoked->getAddress() >= lexicon.memoryUsed()) return locate(lexicon);
    const auto resolveBinding = [&](lexicon::Phrase phrase) -> std::optional<LanguageState> {
      if (phrase.payloadSize() < sizeof(LanguageBinding)) return std::nullopt;
      LanguageBinding binding;
      phrase.fetch(phrase.payloadSize() - sizeof(binding), binding);
      if (binding.magic != LanguageBinding::Magic) return std::nullopt;
      lexicon::Phrase language(&lexicon, binding.language);
      language.load();
      return LanguageState(language);
    };

    lexicon::Phrase original = *invoked;
    if (std::optional<LanguageState> direct = resolveBinding(original)) return *direct;

    bool live = false;
    for (radix::Item item = lexicon.lastItem(); !item.isNull(); item = item.earlier()) {
      if (item.getAddress() == original.getAddress()) {
        live = true;
        break;
      }
    }
    if (!live) return locate(lexicon);

    for (lexicon::Phrase phrase = original; !phrase.isNull(); phrase = phrase.getParent()) {
      if (phrase.containsSubdictionary()) {
        lexicon::Phrase attached = exact(phrase, LanguageBindingPhraseName);
        if (!attached.isNull())
          if (std::optional<LanguageState> resolved = resolveBinding(attached)) return *resolved;
      }
      lexicon::Phrase parent = phrase.getParent();
      if (!parent.isNull())
        if (std::optional<LanguageState> resolved = resolveBinding(parent)) return *resolved;
    }
    return locate(lexicon);
  }

  LanguageBinding LanguageState::binding(lexicon::Lexicon &lexicon) {
    const LanguageState language = locate(lexicon);
    return {LanguageBinding::Magic, language.languageAddress};
  }

  void LanguageState::bind(lexicon::Phrase &host) {
    const LanguageBinding value = binding(*host.getLexicon());
    if (host.payloadSize() >= sizeof(value)) {
      LanguageBinding existing;
      const Size offset = host.payloadSize() - sizeof(existing);
      host.fetch(offset, existing);
      if (existing.magic == LanguageBinding::Magic) {
        host.update(offset, value).save();
        return;
      }
    }
    lexicon::Phrase destination = host;
    if (host.getLexicon()->lastItem().getAddress() != host.getAddress()) {
      if (!host.containsSubdictionary()) THROW(, "cannot attach a language binding to a closed leaf phrase")
      destination = exact(host, LanguageBindingPhraseName);
      if (destination.isNull())
        destination = host.append(std::string(LanguageBindingPhraseName))
                          .make()
                          .setType(lexicon::phrase::type::getData(host))
                          .save();
    }
    destination.store(value).save();
  }

  void LanguageState::setup(lexicon::Phrase root) {
    lexicon::Phrase language = dictionary(root, LanguageDictionaryName);
    if (language.payloadSize() == 0)
      language.store(Language{}).save();
    else
      languageData(language);
    dictionary(language, ConventionsName);
    dictionary(language, FunctionsName);
    dictionary(language, FunctionSourcesName);
    dictionary(language, ModulesName);
    dictionary(language, SettingsName);
    dictionary(language, SelectionsName);
    dictionary(language, LinkObjectsName);
    dictionary(language, LinkArchivesName);
    dictionary(language, LinkPathsName);
    dictionary(language, SharedLibrariesName);
    TypeRegistry::setup(root);

    LanguageState state(language);
    if (exact(registry(*root.getLexicon(), ConventionsName, language.getAddress()), "sysv-amd64").isNull()) {
      state.defineConvention(CallingConvention::systemVAMD64());
      state.defineConvention(CallingConvention::microsoftX64());
      state.defineConvention(CallingConvention::cdeclX86());
      state.defineConvention(CallingConvention::stdcallX86());
      state.defineConvention(CallingConvention::fastcallX86());
    }
    for (std::string_view path : {".", "/usr/local/lib", "/usr/lib", "/lib", "/usr/lib64", "/lib64",
                                  "/usr/lib/x86_64-linux-gnu", "/lib/x86_64-linux-gnu"})
      state.addLinkSearchPath(std::string(path));
    if (exact(registry(*root.getLexicon(), SettingsName, language.getAddress()), "automatic-modules").isNull())
      state.setAutomaticModuleLinking(true);
    if (exact(registry(*root.getLexicon(), SettingsName, language.getAddress()), "embed-language").isNull())
      state.setEmbedLanguage(true);
  }

  void LanguageState::defineConvention(CallingConvention value) {
    Abi::validate(value);
    lexicon::Phrase conventions = registry(*lexicon, ConventionsName, languageAddress);
    if (!exact(conventions, value.name).isNull()) THROW(, "duplicate calling convention: '" << value.name << "'")
    store(conventions, value.name, encode(value));
  }

  CallingConvention LanguageState::convention(std::string_view name) const {
    lexicon::Phrase found = exact(registry(*lexicon, ConventionsName, languageAddress), name);
    if (found.isNull()) THROW(, "unknown calling convention: '" << name << "'")
    return decodeConvention(found);
  }

  void LanguageState::declareFunction(TypedFunction function) {
    if (function.signature.symbol.empty()) THROW(, "typed function symbol cannot be empty")
    if (function.name.empty()) function.name = function.signature.symbol;
    if (function.parameterTypes.size() != function.signature.parameters.size())
      THROW(, "typed function parameter registry is inconsistent")
    lexicon::Phrase functions = registry(*lexicon, FunctionsName, languageAddress);
    lexicon::Phrase overloads = exact(functions, function.name);
    if (overloads.isNull())
      overloads = functions.append(function.name)
                      .make()
                      .enableSubdictionary()
                      .setType(lexicon::phrase::type::getData(functions))
                      .save();
    if (!overloads.containsSubdictionary()) THROW(, "typed function overload set is not a dictionary")
    const std::string key = functionKey(function.parameterTypes, function.signature.variadic);
    lexicon::Phrase existingPhrase = exact(overloads, key);
    if (!existingPhrase.isNull()) {
      const TypedFunction existing = decodeFunction(existingPhrase);
      if (function.imported) THROW(, "duplicate typed function: '" << function.signature.symbol << "'")
      if (!sameDeclaration(existing, function)) {
        if (existing.imported)
          THROW(, "typed function definition does not match forward declaration: '" << function.signature.symbol << "'")
        THROW(, "typed function redefinition changes its signature: '" << function.signature.symbol << "'")
      }
    }
    functionType(function);
    store(overloads, key, encode(function));
  }

  std::optional<TypedFunction> LanguageState::findFunction(std::string_view symbol) const {
    const std::vector<TypedFunction> named = findFunctions(symbol);
    if (named.size() == 1) return named.front();
    // Physical symbols remain directly addressable (methods and relocations use them).
    for (const TypedFunction &function : functions())
      if (function.signature.symbol == symbol) return function;
    return std::nullopt;
  }

  std::vector<TypedFunction> LanguageState::findFunctions(std::string_view name) const {
    lexicon::Phrase overloads = exact(registry(*lexicon, FunctionsName, languageAddress), name);
    if (overloads.isNull() || !overloads.containsSubdictionary()) return {};
    std::vector<TypedFunction> result;
    for (const std::string &key : keys(overloads)) result.push_back(decodeFunction(exact(overloads, key)));
    return result;
  }

  std::vector<TypedFunction> LanguageState::findFunctions(std::string_view name, std::string_view scope) const {
    if (name.find(':') != std::string_view::npos) return findFunctions(name);

    // A lexical name is matched at the longest (nearest) scope first. Each
    // phrase found there is one complete overload dictionary, so a shorter
    // scope never contributes variants after a longer one has matched.
    while (!scope.empty()) {
      std::string qualified;
      qualified.reserve(scope.size() + 1 + name.size());
      qualified.append(scope).append(":").append(name);
      std::vector<TypedFunction> found = findFunctions(qualified);
      if (!found.empty()) return found;
      const std::size_t parent = scope.rfind(':');
      scope = parent == std::string_view::npos ? std::string_view{} : scope.substr(0, parent);
    }
    return findFunctions(name);
  }

  std::optional<TypedFunction> LanguageState::resolveFunction(std::string_view name,
                                                              std::span<const TypeId> arguments) const {
    const std::vector<TypedFunction> candidates = findFunctions(name);
    const TypedFunction *best = nullptr;
    std::size_t bestCost = std::numeric_limits<std::size_t>::max();
    bool ambiguous = false;
    for (const TypedFunction &candidate : candidates) {
      if ((!candidate.signature.variadic && candidate.parameterTypes.size() != arguments.size()) ||
          (candidate.signature.variadic && candidate.parameterTypes.size() > arguments.size()))
        continue;
      std::size_t cost = candidate.signature.variadic ? 2 : 0;
      bool compatible = true;
      for (std::size_t index = 0; index < candidate.parameterTypes.size(); ++index) {
        const std::optional<std::size_t> conversion = conversionCost(candidate.parameterTypes[index], arguments[index]);
        if (!conversion) {
          compatible = false;
          break;
        }
        cost += *conversion;
      }
      if (!compatible) continue;
      if (cost < bestCost) {
        best = &candidate;
        bestCost = cost;
        ambiguous = false;
      } else if (cost == bestCost) {
        ambiguous = true;
      }
    }
    if (ambiguous) THROW(, "ambiguous typed function overload: '" << name << "'")
    return best == nullptr ? std::nullopt : std::optional<TypedFunction>(*best);
  }

  TypeId LanguageState::functionType(const TypedFunction &function) {
    return types.functionOf(function.parameterTypes, function.resultType, function.signature.convention.name,
                            function.signature.variadic);
  }

  FunctionSignature LanguageState::functionSignature(TypeId type, std::string symbol) const {
    const TypeDescriptor descriptor = types.get(type);
    if (descriptor.kind != TypeKind::Function) THROW(, "type is not callable: '" << descriptor.name << "'")
    FunctionSignature result;
    result.symbol = std::move(symbol);
    result.convention = convention(descriptor.convention);
    result.result = types.abiType(descriptor.resultType);
    result.variadic = descriptor.variadic;
    result.parameters.reserve(descriptor.parameterTypes.size());
    for (TypeId parameter : descriptor.parameterTypes) result.parameters.push_back(types.abiType(parameter));
    return result;
  }

  std::optional<std::size_t> LanguageState::conversionCost(TypeId expected, TypeId actual) const {
    if (expected == actual) return 0;
    const TypeDescriptor expectedType = types.get(expected);
    const TypeDescriptor actualType = types.get(actual);
    if (expectedType.kind == TypeKind::Integer && actualType.kind == TypeKind::Integer) return 1;
    if (expectedType.kind == TypeKind::Pointer && actualType.kind == TypeKind::Pointer &&
        expectedType.pointerDepth == actualType.pointerDepth)
      return 1;
    if (expectedType.kind == TypeKind::Pointer && actualType.kind == TypeKind::Function) return 1;
    return std::nullopt;
  }

  std::vector<TypedFunction> LanguageState::functions() const {
    lexicon::Phrase functions = registry(*lexicon, FunctionsName, languageAddress);
    std::vector<TypedFunction> result;
    for (const std::string &name : keys(functions)) {
      lexicon::Phrase overloads = exact(functions, name);
      if (!overloads.containsSubdictionary()) continue;
      for (const std::string &key : keys(overloads)) result.push_back(decodeFunction(exact(overloads, key)));
    }
    return result;
  }

  std::string LanguageState::functionKey(std::span<const TypeId> parameters, bool variadic) const {
    std::string result{"("};
    for (std::size_t index = 0; index < parameters.size(); ++index) {
      if (index != 0) result.push_back(',');
      result += types.get(parameters[index]).name;
    }
    if (variadic) {
      if (!parameters.empty()) result.push_back(',');
      result += "...";
    }
    result.push_back(')');
    return result;
  }

  std::string LanguageState::functionSymbol(std::string_view name, std::span<const TypeId> parameters,
                                            bool variadic) const {
    return std::string(name) + functionKey(parameters, variadic);
  }

  void LanguageState::rememberModule(std::string symbol, Module module) {
    if (symbol.empty()) THROW(, "native module symbol cannot be empty")
    const Symbol *entry = module.findSymbol(symbol);
    if (entry == nullptr || entry->imported)
      THROW(, "native module does not define its entry symbol: '" << symbol << "'")
    store(registry(*lexicon, ModulesName, languageAddress), symbol, ElfWriter::write(module));
  }

  std::optional<Module> LanguageState::findModule(std::string_view symbol) const {
    lexicon::Phrase found = exact(registry(*lexicon, ModulesName, languageAddress), symbol);
    if (found.isNull()) return std::nullopt;
    return ElfReader::read(payload(found), std::string(symbol));
  }

  std::vector<NativeModule> LanguageState::modules() const {
    lexicon::Phrase modules = registry(*lexicon, ModulesName, languageAddress);
    std::vector<NativeModule> result;
    for (const std::string &key : keys(modules)) result.push_back({key, *findModule(key)});
    return result;
  }

  void LanguageState::rememberFunctionSource(std::string symbol, FunctionSource source) {
    if (symbol.empty()) THROW(, "function source symbol cannot be empty")
    Writer writer;
    writer.strings(source.parameterNames);
    writer.text(source.scope);
    writer.text(source.path);
    writer.text(source.body);
    writer.number(static_cast<std::uint64_t>(source.line));
    writer.number(static_cast<std::uint64_t>(source.column));
    lexicon::Phrase sources = dictionary(languageRoot(*lexicon, languageAddress), FunctionSourcesName);
    store(sources, symbol, writer.bytes);
  }

  std::optional<FunctionSource> LanguageState::findFunctionSource(std::string_view symbol) const {
    lexicon::Phrase sources = exact(languageRoot(*lexicon, languageAddress), FunctionSourcesName);
    if (sources.isNull()) return std::nullopt;
    lexicon::Phrase found = exact(sources, symbol);
    if (found.isNull()) return std::nullopt;
    const std::vector<std::uint8_t> bytes = payload(found);
    try {
      Reader reader(bytes);
      FunctionSource result;
      result.parameterNames = reader.strings();
      result.scope = reader.text();
      result.path = reader.text();
      result.body = reader.text();
      result.line = reader.number<std::uint64_t>();
      result.column = reader.number<std::uint64_t>();
      reader.finish();
      return result;
    } catch (const std::exception &error) {
      THROW(, "invalid stored function source for '" << symbol << "': " << error.what())
    }
  }

  void LanguageState::setAutomaticModuleLinking(bool enabled) {
    setSetting(*lexicon, languageAddress, "automatic-modules", enabled);
  }
  bool LanguageState::automaticModuleLinking() const {
    return setting(*lexicon, languageAddress, "automatic-modules", 1) != 0;
  }

  std::vector<std::string> LanguageState::includedModules() const {
    return selected(*lexicon, languageAddress, 1);
  }

  std::vector<std::string> LanguageState::excludedModules() const {
    return selected(*lexicon, languageAddress, 2);
  }

  void LanguageState::includeModule(std::string symbol) {
    if (symbol.empty()) THROW(, "included module symbol cannot be empty")
    select(*lexicon, languageAddress, symbol, 1);
  }

  void LanguageState::excludeModule(std::string symbol) {
    if (symbol.empty()) THROW(, "excluded module symbol cannot be empty")
    select(*lexicon, languageAddress, symbol, 2);
  }

  void LanguageState::setModuleEntry(std::string symbol) {
    if (symbol.empty()) THROW(, "module entry symbol cannot be empty")
    includeModule(symbol);
    Writer writer;
    writer.number(setting(*lexicon, languageAddress, "selection-generation", 0));
    writer.text(symbol);
    store(registry(*lexicon, SettingsName, languageAddress), "module-entry", writer.bytes);
  }

  std::optional<std::string> LanguageState::moduleEntry() const {
    lexicon::Phrase phrase = exact(registry(*lexicon, SettingsName, languageAddress), "module-entry");
    if (phrase.isNull()) return std::nullopt;
    const std::vector<std::uint8_t> bytes = payload(phrase);
    Reader reader(bytes);
    const std::uint64_t generation = reader.number<std::uint64_t>();
    const std::string result = reader.text();
    reader.finish();
    return generation == setting(*lexicon, languageAddress, "selection-generation", 0)
               ? std::optional<std::string>(result)
               : std::nullopt;
  }

  Module LanguageState::composeModule(const Module &root, std::span<const std::string> providedSymbols,
                                      bool includeLinkInputs) const {
    Module result = root;
    std::unordered_set<std::string> merged;
    const std::unordered_set<std::string> provided(providedSymbols.begin(), providedSymbols.end());
    const auto merge = [&](const std::string &symbol, auto &self) -> void {
      if (!merged.insert(symbol).second) return;
      if (provided.contains(symbol)) return;
      const Symbol *existing = result.findSymbol(symbol);
      if (existing != nullptr && !existing->imported) return;
      const std::optional<Module> dependency = findModule(symbol);
      if (!dependency) THROW(, "native module is unavailable for symbol: '" << symbol << "'")
      result.merge(*dependency);
      if (!automaticModuleLinking()) return;
      std::vector<std::string> imports;
      for (const Symbol &candidate : result.symbols())
        if (candidate.imported && selection(*lexicon, languageAddress, candidate.name) != 2 &&
            findModule(candidate.name))
          imports.push_back(candidate.name);
      for (const std::string &candidate : imports) self(candidate, self);
    };

    for (const std::string &symbol : selected(*lexicon, languageAddress, 1)) merge(symbol, merge);
    if (automaticModuleLinking()) {
      std::vector<std::string> imports;
      for (const Symbol &symbol : result.symbols())
        if (symbol.imported && selection(*lexicon, languageAddress, symbol.name) != 2 && findModule(symbol.name))
          imports.push_back(symbol.name);
      for (const std::string &symbol : imports) merge(symbol, merge);
    }

    if (!includeLinkInputs) return result;
    StaticLinker linker;
    for (const LinkInput &input : linkInputs(*lexicon, languageAddress, LinkObjectsName))
      linker.addObject(ElfReader::read(input.bytes, input.path));
    for (const LinkInput &input : linkInputs(*lexicon, languageAddress, LinkArchivesName))
      linker.addArchive(ArchiveReader::read(input.bytes, input.path));
    return linker.link(result);
  }

  void LanguageState::clearModuleSelection() {
    setSetting(*lexicon, languageAddress, "selection-generation",
               setting(*lexicon, languageAddress, "selection-generation", 0) + 1);
  }

  void LanguageState::linkObject(const std::string &path) {
    storeLinkInput(*lexicon, languageAddress, LinkObjectsName, path, readLinkInput(path));
  }

  void LanguageState::linkArchive(const std::string &path) {
    storeLinkInput(*lexicon, languageAddress, LinkArchivesName, path, readLinkInput(path));
  }

  void LanguageState::addLinkSearchPath(const std::string &path) {
    if (path.empty()) THROW(, "link search path cannot be empty")
    lexicon::Phrase paths = registry(*lexicon, LinkPathsName, languageAddress);
    if (exact(paths, path).isNull()) store(paths, path, {});
  }

  void LanguageState::linkLibrary(const std::string &name) {
    if (name.empty() || name.find('/') != std::string::npos)
      THROW(, "static library name must be non-empty and must not contain '/'")
    const std::string file = name.starts_with("lib") && name.ends_with(".a") ? name : "lib" + name + ".a";
    for (const std::string &directory : linkerSearchPaths()) {
      const std::filesystem::path candidate = std::filesystem::path(directory) / file;
      std::error_code error;
      if (std::filesystem::is_regular_file(candidate, error)) {
        linkArchive(candidate.string());
        return;
      }
    }
    THROW(, "cannot find static library '" << file << "' in configured link paths")
  }

  void LanguageState::linkSharedLibrary(const std::string &name) {
    if (name.empty() || name.find('/') != std::string::npos)
      THROW(, "shared library name must be non-empty and must not contain '/'")
    Writer writer;
    writer.number(setting(*lexicon, languageAddress, "link-generation", 0));
    store(registry(*lexicon, SharedLibrariesName, languageAddress), name, writer.bytes);
  }

  std::vector<std::string> LanguageState::sharedLibraries() const {
    const std::uint64_t generation = setting(*lexicon, languageAddress, "link-generation", 0);
    lexicon::Phrase libraries = registry(*lexicon, SharedLibrariesName, languageAddress);
    std::vector<std::string> result;
    for (const std::string &key : keys(libraries)) {
      const std::vector<std::uint8_t> bytes = payload(exact(libraries, key));
      Reader reader(bytes);
      if (reader.number<std::uint64_t>() == generation) result.push_back(key);
      reader.finish();
    }
    return result;
  }

  std::vector<std::string> LanguageState::linkerSearchPaths() const {
    return keys(registry(*lexicon, LinkPathsName, languageAddress));
  }

  std::vector<NativeLinkInput> LanguageState::nativeLinkInputs() const {
    std::vector<NativeLinkInput> result;
    for (LinkInput &input : linkInputs(*lexicon, languageAddress, LinkObjectsName))
      result.push_back({std::move(input.path), std::move(input.bytes), false});
    for (LinkInput &input : linkInputs(*lexicon, languageAddress, LinkArchivesName))
      result.push_back({std::move(input.path), std::move(input.bytes), true});
    return result;
  }

  void LanguageState::clearLinkInputs() {
    setSetting(*lexicon, languageAddress, "link-generation",
               setting(*lexicon, languageAddress, "link-generation", 0) + 1);
  }

  bool LanguageState::hasLinkInputs() const {
    return !linkInputs(*lexicon, languageAddress, LinkObjectsName).empty() ||
           !linkInputs(*lexicon, languageAddress, LinkArchivesName).empty() || hasSharedLibraries();
  }

  bool LanguageState::hasSharedLibraries() const {
    return !sharedLibraries().empty();
  }

  void LanguageState::setEmbedLanguage(bool enabled) {
    setSetting(*lexicon, languageAddress, "embed-language", enabled);
  }
  bool LanguageState::embedsLanguage() const {
    return setting(*lexicon, languageAddress, "embed-language", 1) != 0;
  }
} // namespace compiler
