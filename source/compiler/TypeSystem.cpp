#include <compiler/TypeSystem.hpp>

#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cstring>
#include <limits>
#include <unordered_set>

namespace compiler {
  namespace {
    constexpr std::string_view LanguageDictionaryName{"\0compiler-language", 18};
    constexpr std::string_view TypesName{"types"};
    constexpr std::string_view TypeIdsName{"by-id"};
    constexpr std::string_view NextTypeIdName{"next-id"};
    constexpr std::string_view AbiKindsName{"abi-kinds"};

    bool powerOfTwo(std::size_t value) {
      return value != 0 && (value & (value - 1)) == 0;
    }

    std::size_t alignUp(std::size_t value, std::size_t alignment) {
      if (!powerOfTwo(alignment)) THROW(, "type alignment must be a non-zero power of two")
      if (value > std::numeric_limits<std::size_t>::max() - (alignment - 1)) THROW(, "type layout overflows")
      return (value + alignment - 1) & ~(alignment - 1);
    }

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

    lexicon::Phrase languageRoot(lexicon::Lexicon &lexicon, Size address) {
      lexicon::Phrase result(&lexicon, address);
      result.load();
      if (result.isNull()) THROW(, "compiler language phrase is unavailable")
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
        if (value.size() > std::numeric_limits<std::uint32_t>::max()) THROW(, "type metadata string is too large")
        number(static_cast<std::uint32_t>(value.size()));
        bytes.insert(bytes.end(), value.begin(), value.end());
      }
      void strings(const std::vector<std::string> &values) {
        number(static_cast<std::uint32_t>(values.size()));
        for (const std::string &value : values) text(value);
      }
    };

    class Reader {
    public:
      explicit Reader(lexicon::Phrase phrase) : phrase(phrase), bytes(phrase.payloadSize()) {
        if (!bytes.empty()) std::memcpy(bytes.data(), phrase.content(0, bytes.size()).toPtr(), bytes.size());
      }

      template <typename Number> Number number() {
        if (cursor > bytes.size() || sizeof(Number) > bytes.size() - cursor) THROW(, "truncated type phrase payload")
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
        if (cursor > bytes.size() || size > bytes.size() - cursor) THROW(, "truncated type phrase string")
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
      void finish() const {
        if (cursor != bytes.size()) THROW(, "type phrase contains trailing payload")
      }

    private:
      lexicon::Phrase phrase;
      std::vector<std::uint8_t> bytes;
      std::size_t cursor = 0;
    };

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

    std::vector<std::uint8_t> encode(const TypeDescriptor &type) {
      Writer writer;
      writer.number(type.id);
      writer.text(type.name);
      writer.number(static_cast<std::uint8_t>(type.kind));
      writer.number(static_cast<std::uint64_t>(type.size));
      writer.number(static_cast<std::uint64_t>(type.alignment));
      writer.boolean(type.isSigned);
      writer.number(type.element);
      writer.number(static_cast<std::uint64_t>(type.elementCount));
      writer.number(type.pointerDepth);
      writer.number(static_cast<std::uint32_t>(type.fields.size()));
      for (const TypeField &field : type.fields) {
        writer.text(field.name);
        writer.number(field.type);
        writer.number(static_cast<std::uint64_t>(field.offset));
      }
      writer.number(static_cast<std::uint32_t>(type.methods.size()));
      for (const TypeMethod &method : type.methods) {
        writer.text(method.name);
        writeSignature(writer, method.signature);
      }
      if (type.kind == TypeKind::Function) {
        writer.number(static_cast<std::uint32_t>(type.parameterTypes.size()));
        for (TypeId parameter : type.parameterTypes) writer.number(parameter);
        writer.number(type.resultType);
        writer.text(type.convention);
        writer.boolean(type.variadic);
      }
      return writer.bytes;
    }

