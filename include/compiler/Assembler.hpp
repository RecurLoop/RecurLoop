#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace compiler {
  struct FunctionSignature;
  class TypedValue;
  class Assembler {
  public:
    struct Location {
      std::string path;
      std::size_t line = 1;
      std::size_t column = 1;
    };

    enum class RelocationKind : std::uint8_t { Relative32 };

    struct Relocation {
      std::string label;
      RelocationKind kind = RelocationKind::Relative32;
      std::size_t patchOffset = 0;
      std::size_t instructionEnd = 0;
      Location location;
    };

    struct Result {
      std::vector<std::uint8_t> code;
      std::vector<Relocation> relocations;
    };

    struct PhraseInvocation {
      std::vector<std::uint8_t> code;
      std::size_t contextAddressPatchOffset = 0;
      std::size_t phraseAddressPatchOffset = 0;
      std::size_t trampolineAddressPatchOffset = 0;
    };

    struct NativeInvocation {
      std::vector<std::uint8_t> code;
      std::size_t targetPatchOffset = 0;
      std::size_t instructionEnd = 0;
    };

    struct Register {
      std::uint8_t code = 0;
      std::uint8_t bits = 0;
      bool high = false;
      bool requiresRex = false;
    };

    struct Memory {
      std::optional<Register> base;
      std::optional<Register> index;
      std::uint8_t scale = 1;
      std::int64_t displacement = 0;
      std::uint8_t bits = 0;
    };

    struct Immediate {
      std::int64_t value = 0;
    };

    struct LabelOperand {
      std::string name;
    };

    using Operand = std::variant<Register, Memory, Immediate, LabelOperand>;

    struct Instruction {
      std::string mnemonic;
      std::vector<Operand> operands;
      Location location;
    };

    static Result encode(const std::string &mnemonic, const std::string &operands, const Location &location);
    static Result encode(Instruction instruction);
    static PhraseInvocation encodePhraseInvocation(std::size_t line, std::size_t column);
    static NativeInvocation encodeNativeInvocation();
    static NativeInvocation encodeTypedInvocation(const FunctionSignature &signature,
                                                   const std::vector<TypedValue> &arguments);

    static bool isIdentifier(const std::string &text);
    static bool isMnemonic(const std::string &text);

  private:
    static Operand parseOperand(const std::string &text, const Location &location);
    static Memory parseMemory(const std::string &text, std::uint8_t bits, const Location &location);
    static std::vector<std::uint8_t> encode(Instruction &instruction, std::vector<Relocation> &relocations);
  };
} // namespace compiler
