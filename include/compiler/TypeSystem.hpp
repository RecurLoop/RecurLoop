#pragma once

#include <compiler/Abi.hpp>

#include <utilities/Size.hpp>

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace lexicon {
  class Lexicon;
  class Phrase;
} // namespace lexicon

namespace compiler {
  using TypeId = std::uint32_t;
  inline constexpr TypeId InvalidType = 0;

  enum class TypeKind : std::uint8_t { Void, Integer, FloatingPoint, Pointer, Array, Structure, Function };

  struct FieldDeclaration {
    std::string name;
    TypeId type = InvalidType;
  };

  struct TypeField {
    std::string name;
    TypeId type = InvalidType;
    std::size_t offset = 0;
  };

  struct TypeMethod {
    std::string name;
    FunctionSignature signature;
  };

  struct TypeDescriptor {
    TypeId id = InvalidType;
    std::string name;
    TypeKind kind = TypeKind::Void;
    std::size_t size = 0;
    std::size_t alignment = 1;
    bool isSigned = false;
    TypeId element = InvalidType;
    std::size_t elementCount = 0;
    std::uint16_t pointerDepth = 0;
    std::vector<TypeField> fields;
    std::vector<TypeMethod> methods;
    std::vector<TypeId> parameterTypes;
    TypeId resultType = InvalidType;
    std::string convention;
    bool variadic = false;
  };

  class TypeRegistry {
  public:
    explicit TypeRegistry(lexicon::Phrase language);
    static void setup(lexicon::Phrase root);

    TypeId find(std::string_view name) const;
    TypeDescriptor get(TypeId id) const;
    TypeDescriptor get(std::string_view name) const;

    TypeId defineInteger(std::string name, std::size_t bits, bool isSigned);
    TypeId defineFloatingPoint(std::string name, std::size_t bits);
    TypeId pointerTo(TypeId pointee);
    TypeId arrayOf(TypeId element, std::size_t count);
    TypeId functionOf(std::span<const TypeId> parameters, TypeId result, std::string_view convention,
                      bool variadic = false);
    TypeId declareStructure(std::string name);
    void completeStructure(TypeId structure, std::span<const FieldDeclaration> fields, bool packed = false,
                           std::size_t explicitAlignment = 0);
    TypeId defineStructure(std::string name, std::span<const FieldDeclaration> fields, bool packed = false,
                           std::size_t explicitAlignment = 0);
    TypeId defineStructureLayout(std::string name, std::size_t size, std::size_t alignment,
                                 std::span<const TypeField> fields = {});
    void addMethod(TypeId structure, std::string name, FunctionSignature signature);

    ValueType abiType(TypeId id) const;
    std::vector<TypeDescriptor> types() const;

  private:
    lexicon::Lexicon *lexicon;
    Size languageAddress;

    TypeId append(TypeDescriptor descriptor);
  };

  class TypedValue {
  public:
    TypedValue() = default;
    TypedValue(TypeId type, std::vector<std::uint8_t> bytes);

    static TypedValue integer(TypeId type, std::uint64_t value, std::size_t bytes);
    static TypedValue pointer(TypeId type, std::uintptr_t address, std::size_t bytes = sizeof(std::uintptr_t));

    TypeId type() const;
    std::span<const std::uint8_t> bytes() const;
    std::uint64_t asUnsigned() const;

  private:
    TypeId valueType = InvalidType;
    std::vector<std::uint8_t> valueBytes;
  };
} // namespace compiler
