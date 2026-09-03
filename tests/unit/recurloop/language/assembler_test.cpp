#include <gtest/gtest.h>
#include <compiler/Assembler.hpp>
#include <compiler/ElfWriter.hpp>
#include <recurloop/Assembler.hpp>
#include <recurloop/AssemblerInstructions.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/Recurloop.hpp>

#include <cstdint>
#include <cstring>
#include <array>
#include <elf.h>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iterator>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

#include <sys/wait.h>
#include <unistd.h>

class AssemblerTesting : public recurloop::Recurloop, public testing::Test {
public:
  int execute(const std::string &source, const std::string &initialKey = {}) {
    const char *argv[] = {"Recurloop", "--string", source.c_str()};
    initialize(static_cast<int>(std::size(argv)), const_cast<char **>(argv));
    if (!initialKey.empty()) context.workspace.key.append(initialKey);
    context.io.out = &outputs;
    context.io.err = &errors;
    return Recurloop::execute();
  }

  int executeWithFailingPhrase(const std::string &source) {
    const char *argv[] = {"Recurloop", "--string", source.c_str()};
    initialize(static_cast<int>(std::size(argv)), const_cast<char **>(argv));
    context.io.out = &outputs;
    context.io.err = &errors;
    lexicon::Phrase root = context.lexicon.phrase();
    context.lexicon.phrase()
        .append("failing")
        .make()
        .setType(lexicon::phrase::type::getCallable(root))
        .setAction(actionFailure)
        .save();
    return Recurloop::execute();
  }

  int executeWithNonInvokablePhrase(const std::string &source) {
    const char *argv[] = {"Recurloop", "--string", source.c_str()};
    initialize(static_cast<int>(std::size(argv)), const_cast<char **>(argv));
    context.io.out = &outputs;
    context.io.err = &errors;
    lexicon::Phrase root = context.lexicon.phrase();
    context.lexicon.phrase().append("data").make().setType(lexicon::phrase::type::getData(root)).save();
    return Recurloop::execute();
  }

  int executeContinuing(const std::string &source) {
    const char *argv[] = {"Recurloop"};
    initialize(static_cast<int>(std::size(argv)), const_cast<char **>(argv));
    std::istringstream input(source);
    context.io.in = &input;
    context.io.out = &outputs;
    context.io.err = &errors;
    context.config.exception.continues = true;
    return Recurloop::execute();
  }

  std::vector<std::uint8_t> code() {
    const auto *begin = context.workspace.code.getMemory().toPtr();
    return {begin, begin + context.workspace.code.size()};
  }

  std::string error() const {
    return errors.str();
  }

  std::string key() const {
    return context.workspace.key.c_str();
  }

  std::string output() const {
    return outputs.str();
  }

  std::string lookup() {
    return context.lookup.dictionary.getKey();
  }

  std::string objectPath(const std::string &name) const {
    return "/tmp/recurloop-" + name + "-" + std::to_string(getpid()) + ".o";
  }

  std::string executablePath(const std::string &name) const {
    return "/tmp/recurloop-" + name + "-" + std::to_string(getpid());
  }

