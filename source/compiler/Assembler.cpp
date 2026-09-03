#include <compiler/Assembler.hpp>
#include <compiler/AssemblerInstructions.hpp>
#include <compiler/Abi.hpp>
#include <compiler/TypeSystem.hpp>

#include <utilities/Exception.hpp>

#include <algorithm>
#include <array>
#include <charconv>
#include <cctype>
#include <limits>
#include <sstream>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace {
  using Location = compiler::Assembler::Location;

  [[noreturn]] void fail(const Location &location, const std::string &message) {
    const SourceLocation sourceLocation{location.path, location.line, location.column};
    THROW_AT(sourceLocation, "assembler: " << message)
  }

  std::string lower(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(),
                   [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
    return text;
  }

  std::string trim(std::string text) {
    const auto whitespace = [](unsigned char character) { return std::isspace(character); };
    const auto begin = std::find_if_not(text.begin(), text.end(), whitespace);
    const auto end = std::find_if_not(text.rbegin(), text.rend(), whitespace).base();
    return begin < end ? std::string(begin, end) : std::string();
  }

  std::vector<std::string> splitOperands(const std::string &text, const Location &location) {
    std::vector<std::string> result;
    std::size_t start = 0;
    int brackets = 0;
    char quote = 0;

    for (std::size_t i = 0; i < text.size(); ++i) {
      const char character = text[i];
      if (quote != 0) {
        if (character == '\\') {
          ++i;
        } else if (character == quote) {
          quote = 0;
        }
        continue;
      }

      if (character == '\'' || character == '"') {
        quote = character;
      } else if (character == '[') {
        ++brackets;
      } else if (character == ']') {
        if (--brackets < 0) fail(location, "unexpected ']'");
      } else if (character == ',' && brackets == 0) {
        std::string operand = trim(text.substr(start, i - start));
        if (operand.empty()) fail(location, "empty operand before ','");
        result.push_back(std::move(operand));
        start = i + 1;
      }
    }

    if (quote != 0) fail(location, "unterminated character literal");
    if (brackets != 0) fail(location, "unterminated memory operand");

    std::string operand = trim(text.substr(start));
    if (!operand.empty())
      result.push_back(std::move(operand));
    else if (!result.empty())
      fail(location, "empty operand after ','");
    return result;
  }

  std::int64_t parseInteger(const std::string &source, const Location &location) {
    std::string text = trim(source);
    if (text.size() >= 3 && text.front() == '\'' && text.back() == '\'') {
      if (text.size() == 3) return static_cast<unsigned char>(text[1]);
      if (text.size() == 4 && text[1] == '\\') {
        switch (text[2]) {
        case '0': return 0;
        case 'n': return '\n';
        case 'r': return '\r';
        case 't': return '\t';
        case '\\': return '\\';
        case '\'': return '\'';
        default: fail(location, "unsupported escape in character literal '" + text + "'");
        }
      }
      fail(location, "a character literal must contain exactly one byte");
    }

    bool negative = false;
    if (!text.empty() && (text.front() == '+' || text.front() == '-')) {
      negative = text.front() == '-';
      text.erase(text.begin());
    }

    int base = 10;
    if (text.starts_with("0x") || text.starts_with("0X")) {
      base = 16;
      text.erase(0, 2);
    } else if (text.starts_with("0b") || text.starts_with("0B")) {
      base = 2;
      text.erase(0, 2);
    } else if (text.starts_with("0o") || text.starts_with("0O")) {
      base = 8;
      text.erase(0, 2);
    }
    if (text.empty()) fail(location, "invalid immediate value '" + source + "'");

    std::uint64_t value = 0;
    const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value, base);
    if (error != std::errc() || end != text.data() + text.size())
      fail(location, "invalid immediate value '" + source + "'");

    if (negative) {
      constexpr std::uint64_t minimumMagnitude = std::uint64_t{1} << 63;
      if (value > minimumMagnitude) fail(location, "immediate value is out of range '" + source + "'");
      if (value == minimumMagnitude) return std::numeric_limits<std::int64_t>::min();
      return -static_cast<std::int64_t>(value);
    }
    return static_cast<std::int64_t>(value);
  }

  bool looksLikeInteger(const std::string &text) {
    if (text.empty()) return false;
    std::size_t offset = (text.front() == '+' || text.front() == '-') ? 1 : 0;
    return offset < text.size() && (std::isdigit(static_cast<unsigned char>(text[offset])) || text[offset] == '\'');
  }

  struct Emitter {
    std::vector<std::uint8_t> bytes;

    void byte(std::uint8_t value) {
      bytes.push_back(value);
    }

    void little(std::uint64_t value, std::size_t size) {
      for (std::size_t i = 0; i < size; ++i) byte(static_cast<std::uint8_t>(value >> (i * 8)));
    }
  };

  bool fitsValue(std::int64_t value, std::uint8_t bits) {
    if (bits == 64) return true;
    const std::int64_t signedMinimum = -(std::int64_t{1} << (bits - 1));
    const std::uint64_t unsignedMaximum = (std::uint64_t{1} << bits) - 1;
    return value >= signedMinimum && (value < 0 || static_cast<std::uint64_t>(value) <= unsignedMaximum);
  }

  bool fitsSigned(std::int64_t value, std::uint8_t bits) {
    if (bits == 64) return true;
    const std::int64_t minimum = -(std::int64_t{1} << (bits - 1));
    const std::int64_t maximum = (std::int64_t{1} << (bits - 1)) - 1;
    return value >= minimum && value <= maximum;
  }
} // namespace

