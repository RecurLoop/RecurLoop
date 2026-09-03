#include <compiler/Assembler.hpp>
#include <compiler/Abi.hpp>
#include <compiler/JitLinker.hpp>
#include <compiler/LanguageImage.hpp>
#include <compiler/LanguageState.hpp>
#include <compiler/Module.hpp>
#include <compiler/TypeSystem.hpp>
#include <recurloop/Recurloop.hpp>
#include <utilities/Exception.hpp>

#include <gtest/gtest.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <optional>
#include <string_view>

#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace {
  class LanguageHost : public recurloop::Recurloop {
  public:
    LanguageHost() {
      char executable[] = "Recurloop";
      char *arguments[] = {executable};
      initialize(1, arguments);
    }

    compiler::LanguageState language() {
      return context.language();
    }
  };

  class ModuleLinkerTesting : public testing::Test {
  protected:
    static constexpr std::size_t capacity = 4096;

    void SetUp() override {
      const int descriptor = static_cast<int>(syscall(SYS_memfd_create, "recurloop-module-test", 0));
      ASSERT_GE(descriptor, 0);
      ASSERT_EQ(ftruncate(descriptor, capacity), 0);

      writable = mmap(nullptr, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
      executable = mmap(nullptr, capacity, PROT_READ | PROT_EXEC, MAP_SHARED, descriptor, 0);
      close(descriptor);

      ASSERT_NE(writable, MAP_FAILED);
      ASSERT_NE(executable, MAP_FAILED);
      memory = JitMemory(writable, executable, capacity).clear();
    }

    void TearDown() override {
      if (writable != MAP_FAILED) munmap(writable, capacity);
      if (executable != MAP_FAILED) munmap(executable, capacity);
    }

    void *writable = MAP_FAILED;
    void *executable = MAP_FAILED;
    JitMemory memory;
  };

  extern "C" std::uint64_t importedValue() {
    return 73;
  }

  void *receivedContext = nullptr;
  std::uintptr_t receivedPhrase = 0;
  std::size_t receivedLine = 0;
  std::size_t receivedColumn = 0;

  extern "C" int importedInvoke(void *context, std::uintptr_t phrase, std::size_t line, std::size_t column) {
    receivedContext = context;
    receivedPhrase = phrase;
    receivedLine = line;
    receivedColumn = column;
    return 0;
  }

  std::uint64_t typedLeft = 0;
  std::uint64_t typedRight = 0;
  double typedWeight = 0;
  extern "C" void importedTyped(std::uint64_t left, std::uint64_t right, double weight) {
    typedLeft = left;
    typedRight = right;
    typedWeight = weight;
  }
} // namespace

TEST(ModuleTesting, AppendsAlignedSectionsAndRejectsInvalidDefinitions) {
  compiler::Module module;
  const std::array<std::uint8_t, 1> first = {0xaa};
  const std::array<std::uint8_t, 1> second = {0xbb};

  EXPECT_EQ(module.append(compiler::SectionKind::Text, first), 0);
  EXPECT_EQ(module.append(compiler::SectionKind::Text, second, 4), 4);
  EXPECT_EQ(module.section(compiler::SectionKind::Text).alignment, 4);
  EXPECT_EQ(module.section(compiler::SectionKind::Text).bytes,
            (std::vector<std::uint8_t>{0xaa, 0x00, 0x00, 0x00, 0xbb}));

  module.define("entry", compiler::SectionKind::Text, 0);
  EXPECT_NE(module.findSymbol("entry"), nullptr);
  EXPECT_THROW(module.define("entry", compiler::SectionKind::Text, 0), Exception);
  EXPECT_THROW(module.define("outside", compiler::SectionKind::Text, 6), Exception);
  EXPECT_THROW(module.append(compiler::SectionKind::Data, first, 3), Exception);
}