    TypeDescriptor decode(lexicon::Phrase phrase) {
      Reader reader(phrase);
      TypeDescriptor result;
      result.id = reader.number<TypeId>();
      result.name = reader.text();
      result.kind = static_cast<TypeKind>(reader.number<std::uint8_t>());
      result.size = reader.number<std::uint64_t>();
      result.alignment = reader.number<std::uint64_t>();
      result.isSigned = reader.boolean();
      result.element = reader.number<TypeId>();
      result.elementCount = reader.number<std::uint64_t>();
      result.pointerDepth = reader.number<std::uint16_t>();
      const std::size_t fields = reader.number<std::uint32_t>();
      result.fields.reserve(fields);
      for (std::size_t index = 0; index < fields; ++index)
        result.fields.push_back({reader.text(), reader.number<TypeId>(), reader.number<std::uint64_t>()});
      const std::size_t methods = reader.number<std::uint32_t>();
      result.methods.reserve(methods);
      for (std::size_t index = 0; index < methods; ++index)
        result.methods.push_back({reader.text(), readSignature(reader)});
      if (result.kind == TypeKind::Function) {
        const std::size_t parameters = reader.number<std::uint32_t>();
        result.parameterTypes.reserve(parameters);
        for (std::size_t index = 0; index < parameters; ++index)
          result.parameterTypes.push_back(reader.number<TypeId>());
        result.resultType = reader.number<TypeId>();
        result.convention = reader.text();
        result.variadic = reader.boolean();
      }
      reader.finish();
      return result;
    }

    void store(lexicon::Phrase dictionary, std::string_view key, const TypeDescriptor &type) {
      lexicon::Phrase phrase =
          dictionary.append(std::string(key)).make().setType(lexicon::phrase::type::getData(dictionary)).save();
      const std::vector<std::uint8_t> payload = encode(type);
      Byte output = phrase.allocate(payload.size());
      std::memcpy(output.toPtr(), payload.data(), payload.size());
      phrase.save();
    }

    void storeAbiKind(lexicon::Phrase dictionary, TypeKind kind, ValueKind abiKind) {
      dictionary.append(std::string(1, static_cast<char>(kind)))
          .make()
          .setType(lexicon::phrase::type::getData(dictionary))
          .save()
          .store(abiKind)
          .save();
    }

    std::string idKey(TypeId id) {
      return std::string(reinterpret_cast<const char *>(&id), sizeof(id));
    }

    TypeId nextId(lexicon::Phrase types) {
      lexicon::Phrase next = exact(types, NextTypeIdName);
      if (next.isNull()) return 1;
      if (next.payloadSize() != sizeof(TypeId)) THROW(, "invalid next type id phrase")
      TypeId result;
      next.fetch(0, result);
      return result;
    }

    void setNextId(lexicon::Phrase types, TypeId value) {
      lexicon::Phrase next =
          types.append(std::string(NextTypeIdName)).make().setType(lexicon::phrase::type::getData(types)).save();
      next.store(value).save();
    }
  } // namespace

  TypeRegistry::TypeRegistry(lexicon::Phrase language)
      : lexicon(language.getLexicon()), languageAddress(language.getAddress()) {}

  void TypeRegistry::setup(lexicon::Phrase root) {
    lexicon::Phrase language = dictionary(root, LanguageDictionaryName);
    lexicon::Phrase types = dictionary(language, TypesName);
    dictionary(language, TypeIdsName);
    lexicon::Phrase abiKinds = dictionary(language, AbiKindsName);
    if (exact(abiKinds, std::string(1, static_cast<char>(TypeKind::Void))).isNull()) {
      storeAbiKind(abiKinds, TypeKind::Void, ValueKind::Void);
      storeAbiKind(abiKinds, TypeKind::Integer, ValueKind::Integer);
      storeAbiKind(abiKinds, TypeKind::FloatingPoint, ValueKind::FloatingPoint);
      storeAbiKind(abiKinds, TypeKind::Pointer, ValueKind::Pointer);
      storeAbiKind(abiKinds, TypeKind::Array, ValueKind::Aggregate);
      storeAbiKind(abiKinds, TypeKind::Structure, ValueKind::Aggregate);
      storeAbiKind(abiKinds, TypeKind::Function, ValueKind::Pointer);
    }
    if (!exact(types, NextTypeIdName).isNull()) return;
    setNextId(types, 1);
    TypeRegistry registry(language);
    registry.append({InvalidType, "void", TypeKind::Void, 0, 1});
    registry.defineInteger("i8", 8, true);
    registry.defineInteger("u8", 8, false);
    registry.defineInteger("i16", 16, true);
    registry.defineInteger("u16", 16, false);
    registry.defineInteger("i32", 32, true);
    registry.defineInteger("u32", 32, false);
    registry.defineInteger("i64", 64, true);
    registry.defineInteger("u64", 64, false);
    registry.defineFloatingPoint("f32", 32);
    registry.defineFloatingPoint("f64", 64);
  }