namespace compiler {
  Assembler::NativeInvocation Assembler::encodeTypedInvocation(const FunctionSignature &signature,
                                                               const std::vector<TypedValue> &arguments) {
    std::vector<ValueType> argumentTypes;
    argumentTypes.reserve(arguments.size());
    for (std::size_t index = 0; index < arguments.size(); ++index) argumentTypes.push_back(signature.parameters.at(index));
    Abi::validateCall(signature, argumentTypes);
    const std::vector<ArgumentLocation> locations = Abi::lowerArguments(signature);

    Emitter output;
    const auto append = [&](const Result &encoded) {
      if (!encoded.relocations.empty()) fail({}, "typed ABI setup cannot contain symbol relocations");
      output.bytes.insert(output.bytes.end(), encoded.code.begin(), encoded.code.end());
    };
    const auto immediate = [](const TypedValue &value) {
      if (value.bytes().size() > sizeof(std::uint64_t)) fail({}, "typed ABI argument exceeds one register");
      return static_cast<std::int64_t>(value.asUnsigned());
    };

    output.byte(0x9c);
    output.byte(0x50); output.byte(0x51); output.byte(0x52); output.byte(0x56); output.byte(0x57);
    output.byte(0x41); output.byte(0x50); output.byte(0x41); output.byte(0x51);
    output.byte(0x41); output.byte(0x52); output.byte(0x41); output.byte(0x53);
    output.byte(0x41); output.byte(0x54);

    append(Assembler::encode("mov", "r12, rsp", {}));
    append(Assembler::encode("and", "rsp, -" + std::to_string(signature.convention.stackAlignment), {}));

    std::size_t required = signature.convention.shadowSpace;
    for (std::size_t index = 0; index < locations.size(); ++index)
      if (locations[index].kind == ArgumentLocationKind::Stack)
        required = std::max(required, locations[index].stackOffset + std::max<std::size_t>(8, arguments[index].bytes().size()));
    const std::size_t alignment = signature.convention.stackAlignment;
    if (required > std::numeric_limits<std::size_t>::max() - (alignment - 1))
      fail({}, "typed ABI call frame overflows");
    const std::size_t frame = (required + alignment - 1) & ~(alignment - 1);
    if (frame > std::numeric_limits<std::int32_t>::max()) fail({}, "typed ABI call frame is too large");
    if (frame != 0) append(Assembler::encode("sub", "rsp, " + std::to_string(frame), {}));

    for (std::size_t index = 0; index < arguments.size(); ++index) {
      const ArgumentLocation &location = locations[index];
      const ValueType &type = signature.parameters[index];
      const std::int64_t value = immediate(arguments[index]);
      if (location.kind == ArgumentLocationKind::Stack) {
        append(Assembler::encode("mov", "rax, " + std::to_string(value), {}));
        append(Assembler::encode("mov", "qword [rsp + " + std::to_string(location.stackOffset) + "], rax", {}));
      } else if (type.kind == ValueKind::FloatingPoint) {
        if (!location.registerName.starts_with("xmm")) fail({}, "floating ABI argument requires an XMM register");
        unsigned xmm = 0;
        const std::string number = location.registerName.substr(3);
        const auto [end, error] = std::from_chars(number.data(), number.data() + number.size(), xmm);
        if (error != std::errc() || end != number.data() + number.size() || xmm > 15)
          fail({}, "invalid XMM register in calling convention");
        append(Assembler::encode("mov", type.bits == 32 ? "eax, " + std::to_string(value)
                                                        : "rax, " + std::to_string(value), {}));
        output.byte(0x66);
        std::uint8_t rex = type.bits == 64 ? 0x48 : 0x40;
        if (xmm >= 8) rex |= 0x04;
        if (rex != 0x40) output.byte(rex);
        output.byte(0x0f); output.byte(0x6e);
        output.byte(static_cast<std::uint8_t>(0xc0 | ((xmm & 7) << 3)));
      } else {
        append(Assembler::encode("mov", location.registerName + ", " + std::to_string(value), {}));
      }
    }

    output.byte(0xe8);
    const std::size_t patch = output.bytes.size();
    output.little(0, sizeof(std::int32_t));
    const std::size_t instructionEnd = output.bytes.size();
    append(Assembler::encode("mov", "rsp, r12", {}));
    output.byte(0x41); output.byte(0x5c);
    output.byte(0x41); output.byte(0x5b); output.byte(0x41); output.byte(0x5a);
    output.byte(0x41); output.byte(0x59); output.byte(0x41); output.byte(0x58);
    output.byte(0x5f); output.byte(0x5e); output.byte(0x5a); output.byte(0x59); output.byte(0x58); output.byte(0x9d);
    return {std::move(output.bytes), patch, instructionEnd};
  }

  Assembler::NativeInvocation Assembler::encodeNativeInvocation() {
    Emitter output;
    // A native target already follows the module ABI. Caller-saved registers
    // belong to that ABI and must not be preserved by every call site.
    output.byte(0xe8);
    const std::size_t targetPatchOffset = output.bytes.size();
    output.little(0, sizeof(std::int32_t));
    const std::size_t instructionEnd = output.bytes.size();
    return {std::move(output.bytes), targetPatchOffset, instructionEnd};
  }