TEST(ModuleTesting, CreatesNamedSectionsAndReservesNoBitsStorage) {
  compiler::Module module;
  const compiler::SectionId metadata =
      module.addSection(".recurloop.types", compiler::SectionType::Note, compiler::SectionFlag::None, 8);
  const std::array<std::uint8_t, 3> bytes = {1, 2, 3};

  EXPECT_EQ(module.append(metadata, bytes), 0u);
  EXPECT_EQ(module.section(".recurloop.types").bytes, (std::vector<std::uint8_t>{1, 2, 3}));
  EXPECT_EQ(*module.findSection(".recurloop.types"), metadata);
  EXPECT_THROW(module.addSection(".recurloop.types"), Exception);

  EXPECT_EQ(module.reserve(compiler::SectionKind::Bss, 12, 8), 0u);
  EXPECT_EQ(module.reserve(compiler::SectionKind::Bss, 4, 16), 16u);
  EXPECT_EQ(module.section(compiler::SectionKind::Bss).memorySize, 20u);
  EXPECT_TRUE(module.section(compiler::SectionKind::Bss).bytes.empty());
  module.define("state", compiler::SectionKind::Bss, 16);
  EXPECT_THROW(module.append(compiler::SectionKind::Bss, bytes), Exception);
}

TEST(ModuleTesting, MergesStaticModulesAndAllowsDefinitionsToBeExcluded) {
  compiler::Module caller;
  const std::array<std::uint8_t, 5> call = {0xe8, 0, 0, 0, 0};
  caller.append(compiler::SectionKind::Text, call);
  caller.define("caller", compiler::SectionKind::Text, 0);
  caller.import("callee");
  caller.relocate(compiler::SectionKind::Text, 1, compiler::RelocationKind::PCRelative32, "callee", -4);

  compiler::Module dependency;
  const std::array<std::uint8_t, 1> body = {0xc3};
  dependency.append(compiler::SectionKind::Text, body, 16);
  dependency.define("callee", compiler::SectionKind::Text, 0);
  const compiler::SectionId metadata = dependency.addSection(".types", compiler::SectionType::Note);
  dependency.append(metadata, body);

  caller.merge(dependency);
  ASSERT_NE(caller.findSymbol("callee"), nullptr);
  EXPECT_FALSE(caller.findSymbol("callee")->imported);
  EXPECT_EQ(caller.section(".types").bytes, (std::vector<std::uint8_t>{0xc3}));
  EXPECT_TRUE(caller.removeSymbol("callee"));
  EXPECT_EQ(caller.findSymbol("callee"), nullptr);
  EXPECT_FALSE(caller.removeSymbol("callee"));
}

TEST(AbiTesting, ValidatesTypedCallsAndLowersCustomConventions) {
  compiler::FunctionSignature signature;
  signature.symbol = "walk";
  signature.parameters = {compiler::ValueType::pointer("Node", 2), compiler::ValueType::integer("count", 64),
                          compiler::ValueType::floating("weight", 64)};
  compiler::Abi::validateCall(signature, signature.parameters);
  EXPECT_THROW(compiler::Abi::validateCall(signature, {signature.parameters.front()}), Exception);
  EXPECT_THROW(compiler::Abi::validateCall(signature, {compiler::ValueType::pointer("Node", 1), signature.parameters[1],
                                                       signature.parameters[2]}),
               Exception);

  compiler::CallingConvention custom{"my-vector-call", {"r10"}, {"xmm4"}, "r11", "xmm5", 32, 64, true, false};
  signature.convention = custom;
  const std::vector<compiler::ArgumentLocation> locations = compiler::Abi::lowerArguments(signature);
  ASSERT_EQ(locations.size(), 3u);
  EXPECT_EQ(locations[0].registerName, "r10");
  EXPECT_EQ(locations[1].kind, compiler::ArgumentLocationKind::Stack);
  EXPECT_EQ(locations[1].stackOffset, 64u);
  EXPECT_EQ(locations[2].registerName, "xmm4");

  signature.parameters = {compiler::ValueType::integer("a", 64), compiler::ValueType::integer("b", 64),
                          compiler::ValueType::integer("c", 64)};
  signature.convention.integerRegisters.clear();
  signature.convention.shadowSpace = 16;
  signature.convention.stackGrowsDown = false;
  const std::vector<compiler::ArgumentLocation> upward = compiler::Abi::lowerArguments(signature);
  ASSERT_EQ(upward.size(), 3u);
  EXPECT_EQ(upward[0].stackOffset, 32u);
  EXPECT_EQ(upward[1].stackOffset, 24u);
  EXPECT_EQ(upward[2].stackOffset, 16u);
}

