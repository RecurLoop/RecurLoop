#include <compiler/LanguageImage.hpp>

#include <compiler/LanguageState.hpp>
#include <compiler/Module.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <array>
#include <limits>

namespace compiler {
  namespace {
    constexpr std::array<std::uint8_t, 8> Magic = {'R', 'L', 'L', 'A', 'N', 'G', 0, 1};

    class Writer {
    public:
      std::vector<std::uint8_t> bytes;
      void number(std::uint64_t value, std::size_t width) {
        for (std::size_t byte = 0; byte < width; ++byte) bytes.push_back(value >> (byte * 8));
      }
      void text(const std::string &value) {
        if (value.size() > std::numeric_limits<std::uint32_t>::max()) THROW(, "language image string is too large")
        number(value.size(), 4);
        bytes.insert(bytes.end(), value.begin(), value.end());
      }
      void strings(const std::vector<std::string> &values) {
        number(values.size(), 4);
        for (const std::string &value : values) text(value);
      }
    };

    class Reader {
    public:
      explicit Reader(std::span<const std::uint8_t> input) : input(input) {}
      std::uint64_t number(std::size_t width) {
        if (cursor > input.size() || width > input.size() - cursor) THROW(, "truncated language image")
        std::uint64_t result = 0;
        for (std::size_t byte = 0; byte < width; ++byte) result |= std::uint64_t{input[cursor++]} << (byte * 8);
        return result;
      }
      std::string text() {
        const std::size_t size = number(4);
        if (cursor > input.size() || size > input.size() - cursor) THROW(, "truncated language image string")
        std::string result(reinterpret_cast<const char *>(input.data() + cursor), size);
        cursor += size;
        return result;
      }
      std::vector<std::string> strings() {
        const std::size_t count = number(4);
        std::vector<std::string> result;
        result.reserve(count);
        for (std::size_t index = 0; index < count; ++index) result.push_back(text());
        return result;
      }
      bool done() const {
        return cursor == input.size();
      }

    private:
      std::span<const std::uint8_t> input;
      std::size_t cursor = 0;
    };

    void convention(Writer &writer, const CallingConvention &value) {
      writer.text(value.name);
      writer.strings(value.integerRegisters);
      writer.strings(value.floatingRegisters);
      writer.text(value.resultRegister);
      writer.text(value.floatingResultRegister);
      writer.number(value.stackAlignment, 8);
      writer.number(value.shadowSpace, 8);
      writer.number(value.stackGrowsDown, 1);
      writer.number(value.callerCleansStack, 1);
    }

    CallingConvention convention(Reader &reader) {
      CallingConvention result;
      result.name = reader.text();
      result.integerRegisters = reader.strings();
      result.floatingRegisters = reader.strings();
      result.resultRegister = reader.text();
      result.floatingResultRegister = reader.text();
      result.stackAlignment = reader.number(8);
      result.shadowSpace = reader.number(8);
      result.stackGrowsDown = reader.number(1) != 0;
      result.callerCleansStack = reader.number(1) != 0;
      Abi::validate(result);
      return result;
    }
  } // namespace