  std::vector<std::uint8_t> readFile(const std::string &path) const {
    std::ifstream input(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
  }

  void writeFile(const std::string &path, const std::vector<std::uint8_t> &bytes) const {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output.write(reinterpret_cast<const char *>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  }

  std::vector<std::uint8_t> archiveWith(std::string name, const std::vector<std::uint8_t> &member) const {
    const std::string magic = "!<arch>\n";
    std::vector<std::uint8_t> result(magic.begin(), magic.end());
    std::array<char, 60> header;
    header.fill(' ');
    name += '/';
    std::memcpy(header.data(), name.data(), std::min<std::size_t>(name.size(), 16));
    const std::string size = std::to_string(member.size());
    std::memcpy(header.data() + 48, size.data(), size.size());
    header[58] = '`';
    header[59] = '\n';
    result.insert(result.end(), reinterpret_cast<const std::uint8_t *>(header.data()),
                  reinterpret_cast<const std::uint8_t *>(header.data() + header.size()));
    result.insert(result.end(), member.begin(), member.end());
    if ((result.size() & 1u) != 0) result.push_back('\n');
    return result;
  }

  bool contains(const std::vector<std::uint8_t> &bytes, std::string_view text) const {
    return std::search(bytes.begin(), bytes.end(), text.begin(), text.end()) != bytes.end();
  }

  bool symbolDefined(const std::vector<std::uint8_t> &bytes, std::string_view name) const {
    if (bytes.size() < sizeof(Elf64_Ehdr)) return false;
    Elf64_Ehdr header;
    std::memcpy(&header, bytes.data(), sizeof(header));
    for (std::size_t index = 0; index < header.e_shnum; ++index) {
      Elf64_Shdr symbols;
      std::memcpy(&symbols, bytes.data() + header.e_shoff + index * header.e_shentsize, sizeof(symbols));
      if (symbols.sh_type != SHT_SYMTAB) continue;
      Elf64_Shdr strings;
      std::memcpy(&strings, bytes.data() + header.e_shoff + symbols.sh_link * header.e_shentsize, sizeof(strings));
      for (std::size_t offset = 0; offset < symbols.sh_size; offset += symbols.sh_entsize) {
        Elf64_Sym symbol;
        std::memcpy(&symbol, bytes.data() + symbols.sh_offset + offset, sizeof(symbol));
        const char *symbolName = reinterpret_cast<const char *>(bytes.data() + strings.sh_offset + symbol.st_name);
        if (name == symbolName) return symbol.st_shndx != SHN_UNDEF;
      }
    }
    return false;
  }

  bool symbolExported(const std::vector<std::uint8_t> &bytes, std::string_view name) const {
    if (bytes.size() < sizeof(Elf64_Ehdr)) return false;
    Elf64_Ehdr header;
    std::memcpy(&header, bytes.data(), sizeof(header));
    for (std::size_t index = 0; index < header.e_shnum; ++index) {
      Elf64_Shdr symbols;
      std::memcpy(&symbols, bytes.data() + header.e_shoff + index * header.e_shentsize, sizeof(symbols));
      if (symbols.sh_type != SHT_SYMTAB) continue;
      Elf64_Shdr strings;
      std::memcpy(&strings, bytes.data() + header.e_shoff + symbols.sh_link * header.e_shentsize, sizeof(strings));
      for (std::size_t offset = 0; offset < symbols.sh_size; offset += symbols.sh_entsize) {
        Elf64_Sym symbol;
        std::memcpy(&symbol, bytes.data() + symbols.sh_offset + offset, sizeof(symbol));
        const char *symbolName = reinterpret_cast<const char *>(bytes.data() + strings.sh_offset + symbol.st_name);
        if (name == symbolName) return symbol.st_shndx != SHN_UNDEF && ELF64_ST_BIND(symbol.st_info) == STB_GLOBAL;
      }
    }
    return false;
  }

private:
  static void actionFailure(context::Context &, lexicon::Phrase &){THROW(, "failure raised by invoked phrase")}

  std::ostringstream outputs;
  std::ostringstream errors;
};

TEST_F(AssemblerTesting, EncodesRegistersImmediatesMemoryAndBackwardLabel) {
  ASSERT_EQ(execute(R"(
asm {
start:
  mov rax, 0x1122334455667788
  mov qword [rbp + rcx*4 - 8], rax
  add rax, 7
  jne start
  ret
}
)"),
            0);

  const std::vector<std::uint8_t> expected = {0x48, 0xb8, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11,
                                              0x48, 0x89, 0x44, 0x8d, 0xf8, 0x48, 0x81, 0xc0, 0x07, 0x00,
                                              0x00, 0x00, 0x0f, 0x85, 0xe4, 0xff, 0xff, 0xff, 0xc3};
  EXPECT_EQ(code(), expected);
}

TEST_F(AssemblerTesting, AllowsArbitraryOpcodeBytesInsideText) {
  ASSERT_EQ(execute(R"(
asm {
  db 0x0f, 0xa2
  dw 0x1234
  dd 0x89abcdef
  dq 0x0102030405060708
}
)"),
            0)
      << error();

  EXPECT_EQ(code(), (std::vector<std::uint8_t>{0x0f, 0xa2, 0x34, 0x12, 0xef, 0xcd, 0xab, 0x89, 0x08, 0x07, 0x06, 0x05,
                                               0x04, 0x03, 0x02, 0x01}));
}

TEST_F(AssemblerTesting, EncodesCommonArithmeticExtensionAndSystemInstructions) {
  ASSERT_EQ(execute(R"(
asm {
  adc rax, rbx
  sbb rcx, 7
  movzx eax, byte [rax]
  movsx rax, byte [rax]
  movsxd rax, dword [rax]
  mul qword [rax]
  div qword [rax]
  idiv qword [rax]
  bswap r9
  clc
  stc
  cqo
  cpuid
  rdtsc
  pushfq
  popfq
}
)"),
            0)
      << error();

  EXPECT_EQ(code(), (std::vector<std::uint8_t>{0x48, 0x13, 0xc3, 0x48, 0x81, 0xd9, 0x07, 0x00, 0x00, 0x00, 0x0f,
                                               0xb6, 0x00, 0x48, 0x0f, 0xbe, 0x00, 0x48, 0x63, 0x00, 0x48, 0xf7,
                                               0x20, 0x48, 0xf7, 0x30, 0x48, 0xf7, 0x38, 0x49, 0x0f, 0xc9, 0xf8,
                                               0xf9, 0x48, 0x99, 0x0f, 0xa2, 0x0f, 0x31, 0x9c, 0x9d}));
}

TEST_F(AssemblerTesting, ResolvesForwardLabelDuringClosingBraceSecondPass) {
  ASSERT_EQ(execute(R"(
asm {
  jmp later
  nop
later:
  ret
}
)"),
            0);

  const std::vector<std::uint8_t> expected = {0xe9, 0x01, 0x00, 0x00, 0x00, 0x90, 0xc3};
  EXPECT_EQ(code(), expected);
}

TEST_F(AssemblerTesting, InstructionAliasesKeepThePrototypeInstructionSemantics) {
  ASSERT_EQ(execute(R"(
let asm : { : skocz = <asm:{:jmp>
let asm : { : przeskocz = <asm:{:skocz>
let asm : { : ustaw = <asm:{:mov>
asm {
  ustaw eax, 42
  skocz first
  nop
first:
  przeskocz second
  nop
second:
  ret
}
)"),
            0);

  const std::vector<std::uint8_t> expected = {0xb8, 0x2a, 0x00, 0x00, 0x00, 0xe9, 0x01, 0x00, 0x00,
                                              0x00, 0x90, 0xe9, 0x01, 0x00, 0x00, 0x00, 0x90, 0xc3};
  EXPECT_EQ(code(), expected);
}

TEST_F(AssemblerTesting, DebuggerBooleanArgumentsResolveThroughPhrases) {
  ASSERT_EQ(execute("let enabled = <on>\ndebug:trace enabled\n"), 0) << error();
  EXPECT_NE(output().find("[debug] trace on"), std::string::npos);
}

TEST_F(AssemblerTesting, InstructionPhrasesShareOneDataDrivenAction) {
  ASSERT_EQ(execute(""), 0);

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase assembler = child(root, "asm");
  lexicon::Phrase assemblerBody = child(assembler, "{");
  lexicon::Phrase::Action instructionAction = nullptr;
#define ASSEMBLER_INSTRUCTION(Mnemonic, Name)                                                                          \
  {                                                                                                                    \
    lexicon::Phrase instruction = child(assemblerBody, #Mnemonic);                                                     \
    ASSERT_FALSE(instruction.isNull());                                                                                \
    if (instructionAction == nullptr) instructionAction = instruction.getAction();                                     \
    EXPECT_EQ(instruction.getAction(), instructionAction);                                                             \
    recurloop::AssemblerInstruction descriptor{""};                                                                    \
    ASSERT_GE(instruction.payloadSize(), sizeof(descriptor));                                                          \
    instruction.fetch(0, descriptor);                                                                                  \
    EXPECT_EQ(descriptor.magic, recurloop::AssemblerInstruction::Magic);                                               \
    EXPECT_EQ(std::string_view(descriptor.mnemonic), #Mnemonic);                                                       \
  }
  {ASSEMBLER_INSTRUCTIONS(ASSEMBLER_INSTRUCTION)}
#undef ASSEMBLER_INSTRUCTION
  EXPECT_NE(instructionAction, nullptr);
}

TEST_F(AssemblerTesting, ParsesOperandsThroughKnownAndDynamicPhrases) {
  ASSERT_EQ(execute("asm { mov rax, 40; add rax, 2\nret}"), 0);

  const std::vector<std::uint8_t> expected = {
      0x48, 0xb8, 0x28, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x48, 0x81, 0xc0, 0x02, 0x00, 0x00, 0x00, 0xc3,
  };
  EXPECT_EQ(code(), expected);

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase assembler = child(root, "asm");
  lexicon::Phrase assemblerBody = child(assembler, "{");
  lexicon::Phrase operands = child(assemblerBody, recurloop::assembler::phrases::OPERANDS);
  lexicon::Phrase rax = child(operands, "rax");
  lexicon::Phrase bracket = child(operands, "[");
  lexicon::Phrase dynamic = child(operands, "");

  ASSERT_FALSE(operands.isNull());
  EXPECT_FALSE(operands.isInvokable());
  ASSERT_FALSE(rax.isNull());
  ASSERT_FALSE(bracket.isNull());
  ASSERT_FALSE(dynamic.isNull());
  EXPECT_EQ(rax.getAction(), recurloop::Assembler::operand);
  EXPECT_EQ(bracket.getAction(), recurloop::Assembler::operandMemoryBegin);
  EXPECT_EQ(dynamic.getAction(), recurloop::Assembler::operandDynamic);

  compiler::Assembler::Register raxData;
  rax.fetch(0, raxData);
  EXPECT_EQ(raxData.code, 0);
  EXPECT_EQ(raxData.bits, 64);
  EXPECT_FALSE(raxData.high);
  EXPECT_FALSE(raxData.requiresRex);

  lexicon::Phrase qword = child(operands, "qword");
  std::uint8_t qwordBits = 0;
  qword.fetch(0, qwordBits);
  EXPECT_EQ(qwordBits, 64);
}

TEST_F(AssemblerTesting, PhraseTypesSeparateElaborationFromInvocation) {
  ASSERT_EQ(execute(""), 0);

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase let = child(root, "let");
  lexicon::Phrase debug = child(root, "debug");
  lexicon::Phrase ping = child(debug, "ping");
  lexicon::Phrase assembler = child(root, "asm");
  lexicon::Phrase assemblerBody = child(assembler, "{");
  lexicon::Phrase mov = child(assemblerBody, "mov");
  lexicon::Phrase dataType = lexicon::phrase::type::getData(root);
  lexicon::Phrase elaborateType = lexicon::phrase::type::getElaborate(root);
  lexicon::Phrase callableType = lexicon::phrase::type::getCallable(root);
  lexicon::Phrase scopedCallableType = lexicon::phrase::type::getScopedCallable(root);

  EXPECT_EQ(root.getType().getAddress(), elaborateType.getAddress());
  EXPECT_EQ(let.getType().getAddress(), elaborateType.getAddress());
  EXPECT_TRUE(let.isElaboratable());
  EXPECT_FALSE(let.isInvokable());

  EXPECT_EQ(ping.getType().getAddress(), scopedCallableType.getAddress());
  EXPECT_NE(ping.getAction(), nullptr);
  EXPECT_TRUE(ping.isElaboratable());
  EXPECT_TRUE(ping.isInvokable());

  EXPECT_EQ(mov.getType().getAddress(), elaborateType.getAddress());
  EXPECT_NE(mov.getAction(), nullptr);
  EXPECT_FALSE(mov.isInvokable());

  EXPECT_EQ(dataType.getType().getAddress(), dataType.getAddress());
  EXPECT_FALSE(dataType.isElaboratable());
  EXPECT_EQ(elaborateType.getAction(), nullptr);
  EXPECT_EQ(callableType.getAction(), nullptr);
  EXPECT_EQ(scopedCallableType.getAction(), nullptr);
  EXPECT_FALSE(elaborateType.isInvokable());
  EXPECT_FALSE(callableType.isInvokable());
  EXPECT_FALSE(scopedCallableType.isInvokable());

  lexicon::phrase::type::Behavior elaborateBehavior = lexicon::phrase::type::getBehavior(let);
  lexicon::phrase::type::Behavior callableBehavior;
  callableType.fetch(0, callableBehavior);
  lexicon::phrase::type::Behavior scopedCallableBehavior = lexicon::phrase::type::getBehavior(ping);
  EXPECT_EQ(elaborateBehavior.elaborate, lexicon::phrase::type::action);
  EXPECT_EQ(elaborateBehavior.invoke, nullptr);
  EXPECT_EQ(callableBehavior.elaborate, lexicon::phrase::type::action);
  EXPECT_EQ(callableBehavior.invoke, lexicon::phrase::type::action);
  EXPECT_NE(scopedCallableBehavior.elaborate, nullptr);
  EXPECT_NE(scopedCallableBehavior.elaborate, scopedCallableBehavior.invoke);
  EXPECT_EQ(scopedCallableBehavior.invoke, lexicon::phrase::type::action);
}

TEST_F(AssemblerTesting, EveryLanguagePhraseHasAType) {
  ASSERT_EQ(execute(R"(
let alias = <debug:ping>
let compiled = asm { ret }
let group = []
)"),
            0);

  auto filter = [](radix::Node *item, radix::Node *candidate) -> bool { return !candidate->isEmpty(); };
  std::function<void(lexicon::Phrase)> checkDictionary = [&](lexicon::Phrase dictionary) {
    for (lexicon::Dictionary cursor = dictionary.fore(filter); !cursor.isNull(); cursor = cursor.next(filter)) {
      lexicon::Phrase phrase = cursor.getPhrase();
      EXPECT_FALSE(phrase.getType().isNull()) << "phrase without type: " << phrase.getKeyEscaped();
      if (phrase.containsSubdictionary()) checkDictionary(phrase);
    }
  };

  lexicon::Phrase root = context.lexicon.phrase();
  EXPECT_FALSE(root.getType().isNull());
  checkDictionary(root);
}

TEST_F(AssemblerTesting, RejectsAnEmptyOperandInThePhraseStateMachine) {
  EXPECT_NE(execute("asm { mov , ; }"), 0);
  EXPECT_NE(error().find("<input>:1:7: assembler: empty operand before ','"), std::string::npos);
  EXPECT_TRUE(code().empty());
  EXPECT_EQ(lookup(), "{");
}

TEST_F(AssemblerTesting, RejectsInvalidMemoryTermsInThePhraseStateMachine) {
  EXPECT_NE(execute("asm { mov rax, [eax]; }"), 0);
  EXPECT_NE(error().find("memory addressing requires a 64-bit register"), std::string::npos);

  EXPECT_NE(execute("asm { mov rax, [rax*3]; }"), 0);
  EXPECT_NE(error().find("index scale must be 1, 2, 4, or 8"), std::string::npos);

  EXPECT_NE(execute("asm { mov rax, [rax + + 1]; }"), 0);
  EXPECT_NE(error().find("empty term in memory operand"), std::string::npos);
}

TEST_F(AssemblerTesting, EncodesPreviouslyMissingLegalFormsOfDeclaredInstructionFamilies) {
  ASSERT_EQ(execute(R"(
asm {
  imul rbx
  imul rax, 7
  imul r8, r9, -2
  shl rax
  ror byte [rax]
  xchg rax, qword [rbx]
  nop word [rax]
  nop eax
}
)"),
            0);

  const std::vector<std::uint8_t> expected = {
      0x48, 0xf7, 0xeb,                         // imul rbx
      0x48, 0x69, 0xc0, 0x07, 0x00, 0x00, 0x00, // imul rax, 7
      0x4d, 0x69, 0xc1, 0xfe, 0xff, 0xff, 0xff, // imul r8, r9, -2
      0x48, 0xd1, 0xe0,                         // shl rax
      0xd0, 0x08,                               // ror byte [rax]
      0x48, 0x87, 0x03,                         // xchg rax, qword [rbx]
      0x66, 0x0f, 0x1f, 0x00,                   // nop word [rax]
      0x0f, 0x1f, 0xc0,                         // nop eax
  };
  EXPECT_EQ(code(), expected);
}

TEST_F(AssemblerTesting, EncodesEveryOrdinaryConditionalJumpAlias) {
  ASSERT_EQ(execute(R"(
asm {
  ja target
  jae target
  jb target
  jbe target
  jc target
  jnc target
  jng target
  jnge target
  jnl target
  jnle target
target:
  ret
}
)"),
            0);
}

TEST_F(AssemblerTesting, RejectsNegativeImmediateValuesOutsideInt64Range) {
  EXPECT_NE(execute("asm { mov rax, -9223372036854775809; }"), 0);
  EXPECT_NE(error().find("immediate value is out of range '-9223372036854775809'"), std::string::npos);

  EXPECT_NE(execute("asm { mov rax, -18446744073709551615; }"), 0);
  EXPECT_NE(error().find("immediate value is out of range '-18446744073709551615'"), std::string::npos);

  EXPECT_EQ(execute("asm { mov rax, -9223372036854775808; }"), 0);
  EXPECT_EQ(execute("asm { mov rax, 18446744073709551615; }"), 0);

  EXPECT_ANY_THROW(compiler::Assembler::encode("mov", "rax, -9223372036854775809", {}));
  EXPECT_NO_THROW(compiler::Assembler::encode("mov", "rax, -9223372036854775808", {}));
}

TEST_F(AssemblerTesting, TreatsInlineCommentsAsInstructionTerminators) {
  ASSERT_EQ(execute(R"(
asm {
  nop // instruction without operands
  mov eax, 42 // instruction with operands
  ret
}
)"),
            0);
  EXPECT_EQ(code(), (std::vector<std::uint8_t>{0x90, 0xb8, 0x2a, 0x00, 0x00, 0x00, 0xc3}));

  EXPECT_NE(execute("asm { mov eax, // missing operand\n}"), 0);
  EXPECT_NE(error().find("empty operand after ','"), std::string::npos);

  EXPECT_NE(execute("asm { mov eax, [rax // unfinished memory\n}"), 0);
  EXPECT_NE(error().find("unterminated memory operand before comment"), std::string::npos);
}

TEST_F(AssemblerTesting, ResolvesSeveralRelocationPhrasesForOneLabel) {
  ASSERT_EQ(execute(R"(
asm {
  jmp target
  jne target
target:
  ret
}
)"),
            0);

  const std::vector<std::uint8_t> expected = {0xe9, 0x06, 0x00, 0x00, 0x00, 0x0f, 0x85, 0x00, 0x00, 0x00, 0x00, 0xc3};
  EXPECT_EQ(code(), expected);
}

TEST_F(AssemblerTesting, UsesWorkspaceKeyAsScratchAndRestoresItsOwnerState) {
  ASSERT_EQ(execute("asm { mov eax, 42; ret }", "outer-state"), 0);
  EXPECT_EQ(key(), "outer-state");
}

TEST_F(AssemblerTesting, TracksTheCurrentlyInvokedPhraseInContext) {
  const char *argv[] = {"Recurloop", "--string", ""};
  initialize(static_cast<int>(std::size(argv)), const_cast<char **>(argv));
  lexicon::Phrase phrase = context.lexicon.phrase();

  EXPECT_EQ(context::Context::currentInvoked(context), nullptr);
  context::Context::setCurrentInvoked(context, &phrase);
  EXPECT_EQ(context::Context::currentInvoked(context), &phrase);
  context::Context::setCurrentInvoked(context, nullptr);
  EXPECT_EQ(context::Context::currentInvoked(context), nullptr);
}

TEST_F(AssemblerTesting, CanBeAssignedAndInvokedAsTheValueOfALetPhrase) {
  ASSERT_EQ(execute(R"(
let testassemblera = asm {
  mov eax, 5
  ret
}
testassemblera
)"),
            0);
}

TEST_F(AssemblerTesting, LinksForwardAndBackwardLabelsInAnAssignedNativePhrase) {
  ASSERT_EQ(execute(R"(
let routed = asm {
  jmp forward
backward:
  invoke <debug:ping>
  ret
forward:
  jmp backward
}
routed
)"),
            0);

  EXPECT_EQ(output(), "pong\n");
  EXPECT_TRUE(code().empty());
}

TEST_F(AssemblerTesting, RejectsAnUndefinedLabelBeforeLinkingAnAssignedPhrase) {
  EXPECT_NE(execute(R"(
let broken = asm {
  jmp missing
}
)"),
            0);

  EXPECT_NE(error().find("<input>:3:3: assembler: undefined label 'missing'"), std::string::npos);
  EXPECT_FALSE(code().empty());
  EXPECT_EQ(context.runtime.size(), 0u);
}

TEST_F(AssemblerTesting, LinksCompiledDefinitionsAsIndependentAlignedJitImages) {
  ASSERT_EQ(execute(R"(
let first = {
  invoke <debug:ping>
}
let group = [
  second = {
    invoke <debug:ping>
  }
]
let third = asm { ret }
first
third
group:second
)"),
            0);

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase first = child(root, "first");
  lexicon::Phrase group = child(root, "group");
  lexicon::Phrase second = child(group, "second");
  lexicon::Phrase third = child(root, "third");

  const auto firstAddress = recurloop::Assembler::nativeEntry(first);
  const auto secondAddress = recurloop::Assembler::nativeEntry(second);
  const auto thirdAddress = recurloop::Assembler::nativeEntry(third);
  const auto runtimeBegin = reinterpret_cast<std::uintptr_t>(context.runtime.getExecutable().toPtr());
  const auto runtimeEnd = runtimeBegin + context.runtime.size();

  EXPECT_EQ(firstAddress % 16, 0u);
  EXPECT_EQ(secondAddress % 16, 0u);
  EXPECT_EQ(thirdAddress % 16, 0u);
  EXPECT_LT(firstAddress, secondAddress);
  EXPECT_LT(secondAddress, thirdAddress);
  EXPECT_GE(firstAddress, runtimeBegin);
  EXPECT_LT(thirdAddress, runtimeEnd);
  EXPECT_EQ(output(), "pong\npong\n");
  EXPECT_TRUE(code().empty());
}

TEST_F(AssemblerTesting, EmitsTheNextCompiledDefinitionAsAOneShotElfObject) {
  const std::string path = objectPath("compiled-output");
  std::filesystem::remove(path);
  const std::string source = "emit object \"" + path + R"("
let exported = {
  invoke <debug:ping>
}
let jit = {
  invoke <debug:ping>
}
jit
)";

  ASSERT_EQ(execute(source), 0);
  const std::vector<std::uint8_t> object = readFile(path);
  ASSERT_GE(object.size(), sizeof(Elf64_Ehdr));
  Elf64_Ehdr header;
  std::memcpy(&header, object.data(), sizeof(header));
  EXPECT_EQ(std::memcmp(header.e_ident, ELFMAG, SELFMAG), 0);
  EXPECT_EQ(header.e_type, ET_REL);
  EXPECT_EQ(header.e_machine, EM_X86_64);
  EXPECT_TRUE(contains(object, "exported"));
  EXPECT_TRUE(contains(object, "debug:ping"));
  EXPECT_FALSE(contains(object, "recurloop.context"));
  EXPECT_FALSE(contains(object, "recurloop.invoke"));
  EXPECT_FALSE(contains(object, "recurloop.phrase."));

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };
  lexicon::Phrase root = context.lexicon.phrase();
  EXPECT_FALSE(child(root, "exported").isInvokable());
  EXPECT_TRUE(child(root, "jit").isInvokable());
  EXPECT_EQ(output(), "pong\n");
  EXPECT_GT(context.runtime.size(), 0u);
  EXPECT_TRUE(code().empty());
  EXPECT_TRUE(lookup().empty());
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, EmitsADirectNamedDefinitionWithoutLet) {
  const std::string path = objectPath("direct-named-output");
  std::filesystem::remove(path);
  const std::string source = "emit object \"" + path + R"(" public_api = asm { ret }
)";

  ASSERT_EQ(execute(source), 0) << error();
  const std::vector<std::uint8_t> object = readFile(path);
  EXPECT_TRUE(symbolExported(object, "public_api"));
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, AnonymousObjectExportsEveryNamedAssemblerLabel) {
  const std::string path = objectPath("multiple-exports");
  std::filesystem::remove(path);
  const std::string source = "emit object \"" + path + R"(" = asm {
first_export:
  ret
second_export:
  ret
}
)";

  ASSERT_EQ(execute(source), 0) << error();
  const std::vector<std::uint8_t> object = readFile(path);
  EXPECT_TRUE(symbolExported(object, "first_export"));
  EXPECT_TRUE(symbolExported(object, "second_export"));
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, EmitsHexDefinitionsThroughTheSameObjectDirective) {
  const std::string path = objectPath("hex-output");
  std::filesystem::remove(path);
  const std::string source = "emit object \"" + path + "\"\nlet raw = hex { c3 }\n";

  ASSERT_EQ(execute(source), 0);
  const std::vector<std::uint8_t> object = readFile(path);
  ASSERT_GE(object.size(), sizeof(Elf64_Ehdr));
  EXPECT_TRUE(contains(object, "raw"));
  EXPECT_FALSE(contains(object, "phrase-entry"));
  EXPECT_EQ(context.runtime.size(), 0u);
  EXPECT_TRUE(code().empty());
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, PreservesSourceSymbolNamesWithoutCompilerPrefixes) {
  const std::string path = objectPath("symbol-names");
  std::filesystem::remove(path);
  const std::string source = "emit object \"" + path + R"("
let exported = asm {
  jmp finished
finished:
  ret
}
)";

  ASSERT_EQ(execute(source), 0);
  const std::vector<std::uint8_t> object = readFile(path);
  EXPECT_TRUE(contains(object, "exported"));
  EXPECT_TRUE(contains(object, "finished"));
  EXPECT_FALSE(contains(object, "phrase-entry"));
  EXPECT_FALSE(contains(object, "asm-label:"));
  EXPECT_FALSE(contains(object, "recurloop-executable-entry"));
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, EmitsBytesIntoSelectedElfSections) {
  const std::string path = objectPath("assembler-sections");
  std::filesystem::remove(path);
  const std::string source = std::string(R"(
let custom_section = <.section>
let allocated = <alloc>
let writable = <write>
let initializer_array = <init-array>
let thread_local = <tls>
let aligned = <align>
emit object ")") + path + R"("
let layout = asm {
.text
  ret
.rodata
message:
  db "RL", 0
  dw 0x1234
.data
counter:
  dd 7
  dq 0x1122334455667788
.bss
storage:
  resb 24
custom_section .payload note aligned=8
payload:
  db 0xde, 0xad, 0xbe, 0xef
custom_section .init_array initializer_array allocated writable aligned=8
initializer:
  dq 0
custom_section .tdata allocated writable thread_local aligned=8
thread_value:
  dq 1
}
)";

  ASSERT_EQ(execute(source), 0) << error();
  const std::vector<std::uint8_t> object = readFile(path);
  ASSERT_GE(object.size(), sizeof(Elf64_Ehdr));
  Elf64_Ehdr header;
  std::memcpy(&header, object.data(), sizeof(header));
  const auto sectionName = [&](const Elf64_Shdr &section) {
    Elf64_Shdr names;
    std::memcpy(&names, object.data() + header.e_shoff + header.e_shstrndx * header.e_shentsize, sizeof(names));
    return std::string_view(reinterpret_cast<const char *>(object.data() + names.sh_offset + section.sh_name));
  };
  const auto section = [&](std::string_view name) {
    for (std::size_t index = 0; index < header.e_shnum; ++index) {
      Elf64_Shdr candidate;
      std::memcpy(&candidate, object.data() + header.e_shoff + index * header.e_shentsize, sizeof(candidate));
      if (sectionName(candidate) == name) return candidate;
    }
    return Elf64_Shdr{};
  };

  const Elf64_Shdr rodata = section(".rodata");
  const Elf64_Shdr data = section(".data");
  const Elf64_Shdr bss = section(".bss");
  const Elf64_Shdr payload = section(".payload");
  const Elf64_Shdr language = section(".recurloop.language");
  const Elf64_Shdr initializers = section(".init_array");
  const Elf64_Shdr tls = section(".tdata");
  ASSERT_EQ(rodata.sh_size, 5u);
  EXPECT_EQ((std::vector<std::uint8_t>(object.begin() + rodata.sh_offset,
                                       object.begin() + rodata.sh_offset + rodata.sh_size)),
            (std::vector<std::uint8_t>{'R', 'L', 0, 0x34, 0x12}));
  ASSERT_EQ(data.sh_size, 12u);
  EXPECT_EQ(bss.sh_type, SHT_NOBITS);
  EXPECT_EQ(bss.sh_size, 24u);
  EXPECT_EQ(payload.sh_type, SHT_NOTE);
  EXPECT_EQ(payload.sh_addralign, 8u);
  EXPECT_EQ(payload.sh_size, 4u);
  EXPECT_GT(language.sh_size, 16u);
  EXPECT_EQ(initializers.sh_type, SHT_INIT_ARRAY);
  EXPECT_EQ(initializers.sh_flags, SHF_ALLOC | SHF_WRITE);
  EXPECT_EQ(tls.sh_flags, SHF_ALLOC | SHF_WRITE | SHF_TLS);
  EXPECT_TRUE(contains(object, "message"));
  EXPECT_TRUE(contains(object, "counter"));
  EXPECT_TRUE(contains(object, "storage"));
  EXPECT_TRUE(contains(object, "payload"));
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, ValidatesAndEmitsTypedInvokeArguments) {
  const std::string path = objectPath("typed-invoke");
  std::filesystem::remove(path);
  const std::string source = "let nothing = <null>\n"
                             "extern typed_target(left:u64, right:u64, weight:f64, pointer:u8*) -> void abi "
                             "sysv-amd64\n"
                             "emit object \"" +
                             path + R"("
let caller = asm {
  invoke typed_target(11, 29, 3.5, nothing)
  ret
}
)";
  ASSERT_EQ(execute(source), 0) << error();
  const std::vector<std::uint8_t> object = readFile(path);
  EXPECT_TRUE(contains(object, "typed_target"));
  EXPECT_TRUE(contains(object, "caller"));
  EXPECT_FALSE(contains(object, "recurloop.context"));
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, DeclaresTypedABIForCompiledPhraseActions) {
  const std::string path = objectPath("typed-defined-action");
  std::filesystem::remove(path);
  const std::string source = "let add = asm { mov rax, rdi; add rax, rsi; ret }\n"
                             "function add(left:u64, right:u64) -> u64 abi sysv-amd64\n"
                             "emit object \"" +
                             path + R"("
let caller = asm { invoke add(11, 31) ret }
)";

  ASSERT_EQ(execute(source), 0) << error();
  const std::optional<compiler::TypedFunction> add = context.language().findFunction("add");
  ASSERT_TRUE(add);
  EXPECT_FALSE(add->imported);
  const std::vector<std::uint8_t> object = readFile(path);
  EXPECT_TRUE(symbolDefined(object, "add"));
  EXPECT_TRUE(symbolDefined(object, "caller"));
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, CallsCompiledFunctionsFromRuntimeExpressions) {
  ASSERT_EQ(execute(R"(
let add_ten = fn (value:i64) -> i64 {
  return value + 10
}
assert add_ten(32) == 42
assert add_ten(add_ten(32)) == 52
)"),
            0)
      << error();
}

TEST_F(AssemblerTesting, CompilesRealLiteralsArithmeticCastsAndMultilineGroupsNatively) {
  ASSERT_EQ(execute(R"(
let floating_result = fn () -> i64 {
  var value = 0.5
  return cast(i64, value * 10.0)
}
let multiline_result = fn () -> i64 {
  var value = (
    10 +
    20 +
    12
  )
  return value
}
assert floating_result() == 5
assert multiline_result() == 42
)"),
            0)
      << error();
}

TEST_F(AssemblerTesting, SupportsBothFnDefinitionFormsAndUsesTheExplicitFnName) {
  ASSERT_EQ(execute(R"(
fn direct(value:i64) -> i64 {
  return value + 1
}
let inferred = fn (value:i64) -> i64 {
  return value * 2
}
let discarded = fn explicit(value:i64) -> i64 {
  return value - 1
}
print direct(41)
print inferred(21)
print explicit(43)
)"),
            0)
      << error();
  EXPECT_EQ(output(), "42\n42\n42\n");

  lexicon::Phrase root = context.lexicon.phrase();
  const auto savedPhrase = [](radix::Node *, radix::Match *candidate) {
    return !lexicon::Dictionary(*candidate).getPhrase().isNull();
  };
  EXPECT_TRUE(root.matchExact(Byte((unsigned char *)"discarded"), 0, 9 * Byte::length, savedPhrase).isNull());
  EXPECT_FALSE(root.matchExact(Byte((unsigned char *)"explicit"), 0, 8 * Byte::length, savedPhrase).isNull());
}

TEST_F(AssemblerTesting, PassesContextAndInvokedOnlyToAnExactActionSignature) {
  ASSERT_EQ(execute(R"(
fn mark(any_name:Context*, another_name:Phrase*) -> void {
  if any_name.exec.invoked == another_name {
    any_name.exec.args.index = 42
  }
  return
}
mark
)"),
            0)
      << error();
  EXPECT_EQ(context.exec.args.index, 42);
}

TEST_F(AssemblerTesting, InvokesCompiledActionsThroughPhrasesAddedByAnAliasedParser) {
  ASSERT_EQ(execute(R"(
fn count_invocation(state:Context*, called:Phrase*) -> void {
  if state.exec.invoked == called {
    state.workspace.bssBytes += 1
  }
  return
}
let command = <let>
command alpha = <count_invocation>
command beta = <count_invocation>
alpha beta alpha
)"),
            0)
      << error();
  EXPECT_EQ(context.workspace.bssBytes, 3u);
}

TEST_F(AssemblerTesting, LetsACompiledContextActionParseAndDefinePhrases) {
  ASSERT_EQ(execute(R"(
fn count_invocation(state:Context*, called:Phrase*) -> void {
  if state.exec.invoked == called {
    state.workspace.bssBytes += 1
  }
  return
}

fn install_commands(state:Context*, called:Phrase*) -> void {
  var source:u8* = "alpha,beta,gamma"
  var prototype = context:phrase:find(state, "count_invocation", 0, 16)
  var start = 0
  var index = 0
  while source[index] != 0 {
    if source[index] == 44 {
      context:phrase:define(state, source, start, index - start, prototype)
      set start = index + 1
    }
    set index += 1
  }
  context:phrase:define(state, source, start, index - start, prototype)
  return
}

install_commands
alpha beta alpha
)"),
            0)
      << error();
  EXPECT_EQ(context.workspace.bssBytes, 3u);

  lexicon::Phrase root = context.lexicon.phrase();
  const auto savedPhrase = [](radix::Node *, radix::Match *candidate) {
    return !lexicon::Dictionary(*candidate).getPhrase().isNull();
  };
  for (std::string_view name : {"alpha", "beta", "gamma"})
    EXPECT_FALSE(
        root.matchExact(Byte((unsigned char *)name.data()), 0, name.size() * Byte::length, savedPhrase).isNull());
}

TEST_F(AssemblerTesting, ContextPhraseApiFindsDefinesInspectsAndCallsPhrases) {
  ASSERT_EQ(execute(R"(
fn install_alias(state:Context*, called:Phrase*) -> void {
  var debug = context:phrase:find(state, "debug", 0, 5)
  var ping = context:phrase:find(state, debug, "ping", 0, 4, 0)
  var ping_type = context:phrase:get(state, ping, 1)
  var alias = context:phrase:define(state, 0, "api-alias", 0, 9, ping_type, 0, 0, ping, 72)
  context:phrase:data(state, alias, "data", 0, 4)
  if context:phrase:get(state, alias, 4) == 4 {
    context:phrase:call(state, alias, 0)
  }
  return
}
install_alias
)"),
            0)
      << error();
  EXPECT_EQ(output(), "pong\n");

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase alias = root.matchExact(Byte((unsigned char *)"api-alias"), 0, 9 * Byte::length).getPhrase();
  ASSERT_FALSE(alias.isNull());
  EXPECT_EQ(alias.payloadSize(), 4u);
  EXPECT_TRUE(alias.getPrototype().isNull());
  lexicon::Phrase debug = root.matchExact(Byte((unsigned char *)"debug"), 0, 5 * Byte::length).getPhrase();
  lexicon::Phrase ping = debug.matchExact(Byte((unsigned char *)"ping"), 0, 4 * Byte::length).getPhrase();
  EXPECT_EQ(alias.getType().getAddress(), ping.getType().getAddress());
}

TEST_F(AssemblerTesting, ContextPhraseApiInfersTextLengthAndPreservesBitPreciseKeys) {
  ASSERT_EQ(execute(R"(
fn count_bit_call(state:Context*, called:Phrase*) -> void {
  state.workspace.bssBytes += 1
  return
}

fn install_bit_keys(state:Context*, called:Phrase*) -> void {
  var ok = 1
  var action = context:phrase:find(state, "count_bit_call")
  var action_type = context:phrase:get(state, action, 1)
  var group = context:phrase:define(state, 0, "bit-keys", action_type, 0, 0, action, 73)
  var three = context:phrase:define(state, group, bits"101", action_type, action, 0, action, 88)
  var four = context:phrase:define(state, group, bits"1010", action_type, action, 0, action, 88)

  if context:phrase:find(state, group, bits"101", 0) != three { set ok = 0 }
  if context:phrase:find(state, group, bits"1010", 0) != four { set ok = 0 }
  if context:phrase:find(state, group, bits"0010_1011", 2, 4, 0) != four { set ok = 0 }
  if context:phrase:find(state, group, bits"1010_11", 2) != four { set ok = 0 }

  var data = context:phrase:define(state, group, "data", 0, 0, 0, 0, 2)
  context:phrase:data(state, data, "payload")
  if context:phrase:get(state, data, 4) != 7 { set ok = 0 }

  var alias = context:phrase:define(state, "bit-alias", action)
  if context:phrase:find(state, "bit-alias") != alias { set ok = 0 }
  if context:phrase:call(state, four, 0) != four { set ok = 0 }
  if ok == 0 { state.exec.status = 1 }
  return
}

install_bit_keys
)"),
            0)
      << error();
  EXPECT_EQ(context.workspace.bssBytes, 1u);

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase group = root.matchExact(Byte((unsigned char *)"bit-keys"), 0, 8 * Byte::length).getPhrase();
  ASSERT_FALSE(group.isNull());
  unsigned char packed = 0xa0;
  lexicon::Phrase three = group.matchExact(Byte(&packed), 0, 3).getPhrase();
  lexicon::Phrase four = group.matchExact(Byte(&packed), 0, 4).getPhrase();
  ASSERT_FALSE(three.isNull());
  ASSERT_FALSE(four.isNull());
  EXPECT_NE(three.getAddress(), four.getAddress());
  const compiler::TypeDescriptor bitString = context.language().types.get("BitString");
  ASSERT_EQ(bitString.fields.size(), 2u);
  EXPECT_EQ(bitString.fields[0].name, "data");
  EXPECT_EQ(bitString.fields[1].name, "bits");
}

TEST_F(AssemblerTesting, ContextPhraseApiMutatesAllocatedSlotsAndAcceptsInlineActions) {
  ASSERT_EQ(execute(R"(
fn install_mutable_phrase(state:Context*, called:Phrase*) -> void {
  var types = context:phrase:find(state, "phrase-types")
  var callable = context:phrase:find(state, types, "callable", 0)
  var debug = context:phrase:find(state, "debug")
  var ping = context:phrase:find(state, debug, "ping", 0)
  var ping_type = context:phrase:get(state, ping, 1)
  var phrase = context:phrase:define(
      state, 0, "runtime-mutable", callable, 0, 0,
      fn (context:Context*, phrase:Phrase*) -> void {
        context.workspace.bssBytes += 1
      }, 122)

  if phrase == 0 { state.exec.status = 1 return }
  if context:phrase:set(state, phrase, 2, ping) != phrase { state.exec.status = 1 }
  if context:phrase:set(state, phrase, 3, ping) != phrase { state.exec.status = 1 }
  if context:phrase:set(state, phrase, 1, ping_type) != phrase { state.exec.status = 1 }
  if context:phrase:get(state, phrase, 2) != ping { state.exec.status = 1 }
  if context:phrase:get(state, phrase, 3) != ping { state.exec.status = 1 }
  if context:phrase:get(state, phrase, 1) != ping_type { state.exec.status = 1 }
  if context:phrase:call(state, phrase, 0) != phrase { state.exec.status = 1 }

  if context:phrase:set(state, phrase, 4,
      fn (context:Context*, phrase:Phrase*) -> void {
        context.workspace.bssBytes += 10
      }) != phrase { state.exec.status = 1 }
  context:phrase:call(state, phrase, 0)

  if context:phrase:set(state, phrase, 5, 0) != phrase { state.exec.status = 1 }
  if context:phrase:set(state, phrase, 5, 1) != phrase { state.exec.status = 1 }

  var no_slot = context:phrase:define(state, 0, "without-prototype-slot", 0, 0, 0, 0, 2)
  if context:phrase:set(state, no_slot, 2, ping) != 0 { state.exec.status = 1 }
}

install_mutable_phrase
)"),
            0)
      << error();
  EXPECT_EQ(context.workspace.bssBytes, 11u);
  EXPECT_TRUE(output().empty());
}

TEST_F(AssemblerTesting, RejectsInvalidBitStringLiterals) {
  EXPECT_NE(execute("fn invalid() -> u64 { var value = bits\"10x1\" return value.bits }\n"), 0);
  EXPECT_NE(error().find("bit string literal accepts only"), std::string::npos);
}

TEST_F(AssemblerTesting, DoesNotTreatOtherPointerSignaturesAsPhraseActions) {
  EXPECT_NE(execute(R"(
fn not_an_action(context:u8*, invoked:Phrase*) -> void {
  return
}
not_an_action
)"),
            0);
  EXPECT_NE(error().find("requires 2 typed argument"), std::string::npos);
}

TEST_F(AssemblerTesting, RejectsTheRemovedNativeFunctionKeyword) {
  EXPECT_NE(execute("let old = native () -> i64 { return 42 }\n"), 0);
  EXPECT_NE(error().find("undefined phrase"), std::string::npos);
}

TEST_F(AssemblerTesting, RejectsTheRemovedInterpretedFunctionKeyword) {
  EXPECT_NE(execute("let old = interpreted () { return 42 }\n"), 0);
  EXPECT_NE(error().find("undefined phrase"), std::string::npos);
}

TEST_F(AssemblerTesting, CompilesFunctionControlFlowRecursionAndPointerIndexing) {
  ASSERT_EQ(execute(R"(
let fibonacci = fn (n:i64) -> i64 {
  if n <= 1 {
    return n
  } else {
    return fibonacci(n - 1) + fibonacci(n - 2)
  }
}
let sum_to = fn (limit:i64) -> i64 {
  var index = 1
  var total = 0
  while index <= limit {
    set total += index
    set index += 1
  }
  return total
}
let second_argument = fn (argv:u8**) -> u8* {
  return argv[1]
}
)"),
            0)
      << error();

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase fibonacci = child(root, "fibonacci");
  lexicon::Phrase sum = child(root, "sum_to");
  lexicon::Phrase argument = child(root, "second_argument");

  ASSERT_TRUE(fibonacci.isInvokable()) << fibonacci.getType().getKeyEscaped();
  ASSERT_TRUE(sum.isInvokable());
  ASSERT_TRUE(argument.isInvokable());
  std::uintptr_t fibonacciAddress = 0;
  std::uintptr_t sumAddress = 0;
  std::uintptr_t argumentAddress = 0;
  ASSERT_NO_THROW(fibonacciAddress = recurloop::Assembler::nativeEntry(fibonacci));
  ASSERT_NO_THROW(sumAddress = recurloop::Assembler::nativeEntry(sum));
  ASSERT_NO_THROW(argumentAddress = recurloop::Assembler::nativeEntry(argument));
  auto fibonacciEntry = reinterpret_cast<std::int64_t (*)(std::int64_t)>(fibonacciAddress);
  auto sumEntry = reinterpret_cast<std::int64_t (*)(std::int64_t)>(sumAddress);
  auto argumentEntry = reinterpret_cast<char *(*)(char **)>(argumentAddress);
  EXPECT_EQ(fibonacciEntry(10), 55);
  EXPECT_EQ(sumEntry(10), 55);
  char first[] = "program";
  char second[] = "42";
  char *arguments[] = {first, second, nullptr};
  EXPECT_EQ(argumentEntry(arguments), second);
}

TEST_F(AssemblerTesting, CompilesNativeRecordsWritableLvaluesScopesFunctionReferencesAndStackArguments) {
  ASSERT_EQ(execute(R"(
record NativePair(left:i64, right:i64)
let native_increment = fn (value:i64) -> i64 {
  return value + 1
}
let native_apply = fn (action:u8*, value:i64) -> i64 {
  return action(value)
}
let native_update = fn (pair:NativePair*, values:i64*, delta:i64) -> i64 {
  set pair.right = pair.left + delta
  set values[1] = pair.right
  return values[1]
}
let native_scoped = fn (value:i64) -> i64 {
  if value != 0 {
    const selected = 40
    return selected + 2
  } else {
    const selected = 0
    return selected
  }
}
let native_break_continue = fn (limit:i64) -> i64 {
  var index = 0
  var total = 0
  while index < limit {
    set index += 1
    if index == 2 {
      continue
    }
    if index > 4 {
      break
    }
    set total += index
  }
  return total
}
let native_stack_arguments = fn (a:i64, b:i64, c:i64, d:i64, e:i64, f:i64, g:i64, h:i64) -> i64 {
  return a + b + c + d + e + f + g + h
}
let native_call_stack_arguments = fn () -> i64 {
  return native_stack_arguments(1, 2, 3, 4, 5, 6, 7, 8)
}
let native_pointer_roundtrip = fn (value:i64) -> i64 {
  return cast(i64, cast(u8*, value))
}
)"),
            0)
      << error();

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };
  lexicon::Phrase root = context.lexicon.phrase();
  auto entry = [&](const std::string &name) {
    lexicon::Phrase phrase = child(root, name);
    return recurloop::Assembler::nativeEntry(phrase);
  };

  struct Pair {
    std::int64_t left;
    std::int64_t right;
  } pair{35, 0};
  std::int64_t values[2] = {0, 0};
  auto update = reinterpret_cast<std::int64_t (*)(Pair *, std::int64_t *, std::int64_t)>(entry("native_update"));
  auto apply = reinterpret_cast<std::int64_t (*)(void *, std::int64_t)>(entry("native_apply"));
  auto increment = reinterpret_cast<std::int64_t (*)(std::int64_t)>(entry("native_increment"));
  auto scoped = reinterpret_cast<std::int64_t (*)(std::int64_t)>(entry("native_scoped"));
  auto loop = reinterpret_cast<std::int64_t (*)(std::int64_t)>(entry("native_break_continue"));
  auto stack = reinterpret_cast<std::int64_t (*)()>(entry("native_call_stack_arguments"));
  auto cast = reinterpret_cast<std::int64_t (*)(std::int64_t)>(entry("native_pointer_roundtrip"));

  EXPECT_EQ(update(&pair, values, 7), 42);
  EXPECT_EQ(pair.right, 42);
  EXPECT_EQ(values[1], 42);
  EXPECT_EQ(apply(reinterpret_cast<void *>(increment), 41), 42);
  EXPECT_EQ(scoped(1), 42);
  EXPECT_EQ(scoped(0), 0);
  EXPECT_EQ(loop(10), 8);
  EXPECT_EQ(stack(), 36);
  EXPECT_EQ(cast(42), 42);
}

TEST_F(AssemblerTesting, RequiresAndInvokesFunctionsWithStructuralSignatures) {
  ASSERT_EQ(execute(R"(
let transform = fn (value:i64) -> i64 {
  return value + 1
}
let transform = fn (value:u8*) -> i64 {
  return 100
}
let double = fn (value:i64) -> i64 {
  return value * 2
}
let apply = fn (callback:fn (i64) -> i64, value:i64) -> i64 {
  return callback(value)
}
let raw_apply = fn (callback:u8*, value:i64) -> i64 {
  return callback(value)
}
let select = fn () -> fn (i64) -> i64 {
  return transform
}
let typed_callback_result = fn () -> i64 {
  let selected:fn (i64) -> i64 = select()
  return apply(transform, 40) + selected(0)
}
let inline_callback_result = fn () -> i64 {
  return apply(fn (value:i64) -> i64 { return value + 2 }, 40)
}
let raw_callback_result = fn () -> i64 {
  return raw_apply(double, 21)
}
assert typed_callback_result() == 42
assert inline_callback_result() == 42
assert raw_callback_result() == 42
)"),
            0)
      << error();

  const std::optional<compiler::TypedFunction> apply = context.language().findFunction("apply");
  ASSERT_TRUE(apply);
  const compiler::TypeDescriptor callback = context.language().types.get(apply->parameterTypes.front());
  EXPECT_EQ(callback.kind, compiler::TypeKind::Function);
  EXPECT_EQ(callback.parameterTypes, (std::vector<compiler::TypeId>{context.language().types.find("i64")}));
  EXPECT_EQ(callback.resultType, context.language().types.find("i64"));
  EXPECT_EQ(callback.convention, "sysv-amd64");
}

TEST_F(AssemblerTesting, UsesSignaturePhrasesAsFunctionFactoriesAndStructuralTypeAliases) {
  ASSERT_EQ(execute(R"(
let Nullary = fn () -> i64
let Unary = fn (value:i64) -> i64
let answer = Nullary {
  return 42
}
Unary increment {
  return value + 1
}
let UnaryAlias = <Unary>
let double = UnaryAlias {
  return value * 2
}
let apply = fn (callback:Unary, value:i64) -> i64 {
  return callback(value)
}
let apply_structural = fn (callback:fn (i64) -> i64, value:i64) -> i64 {
  return callback(value)
}
let IntegerClassifier = fn (value:i64) -> i64
let TextClassifier = fn (value:u8*) -> i64
let classify = IntegerClassifier {
  return value + 100
}
let classify = TextClassifier {
  return 200
}
let Types = []
let Types:Unary = fn (value:i64) -> i64
let Types:decrement = Types:Unary {
  return value - 1
}
let Types:apply = fn (callback:Unary, value:i64) -> i64 {
  return callback(value)
}
record Types:Value {
  number:i64
}
let Types:Reader = fn (value:Value*) -> i64
let ReaderAlias = <Types:Reader>
let read_value = ReaderAlias {
  return value.number
}
record CallbackHolder {
  callback:Unary
}
let multiline = fn () -> i64
{
  return 42
}
let signature_result = fn () -> i64 {
  let selected:Unary = increment
  return answer() + apply(selected, 41) + apply_structural(double, 21) + classify(7) + classify("seven") + Types:apply(Types:decrement, 43) + multiline()
}
)"),
            0)
      << error();

  const compiler::TypeId integer = context.language().types.find("i64");
  const std::array<compiler::TypeId, 1> parameters{integer};
  const compiler::TypeId structural = context.language().types.functionOf(parameters, integer, "sysv-amd64");
  EXPECT_EQ(recurloop::Functions::signatureType(context, "Unary"), structural);
  EXPECT_EQ(recurloop::Functions::signatureType(context, "UnaryAlias"), structural);
  EXPECT_EQ(recurloop::Functions::signatureType(context, "Types:Unary"), structural);

  const compiler::TypeId namespacedValue = context.language().types.find("Types:Value");
  ASSERT_NE(namespacedValue, compiler::InvalidType);
  const std::optional<compiler::TypedFunction> reader = context.language().findFunction("read_value");
  ASSERT_TRUE(reader);
  ASSERT_EQ(reader->parameterTypes.size(), 1u);
  EXPECT_EQ(reader->parameterTypes.front(), context.language().types.pointerTo(namespacedValue));

  const std::optional<compiler::TypedFunction> apply = context.language().findFunction("apply");
  ASSERT_TRUE(apply);
  EXPECT_EQ(apply->parameterTypes.front(), structural);
  const compiler::TypeDescriptor holder = context.language().types.get("CallbackHolder");
  ASSERT_EQ(holder.fields.size(), 1u);
  EXPECT_EQ(holder.fields.front().type, structural);

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase resultPhrase =
      root.matchExact(Byte(const_cast<char *>("signature_result")), 0, 16 * Byte::length).getPhrase();
  auto result = reinterpret_cast<std::int64_t (*)()>(recurloop::Assembler::nativeEntry(resultPhrase));
  EXPECT_EQ(result(), 517);
  EXPECT_EQ(context.language().findFunctions("classify").size(), 2u);
}

TEST_F(AssemblerTesting, UsesPhraseBackedFunctionStatementsOperatorsAndTypeConstructors) {
  ASSERT_EQ(execute(R"(
let array_parameter = fn (values:i64[2]*) -> i64 {
  let left = 20
  var right = 22
  if left < right {
    return left + right
  }
  return 0
}
)"),
            0)
      << error();

  const auto child = [](lexicon::Phrase owner, std::string_view key) {
    return owner.matchExact(Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length).getPhrase();
  };
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase statements = child(child(root, std::string_view{"\0fn-grammar", 11}), "statements");
  lexicon::Phrase letSyntax = child(statements, "let");
  lexicon::Phrase topLevelLet = child(root, "let");
  ASSERT_FALSE(letSyntax.isNull());
  ASSERT_TRUE(letSyntax.containsPrototype());
  EXPECT_EQ(letSyntax.getPrototype().getAddress(), topLevelLet.getAddress());
  lexicon::Phrase letEmitter = child(letSyntax, std::string_view{"\0fn-emit", 8});
  ASSERT_FALSE(letEmitter.isNull());
  EXPECT_EQ(context.actions().name(letEmitter.getAction()), "fn.statement.emit-variable");

  lexicon::Phrase addition = recurloop::Expressions::infixOperator(context, "+");
  lexicon::Phrase additionInference = child(addition, std::string_view{"\0fn-infer", 9});
  lexicon::Phrase additionEmitter = child(addition, std::string_view{"\0fn-emit", 8});
  ASSERT_FALSE(additionInference.isNull());
  ASSERT_FALSE(additionEmitter.isNull());
  EXPECT_EQ(context.actions().name(additionInference.getAction()), "fn.operator.infer-left");
  EXPECT_EQ(context.actions().name(additionEmitter.getAction()), "fn.operator.emit-add");

  lexicon::Phrase typePrefix = child(child(root, std::string_view{"\0type-syntax", 12}), "prefix");
  lexicon::Phrase functionConstructor = child(typePrefix, "fn");
  ASSERT_FALSE(functionConstructor.isNull());
  EXPECT_EQ(context.actions().name(functionConstructor.getAction()), "type-syntax.function");

  const compiler::TypeId integer = context.language().types.find("i64");
  const compiler::TypeId array = context.language().types.arrayOf(integer, 2);
  const std::optional<compiler::TypedFunction> function = context.language().findFunction("array_parameter");
  ASSERT_TRUE(function);
  ASSERT_EQ(function->parameterTypes.size(), 1u);
  EXPECT_EQ(function->parameterTypes.front(), context.language().types.pointerTo(array));
}

TEST_F(AssemblerTesting, ExtendsSyntaxWithPrototypePhrasesWithoutParallelSymbolOrBehaviorCopies) {
  ASSERT_EQ(execute(R"(
let otherwise = <else>
let callable = <fn>
let ptr = <*>
let field_kind = <type>
let field_scope = <dictionary>
let automatic = <module:auto>
let word_plus = <+>
let "%%" = <+>
let "@" = <return>
let move = <mov>
let copy = <mov>
let open = <(>
let close = <)>
let begin = <{>
let end = <}>
let address = <&>
let dereference = <*>
let convert = <cast>
let accumulator = <rax>
let base = <rbp>
let octet = <byte>
let memory = <[>
let memory_end = <]>
let offset = <+>
let with = <,>
let text_section = <.text>
let emit_byte = <db>

if false { assert false } otherwise { assert true }
module automatic
let syntax_descriptor = phrase {
  field_kind = <phrase-types:data>
  field_scope = true
}
let apply_syntax = fn (callback:callable (i64) -> i64, value:i64 ptr) -> i64 {
  return callback(value[0]) %% 0
}
let identity_syntax = fn (value:i64) -> i64 { @ value }
let syntax_result = fn () -> i64 {
  let value:i64 = 42
  return apply_syntax(identity_syntax, &value)
}
let intrinsic_aliases = fn (value:i64) -> i64 {
  var copy:i64 = value
  return convert(i64, dereference address copy)
}
fn newline_parameters (left:i64
                       right:i64) -> i64 {
  return left %% right
}
let structural_aliases = fn open value:i64 close -> i64 begin
  @ value
end
let aliased_instruction = asm {
  text_section
  copy accumulator with 40
  move accumulator with 42
  copy al with octet memory base offset 0 memory_end
  emit_byte 0x90
  ret
}
assert 20 %% 22 == 42
assert 20 word_plus 22 == 42
assert syntax_result() == 42
assert intrinsic_aliases(42) == 42
assert newline_parameters(20, 22) == 42
assert structural_aliases open 42 close == 42
)"),
            0)
      << error();
}

TEST_F(AssemblerTesting, RejectsAnIncompleteFunctionOutsideLet) {
  EXPECT_NE(execute("fn missing() -> i64\n"), 0);
  EXPECT_NE(error().find("signature aliases require 'let name = fn ...'"), std::string::npos);
}

TEST_F(AssemblerTesting, RejectsCallbackWithAnIncompatibleSignature) {
  EXPECT_NE(execute(R"(
let text_length = fn (value:u8*) -> i64 {
  return 1
}
let apply = fn (callback:fn (i64) -> i64, value:i64) -> i64 {
  return callback(value)
}
let invalid_callback = fn () -> i64 {
  return apply(text_length, 40)
}
)"),
            0);
  EXPECT_NE(error().find("no matching overload for 'apply'"), std::string::npos) << error();
}

TEST_F(AssemblerTesting, ValidatesArgumentsOfIndirectTypedCalls) {
  EXPECT_NE(execute(R"(
let invalid_indirect_call = fn (callback:fn (i64) -> i64) -> i64 {
  return callback("not an integer")
}
)"),
            0);
  EXPECT_NE(error().find("incompatible"), std::string::npos) << error();
}

TEST_F(AssemblerTesting, KeepsNativeValueSyntaxSmallAndComposable) {
  ASSERT_EQ(execute(R"(
let native_mark = fn (target:i64*, digit:i64) -> i64 {
  target[0] = target[0] * 10 + digit
  return 0
}
let native_add = fn (left:i64, right:i64) -> i64 {
  return left + right
}
let native_features = fn (input:i64, marker:i64*) -> i64 {
  let operation = native_add
  var result = if input > 0 {
    operation(input, 1)
  } else {
    0 - input
  }
  result += {
    let adjustment = 1
    adjustment
  }
  defer native_mark(marker, 1)
  defer native_mark(marker, 2)
  return result
}
let native_require = fn (value:i64*) -> i64* {
  return value?
}
)"),
            0)
      << error();

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };
  lexicon::Phrase root = context.lexicon.phrase();
  auto entry = [&](const std::string &name) {
    lexicon::Phrase phrase = child(root, name);
    return recurloop::Assembler::nativeEntry(phrase);
  };