TEST(TypeSystemTesting, LaysOutStructuresArraysMethodsAndPointerChains) {
  LanguageHost host;
  compiler::TypeRegistry types = host.language().types;
  const compiler::TypeId u8 = types.find("u8");
  const compiler::TypeId i32 = types.find("i32");
  const compiler::TypeId i64 = types.find("i64");
  const compiler::TypeId tag = types.arrayOf(u8, 3);
  const std::array<compiler::FieldDeclaration, 3> fields = {compiler::FieldDeclaration{"tag", tag},
                                                            compiler::FieldDeclaration{"x", i32},
                                                            compiler::FieldDeclaration{"y", i64}};
  const compiler::TypeId point = types.defineStructure("Point", fields);
  const compiler::TypeDescriptor &layout = types.get(point);
  ASSERT_EQ(layout.fields.size(), 3u);
  EXPECT_EQ(layout.fields[0].offset, 0u);
  EXPECT_EQ(layout.fields[1].offset, 4u);
  EXPECT_EQ(layout.fields[2].offset, 8u);
  EXPECT_EQ(layout.size, 16u);
  EXPECT_EQ(layout.alignment, 8u);

  const compiler::TypeId pointer = types.pointerTo(point);
  const compiler::TypeId pointerPointer = types.pointerTo(pointer);
  EXPECT_EQ(types.get(pointer).pointerDepth, 1u);
  EXPECT_EQ(types.get(pointerPointer).pointerDepth, 2u);
  EXPECT_EQ(types.get(pointerPointer).element, pointer);

  const compiler::TypeId callback = types.functionOf(std::array{i64}, i32, "sysv-amd64");
  const compiler::TypeId sameCallback = types.functionOf(std::array{i64}, i32, "sysv-amd64");
  const compiler::TypeDescriptor callbackType = types.get(callback);
  EXPECT_EQ(callback, sameCallback);
  EXPECT_EQ(callbackType.kind, compiler::TypeKind::Function);
  EXPECT_EQ(callbackType.parameterTypes, (std::vector<compiler::TypeId>{i64}));
  EXPECT_EQ(callbackType.resultType, i32);
  EXPECT_EQ(callbackType.convention, "sysv-amd64");
  EXPECT_EQ(types.abiType(callback).kind, compiler::ValueKind::Pointer);

  compiler::FunctionSignature method;
  method.symbol = "Point:length";
  method.parameters = {types.abiType(pointer)};
  method.result = types.abiType(types.find("f64"));
  types.addMethod(point, "length", method);
  EXPECT_EQ(types.get(point).methods.front().signature.symbol, "Point:length");

  const compiler::TypedValue value = compiler::TypedValue::integer(i32, 0x12345678, 4);
  EXPECT_EQ(value.asUnsigned(), 0x12345678u);
  EXPECT_EQ(value.bytes()[0], 0x78u);
}