  TypeId TypeRegistry::append(TypeDescriptor descriptor) {
    if (descriptor.name.empty()) THROW(, "type name cannot be empty")
    if (find(descriptor.name) != InvalidType) THROW(, "duplicate type: '" << descriptor.name << "'")
    if (!powerOfTwo(descriptor.alignment)) THROW(, "type alignment must be a non-zero power of two")
    lexicon::Phrase language = languageRoot(*lexicon, languageAddress);
    lexicon::Phrase names = exact(language, TypesName);
    lexicon::Phrase ids = exact(language, TypeIdsName);
    descriptor.id = nextId(names);
    if (descriptor.id == std::numeric_limits<TypeId>::max()) THROW(, "type registry is full")
    store(names, descriptor.name, descriptor);
    store(ids, idKey(descriptor.id), descriptor);
    setNextId(names, descriptor.id + 1);
    return descriptor.id;
  }

  TypeId TypeRegistry::find(std::string_view name) const {
    lexicon::Phrase names = exact(languageRoot(*lexicon, languageAddress), TypesName);
    lexicon::Phrase found = exact(names, name);
    return found.isNull() ? InvalidType : decode(found).id;
  }

  TypeDescriptor TypeRegistry::get(TypeId id) const {
    if (id == InvalidType) THROW(, "invalid type id")
    lexicon::Phrase ids = exact(languageRoot(*lexicon, languageAddress), TypeIdsName);
    lexicon::Phrase found = exact(ids, idKey(id));
    if (found.isNull()) THROW(, "invalid type id")
    return decode(found);
  }

  TypeDescriptor TypeRegistry::get(std::string_view name) const {
    const TypeId id = find(name);
    if (id == InvalidType) THROW(, "unknown type: '" << name << "'")
    return get(id);
  }

  TypeId TypeRegistry::defineInteger(std::string name, std::size_t bits, bool isSigned) {
    if (bits == 0 || bits % 8 != 0) THROW(, "integer type width must be a positive number of bytes")
    const std::size_t bytes = bits / 8;
    return append({InvalidType, std::move(name), TypeKind::Integer, bytes, std::min<std::size_t>(bytes, 8), isSigned});
  }

  TypeId TypeRegistry::defineFloatingPoint(std::string name, std::size_t bits) {
    if (bits != 16 && bits != 32 && bits != 64 && bits != 80 && bits != 128)
      THROW(, "unsupported floating-point type width")
    const std::size_t bytes = (bits + 7) / 8;
    const std::size_t alignment = bytes == 10 ? 16 : std::min<std::size_t>(bytes, 16);
    return append({InvalidType, std::move(name), TypeKind::FloatingPoint, bytes, alignment});
  }

  TypeId TypeRegistry::pointerTo(TypeId pointee) {
    const TypeDescriptor target = get(pointee);
    const std::string name = target.name + "*";
    if (const TypeId existing = find(name); existing != InvalidType) return existing;
    const std::uint16_t depth = target.kind == TypeKind::Pointer ? target.pointerDepth + 1 : 1;
    return append({InvalidType, name, TypeKind::Pointer, sizeof(std::uintptr_t), alignof(std::uintptr_t), false,
                   pointee, 0, depth});
  }

  TypeId TypeRegistry::arrayOf(TypeId element, std::size_t count) {
    const TypeDescriptor item = get(element);
    if (item.kind == TypeKind::Void) THROW(, "array element cannot be void")
    if (count != 0 && item.size > std::numeric_limits<std::size_t>::max() / count) THROW(, "array size overflows")
    const std::string name = item.name + "[" + std::to_string(count) + "]";
    if (const TypeId existing = find(name); existing != InvalidType) return existing;
    return append({InvalidType, name, TypeKind::Array, item.size * count, item.alignment, false, element, count});
  }

