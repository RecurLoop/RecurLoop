#pragma once

#include <recurloop/AssemblerInstructions.hpp>

#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace compiler {
  class Module;
}

namespace context {
  class Context;
}

namespace lexicon {
  class Phrase;
}

namespace recurloop {
  enum class NativeFileKind : std::uint8_t { Object, Executable, Raw };

  struct NativeFileRequest {
    NativeFileKind kind = NativeFileKind::Object;
    std::string path;
    std::string entry;
    bool anonymous = false;
  };

  struct AssemblerInstruction {
    static constexpr std::uint32_t Magic = 0x524C4153;
    std::uint32_t magic = Magic;
    char mnemonic[16] = {};

    template <std::size_t N> constexpr AssemblerInstruction(const char (&name)[N]) {
      static_assert(N <= sizeof(mnemonic));
      for (std::size_t index = 0; index + 1 < N; ++index) mnemonic[index] = name[index];
    }
  };

  struct AssemblerSectionQualifier {
    enum class Kind : std::uint8_t { Flag, Type, Alignment };

    static constexpr std::uint32_t Magic = 0x524C5351;
    std::uint32_t magic = Magic;
    Kind kind = Kind::Flag;
    std::uint8_t reserved = 0;
    std::uint16_t value = 0;

    constexpr AssemblerSectionQualifier(Kind kind, std::uint16_t value = 0) : kind(kind), value(value) {}
  };

  namespace assembler::phrases {
    inline constexpr char COMPILED_SCOPE_SESSION[] = "\0compiled-scope-session";
    inline constexpr char OPERANDS[] = "assembler-operands";
    inline constexpr char OPERAND_COMPLETE[] = "assembler-operand-complete";
    inline constexpr char OPERAND_SIZE_WHITESPACE[] = "assembler-operand-size-whitespace";
    inline constexpr char OPERAND_SIZE_BRACKET[] = "assembler-operand-size-bracket";
    inline constexpr char MEMORY_EXPECT[] = "assembler-memory-expect";
    inline constexpr char MEMORY_REGISTER[] = "assembler-memory-register";
    inline constexpr char MEMORY_TERM[] = "assembler-memory-term";
    inline constexpr char MEMORY_SCALE[] = "assembler-memory-scale";
  } // namespace assembler::phrases

  // Boundary between the RecurLoop language runtime and the architecture-
  // independent machine-code encoder in compiler::Assembler.
  class Assembler {
  public:
    Assembler() = delete;

    static void registerActions(context::Context &context);

    static void scope(context::Context &context, lexicon::Phrase &invoked);
    static void outputBegin(context::Context &context, lexicon::Phrase &invoked);
    static void objectEnd(context::Context &context, lexicon::Phrase &invoked);
    static void executableEnd(context::Context &context, lexicon::Phrase &invoked);
    static void rawEnd(context::Context &context, lexicon::Phrase &invoked);
    static std::string prepareDefinitionName(context::Context &context, std::string name);
    static std::string dictionarySymbol(context::Context &context);
    static std::string definitionSymbol(context::Context &context);
    static bool hasNativeOutput(context::Context &context);
    static std::optional<NativeFileRequest> nativeFileRequest(context::Context &context);
    static void defineEntry(context::Context &context, compiler::Module &module, std::size_t offset);
    static void finalize(context::Context &context, lexicon::Phrase &invoked, compiler::Module &module);
    static void finalizeLlvm(context::Context &context, lexicon::Phrase &invoked,
                             std::span<const std::vector<std::uint8_t>> objects,
                             std::span<const std::string> providedSymbols, std::span<const std::string> imports);
    static std::uintptr_t nativeEntry(lexicon::Phrase &phrase);
    static void commitNative(context::Context &context, lexicon::Phrase &phrase);

    static void begin(context::Context &context, lexicon::Phrase &invoked);
    static void instruction(context::Context &context, lexicon::Phrase &invoked);
    static void operand(context::Context &context, lexicon::Phrase &invoked);
    static void operandSize(context::Context &context, lexicon::Phrase &invoked);
    static void operandWhitespace(context::Context &context, lexicon::Phrase &invoked);
    static void operandMemoryBegin(context::Context &context, lexicon::Phrase &invoked);
    static void operandMemoryOperator(context::Context &context, lexicon::Phrase &invoked);
    static void operandMemoryEnd(context::Context &context, lexicon::Phrase &invoked);
    static void operandSeparator(context::Context &context, lexicon::Phrase &invoked);
    static void operandComment(context::Context &context, lexicon::Phrase &invoked);
    static void operandDynamic(context::Context &context, lexicon::Phrase &invoked);
    static void invoke(context::Context &context, lexicon::Phrase &invoked);
    static void section(context::Context &context, lexicon::Phrase &invoked);
    static void customSection(context::Context &context, lexicon::Phrase &invoked);
    static void bytes(context::Context &context, lexicon::Phrase &invoked);
    static void reserve(context::Context &context, lexicon::Phrase &invoked);
    static void comment(context::Context &context, lexicon::Phrase &invoked);
    static void end(context::Context &context, lexicon::Phrase &invoked);
    static void unknown(context::Context &context, lexicon::Phrase &invoked);
    static void sourceEnd(context::Context &context);
  };
} // namespace recurloop