  auto features = reinterpret_cast<std::int64_t (*)(std::int64_t, std::int64_t *)>(entry("native_features"));
  auto require = reinterpret_cast<std::int64_t *(*)(std::int64_t *)>(entry("native_require"));
  std::int64_t marker = 0;
  std::int64_t value = 42;
  EXPECT_EQ(features(40, &marker), 42);
  EXPECT_EQ(marker, 21);
  EXPECT_EQ(require(&value), &value);
  EXPECT_EQ(require(nullptr), nullptr);
}

TEST_F(AssemblerTesting, UsesDictionariesAsNamespacesAndRecordFunctionsAsReceiverMethods) {
  ASSERT_EQ(execute(R"(
let Math = [
  add = fn (left:i64, right:i64) -> i64 {
    return left + right
  }
]
let Geometry = []
record Geometry:Point {
  x:i64
  y:i64
}
let Geometry:Point:sum = fn (self:Point*) -> i64 {
  return self.x + self.y
}
let namespace_result = fn () -> i64 {
  return Math:add(19, 23)
}
let Geometry:method_result = fn (point:Point*) -> i64 {
  return point.sum()
}
)"),
            0)
      << error();

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };
  lexicon::Phrase root = context.lexicon.phrase();
  const auto entry = [&](const std::string &name) {
    lexicon::Phrase phrase = child(root, name);
    return recurloop::Assembler::nativeEntry(phrase);
  };

  ASSERT_TRUE(context.language().findFunction("Math:add"));
  ASSERT_TRUE(context.language().findFunction("Geometry:Point:sum"));
  auto namespaceResult = reinterpret_cast<std::int64_t (*)()>(entry("namespace_result"));
  EXPECT_EQ(namespaceResult(), 42);

  struct Point {
    std::int64_t x;
    std::int64_t y;
  } point{20, 22};
  lexicon::Phrase geometry = child(root, "Geometry");
  lexicon::Phrase methodResultPhrase = child(geometry, "method_result");
  auto methodResult =
      reinterpret_cast<std::int64_t (*)(Point *)>(recurloop::Assembler::nativeEntry(methodResultPhrase));
  EXPECT_EQ(methodResult(&point), 42);
}

