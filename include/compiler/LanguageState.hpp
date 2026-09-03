#pragma once

#include <compiler/Module.hpp>
#include <compiler/TypeSystem.hpp>

#include <utilities/Size.hpp>

#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace lexicon {
  class Lexicon;
  class Phrase;
} // namespace lexicon

namespace compiler {
  inline constexpr std::string_view LanguageBindingPhraseName{"\0language", 9};

  struct Language {
    static constexpr std::uint64_t Magic = 0x524C4C414E475545ull;
    static constexpr std::uint32_t Version = 3;

    std::uint64_t magic = Magic;
    std::uint32_t version = Version;
  };

  struct LanguageBinding {
    static constexpr std::uint64_t Magic = 0x524C4C414E474249ull;

    std::uint64_t magic = Magic;
    Size language = 0;
  };

  struct TypedFunction {
    // Source-level phrase name. The ABI symbol may differ for an overload.
    std::string name;
    FunctionSignature signature;
    std::vector<TypeId> parameterTypes;
    TypeId resultType = InvalidType;
    bool imported = false;
  };

  struct NativeModule {
    std::string symbol;
    Module module;
  };

  struct FunctionSource {
    std::vector<std::string> parameterNames;
    std::string scope;
    std::string path;
    std::string body;
    std::size_t line = 1;
    std::size_t column = 1;
  };

  struct NativeLinkInput {
    std::string path;
    std::vector<std::uint8_t> bytes;
    bool archive = false;
  };

  class LanguageState {
  public:
    explicit LanguageState(lexicon::Phrase language);
    static void setup(lexicon::Phrase root);
    static LanguageState locate(lexicon::Lexicon &lexicon);
    static LanguageState resolve(lexicon::Lexicon &lexicon, lexicon::Phrase *invoked);
    static LanguageBinding binding(lexicon::Lexicon &lexicon);
    static void bind(lexicon::Phrase &host);
    TypeRegistry types;

    void defineConvention(CallingConvention convention);
    CallingConvention convention(std::string_view name) const;

    void declareFunction(TypedFunction function);
    std::optional<TypedFunction> findFunction(std::string_view symbol) const;
    std::vector<TypedFunction> findFunctions(std::string_view name) const;
    std::vector<TypedFunction> findFunctions(std::string_view name, std::string_view scope) const;
    std::optional<TypedFunction> resolveFunction(std::string_view name, std::span<const TypeId> arguments) const;
    std::vector<TypedFunction> functions() const;
    TypeId functionType(const TypedFunction &function);
    FunctionSignature functionSignature(TypeId type, std::string symbol = {}) const;
    std::optional<std::size_t> conversionCost(TypeId expected, TypeId actual) const;

    std::string functionKey(std::span<const TypeId> parameters, bool variadic = false) const;
    std::string functionSymbol(std::string_view name, std::span<const TypeId> parameters, bool variadic = false) const;

    void rememberModule(std::string symbol, Module module);
    std::optional<Module> findModule(std::string_view symbol) const;
    std::vector<NativeModule> modules() const;
    void rememberFunctionSource(std::string symbol, FunctionSource source);
    std::optional<FunctionSource> findFunctionSource(std::string_view symbol) const;
    void setAutomaticModuleLinking(bool enabled);
    bool automaticModuleLinking() const;
    std::vector<std::string> includedModules() const;
    std::vector<std::string> excludedModules() const;
    void includeModule(std::string symbol);
    void excludeModule(std::string symbol);
    void setModuleEntry(std::string symbol);
    std::optional<std::string> moduleEntry() const;
    Module composeModule(const Module &root, std::span<const std::string> providedSymbols = {},
                         bool includeLinkInputs = true) const;
    void clearModuleSelection();
    void linkObject(const std::string &path);
    void linkArchive(const std::string &path);
    void addLinkSearchPath(const std::string &path);
    void linkLibrary(const std::string &name);
    void linkSharedLibrary(const std::string &name);
    std::vector<std::string> sharedLibraries() const;
    std::vector<std::string> linkerSearchPaths() const;
    std::vector<NativeLinkInput> nativeLinkInputs() const;
    void clearLinkInputs();
    bool hasLinkInputs() const;
    bool hasSharedLibraries() const;
    void setEmbedLanguage(bool enabled);
    bool embedsLanguage() const;

  private:
    lexicon::Lexicon *lexicon;
    Size languageAddress;
  };
} // namespace compiler
