#include <compiler/DebugInfo.hpp>
#include <compiler/ElfReader.hpp>
#include <compiler/ElfWriter.hpp>
#include <compiler/Module.hpp>
#include <compiler/TypeSystem.hpp>
#include <utilities/Exception.hpp>

#include <gtest/gtest.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <elf.h>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {
  template <typename Type> Type readObject(std::span<const std::uint8_t> bytes, std::size_t offset) {
    if (offset > bytes.size() || sizeof(Type) > bytes.size() - offset) throw std::out_of_range("ELF test read");
    Type result;
    std::memcpy(&result, bytes.data() + offset, sizeof(result));
    return result;
  }

  std::string_view tableString(std::span<const std::uint8_t> bytes, const Elf64_Shdr &table, std::size_t offset) {
    if (offset >= table.sh_size || table.sh_offset + offset >= bytes.size()) return {};
    const char *begin = reinterpret_cast<const char *>(bytes.data() + table.sh_offset + offset);
    const std::size_t available = table.sh_size - offset;
    const void *end = std::memchr(begin, 0, available);
    return end == nullptr ? std::string_view{} : std::string_view(begin, static_cast<const char *>(end) - begin);
  }

  struct ParsedElf {
    explicit ParsedElf(const std::vector<std::uint8_t> &object)
        : bytes(object), header(readObject<Elf64_Ehdr>(bytes, 0)) {
      for (std::size_t index = 0; index < header.e_shnum; ++index)
        sections.push_back(readObject<Elf64_Shdr>(bytes, header.e_shoff + index * header.e_shentsize));
    }

    std::size_t section(std::string_view name) const {
      const Elf64_Shdr &names = sections.at(header.e_shstrndx);
      for (std::size_t index = 0; index < sections.size(); ++index)
        if (tableString(bytes, names, sections[index].sh_name) == name) return index;
      throw std::out_of_range("missing ELF section");
    }

    std::span<const std::uint8_t> bytes;
    Elf64_Ehdr header;
    std::vector<Elf64_Shdr> sections;
  };
} // namespace