TEST_F(AssemblerTesting, ResolvesBareFunctionsFromTheLongestLexicalScope) {
  ASSERT_EQ(execute(R"(
let root_value = fn (value:i64) -> i64 {
  return value + 10
}
let Scope = []
let Scope:value = fn (value:i64) -> i64 {
  return value + 1
}
let Scope:value = fn (value:u8*) -> i64 {
  return 100
}
let Scope:apply = fn (callback:fn (i64) -> i64, value:i64) -> i64 {
  return callback(value)
}
let Scope:recurse = fn (value:i64) -> i64 {
  if value == 0 {
    return 0
  }
  return recurse(value - 1) + 1
}
let Scope:Nested = []
let Scope:Nested:parent_call = fn () -> i64 {
  return value(41)
}
let Scope:Nested:value = fn (value:i64) -> i64 {
  return value + 2
}
let Scope:Nested:nearest_call = fn () -> i64 {
  return value(40)
}
let Scope:callback = fn () -> i64 {
  let selected:fn (i64) -> i64 = value
  return apply(selected, 41)
}
let Scope:inline_callback = fn () -> i64 {
  return apply(fn (input:i64) -> i64 { return value(input) }, 41)
}
let Scope:root_fallback = fn () -> i64 {
  return root_value(32)
}
let Scope:owned = []
let Scope:owned:value = fn (value:i64) -> i64 {
  return value + 3
}
let Scope:owned = fn () -> i64 {
  return value(39)
}
let lexical_result = fn () -> i64 {
  return Scope:Nested:parent_call() + Scope:Nested:nearest_call() + Scope:callback() + Scope:inline_callback() + Scope:root_fallback() + Scope:owned() + Scope:recurse(6)
}
)"),
            0)
      << error();

  const std::vector<compiler::TypedFunction> nearest =
      context.language().findFunctions("value", "Scope:Nested:nearest_call");
  ASSERT_EQ(nearest.size(), 1u);
  EXPECT_EQ(nearest.front().name, "Scope:Nested:value");

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase resultPhrase =
      root.matchExact(Byte(const_cast<char *>("lexical_result")), 0, 14 * Byte::length).getPhrase();
  auto result = reinterpret_cast<std::int64_t (*)()>(recurloop::Assembler::nativeEntry(resultPhrase));
  EXPECT_EQ(result(), 258);
}