  Assembler::PhraseInvocation Assembler::encodePhraseInvocation(std::size_t line, std::size_t column) {
    static_assert(sizeof(std::uintptr_t) == sizeof(std::uint64_t),
                  "phrase invocation requires a 64-bit target architecture");

    Emitter output;

    if (line > std::numeric_limits<std::uint32_t>::max() || column > std::numeric_limits<std::uint32_t>::max())
      fail(Location{}, "phrase invocation source location exceeds 32 bits");

    // `invoke` is an ordinary ABI call. Caller-saved registers and flags may
    // be clobbered; preserving them at every site caused most of the old
    // 109-byte template. Align the stack before entering the C++ fallback.
    output.byte(0x48);
    output.byte(0x83);
    output.byte(0xec);
    output.byte(0x08); // sub rsp, 8

    output.byte(0x48);
    output.byte(0xbf); // movabs rdi, Context*
    const std::size_t contextAddressPatchOffset = output.bytes.size();
    output.little(0, sizeof(std::uint64_t));

    output.byte(0x48);
    output.byte(0xbe); // movabs rsi, Phrase address
    const std::size_t phraseAddressPatchOffset = output.bytes.size();
    output.little(0, sizeof(std::uint64_t));

    output.byte(0xba); // mov edx, source line
    output.little(line, sizeof(std::uint32_t));

    output.byte(0xb9); // mov ecx, source column
    output.little(column, sizeof(std::uint32_t));

    output.byte(0x48);
    output.byte(0xb8); // movabs rax, trampoline
    const std::size_t trampolineAddressPatchOffset = output.bytes.size();
    output.little(0, sizeof(std::uint64_t));

    output.byte(0xff);
    output.byte(0xd0); // call rax

    output.byte(0x48);
    output.byte(0x83);
    output.byte(0xc4);
    output.byte(0x08); // add rsp, 8

    // A non-zero result means that the trampoline captured an exception.
    // Return from the generated phrase; the Phrase elaboration/invocation
    // boundary will rethrow it from an ordinary C++ frame.
    output.byte(0x85);
    output.byte(0xc0); // test eax, eax
    output.byte(0x74); // jz success
    output.byte(0x01);
    output.byte(0xc3); // error: return to the Phrase boundary

    return {std::move(output.bytes), contextAddressPatchOffset, phraseAddressPatchOffset, trampolineAddressPatchOffset};
  }

  bool Assembler::isIdentifier(const std::string &text) {
    if (text.empty()) return false;
    const auto first = [](unsigned char character) {
      return std::isalpha(character) || character == '_' || character == '.' || character == '$';
    };
    const auto next = [&](unsigned char character) { return first(character) || std::isdigit(character); };
    return first(static_cast<unsigned char>(text.front())) &&
           std::all_of(text.begin() + 1, text.end(), [&](unsigned char character) { return next(character); });
  }

  bool Assembler::isMnemonic(const std::string &text) {
    static const std::unordered_set<std::string> mnemonics = {
#define ASSEMBLER_INSTRUCTION(Mnemonic, Name) #Mnemonic,
        ASSEMBLER_INSTRUCTIONS(ASSEMBLER_INSTRUCTION)
#undef ASSEMBLER_INSTRUCTION
            "invoke"};
    return mnemonics.contains(lower(text));
  }

  Assembler::Operand Assembler::parseOperand(const std::string &source, const Location &location) {
    static const std::unordered_map<std::string, Register> registers = [] {
      std::unordered_map<std::string, Register> result;
      const std::array<const char *, 8> byteLow = {"al", "cl", "dl", "bl", "spl", "bpl", "sil", "dil"};
      const std::array<const char *, 4> byteHigh = {"ah", "ch", "dh", "bh"};
      const std::array<const char *, 8> word = {"ax", "cx", "dx", "bx", "sp", "bp", "si", "di"};
      const std::array<const char *, 8> dword = {"eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"};
      const std::array<const char *, 8> qword = {"rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi"};
      for (std::uint8_t i = 0; i < 8; ++i) {
        result.emplace(byteLow[i], Register{i, 8, false, i >= 4});
        result.emplace(word[i], Register{i, 16, false, false});
        result.emplace(dword[i], Register{i, 32, false, false});
        result.emplace(qword[i], Register{i, 64, false, false});
      }
      for (std::uint8_t i = 0; i < 4; ++i)
        result.emplace(byteHigh[i], Register{static_cast<std::uint8_t>(i + 4), 8, true, false});
      for (std::uint8_t i = 8; i < 16; ++i) {
        result.emplace("r" + std::to_string(i) + "b", Register{i, 8, false, true});
        result.emplace("r" + std::to_string(i) + "w", Register{i, 16, false, false});
        result.emplace("r" + std::to_string(i) + "d", Register{i, 32, false, false});
        result.emplace("r" + std::to_string(i), Register{i, 64, false, false});
      }
      return result;
    }();

    std::string text = trim(source);
    const std::string lowered = lower(text);
    if (auto found = registers.find(lowered); found != registers.end()) return found->second;

    std::uint8_t memoryBits = 0;
    for (const auto &[prefix, bits] : std::array<std::pair<std::string_view, std::uint8_t>, 4>{
             std::pair{"byte", 8}, std::pair{"word", 16}, std::pair{"dword", 32}, std::pair{"qword", 64}}) {
      if (lowered.starts_with(prefix) && lowered.size() > prefix.size() &&
          std::isspace(static_cast<unsigned char>(lowered[prefix.size()]))) {
        memoryBits = bits;
        text = trim(text.substr(prefix.size()));
        break;
      }
    }
    if (!text.empty() && text.front() == '[') return parseMemory(text, memoryBits, location);
    if (memoryBits != 0) fail(location, "memory size prefix must be followed by '[...]'");

    if (looksLikeInteger(text)) return Immediate{parseInteger(text, location)};
    if (!isIdentifier(text)) fail(location, "invalid operand '" + source + "'");
    return LabelOperand{text};
  }