TEST(ElfWriterTesting, WritesModuleSectionsSymbolsAndX86Relocations) {
  compiler::Module module;
  const std::array<std::uint8_t, 16> text = {0xe8, 0, 0, 0, 0, 0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0xc3};
  const std::array<std::uint8_t, 1> readOnlyData = {42};
  const std::array<std::uint8_t, 8> data = {};
  module.append(compiler::SectionKind::Text, text, 16);
  module.append(compiler::SectionKind::ReadOnlyData, readOnlyData, 8);
  module.append(compiler::SectionKind::Data, data, 8);
  module.define("entry", compiler::SectionKind::Text, 0);
  module.define("answer", compiler::SectionKind::ReadOnlyData, 0);
  module.define("counter", compiler::SectionKind::Data, 0);
  module.import("external");
  module.relocate(compiler::SectionKind::Text, 1, compiler::RelocationKind::PCRelative32, "answer", -4);
  module.relocate(compiler::SectionKind::Text, 7, compiler::RelocationKind::Absolute64, "external", 3);
  module.relocate(compiler::SectionKind::Data, 0, compiler::RelocationKind::Absolute64, "entry");

  const std::vector<std::uint8_t> object = compiler::ElfWriter::write(module);
  const ParsedElf elf(object);

  EXPECT_EQ(std::memcmp(elf.header.e_ident, ELFMAG, SELFMAG), 0);
  EXPECT_EQ(elf.header.e_ident[EI_CLASS], ELFCLASS64);
  EXPECT_EQ(elf.header.e_ident[EI_DATA], ELFDATA2LSB);
  EXPECT_EQ(elf.header.e_type, ET_REL);
  EXPECT_EQ(elf.header.e_machine, EM_X86_64);
  EXPECT_EQ(elf.header.e_shentsize, sizeof(Elf64_Shdr));

  const std::size_t textIndex = elf.section(".text");
  const std::size_t readOnlyDataIndex = elf.section(".rodata");
  const std::size_t dataIndex = elf.section(".data");
  const std::size_t stackNoteIndex = elf.section(".note.GNU-stack");
  const std::size_t symbolTableIndex = elf.section(".symtab");
  const std::size_t stringTableIndex = elf.section(".strtab");
  EXPECT_EQ(elf.sections[textIndex].sh_flags, SHF_ALLOC | SHF_EXECINSTR);
  EXPECT_EQ(elf.sections[readOnlyDataIndex].sh_flags, SHF_ALLOC);
  EXPECT_EQ(elf.sections[dataIndex].sh_flags, SHF_ALLOC | SHF_WRITE);
  EXPECT_EQ(elf.sections[stackNoteIndex].sh_flags, 0u);
  EXPECT_EQ(elf.sections[stackNoteIndex].sh_size, 0u);
  EXPECT_EQ(elf.sections[textIndex].sh_addralign, 16u);
  EXPECT_EQ(elf.sections[readOnlyDataIndex].sh_addralign, 8u);

  const Elf64_Shdr &symbolTable = elf.sections[symbolTableIndex];
  const Elf64_Shdr &strings = elf.sections[stringTableIndex];
  ASSERT_EQ(symbolTable.sh_link, stringTableIndex);
  ASSERT_EQ(symbolTable.sh_info, 5u);
  ASSERT_EQ(symbolTable.sh_entsize, sizeof(Elf64_Sym));

  std::vector<Elf64_Sym> symbols;
  for (std::size_t offset = 0; offset < symbolTable.sh_size; offset += symbolTable.sh_entsize)
    symbols.push_back(readObject<Elf64_Sym>(elf.bytes, symbolTable.sh_offset + offset));
  const auto symbol = [&](std::string_view name) -> const Elf64_Sym & {
    const auto found = std::find_if(symbols.begin(), symbols.end(), [&](const Elf64_Sym &candidate) {
      return tableString(elf.bytes, strings, candidate.st_name) == name;
    });
    if (found == symbols.end()) throw std::out_of_range("missing ELF symbol");
    return *found;
  };

  EXPECT_EQ(symbol("entry").st_shndx, textIndex);
  EXPECT_EQ(ELF64_ST_TYPE(symbol("entry").st_info), STT_FUNC);
  EXPECT_EQ(symbol("answer").st_shndx, readOnlyDataIndex);
  EXPECT_EQ(ELF64_ST_TYPE(symbol("answer").st_info), STT_OBJECT);
  EXPECT_EQ(symbol("counter").st_shndx, dataIndex);
  EXPECT_EQ(symbol("external").st_shndx, SHN_UNDEF);
  EXPECT_EQ(ELF64_ST_BIND(symbol("external").st_info), STB_GLOBAL);

  const auto checkRelocation = [&](std::string_view sectionName, std::size_t expectedTarget, std::size_t expectedOffset,
                                   Elf64_Word expectedType, std::string_view expectedSymbol,
                                   Elf64_Sxword expectedAddend) {
    const Elf64_Shdr &relocations = elf.sections[elf.section(sectionName)];
    ASSERT_EQ(relocations.sh_link, symbolTableIndex);
    ASSERT_EQ(relocations.sh_info, expectedTarget);
    ASSERT_EQ(relocations.sh_entsize, sizeof(Elf64_Rela));
    ASSERT_GE(relocations.sh_size, sizeof(Elf64_Rela));
    const Elf64_Rela relocation = readObject<Elf64_Rela>(elf.bytes, relocations.sh_offset);
    EXPECT_EQ(relocation.r_offset, expectedOffset);
    EXPECT_EQ(ELF64_R_TYPE(relocation.r_info), expectedType);
    EXPECT_EQ(tableString(elf.bytes, strings, symbols.at(ELF64_R_SYM(relocation.r_info)).st_name), expectedSymbol);
    EXPECT_EQ(relocation.r_addend, expectedAddend);
  };
  checkRelocation(".rela.text", textIndex, 1, R_X86_64_PC32, "answer", -4);
  const Elf64_Shdr &textRelocations = elf.sections[elf.section(".rela.text")];
  const Elf64_Rela absolute = readObject<Elf64_Rela>(elf.bytes, textRelocations.sh_offset + sizeof(Elf64_Rela));
  EXPECT_EQ(ELF64_R_TYPE(absolute.r_info), R_X86_64_64);
  EXPECT_EQ(tableString(elf.bytes, strings, symbols.at(ELF64_R_SYM(absolute.r_info)).st_name), "external");
  EXPECT_EQ(absolute.r_addend, 3);
  checkRelocation(".rela.data", dataIndex, 0, R_X86_64_64, "entry", 0);
}

