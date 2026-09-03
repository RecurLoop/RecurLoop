#pragma once

#include <compiler/Abi.hpp>
#include <compiler/TypeSystem.hpp>

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace compiler {
  class LanguageState;
  class Module;

  struct EmbeddedField {
    std::string name;
    std::string type;
    std::size_t offset = 0;
  };

  struct EmbeddedType {
    std::string name;
    TypeKind kind = TypeKind::Void;
    std::size_t size = 0;
    std::size_t alignment = 1;
    bool isSigned = false;
    std::string element;
    std::size_t elementCount = 0;
    std::uint16_t pointerDepth = 0;
    std::vector<EmbeddedField> fields;
    std::vector<std::string> parameters;
    std::string result;
    std::string convention;
    bool variadic = false;
  };

  struct EmbeddedFunction {
    std::string name;
    std::string symbol;
    std::string result;
    std::vector<std::string> parameters;
    CallingConvention convention;
    bool imported = false;
    bool variadic = false;
  };

  struct EmbeddedLanguage {
    std::vector<EmbeddedType> types;
    std::vector<EmbeddedFunction> functions;
    std::vector<std::string> nativeActions;
  };

  class LanguageImage {
  public:
    LanguageImage() = delete;
    static constexpr std::uint32_t Version = 3;
    static constexpr const char *SectionName = ".recurloop.language";

    static std::vector<std::uint8_t> encode(const LanguageState &language);
    static EmbeddedLanguage decode(std::span<const std::uint8_t> bytes);
    static void embed(const LanguageState &language, Module &module);
  };
} // namespace compiler