  Assembler::Memory Assembler::parseMemory(const std::string &source, std::uint8_t bits, const Location &location) {
    if (source.size() < 2 || source.front() != '[' || source.back() != ']')
      fail(location, "memory operand must end with ']': '" + source + "'");

    Memory memory;
    memory.bits = bits;
    std::string expression;
    for (char character : source.substr(1, source.size() - 2))
      if (!std::isspace(static_cast<unsigned char>(character))) expression.push_back(character);
    if (expression.empty()) fail(location, "empty memory operand");

    std::vector<std::pair<int, std::string>> terms;
    std::size_t start = 0;
    int sign = 1;
    if (expression.front() == '+' || expression.front() == '-') {
      sign = expression.front() == '-' ? -1 : 1;
      start = 1;
    }
    for (std::size_t i = start; i <= expression.size(); ++i) {
      if (i == expression.size() || expression[i] == '+' || expression[i] == '-') {
        if (i == start) fail(location, "empty term in memory operand '" + source + "'");
        terms.emplace_back(sign, expression.substr(start, i - start));
        if (i < expression.size()) sign = expression[i] == '-' ? -1 : 1;
        start = i + 1;
      }
    }

    for (const auto &[termSign, term] : terms) {
      const std::size_t star = term.find('*');
      std::string registerText = star == std::string::npos ? term : term.substr(0, star);
      Operand parsed = parseOperand(registerText, location);
      if (auto reg = std::get_if<Register>(&parsed)) {
        if (reg->bits != 64 || reg->high) fail(location, "memory addressing requires a 64-bit register");
        if (termSign < 0) fail(location, "a memory address register cannot be subtracted");
        if (star != std::string::npos) {
          if (term.find('*', star + 1) != std::string::npos) fail(location, "invalid scaled index '" + term + "'");
          const std::int64_t scale = parseInteger(term.substr(star + 1), location);
          if (scale != 1 && scale != 2 && scale != 4 && scale != 8) fail(location, "index scale must be 1, 2, 4, or 8");
          if (memory.index) fail(location, "memory operand has more than one index register");
          memory.index = *reg;
          memory.scale = static_cast<std::uint8_t>(scale);
        } else if (!memory.base) {
          memory.base = *reg;
        } else if (!memory.index) {
          if ((reg->code & 7) == 4) fail(location, "rsp/r12 cannot be used as an index register");
          memory.index = *reg;
        } else {
          fail(location, "memory operand has too many registers");
        }
      } else if (std::holds_alternative<Immediate>(parsed) && star == std::string::npos) {
        const std::int64_t displacement = std::get<Immediate>(parsed).value;
        if ((termSign > 0 && displacement > 0 &&
             memory.displacement > std::numeric_limits<std::int64_t>::max() - displacement) ||
            (termSign < 0 && displacement > 0 &&
             memory.displacement < std::numeric_limits<std::int64_t>::min() + displacement))
          fail(location, "memory displacement overflow");
        memory.displacement += termSign * displacement;
      } else {
        fail(location, "invalid memory term '" + term + "'");
      }
    }

    if (!memory.base && !memory.index && !fitsSigned(memory.displacement, 32))
      fail(location, "absolute address does not fit a 32-bit displacement");
    if (memory.index && (memory.index->code & 7) == 4) fail(location, "rsp/r12 cannot be used as an index register");
    return memory;
  }

  Assembler::Result Assembler::encode(const std::string &mnemonicSource, const std::string &operandSource,
                                      const Location &location) {
    const std::string mnemonic = lower(mnemonicSource);
    if (!isMnemonic(mnemonic)) fail(location, "unknown instruction '" + mnemonicSource + "'");

    Instruction instruction;
    instruction.mnemonic = mnemonic;
    instruction.location = location;
    for (const std::string &operand : splitOperands(operandSource, location))
      instruction.operands.push_back(parseOperand(operand, location));

    return encode(std::move(instruction));
  }

  Assembler::Result Assembler::encode(Instruction instruction) {
    const std::string mnemonicSource = instruction.mnemonic;
    instruction.mnemonic = lower(std::move(instruction.mnemonic));
    if (!isMnemonic(instruction.mnemonic)) fail(instruction.location, "unknown instruction '" + mnemonicSource + "'");

    Result result;
    result.code = encode(instruction, result.relocations);
    return result;
  }