TEST(ElfWriterTesting, PreservesCustomAndNoBitsSections) {
  compiler::Module module;
  const compiler::SectionId metadata =
      module.addSection(".recurloop.types", compiler::SectionType::Note, compiler::SectionFlag::None, 8);
  const std::array<std::uint8_t, 4> note = {0x52, 0x4c, 0x01, 0x00};
  module.append(metadata, note);
  module.reserve(compiler::SectionKind::Bss, 32, 16);
  module.define("descriptor", metadata, 0);
  module.define("storage", compiler::SectionKind::Bss, 8);

  const std::vector<std::uint8_t> object = compiler::ElfWriter::write(module);
  const ParsedElf elf(object);
  const std::size_t metadataIndex = elf.section(".recurloop.types");
  const std::size_t bssIndex = elf.section(".bss");
  EXPECT_EQ(elf.sections[metadataIndex].sh_type, SHT_NOTE);
  EXPECT_EQ(elf.sections[metadataIndex].sh_size, note.size());
  EXPECT_EQ(elf.sections[metadataIndex].sh_addralign, 8u);
  EXPECT_EQ(elf.sections[bssIndex].sh_type, SHT_NOBITS);
  EXPECT_EQ(elf.sections[bssIndex].sh_size, 32u);
  EXPECT_EQ(elf.sections[bssIndex].sh_addralign, 16u);
}

TEST(ElfWriterTesting, PreservesLocalWeakAndAbsoluteSymbols) {
  compiler::Module module;
  const std::array<std::uint8_t, 1> code = {0xc3};
  module.append(compiler::SectionKind::Text, code);
  module.define("local_helper", compiler::SectionKind::Text, 0, compiler::SymbolBinding::Local);
  module.define("weak_api", compiler::SectionKind::Text, 0, compiler::SymbolBinding::Weak);
  module.defineAbsolute("constant", 17);

  const ParsedElf elf(compiler::ElfWriter::write(module));
  const Elf64_Shdr &table = elf.sections[elf.section(".symtab")];
  const Elf64_Shdr &strings = elf.sections[table.sh_link];
  const auto symbol = [&](std::string_view name) {
    for (std::size_t offset = 0; offset < table.sh_size; offset += table.sh_entsize) {
      const Elf64_Sym candidate = readObject<Elf64_Sym>(elf.bytes, table.sh_offset + offset);
      if (tableString(elf.bytes, strings, candidate.st_name) == name) return candidate;
    }
    throw std::out_of_range("missing ELF symbol");
  };

  EXPECT_EQ(ELF64_ST_BIND(symbol("local_helper").st_info), STB_LOCAL);
  EXPECT_EQ(ELF64_ST_BIND(symbol("weak_api").st_info), STB_WEAK);
  EXPECT_EQ(symbol("constant").st_shndx, SHN_ABS);
  EXPECT_EQ(symbol("constant").st_value, 17u);
  EXPECT_EQ(table.sh_info, 1u + module.sections().size() + 1u);
}

TEST(ElfWriterTesting, PreservesStandardArrayAndExtendedSectionFlags) {
  compiler::Module module;
  const compiler::SectionId initializers = module.addSection(
      ".init_array", compiler::SectionType::InitArray,
      compiler::SectionFlag::Alloc | compiler::SectionFlag::Write, 8);
  const compiler::SectionId strings = module.addSection(
      ".rodata.str1.1", compiler::SectionType::ProgramBits,
      compiler::SectionFlag::Alloc | compiler::SectionFlag::Merge | compiler::SectionFlag::Strings, 1);
  const compiler::SectionId tls = module.addSection(
      ".tdata", compiler::SectionType::ProgramBits,
      compiler::SectionFlag::Alloc | compiler::SectionFlag::Write | compiler::SectionFlag::ThreadLocal, 8);
  const std::array<std::uint8_t, 8> bytes = {};
  module.append(initializers, bytes);
  module.append(strings, std::span<const std::uint8_t>(bytes).first(2));
  module.append(tls, bytes);

  const ParsedElf elf(compiler::ElfWriter::write(module));
  EXPECT_EQ(elf.sections[elf.section(".init_array")].sh_type, SHT_INIT_ARRAY);
  EXPECT_EQ(elf.sections[elf.section(".rodata.str1.1")].sh_flags, SHF_ALLOC | SHF_MERGE | SHF_STRINGS);
  EXPECT_EQ(elf.sections[elf.section(".tdata")].sh_flags, SHF_ALLOC | SHF_WRITE | SHF_TLS);
}

