#pragma once

#include <recurloop/Assembler.hpp>
#include <compiler/Assembler.hpp>
#include <compiler/Module.hpp>
#include <compiler/TypeSystem.hpp>
#include <utilities/Size.hpp>

#include <cstdint>
#include <string>
#include <type_traits>
#include <vector>

namespace recurloop {
  namespace phrases = assembler::phrases;

  struct CompiledScopeSessionData {
    Size lexiconCheckpoint = 0;
    Size codeStartBits = 0;
    Size keyStartBits = 0;
    Size referenceRootAddress = 0;
    Size invocationCount = 0;
    Size tailCallOpcodeOffset = 0;
    Size tailCallEnd = 0;
    bool tailCallEligible = false;
  };

  struct CompiledInvocationData {
    Size contextAddressPatchOffset = 0;
    Size phraseAddressPatchOffset = 0;
    Size trampolineAddressPatchOffset = 0;
    Size phraseAddress = 0;
    Size directEntry = 0;
    Size referenceBytes = 0;
    Size argumentCount = 0;
    Size line = 1;
    Size column = 1;
    bool nativeAbi = false;
  };

  struct CompiledArgumentData {
    compiler::TypeId type = compiler::InvalidType;
    std::uint64_t value = 0;
    Size bytes = 0;
  };

  enum class AssemblerOperandKind : std::uint8_t { EMPTY, REGISTER, MEMORY, IMMEDIATE, LABEL };

  struct AssemblerMemoryData {
    compiler::Assembler::Register base;
    compiler::Assembler::Register index;
    compiler::Assembler::Register pendingRegister;
    std::int64_t displacement = 0;
    std::int8_t termSign = 1;
    std::uint8_t scale = 1;
    std::uint8_t bits = 0;
    bool hasBase = false;
    bool hasIndex = false;
    bool hasPendingRegister = false;
    bool hasTerm = false;
    bool signExplicit = false;
  };

  struct AssemblerOperandData {
    AssemblerOperandKind kind = AssemblerOperandKind::EMPTY;
    compiler::Assembler::Register reg;
    AssemblerMemoryData memory;
    std::int64_t immediate = 0;
    Size labelBytes = 0;
  };

  struct AssemblerSessionData {
    Size lexiconCheckpoint = 0;
    Size codeStartBits = 0;
    Size keyStartBits = 0;
    Size referenceRootAddress = 0;
    Size invocationCount = 0;
    Size instructionLine = 1;
    Size instructionColumn = 1;
    Size instructionLexiconCheckpoint = 0;
    Size operandCount = 0;
    Size currentSection = compiler::Module::id(compiler::SectionKind::Text);
    bool instructionOpen = false;
    bool operandRequired = false;
    char mnemonic[16] = {};
    AssemblerOperandData operand;
  };

  struct AssemblerLabelData {
    bool defined = false;
    Size codeOffset = 0;
    Size section = compiler::Module::id(compiler::SectionKind::Text);
    Size referenceCount = 0;
  };

  struct AssemblerSourceData {
    Size line = 1;
    Size column = 1;
    Size pathBytes = 0;
  };

  struct AssemblerRelocationData {
    std::uint8_t kind = 0;
    Size patchOffset = 0;
    Size instructionEnd = 0;
    AssemblerSourceData source;
  };

  struct AssemblerInvocationData {
    Size contextAddressPatchOffset = 0;
    Size phraseAddressPatchOffset = 0;
    Size trampolineAddressPatchOffset = 0;
    Size referenceBytes = 0;
    bool nativeAbi = false;
    AssemblerSourceData source;
  };

  struct NativeImport {
    std::string name;
    std::uintptr_t address = 0;
  };

  struct NativeDefinition {
    compiler::Module module;
    std::vector<NativeImport> imports;
  };

  struct NativeActionData {
    std::uintptr_t entry = 0;
  };

  struct DeferredNativeActionData {
    Size symbolBytes = 0;
  };

  enum class NativeOutputKind : std::uint8_t { None, Object, Executable, Raw };

  struct NativeOutputData {
    Size pathBytes = 0;
    NativeOutputKind kind = NativeOutputKind::None;
    bool anonymous = false;
  };

  static_assert(std::is_trivially_copyable_v<CompiledScopeSessionData>);
  static_assert(std::is_trivially_copyable_v<CompiledInvocationData>);
  static_assert(std::is_trivially_copyable_v<CompiledArgumentData>);
  static_assert(std::is_trivially_copyable_v<AssemblerMemoryData>);
  static_assert(std::is_trivially_copyable_v<AssemblerOperandData>);
  static_assert(std::is_trivially_copyable_v<AssemblerSessionData>);
  static_assert(std::is_trivially_copyable_v<AssemblerLabelData>);
  static_assert(std::is_trivially_copyable_v<AssemblerSourceData>);
  static_assert(std::is_trivially_copyable_v<AssemblerRelocationData>);
  static_assert(std::is_trivially_copyable_v<AssemblerInvocationData>);
  static_assert(std::is_trivially_copyable_v<NativeOutputData>);
  static_assert(std::is_trivially_copyable_v<NativeActionData>);
  static_assert(std::is_trivially_copyable_v<DeferredNativeActionData>);

  static constexpr unsigned char ASSEMBLER_SESSION = 0;
  static constexpr unsigned char ASSEMBLER_DEFINITION = 1;
  static constexpr unsigned char ASSEMBLER_RELOCATION = 2;
  static constexpr unsigned char ASSEMBLER_INVOCATION = 3;
  static constexpr unsigned char ASSEMBLER_OPERAND = 4;
  static constexpr unsigned char COMPILED_INVOCATION = 5;
  static constexpr char NATIVE_OUTPUT_KEY[] = "\0native-output";
} // namespace recurloop