TEST_F(AssemblerTesting, DoesNotMergeOverloadsFromShorterLexicalScopes) {
  EXPECT_NE(execute(R"(
let Scope = []
let Scope:convert = fn (value:i64) -> i64 {
  return value
}
let Scope:Nested = []
let Scope:Nested:convert = fn (value:u8*) -> i64 {
  return 0
}
let Scope:Nested:run = fn () -> i64 {
  return convert(42)
}
)"),
            0);
  EXPECT_NE(error().find("no matching overload for 'convert'"), std::string::npos);
}

TEST_F(AssemblerTesting, ResolvesForwardNativeCallsLazily) {
  ASSERT_EQ(execute(R"(
forward second() -> i64
let first = fn () -> i64 {
  return second()
}
let second = fn () -> i64 {
  return 42
}
)"),
            0)
      << error();

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase first = child(root, "first");
  ASSERT_TRUE(first.isInvokable());
  ASSERT_NO_THROW(first.invoke(context));

  std::uintptr_t entry = 0;
  ASSERT_NO_THROW(entry = recurloop::Assembler::nativeEntry(first));
  EXPECT_EQ(reinterpret_cast<std::int64_t (*)()>(entry)(), 42);
  const std::optional<compiler::TypedFunction> second = context.language().findFunction("second");
  ASSERT_TRUE(second);
  EXPECT_FALSE(second->imported);
}