TEST(ElfWriterTesting, RejectsInvalidSymbolsAndRelocations) {
  compiler::Module module;
  const std::array<std::uint8_t, 8> placeholder = {};
  module.append(compiler::SectionKind::Text, placeholder);
  module.relocate(compiler::SectionKind::Text, 0, compiler::RelocationKind::Absolute64, "missing");

  EXPECT_THROW(compiler::ElfWriter::write(module), Exception);

  compiler::Module invalidName;
  invalidName.define(std::string("bad\0name", 8), compiler::SectionKind::Text, 0);
  EXPECT_THROW(compiler::ElfWriter::write(invalidName), Exception);
}

TEST(ElfWriterTesting, WritesStaticExecutableSegmentsAndResolvesInternalRelocations) {
  compiler::Module module;
  const std::array<std::uint8_t, 16> text = {0xe8, 0, 0, 0, 0, 0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0xc3};
  const std::array<std::uint8_t, 1> readOnlyData = {42};
  const std::array<std::uint8_t, 8> data = {};
  module.append(compiler::SectionKind::Text, text, 16);
  module.append(compiler::SectionKind::ReadOnlyData, readOnlyData, 8);
  module.append(compiler::SectionKind::Data, data, 8);
  module.define("entry", compiler::SectionKind::Text, 0);
  module.define("local", compiler::SectionKind::Text, 15);
  module.define("answer", compiler::SectionKind::ReadOnlyData, 0);
  module.relocate(compiler::SectionKind::Text, 1, compiler::RelocationKind::PCRelative32, "local", -4);
  module.relocate(compiler::SectionKind::Text, 7, compiler::RelocationKind::Absolute64, "answer", 3);
  module.relocate(compiler::SectionKind::Data, 0, compiler::RelocationKind::Absolute64, "entry");

  const std::vector<std::uint8_t> executable = compiler::ElfWriter::writeExecutable(module, "entry");
  const Elf64_Ehdr header = readObject<Elf64_Ehdr>(executable, 0);
  EXPECT_EQ(std::memcmp(header.e_ident, ELFMAG, SELFMAG), 0);
  EXPECT_EQ(header.e_type, ET_EXEC);
  EXPECT_EQ(header.e_machine, EM_X86_64);
  EXPECT_EQ(header.e_entry, 0x400000u);
  EXPECT_EQ(header.e_phnum, 4u);
  EXPECT_EQ(header.e_shnum, 0u);

  std::vector<Elf64_Phdr> segments;
  for (std::size_t index = 0; index < header.e_phnum; ++index)
    segments.push_back(readObject<Elf64_Phdr>(executable, header.e_phoff + index * header.e_phentsize));
  const auto load = [&](Elf64_Word flags) -> const Elf64_Phdr & {
    const auto found = std::find_if(segments.begin(), segments.end(), [&](const Elf64_Phdr &segment) {
      return segment.p_type == PT_LOAD && segment.p_flags == flags;
    });
    if (found == segments.end()) throw std::out_of_range("missing executable segment");
    return *found;
  };

  const Elf64_Phdr &textSegment = load(PF_R | PF_X);
  const Elf64_Phdr &readOnlySegment = load(PF_R);
  const Elf64_Phdr &dataSegment = load(PF_R | PF_W);
  EXPECT_EQ(textSegment.p_filesz, text.size());
  EXPECT_EQ(readOnlySegment.p_filesz, readOnlyData.size());
  EXPECT_EQ(dataSegment.p_filesz, data.size());
  EXPECT_EQ(readObject<std::int32_t>(executable, textSegment.p_offset + 1), 10);
  EXPECT_EQ(readObject<std::uint64_t>(executable, textSegment.p_offset + 7), readOnlySegment.p_vaddr + 3);
  EXPECT_EQ(readObject<std::uint64_t>(executable, dataSegment.p_offset), textSegment.p_vaddr);

  const auto stack = std::find_if(segments.begin(), segments.end(),
                                  [](const Elf64_Phdr &segment) { return segment.p_type == PT_GNU_STACK; });
  ASSERT_NE(stack, segments.end());
  EXPECT_EQ(stack->p_flags, PF_R | PF_W);
}