TEST(LanguageImageTesting, RoundTripsTypesFunctionsConventionsAndNativeActions) {
  LanguageHost host;
  compiler::LanguageState language = host.language();
  const compiler::TypeId point = language.types.defineStructure(
      "Point", std::array{compiler::FieldDeclaration{"x", language.types.find("i32")},
                          compiler::FieldDeclaration{"next", language.types.pointerTo(language.types.find("u8"))}});
  const compiler::TypeId callback =
      language.types.functionOf(std::array{language.types.find("i32")}, language.types.find("i64"), "sysv-amd64");
  compiler::CallingConvention custom{"vector-call", {"r10"}, {"xmm4"}, "r11", "xmm5", 32, 64, false, false};
  language.defineConvention(custom);
  compiler::TypedFunction function;
  function.signature.symbol = "Point:move";
  function.signature.convention = custom;
  function.parameterTypes = {language.types.pointerTo(point), language.types.find("f64")};
  function.resultType = language.types.find("i32");
  for (compiler::TypeId type : function.parameterTypes)
    function.signature.parameters.push_back(language.types.abiType(type));
  function.signature.result = language.types.abiType(function.resultType);
  language.declareFunction(function);
  compiler::Module action;
  const std::array<std::uint8_t, 1> code = {0xc3};
  action.append(compiler::SectionKind::Text, code);
  action.define("move", compiler::SectionKind::Text, 0);
  language.rememberModule("move", action);

  const std::vector<std::uint8_t> bytes = compiler::LanguageImage::encode(language);
  const compiler::EmbeddedLanguage decoded = compiler::LanguageImage::decode(bytes);
  const auto decodedPoint =
      std::find_if(decoded.types.begin(), decoded.types.end(), [](const auto &type) { return type.name == "Point"; });
  ASSERT_NE(decodedPoint, decoded.types.end());
  ASSERT_EQ(decodedPoint->fields.size(), 2u);
  EXPECT_EQ(decodedPoint->fields[1].type, "u8*");
  const std::string callbackName = language.types.get(callback).name;
  const auto decodedCallback = std::find_if(decoded.types.begin(), decoded.types.end(),
                                            [&](const auto &type) { return type.name == callbackName; });
  ASSERT_NE(decodedCallback, decoded.types.end());
  EXPECT_EQ(decodedCallback->parameters, (std::vector<std::string>{"i32"}));
  EXPECT_EQ(decodedCallback->result, "i64");
  EXPECT_EQ(decodedCallback->convention, "sysv-amd64");
  EXPECT_FALSE(decodedCallback->variadic);
  EXPECT_EQ(callbackName, decodedCallback->name);
  const auto decodedMove = std::find_if(decoded.functions.begin(), decoded.functions.end(),
                                        [](const auto &candidate) { return candidate.symbol == "Point:move"; });
  ASSERT_NE(decodedMove, decoded.functions.end());
  EXPECT_EQ(decodedMove->convention.integerRegisters, (std::vector<std::string>{"r10"}));
  EXPECT_EQ(decodedMove->convention.stackAlignment, 32u);
  EXPECT_FALSE(decodedMove->convention.stackGrowsDown);
  EXPECT_EQ(decoded.nativeActions, (std::vector<std::string>{"move"}));

  compiler::Module embedded;
  compiler::LanguageImage::embed(language, embedded);
  ASSERT_NE(embedded.findSection(compiler::LanguageImage::SectionName), nullptr);
  EXPECT_EQ(embedded.section(compiler::LanguageImage::SectionName).bytes, bytes);
}

TEST_F(ModuleLinkerTesting, ResolvesLocalPCRelativeCallsAndExecutesNativeCode) {
  compiler::Module module;
  const std::array<std::uint8_t, 15> code = {
      0xe8, 0x00, 0x00, 0x00, 0x00, // call helper
      0x83, 0xc0, 0x01,             // add eax, 1
      0xc3,                         // ret
      0xb8, 0x29, 0x00, 0x00, 0x00, // helper: mov eax, 41
      0xc3,                         // ret
  };

  module.append(compiler::SectionKind::Text, code, 16);
  module.define("entry", compiler::SectionKind::Text, 0);
  module.define("helper", compiler::SectionKind::Text, 9);
  module.relocate(compiler::SectionKind::Text, 1, compiler::RelocationKind::PCRelative32, "helper", -4);

  const compiler::JitImage image = compiler::JitLinker::link(module, memory);
  const auto entry = reinterpret_cast<std::uint64_t (*)()>(image.address("entry"));

  EXPECT_EQ(entry(), 42);
  EXPECT_EQ(image.offset(), 0);
  EXPECT_GE(image.size(), code.size());
}