TEST_F(AssemblerTesting, DeclaresVariadicExternalPhrasesForNativeCalls) {
  ASSERT_EQ(execute("extern printf(format:u8*, ...) -> i64 abi sysv-amd64\n"), 0) << error();
  const std::optional<compiler::TypedFunction> function = context.language().findFunction("printf");
  ASSERT_TRUE(function);
  EXPECT_TRUE(function->imported);
  EXPECT_TRUE(function->signature.variadic);
  EXPECT_EQ(function->parameterTypes.size(), 1u);
}

TEST_F(AssemblerTesting, LinksAnExternalObjectIntoObjectAndExecutableOutputs) {
  const std::string inputPath = objectPath("linked input");
  const std::string outputPath = objectPath("linked-output");
  const std::string executable = executablePath("linked-output");
  std::filesystem::remove(inputPath);
  std::filesystem::remove(outputPath);
  std::filesystem::remove(executable);

  compiler::Module dependency;
  const std::array<std::uint8_t, 1> body = {0xc3};
  dependency.append(compiler::SectionKind::Text, body, 16);
  dependency.define("linked_helper", compiler::SectionKind::Text, 0);
  writeFile(inputPath, compiler::ElfWriter::write(dependency));

  const std::string source = "link object \"" + inputPath +
                             "\"\n"
                             "extern linked_helper() -> void abi sysv-amd64\n"
                             "emit object \"" +
                             outputPath + R"(" object_caller = asm {
  invoke linked_helper()
  ret
}
emit executable ")" + executable +
                             R"(" executable_caller = asm {
  invoke linked_helper()
  ret
}
)";

  ASSERT_EQ(execute(source), 0) << error();
  const std::vector<std::uint8_t> object = readFile(outputPath);
  EXPECT_TRUE(symbolDefined(object, "object_caller"));
  EXPECT_TRUE(symbolDefined(object, "linked_helper"));

  const pid_t process = fork();
  ASSERT_NE(process, -1);
  if (process == 0) {
    execl(executable.c_str(), executable.c_str(), static_cast<char *>(nullptr));
    _exit(127);
  }
  int status = 0;
  ASSERT_EQ(waitpid(process, &status, 0), process);
  EXPECT_TRUE(WIFEXITED(status));
  EXPECT_EQ(WEXITSTATUS(status), 0);

  std::filesystem::remove(inputPath);
  std::filesystem::remove(outputPath);
  std::filesystem::remove(executable);
}

TEST_F(AssemblerTesting, LinksAndRunsAnExecutableWithTheSystemLibc) {
  const std::string executable = executablePath("shared-libc");
  std::filesystem::remove(executable);

  const std::string source = "link shared \"c\"\n"
                             "extern atoi(text:u8*) -> i64 abi sysv-amd64\n"
                             "extern printf(format:u8*, ...) -> i64 abi sysv-amd64\n"
                             "emit executable \"" +
                             executable + R"(" libc_entry = fn (argc:i64, argv:u8**) -> i64 {
  if argc <= 1 {
    return 1
  } else {
    printf("libc %lld\n", atoi(argv[1]))
    return 0
  }
}
link clear
)";

  ASSERT_EQ(execute(source), 0) << error();
  int outputPipe[2];
  ASSERT_EQ(pipe(outputPipe), 0);
  const pid_t process = fork();
  ASSERT_NE(process, -1);
  if (process == 0) {
    close(outputPipe[0]);
    if (dup2(outputPipe[1], STDOUT_FILENO) == -1) _exit(126);
    close(outputPipe[1]);
    execl(executable.c_str(), executable.c_str(), "42", static_cast<char *>(nullptr));
    _exit(127);
  }
  close(outputPipe[1]);
  std::string childOutput;
  std::array<char, 64> outputBuffer;
  for (ssize_t bytes = 0; (bytes = read(outputPipe[0], outputBuffer.data(), outputBuffer.size())) > 0;)
    childOutput.append(outputBuffer.data(), static_cast<std::size_t>(bytes));
  close(outputPipe[0]);
  int status = 0;
  ASSERT_EQ(waitpid(process, &status, 0), process);
  EXPECT_TRUE(WIFEXITED(status));
  EXPECT_EQ(WEXITSTATUS(status), 0);
  EXPECT_EQ(childOutput, "libc 42\n");

  std::filesystem::remove(executable);
}

TEST_F(AssemblerTesting, FindsAndLinksALazilySelectedLibraryMember) {
  const std::string libraryName = "recurloop-linked-archive-" + std::to_string(getpid());
  const std::string archivePath = "/tmp/lib" + libraryName + ".a";
  const std::string outputPath = objectPath("archive-output");
  std::filesystem::remove(archivePath);
  std::filesystem::remove(outputPath);

  compiler::Module dependency;
  const std::array<std::uint8_t, 1> body = {0xc3};
  dependency.append(compiler::SectionKind::Text, body);
  dependency.define("archive_helper", compiler::SectionKind::Text, 0);
  writeFile(archivePath, archiveWith("helper.o", compiler::ElfWriter::write(dependency)));

  const std::string source = "link archive \"" + archivePath +
                             "\"\n"
                             "link clear\n"
                             "link path \"/tmp\"\n"
                             "link library \"" +
                             libraryName +
                             "\"\n"
                             "extern archive_helper() -> void\n"
                             "emit object \"" +
                             outputPath + R"(" archive_caller = asm {
  invoke archive_helper()
  ret
}
)";
  ASSERT_EQ(execute(source), 0) << error();
  const std::vector<std::uint8_t> object = readFile(outputPath);
  EXPECT_TRUE(symbolDefined(object, "archive_helper"));

  std::filesystem::remove(archivePath);
  std::filesystem::remove(outputPath);
}

TEST_F(AssemblerTesting, ClearsExternalLinkInputsExplicitly) {
  const std::string inputPath = objectPath("clear-link-input");
  const std::string outputPath = objectPath("clear-link-output");
  compiler::Module dependency;
  const std::array<std::uint8_t, 1> body = {0xc3};
  dependency.append(compiler::SectionKind::Text, body);
  dependency.define("cleared_helper", compiler::SectionKind::Text, 0);
  writeFile(inputPath, compiler::ElfWriter::write(dependency));

  const std::string source = "link object \"" + inputPath +
                             "\"\n"
                             "link clear\n"
                             "extern cleared_helper() -> void\n"
                             "emit object \"" +
                             outputPath + R"(" caller = asm {
  invoke cleared_helper()
  ret
}
)";
  ASSERT_EQ(execute(source), 0) << error();
  const std::vector<std::uint8_t> object = readFile(outputPath);
  EXPECT_FALSE(symbolDefined(object, "cleared_helper"));

  std::filesystem::remove(inputPath);
  std::filesystem::remove(outputPath);
}