TEST(ElfWriterTesting, EmbedsResolvedRecurLoopDebugPointsAfterTheExecutableImage) {
  compiler::Module module;
  const std::array<std::uint8_t, 2> code = {0x90, 0xc3};
  module.append(compiler::SectionKind::Text, code, 16);
  module.define("entry", compiler::SectionKind::Text, 0);

  compiler::DebugPoint input;
  input.symbol = "entry";
  input.path = "program.rl";
  input.function = "main";
  input.phrase = "return";
  input.offset = 1;
  input.line = 7;
  input.column = 3;
  input.locals.push_back({"answer", "i64", 8, 8, static_cast<std::uint8_t>(compiler::TypeKind::Integer), true});
  compiler::DebugInfo::add(module, input);

  module = compiler::ElfReader::read(compiler::ElfWriter::write(module), "debug-roundtrip.o");
  const std::vector<std::uint8_t> executable = compiler::ElfWriter::writeExecutable(module, "entry");
  const std::vector<compiler::DebugPoint> points = compiler::DebugInfo::readExecutable(executable);
  ASSERT_EQ(points.size(), 1u);
  EXPECT_EQ(points[0].address, 0x400001u);
  EXPECT_EQ(points[0].path, "program.rl");
  EXPECT_EQ(points[0].function, "main");
  EXPECT_EQ(points[0].phrase, "return");
  EXPECT_EQ(points[0].line, 7u);
  EXPECT_EQ(points[0].column, 3u);
  ASSERT_EQ(points[0].locals.size(), 1u);
  EXPECT_EQ(points[0].locals[0].name, "answer");
  EXPECT_EQ(points[0].locals[0].frameOffset, 8u);
  EXPECT_TRUE(points[0].locals[0].signedValue);
}

TEST(ElfWriterTesting, DoesNotInventDebugPointsForAnExecutableWithoutMetadata) {
  compiler::Module module;
  const std::array<std::uint8_t, 1> code = {0xc3};
  module.append(compiler::SectionKind::Text, code);
  module.define("entry", compiler::SectionKind::Text, 0);
  const std::vector<std::uint8_t> executable = compiler::ElfWriter::writeExecutable(module, "entry");
  EXPECT_THROW(compiler::DebugInfo::readExecutable(executable), Exception);
}

TEST(ElfWriterTesting, RejectsExecutableImportsAndInvalidEntrySymbols) {
  const std::array<std::uint8_t, 1> code = {0xc3};

  compiler::Module imported;
  imported.append(compiler::SectionKind::Text, code);
  imported.define("entry", compiler::SectionKind::Text, 0);
  imported.import("external");
  EXPECT_THROW(compiler::ElfWriter::writeExecutable(imported, "entry"), Exception);

  compiler::Module missing;
  missing.append(compiler::SectionKind::Text, code);
  EXPECT_THROW(compiler::ElfWriter::writeExecutable(missing, "entry"), Exception);

  compiler::Module dataEntry;
  dataEntry.append(compiler::SectionKind::Data, code);
  dataEntry.define("entry", compiler::SectionKind::Data, 0);
  EXPECT_THROW(compiler::ElfWriter::writeExecutable(dataEntry, "entry"), Exception);

  compiler::Module pastEnd;
  pastEnd.append(compiler::SectionKind::Text, code);
  pastEnd.define("entry", compiler::SectionKind::Text, code.size());
  EXPECT_THROW(compiler::ElfWriter::writeExecutable(pastEnd, "entry"), Exception);
}