TEST_F(ModuleLinkerTesting, AlignsASecondLinkedModuleWithoutMovingTheFirstOne) {
  compiler::Module first;
  const std::array<std::uint8_t, 1> firstCode = {0xc3};
  first.append(compiler::SectionKind::Text, firstCode);
  first.define("first", compiler::SectionKind::Text, 0);
  const compiler::JitImage firstImage = compiler::JitLinker::link(first, memory);

  compiler::Module second;
  const std::array<std::uint8_t, 6> secondCode = {0xb8, 0x2a, 0x00, 0x00, 0x00, 0xc3};
  second.append(compiler::SectionKind::Text, secondCode, 16);
  second.define("second", compiler::SectionKind::Text, 0);
  const compiler::JitImage secondImage = compiler::JitLinker::link(second, memory);
  const auto entry = reinterpret_cast<std::uint64_t (*)()>(secondImage.address("second"));

  EXPECT_EQ(firstImage.address("first"), reinterpret_cast<std::uintptr_t>(executable));
  EXPECT_EQ(secondImage.offset(), firstCode.size());
  EXPECT_EQ(secondImage.address("second") % 16, 0u);
  EXPECT_EQ(entry(), 42);
}

TEST_F(ModuleLinkerTesting, ResolvesReadOnlyAndWritableSectionSymbols) {
  compiler::Module module;
  const std::array<std::uint8_t, 23> code = {
      0x0f, 0xb6, 0x05, 0x00, 0x00, 0x00, 0x00,                   // movzx eax, byte ptr [rip + value]
      0x48, 0xb9, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // movabs rcx, counter
      0x83, 0x01, 0x01,                                           // add dword ptr [rcx], 1
      0x03, 0x01,                                                 // add eax, dword ptr [rcx]
      0xc3,                                                       // ret
  };
  const std::array<std::uint8_t, 1> value = {40};
  const std::array<std::uint8_t, 4> counter = {};

  module.append(compiler::SectionKind::Text, code, 16);
  module.append(compiler::SectionKind::ReadOnlyData, value, 8);
  module.append(compiler::SectionKind::Data, counter, 8);
  module.define("entry", compiler::SectionKind::Text, 0);
  module.define("value", compiler::SectionKind::ReadOnlyData, 0);
  module.define("counter", compiler::SectionKind::Data, 0);
  module.relocate(compiler::SectionKind::Text, 3, compiler::RelocationKind::PCRelative32, "value", -4);
  module.relocate(compiler::SectionKind::Text, 9, compiler::RelocationKind::Absolute64, "counter");

  const compiler::JitImage image = compiler::JitLinker::link(module, memory);
  const auto entry = reinterpret_cast<std::uint64_t (*)()>(image.address("entry"));

  EXPECT_EQ(entry(), 41);
  EXPECT_EQ(entry(), 42);
  EXPECT_EQ(*reinterpret_cast<const std::uint32_t *>(image.address("counter")), 2u);
}

TEST_F(ModuleLinkerTesting, LinksCustomAllocatedSectionsAndZeroFilledBss) {
  compiler::Module module;
  const compiler::SectionId constants =
      module.addSection(".constants.extra", compiler::SectionType::ProgramBits, compiler::SectionFlag::Alloc, 16);
  const std::array<std::uint8_t, 1> value = {99};
  module.append(constants, value);
  module.reserve(compiler::SectionKind::Bss, 8, 8);
  module.define("constant", constants, 0);
  module.define("zero", compiler::SectionKind::Bss, 0);

  const compiler::JitImage image = compiler::JitLinker::link(module, memory);
  EXPECT_EQ(*reinterpret_cast<const std::uint8_t *>(image.address("constant")), 99);
  EXPECT_EQ(*reinterpret_cast<const std::uint64_t *>(image.address("zero")), 0u);
}