  TypeId TypeRegistry::functionOf(std::span<const TypeId> parameters, TypeId result, std::string_view convention,
                                  bool variadic) {
    if (convention.empty()) THROW(, "function type requires an ABI convention")
    const TypeDescriptor resultDescriptor = get(result);
    std::string name{"fn("};
    for (std::size_t index = 0; index < parameters.size(); ++index) {
      const TypeDescriptor parameter = get(parameters[index]);
      if (parameter.kind == TypeKind::Void) THROW(, "function parameter cannot be void")
      if (index != 0) name.push_back(',');
      name += parameter.name;
    }
    if (variadic) {
      if (!parameters.empty()) name.push_back(',');
      name += "...";
    }
    name += ")->" + resultDescriptor.name + " abi " + std::string(convention);
    if (const TypeId existing = find(name); existing != InvalidType) return existing;

    TypeDescriptor descriptor{InvalidType,
                              std::move(name),
                              TypeKind::Function,
                              sizeof(std::uintptr_t),
                              alignof(std::uintptr_t),
                              false,
                              InvalidType,
                              0,
                              1};
    descriptor.parameterTypes.assign(parameters.begin(), parameters.end());
    descriptor.resultType = result;
    descriptor.convention = convention;
    descriptor.variadic = variadic;
    return append(std::move(descriptor));
  }

  TypeId TypeRegistry::declareStructure(std::string name) {
    return append({InvalidType, std::move(name), TypeKind::Structure, 0, 1});
  }

  void TypeRegistry::completeStructure(TypeId structure, std::span<const FieldDeclaration> declarations, bool packed,
                                       std::size_t explicitAlignment) {
    if (explicitAlignment != 0 && !powerOfTwo(explicitAlignment))
      THROW(, "explicit structure alignment must be a power of two")
    TypeDescriptor descriptor = get(structure);
    if (descriptor.kind != TypeKind::Structure || descriptor.size != 0 || !descriptor.fields.empty())
      THROW(, "type is not an incomplete structure: '" << descriptor.name << "'")
    std::unordered_set<std::string> names;
    std::vector<TypeField> fields;
    fields.reserve(declarations.size());
    std::size_t cursor = 0;
    std::size_t structureAlignment = explicitAlignment == 0 ? 1 : explicitAlignment;
    for (const FieldDeclaration &declaration : declarations) {
      if (declaration.name.empty() || !names.insert(declaration.name).second)
        THROW(, "structure field name is empty or duplicated")
      const TypeDescriptor field = get(declaration.type);
      if (field.kind == TypeKind::Void) THROW(, "structure field cannot be void")
      TypeId contained = declaration.type;
      TypeDescriptor containedType = field;
      while (containedType.kind == TypeKind::Array) {
        contained = containedType.element;
        containedType = get(contained);
      }
      if (contained == structure)
        THROW(, "structure '" << descriptor.name << "' cannot contain itself by value; use a pointer")
      const std::size_t fieldAlignment = packed ? 1 : field.alignment;
      cursor = alignUp(cursor, fieldAlignment);
      fields.push_back({declaration.name, declaration.type, cursor});
      if (field.size > std::numeric_limits<std::size_t>::max() - cursor) THROW(, "structure size overflows")
      cursor += field.size;
      structureAlignment = std::max(structureAlignment, fieldAlignment);
    }
    descriptor.size = alignUp(cursor, structureAlignment);
    descriptor.alignment = structureAlignment;
    descriptor.fields = std::move(fields);
    lexicon::Phrase language = languageRoot(*lexicon, languageAddress);
    store(exact(language, TypesName), descriptor.name, descriptor);
    store(exact(language, TypeIdsName), idKey(descriptor.id), descriptor);
  }

  TypeId TypeRegistry::defineStructure(std::string name, std::span<const FieldDeclaration> declarations, bool packed,
                                       std::size_t explicitAlignment) {
    const TypeId result = declareStructure(std::move(name));
    completeStructure(result, declarations, packed, explicitAlignment);
    return result;
  }