  std::vector<std::uint8_t> LanguageImage::encode(const LanguageState &language) {
    Writer writer;
    writer.bytes.insert(writer.bytes.end(), Magic.begin(), Magic.end());
    writer.number(Version, 4);
    const std::vector<TypeDescriptor> types = language.types.types();
    writer.number(types.size() - 1, 4);
    for (std::size_t index = 1; index < types.size(); ++index) {
      const TypeDescriptor &type = types[index];
      writer.text(type.name);
      writer.number(static_cast<std::uint8_t>(type.kind), 1);
      writer.number(type.size, 8);
      writer.number(type.alignment, 8);
      writer.number(type.isSigned, 1);
      writer.text(type.element == InvalidType ? std::string{} : language.types.get(type.element).name);
      writer.number(type.elementCount, 8);
      writer.number(type.pointerDepth, 2);
      writer.number(type.fields.size(), 4);
      for (const TypeField &field : type.fields) {
        writer.text(field.name);
        writer.text(language.types.get(field.type).name);
        writer.number(field.offset, 8);
      }
      if (type.kind == TypeKind::Function) {
        writer.number(type.parameterTypes.size(), 4);
        for (TypeId parameter : type.parameterTypes) writer.text(language.types.get(parameter).name);
        writer.text(language.types.get(type.resultType).name);
        writer.text(type.convention);
        writer.number(type.variadic, 1);
      }
    }

    std::vector<TypedFunction> functionValues = language.functions();
    std::vector<const TypedFunction *> functions;
    functions.reserve(functionValues.size());
    for (const TypedFunction &function : functionValues) functions.push_back(&function);
    std::sort(functions.begin(), functions.end(),
              [](const auto *left, const auto *right) { return left->signature.symbol < right->signature.symbol; });
    writer.number(functions.size(), 4);
    for (const TypedFunction *function : functions) {
      writer.text(function->name);
      writer.text(function->signature.symbol);
      writer.text(language.types.get(function->resultType).name);
      writer.number(function->parameterTypes.size(), 4);
      for (TypeId type : function->parameterTypes) writer.text(language.types.get(type).name);
      convention(writer, function->signature.convention);
      writer.number(function->imported, 1);
      writer.number(function->signature.variadic, 1);
    }

    std::vector<std::string> actions;
    for (const NativeModule &module : language.modules()) actions.push_back(module.symbol);
    std::sort(actions.begin(), actions.end());
    writer.strings(actions);
    return writer.bytes;
  }

  EmbeddedLanguage LanguageImage::decode(std::span<const std::uint8_t> bytes) {
    Reader reader(bytes);
    for (std::uint8_t expected : Magic)
      if (reader.number(1) != expected) THROW(, "invalid language image magic")
    if (reader.number(4) != Version) THROW(, "unsupported language image version")
    EmbeddedLanguage result;
    const std::size_t typeCount = reader.number(4);
    result.types.reserve(typeCount);
    for (std::size_t index = 0; index < typeCount; ++index) {
      EmbeddedType type;
      type.name = reader.text();
      type.kind = static_cast<TypeKind>(reader.number(1));
      type.size = reader.number(8);
      type.alignment = reader.number(8);
      type.isSigned = reader.number(1) != 0;
      type.element = reader.text();
      type.elementCount = reader.number(8);
      type.pointerDepth = reader.number(2);
      const std::size_t fieldCount = reader.number(4);
      type.fields.reserve(fieldCount);
      for (std::size_t field = 0; field < fieldCount; ++field)
        type.fields.push_back({reader.text(), reader.text(), reader.number(8)});
      if (type.kind == TypeKind::Function) {
        type.parameters = reader.strings();
        type.result = reader.text();
        type.convention = reader.text();
        type.variadic = reader.number(1) != 0;
      }
      result.types.push_back(std::move(type));
    }
    const std::size_t functionCount = reader.number(4);
    result.functions.reserve(functionCount);
    for (std::size_t index = 0; index < functionCount; ++index) {
      EmbeddedFunction function;
      function.name = reader.text();
      function.symbol = reader.text();
      function.result = reader.text();
      function.parameters = reader.strings();
      function.convention = convention(reader);
      function.imported = reader.number(1) != 0;
      function.variadic = reader.number(1) != 0;
      result.functions.push_back(std::move(function));
    }
    result.nativeActions = reader.strings();
    if (!reader.done()) THROW(, "language image contains trailing bytes")
    return result;
  }

  void LanguageImage::embed(const LanguageState &language, Module &module) {
    if (module.findSection(SectionName) != nullptr) THROW(, "module already contains a language image")
    const SectionId section =
        module.addSection(SectionName, SectionType::ProgramBits, SectionFlag::Alloc, alignof(std::uint64_t));
    const std::vector<std::uint8_t> bytes = encode(language);
    module.append(section, bytes, alignof(std::uint64_t));
  }
} // namespace compiler