TEST_F(ModuleLinkerTesting, ResolvesImportedAbsoluteSymbols) {
  compiler::Module module;
  const std::array<std::uint8_t, 21> code = {
      0x48, 0x83, 0xec, 0x08,                                     // sub rsp, 8
      0x48, 0xb8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // movabs rax, imported
      0xff, 0xd0,                                                 // call rax
      0x48, 0x83, 0xc4, 0x08,                                     // add rsp, 8
      0xc3,                                                       // ret
  };

  module.append(compiler::SectionKind::Text, code, 16);
  module.define("entry", compiler::SectionKind::Text, 0);
  module.import("imported-value");
  module.relocate(compiler::SectionKind::Text, 6, compiler::RelocationKind::Absolute64, "imported-value");

  const compiler::JitImage image =
      compiler::JitLinker::link(module, memory, [](std::string_view symbol) -> std::optional<std::uintptr_t> {
        if (symbol == "imported-value") return reinterpret_cast<std::uintptr_t>(&importedValue);
        return std::nullopt;
      });
  const auto entry = reinterpret_cast<std::uint64_t (*)()>(image.address("entry"));

  EXPECT_EQ(entry(), 73);
}

TEST_F(ModuleLinkerTesting, RoutesImportedPltCallsThroughNearbyStubs) {
  compiler::Module module;
  const std::array<std::uint8_t, 6> code = {
      0xe8, 0x00, 0x00, 0x00, 0x00, 0xc3,
  };
  module.append(compiler::SectionKind::Text, code, 16);
  module.define("entry", compiler::SectionKind::Text, 0);
  module.import("imported-value");
  module.relocate(compiler::SectionKind::Text, 1, compiler::RelocationKind::PLTRelative32, "imported-value", -4);

  const compiler::JitImage image =
      compiler::JitLinker::link(module, memory, [](std::string_view symbol) -> std::optional<std::uintptr_t> {
        if (symbol == "imported-value") return reinterpret_cast<std::uintptr_t>(&importedValue);
        return std::nullopt;
      });
  const auto entry = reinterpret_cast<std::uint64_t (*)()>(image.address("entry"));

  EXPECT_EQ(entry(), 73);
  EXPECT_GE(image.size(), code.size() + 16);
}

TEST_F(ModuleLinkerTesting, RelocatesEveryAddressInTheNativePhraseInvocationTemplate) {
  compiler::Assembler::PhraseInvocation invocation = compiler::Assembler::encodePhraseInvocation(17, 29);
  const auto placeholderIsZero = [&](std::size_t offset) {
    return std::all_of(invocation.code.begin() + offset, invocation.code.begin() + offset + sizeof(std::uintptr_t),
                       [](std::uint8_t byte) { return byte == 0; });
  };
  ASSERT_TRUE(placeholderIsZero(invocation.contextAddressPatchOffset));
  ASSERT_TRUE(placeholderIsZero(invocation.phraseAddressPatchOffset));
  ASSERT_TRUE(placeholderIsZero(invocation.trampolineAddressPatchOffset));

  invocation.code.push_back(0xc3);
  compiler::Module module;
  module.append(compiler::SectionKind::Text, invocation.code, 16);
  module.define("entry", compiler::SectionKind::Text, 0);
  module.import("context");
  module.import("phrase");
  module.import("trampoline");
  module.relocate(compiler::SectionKind::Text, invocation.contextAddressPatchOffset,
                  compiler::RelocationKind::Absolute64, "context");
  module.relocate(compiler::SectionKind::Text, invocation.phraseAddressPatchOffset,
                  compiler::RelocationKind::Absolute64, "phrase");
  module.relocate(compiler::SectionKind::Text, invocation.trampolineAddressPatchOffset,
                  compiler::RelocationKind::Absolute64, "trampoline");

  int contextValue = 0;
  constexpr std::uintptr_t phraseAddress = 0x12345678;
  const compiler::JitImage image =
      compiler::JitLinker::link(module, memory, [&](std::string_view symbol) -> std::optional<std::uintptr_t> {
        if (symbol == "context") return reinterpret_cast<std::uintptr_t>(&contextValue);
        if (symbol == "phrase") return phraseAddress;
        if (symbol == "trampoline") return reinterpret_cast<std::uintptr_t>(&importedInvoke);
        return std::nullopt;
      });

  receivedContext = nullptr;
  receivedPhrase = 0;
  receivedLine = 0;
  receivedColumn = 0;
  reinterpret_cast<void (*)()>(image.address("entry"))();

  EXPECT_EQ(receivedContext, &contextValue);
  EXPECT_EQ(receivedPhrase, phraseAddress);
  EXPECT_EQ(receivedLine, 17u);
  EXPECT_EQ(receivedColumn, 29u);
}

