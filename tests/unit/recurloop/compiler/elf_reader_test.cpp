#include <compiler/ElfReader.hpp>
#include <compiler/ElfWriter.hpp>
#include <compiler/Module.hpp>
#include <utilities/Exception.hpp>

#include <gtest/gtest.h>

#include <array>
#include <cstdint>
#include <cstring>
#include <elf.h>
#include <span>
#include <string>
#include <vector>

TEST(ElfReaderTesting, ReadsAllocatedSectionsBindingsAndCommonX86Relocations) {
  compiler::Module input;
  const std::array<std::uint8_t, 32> code = {};
  input.append(compiler::SectionKind::Text, code, 16);
  input.define("entry", compiler::SectionKind::Text, 0);
  input.define("local_target", compiler::SectionKind::Text, 31, compiler::SymbolBinding::Local);
  input.define("weak_target", compiler::SectionKind::Text, 31, compiler::SymbolBinding::Weak);
  input.defineAbsolute("constant", 123);
  input.import("external");
  input.import("optional", compiler::SymbolBinding::Weak);
  input.relocate(compiler::SectionKind::Text, 0, compiler::RelocationKind::PCRelative32, "local_target", -4);
  input.relocate(compiler::SectionKind::Text, 4, compiler::RelocationKind::PLTRelative32, "external", -4);
  input.relocate(compiler::SectionKind::Text, 8, compiler::RelocationKind::Absolute64, "constant");
  input.relocate(compiler::SectionKind::Text, 16, compiler::RelocationKind::Absolute32, "weak_target");
  input.relocate(compiler::SectionKind::Text, 20, compiler::RelocationKind::Absolute32Signed, "optional");

  const compiler::Module output = compiler::ElfReader::read(compiler::ElfWriter::write(input), "roundtrip.o");
  ASSERT_NE(output.findSymbol("entry"), nullptr);
  ASSERT_NE(output.findSymbol("weak_target"), nullptr);
  EXPECT_EQ(output.findSymbol("weak_target")->binding, compiler::SymbolBinding::Weak);
  ASSERT_NE(output.findSymbol("constant"), nullptr);
  EXPECT_TRUE(output.findSymbol("constant")->absolute);
  EXPECT_EQ(output.findSymbol("constant")->offset, 123u);
  ASSERT_NE(output.findSymbol("external"), nullptr);
  EXPECT_TRUE(output.findSymbol("external")->imported);
  ASSERT_NE(output.findSymbol("optional"), nullptr);
  EXPECT_EQ(output.findSymbol("optional")->binding, compiler::SymbolBinding::Weak);

  ASSERT_EQ(output.relocations().size(), 5u);
  EXPECT_EQ(output.relocations()[0].kind, compiler::RelocationKind::PCRelative32);
  EXPECT_EQ(output.relocations()[1].kind, compiler::RelocationKind::PLTRelative32);
  EXPECT_EQ(output.relocations()[2].kind, compiler::RelocationKind::Absolute64);
  EXPECT_EQ(output.relocations()[3].kind, compiler::RelocationKind::Absolute32);
  EXPECT_EQ(output.relocations()[4].kind, compiler::RelocationKind::Absolute32Signed);
  EXPECT_TRUE(output.relocations()[0].symbol.starts_with(".Lrecurloop."));
}

TEST(ElfReaderTesting, ProducesAModuleThatCanResolveAnExecutableImport) {
  compiler::Module dependency;
  const std::array<std::uint8_t, 1> body = {0xc3};
  dependency.append(compiler::SectionKind::Text, body, 16);
  dependency.define("external_helper", compiler::SectionKind::Text, 0);
  const compiler::Module loaded =
      compiler::ElfReader::read(compiler::ElfWriter::write(dependency), "external-helper.o");

  compiler::Module caller;
  const std::array<std::uint8_t, 6> code = {0xe8, 0, 0, 0, 0, 0xc3};
  caller.append(compiler::SectionKind::Text, code, 16);
  caller.define("entry", compiler::SectionKind::Text, 0);
  caller.import("external_helper");
  caller.relocate(compiler::SectionKind::Text, 1, compiler::RelocationKind::PLTRelative32, "external_helper", -4);
  caller.merge(loaded);

  EXPECT_NO_THROW(compiler::ElfWriter::writeExecutable(caller, "entry"));
}

TEST(ElfReaderTesting, LowersPicGotRelocationsIntoAnExplicitGotSection) {
  compiler::Module input;
  const std::array<std::uint8_t, 5> code = {0x48, 0x8b, 0x05, 0, 0};
  input.append(compiler::SectionKind::Text, code);
  input.define("entry", compiler::SectionKind::Text, 0);
  input.import("external_data");
  input.relocate(compiler::SectionKind::Text, 1, compiler::RelocationKind::PCRelative32, "external_data", -4);
  std::vector<std::uint8_t> object = compiler::ElfWriter::write(input);

  Elf64_Ehdr header;
  std::memcpy(&header, object.data(), sizeof(header));
  bool replaced = false;
  for (std::size_t index = 0; index < header.e_shnum; ++index) {
    Elf64_Shdr section;
    std::memcpy(&section, object.data() + header.e_shoff + index * header.e_shentsize, sizeof(section));
    if (section.sh_type != SHT_RELA || section.sh_size == 0) continue;
    Elf64_Rela relocation;
    std::memcpy(&relocation, object.data() + section.sh_offset, sizeof(relocation));
    relocation.r_info = ELF64_R_INFO(ELF64_R_SYM(relocation.r_info), R_X86_64_REX_GOTPCRELX);
    std::memcpy(object.data() + section.sh_offset, &relocation, sizeof(relocation));
    replaced = true;
    break;
  }
  ASSERT_TRUE(replaced);

  compiler::Module loaded = compiler::ElfReader::read(object, "pic.o");
  ASSERT_NE(loaded.findSection(".got"), nullptr);
  EXPECT_EQ(loaded.section(".got").bytes.size(), sizeof(std::uint64_t));
  ASSERT_EQ(loaded.relocations().size(), 2u);
  EXPECT_EQ(loaded.relocations()[0].kind, compiler::RelocationKind::Absolute64);
  EXPECT_EQ(loaded.relocations()[0].symbol, "external_data");
  EXPECT_EQ(loaded.relocations()[1].kind, compiler::RelocationKind::PCRelative32);
  EXPECT_TRUE(loaded.relocations()[1].symbol.starts_with(".Lrecurloop."));

  compiler::Module definition;
  const std::array<std::uint8_t, 8> data = {};
  definition.append(compiler::SectionKind::Data, data);
  definition.define("external_data", compiler::SectionKind::Data, 0);
  loaded.merge(definition);
  EXPECT_NO_THROW(compiler::ElfWriter::writeExecutable(loaded, "entry"));
}

TEST(ElfReaderTesting, RejectsMalformedAndNonRelocatableInputs) {
  EXPECT_THROW(compiler::ElfReader::read(std::array<std::uint8_t, 3>{1, 2, 3}, "tiny.o"), Exception);

  compiler::Module module;
  const std::array<std::uint8_t, 1> code = {0xc3};
  module.append(compiler::SectionKind::Text, code);
  module.define("entry", compiler::SectionKind::Text, 0);
  std::vector<std::uint8_t> executable = compiler::ElfWriter::writeExecutable(module, "entry");
  EXPECT_THROW(compiler::ElfReader::read(executable, "program"), Exception);
}