  std::vector<std::uint8_t> Assembler::encode(Instruction &instruction, std::vector<Relocation> &relocations) {
    Emitter output;

    auto operandBits = [](const Operand &operand) -> std::uint8_t {
      if (auto reg = std::get_if<Register>(&operand)) return reg->bits;
      if (auto memory = std::get_if<Memory>(&operand)) return memory->bits;
      return 0;
    };

    auto requireCount = [](const Instruction &instruction, std::size_t count) {
      if (instruction.operands.size() != count)
        fail(instruction.location, "'" + instruction.mnemonic + "' expects " + std::to_string(count) +
                                       (count == 1 ? " operand" : " operands") + ", got " +
                                       std::to_string(instruction.operands.size()));
    };

    struct EncodedRM {
      std::uint8_t modrm = 0;
      std::optional<std::uint8_t> sib;
      std::uint8_t displacementBytes = 0;
      std::int64_t displacement = 0;
      bool rexB = false;
      bool rexX = false;
      bool requiresRex = false;
      bool highByte = false;
    };

    auto makeRM = [&](const Operand &operand, std::uint8_t field, const Instruction &instruction) {
      EncodedRM encoded;
      if (auto reg = std::get_if<Register>(&operand)) {
        encoded.modrm = static_cast<std::uint8_t>(0xc0 | ((field & 7) << 3) | (reg->code & 7));
        encoded.rexB = reg->code >= 8;
        encoded.requiresRex = reg->requiresRex;
        encoded.highByte = reg->high;
        return encoded;
      }

      const auto memory = std::get_if<Memory>(&operand);
      if (!memory) fail(instruction.location, "expected a register or memory operand");
      const bool hasBase = memory->base.has_value();
      const bool hasIndex = memory->index.has_value();
      const std::uint8_t baseLow = hasBase ? memory->base->code & 7 : 5;
      const bool needsSib = hasIndex || !hasBase || baseLow == 4;

      std::uint8_t mode = 0;
      if (!hasBase) {
        mode = 0;
        encoded.displacementBytes = 4;
      } else if (memory->displacement == 0 && baseLow != 5) {
        mode = 0;
      } else if (memory->displacement >= -128 && memory->displacement <= 127) {
        mode = 1;
        encoded.displacementBytes = 1;
      } else if (fitsSigned(memory->displacement, 32)) {
        mode = 2;
        encoded.displacementBytes = 4;
      } else {
        fail(instruction.location, "memory displacement does not fit 32 bits");
      }

      encoded.modrm = static_cast<std::uint8_t>((mode << 6) | ((field & 7) << 3) | (needsSib ? 4 : baseLow));
      if (needsSib) {
        std::uint8_t scaleBits = 0;
        if (memory->scale == 2)
          scaleBits = 1;
        else if (memory->scale == 4)
          scaleBits = 2;
        else if (memory->scale == 8)
          scaleBits = 3;
        const std::uint8_t index = hasIndex ? memory->index->code & 7 : 4;
        encoded.sib = static_cast<std::uint8_t>((scaleBits << 6) | (index << 3) | baseLow);
      }
      encoded.displacement = memory->displacement;
      encoded.rexB = hasBase && memory->base->code >= 8;
      encoded.rexX = hasIndex && memory->index->code >= 8;
      return encoded;
    };

    auto emitRM = [&](const Instruction &instruction, std::initializer_list<std::uint8_t> opcodes, std::uint8_t field,
                      const Register *fieldRegister, const Operand &rm, std::uint8_t bits) {
      if (bits != 8 && bits != 16 && bits != 32 && bits != 64)
        fail(instruction.location, "cannot infer operand size; use byte/word/dword/qword before memory");
      EncodedRM encoded = makeRM(rm, field, instruction);
      const bool rexR = field >= 8;
      const bool rexW = bits == 64;
      const bool fieldNeedsRex = fieldRegister && fieldRegister->requiresRex;
      const bool fieldHigh = fieldRegister && fieldRegister->high;
      const bool rex = rexW || rexR || encoded.rexX || encoded.rexB || encoded.requiresRex || fieldNeedsRex;
      if ((fieldHigh || encoded.highByte) && rex)
        fail(instruction.location, "ah/ch/dh/bh cannot be encoded with a REX prefix");
      if (bits == 16) output.byte(0x66);
      if (rex)
        output.byte(static_cast<std::uint8_t>(0x40 | (rexW ? 8 : 0) | (rexR ? 4 : 0) | (encoded.rexX ? 2 : 0) |
                                              (encoded.rexB ? 1 : 0)));
      for (std::uint8_t opcode : opcodes) output.byte(opcode);
      output.byte(encoded.modrm);
      if (encoded.sib) output.byte(*encoded.sib);
      output.little(static_cast<std::uint64_t>(encoded.displacement), encoded.displacementBytes);
    };

    auto inferPairBits = [&](std::vector<Operand> &operands, const Instruction &instruction) {
      std::uint8_t left = operandBits(operands[0]);
      std::uint8_t right = operandBits(operands[1]);
      if (left == 0 && right != 0)
        if (auto memory = std::get_if<Memory>(&operands[0])) memory->bits = right;
      if (right == 0 && left != 0)
        if (auto memory = std::get_if<Memory>(&operands[1])) memory->bits = left;
      left = operandBits(operands[0]);
      right = operandBits(operands[1]);
      if (left != 0 && right != 0 && left != right) fail(instruction.location, "operand sizes do not match");
      return left != 0 ? left : right;
    };

    auto emitImmediate = [&](const Instruction &instruction, std::int64_t value, std::uint8_t bits) {
      if (!fitsValue(value, bits))
        fail(instruction.location, "immediate value does not fit " + std::to_string(bits) + " bits");
      output.little(static_cast<std::uint64_t>(value), bits / 8);
    };

    auto emitSignedImmediate = [&](const Instruction &instruction, std::int64_t value, std::uint8_t bits) {
      if (!fitsSigned(value, bits))
        fail(instruction.location, "immediate value does not fit signed " + std::to_string(bits) + " bits");
      output.little(static_cast<std::uint64_t>(value), bits / 8);
    };

    auto emitRelative = [&](const Instruction &instruction, const LabelOperand &operand) {
      const std::size_t patchOffset = output.bytes.size();
      output.little(0, 4);
      relocations.push_back(
          {operand.name, RelocationKind::Relative32, patchOffset, output.bytes.size(), instruction.location});
    };

    for (bool once = true; once; once = false) {
      std::vector<Operand> operands = instruction.operands;
      const std::string &name = instruction.mnemonic;

      if (name == "nop" || name == "ret" || name == "leave" || name == "syscall" || name == "int3" || name == "ud2" ||
          name == "hlt" || name == "clc" || name == "stc" || name == "cmc" || name == "cld" || name == "std" ||
          name == "cli" || name == "sti" || name == "pushfq" || name == "popfq" || name == "cdq" || name == "cqo" ||
          name == "cpuid" || name == "rdtsc") {
        if (name == "nop" && operands.size() == 1) {
          const std::uint8_t bits = operandBits(operands[0]);
          if (bits == 8) fail(instruction.location, "'nop' operand cannot be 8-bit");
          emitRM(instruction, {0x0f, 0x1f}, 0, nullptr, operands[0], bits);
          continue;
        }
        if (name == "ret" && operands.size() == 1) {
          const auto immediate = std::get_if<Immediate>(&operands[0]);
          if (!immediate) fail(instruction.location, "'ret' operand must be an immediate");
          output.byte(0xc2);
          emitImmediate(instruction, immediate->value, 16);
          continue;
        }
        requireCount(instruction, 0);
        if (name == "nop")
          output.byte(0x90);
        else if (name == "ret")
          output.byte(0xc3);
        else if (name == "leave")
          output.byte(0xc9);
        else if (name == "syscall") {
          output.byte(0x0f);
          output.byte(0x05);
        } else if (name == "int3")
          output.byte(0xcc);
        else if (name == "ud2") {
          output.byte(0x0f);
          output.byte(0x0b);
        } else if (name == "clc")
          output.byte(0xf8);
        else if (name == "stc")
          output.byte(0xf9);
        else if (name == "cmc")
          output.byte(0xf5);
        else if (name == "cld")
          output.byte(0xfc);
        else if (name == "std")
          output.byte(0xfd);
        else if (name == "cli")
          output.byte(0xfa);
        else if (name == "sti")
          output.byte(0xfb);
        else if (name == "pushfq")
          output.byte(0x9c);
        else if (name == "popfq")
          output.byte(0x9d);
        else if (name == "cdq")
          output.byte(0x99);
        else if (name == "cqo") {
          output.byte(0x48);
          output.byte(0x99);
        } else if (name == "cpuid") {
          output.byte(0x0f);
          output.byte(0xa2);
        } else if (name == "rdtsc") {
          output.byte(0x0f);
          output.byte(0x31);
        } else
          output.byte(0xf4);
        continue;
      }

      if (name == "int") {
        requireCount(instruction, 1);
        const auto immediate = std::get_if<Immediate>(&operands[0]);
        if (!immediate) fail(instruction.location, "'int' operand must be an immediate");
        output.byte(0xcd);
        emitImmediate(instruction, immediate->value, 8);
        continue;
      }

      static const std::unordered_map<std::string, std::uint8_t> conditions = {
          {"jo", 0},   {"jno", 1},  {"jb", 2},   {"jc", 2},   {"jnae", 2}, {"jae", 3},  {"jnb", 3}, {"jnc", 3},
          {"je", 4},   {"jz", 4},   {"jne", 5},  {"jnz", 5},  {"jbe", 6},  {"jna", 6},  {"ja", 7},  {"jnbe", 7},
          {"js", 8},   {"jns", 9},  {"jpe", 10}, {"jp", 10},  {"jpo", 11}, {"jnp", 11}, {"jl", 12}, {"jnge", 12},
          {"jge", 13}, {"jnl", 13}, {"jle", 14}, {"jng", 14}, {"jg", 15},  {"jnle", 15}};
      if (name == "jmp" || name == "call" || conditions.contains(name)) {
        requireCount(instruction, 1);
        if (auto target = std::get_if<LabelOperand>(&operands[0])) {
          if (name == "jmp")
            output.byte(0xe9);
          else if (name == "call")
            output.byte(0xe8);
          else {
            output.byte(0x0f);
            output.byte(static_cast<std::uint8_t>(0x80 + conditions.at(name)));
          }
          emitRelative(instruction, *target);
        } else {
          if (conditions.contains(name)) fail(instruction.location, "conditional branch target must be a label");
          const std::uint8_t bits = operandBits(operands[0]);
          if (bits != 64) fail(instruction.location, "indirect branch operand must be 64-bit");
          emitRM(instruction, {0xff}, name == "call" ? 2 : 4, nullptr, operands[0], 64);
        }
        continue;
      }

      if (name == "push" || name == "pop") {
        requireCount(instruction, 1);
        if (auto reg = std::get_if<Register>(&operands[0])) {
          if (reg->bits != 16 && reg->bits != 64)
            fail(instruction.location, "'" + name + "' register must be 16-bit or 64-bit");
          if (reg->bits == 16) output.byte(0x66);
          if (reg->code >= 8) output.byte(0x41);
          output.byte(static_cast<std::uint8_t>((name == "push" ? 0x50 : 0x58) + (reg->code & 7)));
        } else if (auto immediate = std::get_if<Immediate>(&operands[0]); immediate && name == "push") {
          output.byte(0x68);
          emitSignedImmediate(instruction, immediate->value, 32);
        } else {
          const std::uint8_t bits = operandBits(operands[0]);
          if (bits != 16 && bits != 64)
            fail(instruction.location, "'" + name + "' memory operand must be word or qword");
          emitRM(instruction, {static_cast<std::uint8_t>(name == "push" ? 0xff : 0x8f)}, name == "push" ? 6 : 0,
                 nullptr, operands[0], bits);
        }
        continue;
      }

      if (name == "mov") {
        requireCount(instruction, 2);
        if (auto destination = std::get_if<Register>(&operands[0])) {
          if (auto immediate = std::get_if<Immediate>(&operands[1])) {
            if (destination->bits == 16) output.byte(0x66);
            const bool rex = destination->bits == 64 || destination->code >= 8 || destination->requiresRex;
            if (destination->high && rex)
              fail(instruction.location, "ah/ch/dh/bh cannot be an immediate destination with a REX prefix");
            if (rex)
              output.byte(static_cast<std::uint8_t>(0x40 | (destination->bits == 64 ? 8 : 0) |
                                                    (destination->code >= 8 ? 1 : 0)));
            output.byte(static_cast<std::uint8_t>((destination->bits == 8 ? 0xb0 : 0xb8) + (destination->code & 7)));
            emitImmediate(instruction, immediate->value, destination->bits);
            continue;
          }
        }

        const std::uint8_t bits = inferPairBits(operands, instruction);
        if (auto destination = std::get_if<Register>(&operands[0])) {
          if (!std::holds_alternative<Register>(operands[1]) && !std::holds_alternative<Memory>(operands[1]))
            fail(instruction.location, "source operand of 'mov' must be register, memory, or immediate");
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0x8a : 0x8b)}, destination->code, destination,
                 operands[1], bits);
        } else if (std::holds_alternative<Memory>(operands[0])) {
          if (auto source = std::get_if<Register>(&operands[1])) {
            emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0x88 : 0x89)}, source->code, source, operands[0],
                   bits);
          } else if (auto immediate = std::get_if<Immediate>(&operands[1])) {
            emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0xc6 : 0xc7)}, 0, nullptr, operands[0], bits);
            if (bits == 64)
              emitSignedImmediate(instruction, immediate->value, 32);
            else
              emitImmediate(instruction, immediate->value, bits);
          } else {
            fail(instruction.location, "invalid source operand for 'mov'");
          }
        } else {
          fail(instruction.location, "destination operand of 'mov' must be register or memory");
        }
        continue;
      }

      if (name == "lea") {
        requireCount(instruction, 2);
        auto destination = std::get_if<Register>(&operands[0]);
        auto source = std::get_if<Memory>(&operands[1]);
        if (!destination || !source) fail(instruction.location, "'lea' expects register, memory");
        if (destination->bits == 8) fail(instruction.location, "'lea' destination cannot be 8-bit");
        emitRM(instruction, {0x8d}, destination->code, destination, operands[1], destination->bits);
        continue;
      }

      if (name == "movzx" || name == "movsx" || name == "movsxd") {
        requireCount(instruction, 2);
        auto destination = std::get_if<Register>(&operands[0]);
        if (!destination) fail(instruction.location, "'" + name + "' destination must be a register");
        const std::uint8_t sourceBits = operandBits(operands[1]);
        if (name == "movsxd") {
          if (destination->bits != 64 || sourceBits != 32)
            fail(instruction.location, "'movsxd' expects a 64-bit register and a 32-bit source");
          emitRM(instruction, {0x63}, destination->code, destination, operands[1], 64);
        } else {
          if ((sourceBits != 8 && sourceBits != 16) || destination->bits <= sourceBits)
            fail(instruction.location, "'" + name + "' requires an 8/16-bit source and a wider register");
          const std::uint8_t opcode = name == "movzx" ? (sourceBits == 8 ? 0xb6 : 0xb7)
                                                       : (sourceBits == 8 ? 0xbe : 0xbf);
          emitRM(instruction, {0x0f, opcode}, destination->code, destination, operands[1], destination->bits);
        }
        continue;
      }

      if (name == "bswap") {
        requireCount(instruction, 1);
        const auto reg = std::get_if<Register>(&operands[0]);
        if (!reg || (reg->bits != 32 && reg->bits != 64))
          fail(instruction.location, "'bswap' expects a 32-bit or 64-bit register");
        if (reg->bits == 64 || reg->code >= 8)
          output.byte(static_cast<std::uint8_t>(0x40 | (reg->bits == 64 ? 8 : 0) | (reg->code >= 8 ? 1 : 0)));
        output.byte(0x0f);
        output.byte(static_cast<std::uint8_t>(0xc8 + (reg->code & 7)));
        continue;
      }

      static const std::unordered_map<std::string, std::array<std::uint8_t, 5>> binary = {
          {"add", {0x00, 0x01, 0x02, 0x03, 0}}, {"or", {0x08, 0x09, 0x0a, 0x0b, 1}},
          {"adc", {0x10, 0x11, 0x12, 0x13, 2}}, {"sbb", {0x18, 0x19, 0x1a, 0x1b, 3}},
          {"and", {0x20, 0x21, 0x22, 0x23, 4}}, {"sub", {0x28, 0x29, 0x2a, 0x2b, 5}},
          {"xor", {0x30, 0x31, 0x32, 0x33, 6}}, {"cmp", {0x38, 0x39, 0x3a, 0x3b, 7}}};
      if (binary.contains(name)) {
        requireCount(instruction, 2);
        const std::uint8_t bits = inferPairBits(operands, instruction);
        const auto &opcodes = binary.at(name);
        if (auto immediate = std::get_if<Immediate>(&operands[1])) {
          if (!std::holds_alternative<Register>(operands[0]) && !std::holds_alternative<Memory>(operands[0]))
            fail(instruction.location, "immediate destination is not allowed");
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0x80 : 0x81)}, opcodes[4], nullptr, operands[0],
                 bits);
          if (bits == 64)
            emitSignedImmediate(instruction, immediate->value, 32);
          else
            emitImmediate(instruction, immediate->value, bits);
        } else if (auto destination = std::get_if<Register>(&operands[0])) {
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? opcodes[2] : opcodes[3])}, destination->code,
                 destination, operands[1], bits);
        } else if (auto source = std::get_if<Register>(&operands[1])) {
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? opcodes[0] : opcodes[1])}, source->code, source,
                 operands[0], bits);
        } else {
          fail(instruction.location, "memory-to-memory operation is not encodable");
        }
        continue;
      }

      if (name == "test") {
        requireCount(instruction, 2);
        const std::uint8_t bits = inferPairBits(operands, instruction);
        if (auto immediate = std::get_if<Immediate>(&operands[1])) {
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0xf6 : 0xf7)}, 0, nullptr, operands[0], bits);
          if (bits == 64)
            emitSignedImmediate(instruction, immediate->value, 32);
          else
            emitImmediate(instruction, immediate->value, bits);
        } else if (auto source = std::get_if<Register>(&operands[1])) {
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0x84 : 0x85)}, source->code, source, operands[0],
                 bits);
        } else {
          fail(instruction.location, "'test' expects register/memory, register/immediate");
        }
        continue;
      }

      if (name == "imul") {
        if (operands.size() == 1) {
          const std::uint8_t bits = operandBits(operands[0]);
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0xf6 : 0xf7)}, 5, nullptr, operands[0], bits);
          continue;
        }

        if (operands.size() != 2 && operands.size() != 3)
          fail(instruction.location, "'imul' expects 1, 2, or 3 operands, got " + std::to_string(operands.size()));

        auto destination = std::get_if<Register>(&operands[0]);
        if (!destination) fail(instruction.location, "multi-operand 'imul' destination must be a register");

        if (operands.size() == 2 && !std::holds_alternative<Immediate>(operands[1])) {
          const std::uint8_t bits = inferPairBits(operands, instruction);
          if (bits == 8) fail(instruction.location, "multi-operand 'imul' does not support 8-bit operands");
          emitRM(instruction, {0x0f, 0xaf}, destination->code, destination, operands[1], bits);
          continue;
        }

        const Operand &source = operands.size() == 2 ? operands[0] : operands[1];
        const auto immediate = std::get_if<Immediate>(&operands.back());
        if (!immediate) fail(instruction.location, "last operand of multi-operand 'imul' must be an immediate");

        std::vector<Operand> pair = {operands[0], source};
        const std::uint8_t bits = inferPairBits(pair, instruction);
        if (bits == 8) fail(instruction.location, "multi-operand 'imul' does not support 8-bit operands");
        emitRM(instruction, {0x69}, destination->code, destination, source, bits);
        if (bits == 64)
          emitSignedImmediate(instruction, immediate->value, 32);
        else
          emitImmediate(instruction, immediate->value, bits);
        continue;
      }

      if (name == "mul" || name == "div" || name == "idiv") {
        requireCount(instruction, 1);
        const std::uint8_t bits = operandBits(operands[0]);
        const std::uint8_t extension = name == "mul" ? 4 : name == "div" ? 6 : 7;
        emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0xf6 : 0xf7)}, extension, nullptr, operands[0], bits);
        continue;
      }

      if (name == "inc" || name == "dec" || name == "not" || name == "neg") {
        requireCount(instruction, 1);
        const std::uint8_t bits = operandBits(operands[0]);
        const std::uint8_t extension = name == "inc" ? 0 : name == "dec" ? 1 : name == "not" ? 2 : 3;
        emitRM(instruction,
               {static_cast<std::uint8_t>(bits == 8 ? (extension < 2 ? 0xfe : 0xf6) : (extension < 2 ? 0xff : 0xf7))},
               extension, nullptr, operands[0], bits);
        continue;
      }

      if (name == "rol" || name == "ror" || name == "shl" || name == "sal" || name == "shr" || name == "sar") {
        if (operands.size() != 1 && operands.size() != 2)
          fail(instruction.location, "'" + name + "' expects 1 or 2 operands, got " + std::to_string(operands.size()));
        const std::uint8_t bits = operandBits(operands[0]);
        const std::uint8_t extension = name == "rol"                      ? 0
                                       : name == "ror"                    ? 1
                                       : (name == "shl" || name == "sal") ? 4
                                       : name == "shr"                    ? 5
                                                                          : 7;
        if (operands.size() == 1) {
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0xd0 : 0xd1)}, extension, nullptr, operands[0],
                 bits);
        } else if (auto immediate = std::get_if<Immediate>(&operands[1])) {
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0xc0 : 0xc1)}, extension, nullptr, operands[0],
                 bits);
          emitImmediate(instruction, immediate->value, 8);
        } else if (auto reg = std::get_if<Register>(&operands[1]);
                   reg && reg->bits == 8 && reg->code == 1 && !reg->high) {
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0xd2 : 0xd3)}, extension, nullptr, operands[0],
                 bits);
        } else {
          fail(instruction.location, "shift count must be an immediate or cl");
        }
        continue;
      }

      if (name == "xchg") {
        requireCount(instruction, 2);
        const std::uint8_t bits = inferPairBits(operands, instruction);
        if (auto source = std::get_if<Register>(&operands[1])) {
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0x86 : 0x87)}, source->code, source, operands[0],
                 bits);
        } else if (auto source = std::get_if<Register>(&operands[0]);
                   source && std::holds_alternative<Memory>(operands[1])) {
          emitRM(instruction, {static_cast<std::uint8_t>(bits == 8 ? 0x86 : 0x87)}, source->code, source, operands[1],
                 bits);
        } else {
          fail(instruction.location, "'xchg' expects one register and one register/memory operand");
        }
        continue;
      }

      fail(instruction.location, "encoding for instruction '" + name + "' is not implemented");
    }
    return output.bytes;
  }

} // namespace compiler