TEST_F(AssemblerTesting, RejectsInvalidTypedInvokeArgumentsBeforeWritingObject) {
  const std::string path = objectPath("typed-invalid");
  std::filesystem::remove(path);
  const std::string source = "extern target(value:i64) -> void\n"
                             "emit object \"" +
                             path + R"("
let caller = asm { invoke target() ret }
)";
  EXPECT_NE(execute(source), 0);
  EXPECT_NE(error().find("invalid argument count"), std::string::npos);
  EXPECT_FALSE(std::filesystem::exists(path));
}

TEST_F(AssemblerTesting, PreservesThePendingDefinitionWhenObjectOutputCannotBeOpened) {
  const std::string path = "/tmp/recurloop-missing-" + std::to_string(getpid()) + "/output.o";
  const std::string source = "emit object \"" + path + "\"\nlet broken = asm { ret }\n";

  EXPECT_NE(execute(source), 0);
#ifdef RECURLOOP_ENABLE_LLVM
  EXPECT_NE(error().find("LLVM object: linker exited with status"), std::string::npos);
#else
  EXPECT_NE(error().find("native object: cannot open output file '" + path + "'"), std::string::npos);
#endif
  EXPECT_EQ(context.runtime.size(), 0u);
  EXPECT_FALSE(code().empty());
}

TEST_F(AssemblerTesting, WritesExactUserControlledBytesWithoutAnObjectContainer) {
  const std::string path = objectPath("raw-output");
  std::filesystem::remove(path);
  const std::string source = "emit raw \"" + path + "\" = hex { 7f 45 4c 46 02 01 00 ff }\n";

  ASSERT_EQ(execute(source), 0) << error();
  EXPECT_EQ(readFile(path), (std::vector<std::uint8_t>{0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01, 0x00, 0xff}));
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, RejectsANameThatRawOutputWouldIgnore) {
  const std::string path = objectPath("named-raw-output");
  std::filesystem::remove(path);
  const std::string source = "emit raw \"" + path + "\" ignored = hex { 01 }\n";

  EXPECT_NE(execute(source), 0);
  EXPECT_NE(error().find("a definition name is not allowed because raw output has no symbols"), std::string::npos);
  EXPECT_FALSE(std::filesystem::exists(path));
}

TEST_F(AssemblerTesting, EmitsAndRunsAnAnonymousExecutableWithoutLet) {
  const std::string path = executablePath("anonymous-output");
  std::filesystem::remove(path);
  const std::string source = "emit executable \"" + path + "\" = asm { ret }\n";

  ASSERT_EQ(execute(source), 0) << error();
  const pid_t process = fork();
  ASSERT_NE(process, -1);
  if (process == 0) {
    execl(path.c_str(), path.c_str(), static_cast<char *>(nullptr));
    _exit(127);
  }
  int status = 0;
  ASSERT_EQ(waitpid(process, &status, 0), process);
  EXPECT_TRUE(WIFEXITED(status));
  EXPECT_EQ(WEXITSTATUS(status), 0);
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, ReturnsTheNativeEntrypointStatusFromAStaticExecutable) {
  const std::string path = executablePath("exit-status");
  std::filesystem::remove(path);
  const std::string source = "emit executable \"" + path + R"(" status_entry = fn () -> i64 {
  return 42
}
)";

  ASSERT_EQ(execute(source), 0) << error();
  const pid_t process = fork();
  ASSERT_NE(process, -1);
  if (process == 0) {
    execl(path.c_str(), path.c_str(), static_cast<char *>(nullptr));
    _exit(127);
  }
  int status = 0;
  ASSERT_EQ(waitpid(process, &status, 0), process);
  EXPECT_TRUE(WIFEXITED(status));
  EXPECT_EQ(WEXITSTATUS(status), 42);
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, RejectsAnEmitDirectiveWithoutADefinition) {
  const std::string path = objectPath("missing-definition");
  std::filesystem::remove(path);

  EXPECT_NE(execute("emit object \"" + path + "\""), 0);
  EXPECT_NE(error().find("expected a definition after the output path"), std::string::npos);
  EXPECT_FALSE(std::filesystem::exists(path));
}

TEST_F(AssemblerTesting, EmitsAndRunsTheNextNativeDefinitionAsAStaticElfExecutable) {
  const std::string path = executablePath("standalone-output");
  std::filesystem::remove(path);
  const std::string source = "emit executable \"" + path + R"("
let standalone = asm { ret }
let jit = asm { ret }
)";

  ASSERT_EQ(execute(source), 0);
  const std::vector<std::uint8_t> executable = readFile(path);
  ASSERT_GE(executable.size(), sizeof(Elf64_Ehdr));
  Elf64_Ehdr header;
  std::memcpy(&header, executable.data(), sizeof(header));
  EXPECT_EQ(std::memcmp(header.e_ident, ELFMAG, SELFMAG), 0);
  EXPECT_EQ(header.e_type, ET_EXEC);
  EXPECT_EQ(header.e_machine, EM_X86_64);
  EXPECT_NE(std::filesystem::status(path).permissions() & std::filesystem::perms::owner_exec,
            std::filesystem::perms::none);

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };
  lexicon::Phrase root = context.lexicon.phrase();
  EXPECT_FALSE(child(root, "standalone").isInvokable());
  EXPECT_TRUE(child(root, "jit").isInvokable());
  EXPECT_GT(context.runtime.size(), 0u);

  const pid_t process = fork();
  ASSERT_NE(process, -1);
  if (process == 0) {
    execl(path.c_str(), path.c_str(), static_cast<char *>(nullptr));
    _exit(127);
  }
  int status = 0;
  ASSERT_EQ(waitpid(process, &status, 0), process);
  EXPECT_TRUE(WIFEXITED(status));
  EXPECT_EQ(WEXITSTATUS(status), 0);
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, AutomaticallyLinksInvokedPhraseModulesIntoExecutable) {
  const std::string path = executablePath("automatic-module-output");
  std::filesystem::remove(path);
  const std::string source = "let helper = asm { ret }\n"
                             "emit executable \"" +
                             path + R"("
let caller = asm {
  invoke helper
  ret
}
)";

  ASSERT_EQ(execute(source), 0) << error();
  const pid_t process = fork();
  ASSERT_NE(process, -1);
  if (process == 0) {
    execl(path.c_str(), path.c_str(), static_cast<char *>(nullptr));
    _exit(127);
  }
  int status = 0;
  ASSERT_EQ(waitpid(process, &status, 0), process);
  EXPECT_TRUE(WIFEXITED(status));
  EXPECT_EQ(WEXITSTATUS(status), 0);
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, SelectsTheRootDefinitionAsAnExplicitModuleEntry) {
  const std::string path = executablePath("explicit-entry-output");
  std::filesystem::remove(path);
  const std::string source = "module entry start\nemit executable \"" + path + R"("
let start = asm { ret }
)";

  ASSERT_EQ(execute(source), 0) << error();
  const pid_t process = fork();
  ASSERT_NE(process, -1);
  if (process == 0) {
    execl(path.c_str(), path.c_str(), static_cast<char *>(nullptr));
    _exit(127);
  }
  int status = 0;
  ASSERT_EQ(waitpid(process, &status, 0), process);
  EXPECT_TRUE(WIFEXITED(status));
  EXPECT_EQ(WEXITSTATUS(status), 0);
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, ManuallyIncludesUnreferencedPhraseModulesInObject) {
  const std::string path = objectPath("manual-module-output");
  std::filesystem::remove(path);
  const std::string source = "let helper = asm { ret }\n"
                             "module manual\nmodule include helper\n"
                             "emit object \"" +
                             path + R"("
let caller = asm { ret }
)";

  ASSERT_EQ(execute(source), 0) << error();
  const std::vector<std::uint8_t> object = readFile(path);
  EXPECT_TRUE(symbolDefined(object, "caller"));
  EXPECT_TRUE(symbolDefined(object, "helper"));
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, ExcludesPhraseModulesForLaterOrDynamicLinking) {
  const std::string path = objectPath("excluded-module-output");
  std::filesystem::remove(path);
  const std::string source = "let helper = asm { ret }\n"
                             "module exclude helper\n"
                             "emit object \"" +
                             path + R"("
let caller = asm { invoke helper ret }
)";

  ASSERT_EQ(execute(source), 0) << error();
  const std::vector<std::uint8_t> object = readFile(path);
  EXPECT_TRUE(symbolDefined(object, "caller"));
  EXPECT_FALSE(symbolDefined(object, "helper"));
  std::filesystem::remove(path);
}

TEST_F(AssemblerTesting, RejectsProcessLocalPhraseImportsInAStandaloneExecutable) {
  const std::string path = executablePath("imported-output");
  std::filesystem::remove(path);
  const std::string source = "emit executable \"" + path + R"("
let broken = {
  invoke <debug:ping>
}
)";

  EXPECT_NE(execute(source), 0);
#ifdef RECURLOOP_ENABLE_LLVM
  EXPECT_NE(error().find("LLVM executable: linker exited with status"), std::string::npos);
#else
  EXPECT_NE(error().find("ELF executable cannot resolve imported symbol"), std::string::npos);
#endif
  EXPECT_FALSE(std::filesystem::exists(path));
  EXPECT_EQ(context.runtime.size(), 0u);
  EXPECT_FALSE(code().empty());
}

TEST_F(AssemblerTesting, InvokesLanguageAndGeneratedPhrases) {
  ASSERT_EQ(execute(R"(
let callee = asm {
  invoke debug:ping
  ret
}
let caller = asm {
  invoke <callee>
  ret
}
caller
)"),
            0);
  EXPECT_EQ(output(), "pong\n");
}

TEST_F(AssemblerTesting, EmitsFiveByteNativeCallsAndTurnsTheFinalInvokeIntoATailJump) {
  const compiler::Assembler::NativeInvocation direct = compiler::Assembler::encodeNativeInvocation();
  ASSERT_EQ(direct.code.size(), 5u);
  EXPECT_EQ(direct.code[0], 0xe8);

  ASSERT_EQ(execute(R"(
let invoke_leaf = asm {
  ret
}
let invoke_chain = {
  invoke <invoke_leaf>
  invoke <invoke_leaf>
}
invoke_chain
)"),
            0)
      << error();

  const std::optional<compiler::Module> module = context.language().findModule("invoke_chain");
  ASSERT_TRUE(module);
  const std::vector<std::uint8_t> &text = module->section(compiler::SectionKind::Text).bytes;
#ifdef RECURLOOP_ENABLE_LLVM
  EXPECT_FALSE(text.empty());
#else
  ASSERT_EQ(text.size(), 10u);
  EXPECT_EQ(text[0], 0xe8); // ordinary direct call
  EXPECT_EQ(text[5], 0xe9); // final invoke is a tail jump; no trailing ret
#endif
}

TEST_F(AssemblerTesting, ResolvesSharedAndPerPhraseImportsForSeveralAsmInvocations) {
  ASSERT_EQ(execute(R"(
let caller = asm {
  invoke <debug:ping>
  invoke <debug:ping>
  ret
}
caller
)"),
            0);

  EXPECT_EQ(output(), "pong\npong\n");
  EXPECT_TRUE(code().empty());
}

TEST_F(AssemblerTesting, KeepsStandaloneAsmInvocationsAsResolvedDiagnosticBytes) {
  ASSERT_EQ(execute(R"(
asm {
  invoke <debug:ping>
  ret
}
)"),
            0);

  const std::vector<std::uint8_t> emitted = code();
  const compiler::Assembler::PhraseInvocation invocation = compiler::Assembler::encodePhraseInvocation(3, 3);
  const auto readAddress = [&](std::size_t offset) {
    std::uintptr_t address = 0;
    for (std::size_t byte = 0; byte < sizeof(address); ++byte)
      address |= static_cast<std::uintptr_t>(emitted[offset + byte]) << (byte * 8);
    return address;
  };

  ASSERT_GE(emitted.size(), invocation.code.size());
  EXPECT_EQ(readAddress(invocation.contextAddressPatchOffset), reinterpret_cast<std::uintptr_t>(&context));
  EXPECT_NE(readAddress(invocation.phraseAddressPatchOffset), 0u);
  EXPECT_NE(readAddress(invocation.trampolineAddressPatchOffset), 0u);
}

TEST_F(AssemblerTesting, CompilesLanguageInvokeInBareAndBracketedForms) {
  ASSERT_EQ(execute(R"(
let show = <debug:ping>
let func = {
  invoke show
  invoke <show>
}
func
)"),
            0);
  EXPECT_EQ(output(), "pong\npong\n");
}

TEST_F(AssemblerTesting, LinksSeveralLanguageInvocationsAsNativeModuleImports) {
  ASSERT_EQ(execute(R"(
let first = <debug:ping>
let second = <debug:ping>
let caller = {
  invoke <first>
  invoke <second>
}
caller
)"),
            0);

  EXPECT_EQ(output(), "pong\npong\n");
  EXPECT_TRUE(code().empty());
}