TEST_F(ModuleLinkerTesting, LowersTypedSystemVArgumentsIntoNativeCalls) {
  compiler::FunctionSignature signature;
  signature.symbol = "typed-target";
  signature.parameters = {compiler::ValueType::integer("u64", 64), compiler::ValueType::integer("u64", 64),
                          compiler::ValueType::floating("f64", 64)};
  const double weight = 3.5;
  std::uint64_t weightBits = 0;
  std::memcpy(&weightBits, &weight, sizeof(weight));
  const std::vector<compiler::TypedValue> arguments = {compiler::TypedValue::integer(1, 11, 8),
                                                       compiler::TypedValue::integer(1, 29, 8),
                                                       compiler::TypedValue::integer(1, weightBits, 8)};
  compiler::Assembler::NativeInvocation invocation = compiler::Assembler::encodeTypedInvocation(signature, arguments);
  invocation.code.push_back(0xc3);

  compiler::Module module;
  module.append(compiler::SectionKind::Text, invocation.code, 16);
  module.define("entry", compiler::SectionKind::Text, 0);
  std::vector<std::uint8_t> target;
  const auto little = [&](std::uintptr_t value) {
    for (std::size_t byte = 0; byte < sizeof(value); ++byte) target.push_back(value >> (byte * 8));
  };
  target.insert(target.end(), {0x48, 0xb8});
  little(reinterpret_cast<std::uintptr_t>(&typedLeft));
  target.insert(target.end(), {0x48, 0x89, 0x38});
  target.insert(target.end(), {0x48, 0xb8});
  little(reinterpret_cast<std::uintptr_t>(&typedRight));
  target.insert(target.end(), {0x48, 0x89, 0x30});
  target.insert(target.end(), {0x48, 0xb8});
  little(reinterpret_cast<std::uintptr_t>(&typedWeight));
  target.insert(target.end(), {0x66, 0x0f, 0xd6, 0x00, 0xc3});
  const std::size_t targetOffset = module.append(compiler::SectionKind::Text, target, 16);
  module.define(signature.symbol, compiler::SectionKind::Text, targetOffset);
  module.relocate(compiler::SectionKind::Text, invocation.targetPatchOffset, compiler::RelocationKind::PCRelative32,
                  signature.symbol, -4);
  const compiler::JitImage image = compiler::JitLinker::link(module, memory);

  typedLeft = typedRight = 0;
  typedWeight = 0;
  reinterpret_cast<void (*)()>(image.address("entry"))();
  EXPECT_EQ(typedLeft, 11u);
  EXPECT_EQ(typedRight, 29u);
  EXPECT_DOUBLE_EQ(typedWeight, 3.5);
}

TEST_F(ModuleLinkerTesting, RejectsUndeclaredAndUnresolvedSymbolsWithoutWritingMemory) {
  compiler::Module undeclared;
  const std::array<std::uint8_t, 8> placeholder = {};
  undeclared.append(compiler::SectionKind::Text, placeholder);
  undeclared.relocate(compiler::SectionKind::Text, 0, compiler::RelocationKind::Absolute64, "missing");

  EXPECT_THROW(compiler::JitLinker::link(undeclared, memory), Exception);
  EXPECT_EQ(memory.size(), 0);

  compiler::Module unresolved;
  unresolved.append(compiler::SectionKind::Text, placeholder);
  unresolved.import("missing");
  unresolved.relocate(compiler::SectionKind::Text, 0, compiler::RelocationKind::Absolute64, "missing");

  EXPECT_THROW(compiler::JitLinker::link(unresolved, memory), Exception);
  EXPECT_EQ(memory.size(), 0);
}