  TypeId TypeRegistry::defineStructureLayout(std::string name, std::size_t size, std::size_t alignment,
                                             std::span<const TypeField> fields) {
    if (!powerOfTwo(alignment)) THROW(, "structure alignment must be a non-zero power of two")
    if (size % alignment != 0) THROW(, "structure size must be aligned")
    std::unordered_set<std::string> names;
    for (const TypeField &field : fields) {
      if (field.name.empty() || !names.insert(field.name).second) THROW(, "structure field name is empty or duplicated")
      const TypeDescriptor descriptor = get(field.type);
      if (descriptor.kind == TypeKind::Void) THROW(, "structure field cannot be void")
      if (field.offset > size || descriptor.size > size - field.offset)
        THROW(, "structure field lies outside the explicit layout")
      if (field.offset % descriptor.alignment != 0) THROW(, "structure field is misaligned in the explicit layout")
    }
    TypeDescriptor descriptor{InvalidType, std::move(name), TypeKind::Structure, size, alignment};
    descriptor.fields.assign(fields.begin(), fields.end());
    return append(std::move(descriptor));
  }

  void TypeRegistry::addMethod(TypeId structure, std::string name, FunctionSignature signature) {
    TypeDescriptor type = get(structure);
    if (type.kind != TypeKind::Structure) THROW(, "methods can only be attached to structure types")
    if (name.empty() || std::any_of(type.methods.begin(), type.methods.end(), [&](const TypeMethod &method) {
          return method.name == name && method.signature.parameters == signature.parameters &&
                 method.signature.variadic == signature.variadic;
        }))
      THROW(, "structure method name is empty or duplicated")
    type.methods.push_back({std::move(name), std::move(signature)});
    lexicon::Phrase language = languageRoot(*lexicon, languageAddress);
    store(exact(language, TypesName), type.name, type);
    store(exact(language, TypeIdsName), idKey(type.id), type);
  }

  ValueType TypeRegistry::abiType(TypeId id) const {
    const TypeDescriptor type = get(id);
    lexicon::Phrase language = languageRoot(*lexicon, languageAddress);
    lexicon::Phrase kinds = exact(language, AbiKindsName);
    lexicon::Phrase behavior = exact(kinds, std::string(1, static_cast<char>(type.kind)));
    if (behavior.isNull() || behavior.payloadSize() != sizeof(ValueKind))
      THROW(, "type has no phrase-defined ABI behavior: '" << type.name << "'")
    ValueKind abiKind;
    behavior.fetch(0, abiKind);
    return {type.name, abiKind, static_cast<std::uint16_t>(type.size * 8), type.pointerDepth};
  }

  std::vector<TypeDescriptor> TypeRegistry::types() const {
    lexicon::Phrase language = languageRoot(*lexicon, languageAddress);
    lexicon::Phrase names = exact(language, TypesName);
    const TypeId next = nextId(names);
    std::vector<TypeDescriptor> result(next);
    for (TypeId id = 1; id < next; ++id) result[id] = get(id);
    return result;
  }

  TypedValue::TypedValue(TypeId type, std::vector<std::uint8_t> bytes) : valueType(type), valueBytes(std::move(bytes)) {
    if (type == InvalidType) THROW(, "typed value requires a valid type")
  }

  TypedValue TypedValue::integer(TypeId type, std::uint64_t value, std::size_t bytes) {
    std::vector<std::uint8_t> result(bytes);
    for (std::size_t index = 0; index < bytes; ++index) result[index] = value >> (index * 8);
    return {type, std::move(result)};
  }

  TypedValue TypedValue::pointer(TypeId type, std::uintptr_t address, std::size_t bytes) {
    return integer(type, address, bytes);
  }

  TypeId TypedValue::type() const {
    return valueType;
  }
  std::span<const std::uint8_t> TypedValue::bytes() const {
    return valueBytes;
  }

  std::uint64_t TypedValue::asUnsigned() const {
    if (valueBytes.size() > sizeof(std::uint64_t)) THROW(, "typed value does not fit in 64 bits")
    std::uint64_t result = 0;
    for (std::size_t index = 0; index < valueBytes.size(); ++index)
      result |= static_cast<std::uint64_t>(valueBytes[index]) << (index * 8);
    return result;
  }
} // namespace compiler