TEST_F(AssemblerTesting, AssemblerInvokeUsesTheLanguageInvokeAsItsPrototype) {
  ASSERT_EQ(execute(""), 0);

  auto child = [](lexicon::Phrase &dictionary, const std::string &key) {
    return dictionary.matchExact(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length).getPhrase();
  };

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase languageInvoke = child(root, "invoke");
  lexicon::Phrase assembler = child(root, "asm");
  lexicon::Phrase assemblerBody = child(assembler, "{");
  lexicon::Phrase assemblerInvoke = child(assemblerBody, "invoke");

  ASSERT_FALSE(languageInvoke.isNull());
  ASSERT_FALSE(assemblerInvoke.isNull());
  EXPECT_EQ(assemblerInvoke.getPrototype().getAddress(), languageInvoke.getAddress());
  EXPECT_EQ(assemblerInvoke.getType().getAddress(), languageInvoke.getType().getAddress());
  EXPECT_EQ(assemblerInvoke.getAction(), languageInvoke.getAction());
}

TEST_F(AssemblerTesting, ResolvesLanguageInvokeFromTheDefinitionDictionary) {
  ASSERT_EQ(execute(R"(
let commands = [
  show = <debug:ping>
  func = {
    invoke show
    invoke <debug:ping>
  }
]
commands:func
)"),
            0);
  EXPECT_EQ(output(), "pong\npong\n");
}

TEST_F(AssemblerTesting, RejectsLanguageInvokeOutsideACompiledPhrase) {
  EXPECT_NE(execute("invoke <debug:ping>\n"), 0);
  EXPECT_NE(error().find(
                "<input>:1:1: invoke: 'invoke' can emit code only inside a compiled phrase block: let name = { ... }"),
            std::string::npos);
}

TEST_F(AssemblerTesting, ReportsAnInvalidLanguageInvokeBeforeEmittingIt) {
  EXPECT_NE(execute(R"(
let func = {
  invoke <missing>
}
)"),
            0);
  EXPECT_NE(error().find("<input>:3:3: invoke: undefined phrase reference '<missing>'; missing 'missing'"),
            std::string::npos);
  EXPECT_TRUE(code().empty());
}

TEST_F(AssemblerTesting, RejectsAnUnclosedCompiledPhraseAndPreservesItsCode) {
  EXPECT_NE(execute(R"(
let show = <debug:ping>
let func = {
  invoke <show>
)"),
            0);
  EXPECT_NE(error().find("<input>:5:1: compiled phrase: unexpected end of input; expected '}'"), std::string::npos);
  EXPECT_FALSE(code().empty());
}

TEST_F(AssemblerTesting, RejectsAnInvokedPhraseThatExpiresWithTheCompiledBlock) {
  EXPECT_NE(execute(R"(
let func = {
  let local = <debug:ping>
  invoke <local>
}
)"),
            0);
  EXPECT_NE(error().find("resolves to a temporary phrase that will not survive the compiled block"), std::string::npos);
  EXPECT_TRUE(code().empty());
}

TEST_F(AssemblerTesting, InvokeRunsTheActionWithoutTheCalleeSourceTransition) {
  ASSERT_EQ(execute(R"(
let group = [
  caller = asm {
    invoke <debug:ping>
    ret
  }
  after = <debug:ping>
]
group:caller after
)"),
            0);
  EXPECT_EQ(output(), "pong\npong\n");
}

TEST_F(AssemblerTesting, UsesTheOrdinaryCallerSavedAbiAcrossGenericInvoke) {
  const compiler::Assembler::PhraseInvocation invocation = compiler::Assembler::encodePhraseInvocation(1, 1);
  EXPECT_EQ(invocation.code.size(), 55u);

  ASSERT_EQ(execute(R"(
let caller = asm {
  invoke <debug:ping>
  ret
}
caller
)"),
            0);
  EXPECT_EQ(output(), "pong\n");
}

TEST_F(AssemblerTesting, ResolvesAColonSeparatedPhraseReference) {
  ASSERT_EQ(execute(R"(
let messages = [
  say = <debug:ping>
]
let caller = asm {
  invoke <messages:say>
  ret
}
caller
)"),
            0);
  EXPECT_EQ(output(), "pong\n");
}

TEST_F(AssemblerTesting, FallsBackToTheGlobalDictionaryFromANestedDefinition) {
  ASSERT_EQ(execute(R"(
let group = []
let group : caller = asm {
  invoke <debug:ping>
  ret
}
group:caller
)"),
            0);
  EXPECT_EQ(output(), "pong\n");
}

TEST_F(AssemblerTesting, KeepsCallAsANativeLabelInstruction) {
  ASSERT_EQ(execute(R"(
asm {
  call target
  ret
target:
  ret
}
)"),
            0);

  const std::vector<std::uint8_t> expected = {0xe8, 0x01, 0x00, 0x00, 0x00, 0xc3, 0xc3};
  EXPECT_EQ(code(), expected);
}

TEST_F(AssemblerTesting, ReportsAnUndefinedInvokedPhraseDuringTheClosingBraceSecondPass) {
  EXPECT_NE(execute(R"(
asm {
  invoke <missing:phrase>
  ret
}
)"),
            0);
  EXPECT_NE(error().find("<input>:3:3: assembler: undefined phrase reference '<missing:phrase>'; missing 'missing'"),
            std::string::npos);
  EXPECT_FALSE(code().empty());
}

TEST_F(AssemblerTesting, ReportsMalformedInvokeOperandsPrecisely) {
  EXPECT_NE(execute("asm {\n  invoke <>\n}\n"), 0);
  EXPECT_NE(error().find("<input>:2:3: assembler: 'invoke' phrase reference cannot be empty"), std::string::npos);
}

TEST_F(AssemblerTesting, RejectsANonInvokablePhraseDuringTheSecondPass) {
  EXPECT_NE(executeWithNonInvokablePhrase("asm {\n  invoke <data>\n}\n"), 0);
  EXPECT_NE(error().find("<input>:2:3: assembler: phrase reference '<data>' resolves to a non-invokable phrase"),
            std::string::npos);
}

TEST_F(AssemblerTesting, RejectsElaborationPhrasesAsInvokeTargets) {
  EXPECT_NE(execute(R"(
let caller = asm {
  invoke <let>
  ret
}
)"),
            0);
  EXPECT_NE(error().find("phrase reference '<let>' resolves to a non-invokable phrase"), std::string::npos);
}

TEST_F(AssemblerTesting, LanguageInvokeAlsoRejectsElaborationPhrases) {
  EXPECT_NE(execute(R"(
let caller = {
  invoke <let>
}
)"),
            0);
  EXPECT_NE(error().find("phrase reference '<let>' resolves to a non-invokable phrase"), std::string::npos);
}

TEST_F(AssemblerTesting, PropagatesAnInvokedPhraseErrorAfterReturningFromJit) {
  EXPECT_NE(executeWithFailingPhrase(R"(
let caller = asm {
  invoke <failing>
  ret
}
caller
)"),
            0);
  EXPECT_NE(error().find("failure raised by invoked phrase"), std::string::npos);
  EXPECT_NE(error().find("<input>:3:3: invoke: invoked phrase 'failing' failed"), std::string::npos);
}

TEST_F(AssemblerTesting, RestoresTheCallerLookupWhenTheInvokedPhraseThrows) {
  EXPECT_NE(executeWithFailingPhrase(R"(
let group = [
  caller = asm {
    invoke <failing>
    ret
  }
]
group:caller
)"),
            0);
  EXPECT_EQ(lookup(), "group");
}

TEST_F(AssemblerTesting, RejectsLabelsThatConflictWithBuiltInPhrases) {
  EXPECT_NE(execute("asm { jmp ret }"), 0);
  EXPECT_NE(error().find("label name 'ret' conflicts with a built-in phrase"), std::string::npos);

  EXPECT_NE(execute("asm { invoke: ret }"), 0);
  EXPECT_NE(error().find("label name 'invoke' conflicts with a built-in phrase"), std::string::npos);

  EXPECT_NE(execute("asm { ret: nop }"), 0);
  EXPECT_NE(error().find("label name 'ret' conflicts with a built-in phrase"), std::string::npos);

  EXPECT_NE(execute("asm { rax: nop }"), 0);
  EXPECT_NE(error().find("label name 'rax' conflicts with a built-in phrase"), std::string::npos);

  EXPECT_NE(execute("asm { qword: nop }"), 0);
  EXPECT_NE(error().find("label name 'qword' conflicts with a built-in phrase"), std::string::npos);
}

TEST_F(AssemblerTesting, LabelsRemainIndependentWhenTheirNamesSharePrefixes) {
  ASSERT_EQ(execute(R"(
asm {
ret_again:
  nop
invoke_later:
  jmp ret_again
}
asm {
ret_again:
  ret
}
)"),
            0);

  const std::vector<std::uint8_t> expected = {0x90, 0xe9, 0xfa, 0xff, 0xff, 0xff, 0xc3};
  EXPECT_EQ(code(), expected);
}

TEST_F(AssemblerTesting, ReportsUndefinedLabelAtItsInstruction) {
  EXPECT_NE(execute(R"(
asm {
  jmp missing
}
)"),
            0);
  EXPECT_NE(error().find("<input>:3:3: assembler: undefined label 'missing'"), std::string::npos);
  EXPECT_FALSE(code().empty());
}

TEST_F(AssemblerTesting, ReportsDuplicateLabelWithBothLocations) {
  EXPECT_NE(execute(R"(
asm {
same:
same:
  ret
}
)"),
            0);
  EXPECT_NE(error().find("<input>:4:1: assembler: duplicate label 'same'; first declared at <input>:3:1"),
            std::string::npos);
}

TEST_F(AssemblerTesting, ReportsOperandTypeAndSizeErrorsPrecisely) {
  EXPECT_NE(execute(R"(
asm {
  mov byte [rax], rbx
}
)"),
            0);
  EXPECT_NE(error().find("<input>:3:3: assembler: operand sizes do not match"), std::string::npos);
}

TEST_F(AssemblerTesting, PreservesTheAssemblerBlockAfterAnInstructionError) {
  EXPECT_NE(execute(R"(
hex {90}
asm {
  nop
  mov byte [rax], rbx
}
)"),
            0);

  const std::vector<std::uint8_t> expected = {0x90, 0x90};
  EXPECT_EQ(code(), expected);
}

TEST_F(AssemblerTesting, RejectsAnUnclosedAssemblerBlockWithoutRunningSecondPass) {
  EXPECT_NE(execute("asm {\n  jmp missing\n"), 0);
  EXPECT_NE(error().find("unexpected end of input; expected '}'"), std::string::npos);
  EXPECT_FALSE(code().empty());
}

TEST_F(AssemblerTesting, ContinuesAnOpenAssemblerAfterDiscardingAnInvalidInputLine) {
  EXPECT_EQ(executeContinuing(R"(
asm {
  nop
  mov byte [rax], rbx
  ret
}
)"),
            0);
  EXPECT_NE(error().find("<input>:4:3: assembler: operand sizes do not match"), std::string::npos);

  const std::vector<std::uint8_t> expected = {0x90, 0xc3};
  EXPECT_EQ(code(), expected);
  EXPECT_TRUE(lookup().empty());
}

TEST_F(AssemblerTesting, LetsInteractiveInputRepairASecondPassError) {
  EXPECT_EQ(executeContinuing(R"(
asm {
  jmp missing
}
missing:
  ret
}
)"),
            0);
  EXPECT_NE(error().find("<input>:3:3: assembler: undefined label 'missing'"), std::string::npos);

  const std::vector<std::uint8_t> expected = {0xe9, 0x00, 0x00, 0x00, 0x00, 0xc3};
  EXPECT_EQ(code(), expected);
  EXPECT_TRUE(lookup().empty());
}

TEST_F(AssemblerTesting, ClearsARecoveredInteractiveErrorBeforeDefaultExit) {
  EXPECT_EQ(executeContinuing("unknown phrase\nexit\n"), 0);
  EXPECT_NE(error().find("undefined phrase"), std::string::npos);
}

TEST_F(AssemblerTesting, InteractiveExitAcceptsAnIntegerExpression) {
  EXPECT_EQ(executeContinuing("var base = 40\nexit base + 2\n"), 42) << error();
}

TEST_F(AssemblerTesting, RejectsAnInvalidInteractiveExitStatusAndContinues) {
  EXPECT_EQ(executeContinuing("exit 256\nexit\n"), 0);
  EXPECT_NE(error().find("exit status must be between 0 and 255"), std::string::npos);
}

TEST_F(AssemblerTesting, StopsAtInteractiveEofWithTheOpenStateIntact) {
  EXPECT_NE(executeContinuing("asm {\n  nop\n"), 0);
  EXPECT_NE(error().find("unexpected end of input; expected '}'"), std::string::npos);

  const std::vector<std::uint8_t> expected = {0x90};
  EXPECT_EQ(code(), expected);
  EXPECT_FALSE(lookup().empty());
}
