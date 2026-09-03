#include <compiler/ArchiveReader.hpp>
#include <compiler/ElfWriter.hpp>
#include <compiler/StaticLinker.hpp>
#include <utilities/Exception.hpp>

#include <gtest/gtest.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace {
  void appendArchiveMember(std::vector<std::uint8_t> &archive, std::string name,
                           const std::vector<std::uint8_t> &contents) {
    std::array<char, 60> header;
    header.fill(' ');
    name += '/';
    std::memcpy(header.data(), name.data(), std::min<std::size_t>(name.size(), 16));
    const std::string size = std::to_string(contents.size());
    std::memcpy(header.data() + 48, size.data(), size.size());
    header[58] = '`';
    header[59] = '\n';
    archive.insert(archive.end(), reinterpret_cast<const std::uint8_t *>(header.data()),
                   reinterpret_cast<const std::uint8_t *>(header.data() + header.size()));
    archive.insert(archive.end(), contents.begin(), contents.end());
    if ((archive.size() & 1u) != 0) archive.push_back('\n');
  }

  compiler::Module functionModule(std::string name, std::string import = {}) {
    compiler::Module module;
    const std::array<std::uint8_t, 6> body = {0xe8, 0, 0, 0, 0, 0xc3};
    const std::array<std::uint8_t, 1> leaf = {0xc3};
    module.append(compiler::SectionKind::Text, import.empty() ? std::span<const std::uint8_t>(leaf)
                                                              : std::span<const std::uint8_t>(body),
                  16);
    module.define(std::move(name), compiler::SectionKind::Text, 0);
    if (!import.empty()) {
      module.import(import);
      module.relocate(compiler::SectionKind::Text, 1, compiler::RelocationKind::PLTRelative32, std::move(import), -4);
    }
    return module;
  }

  std::vector<std::uint8_t> archive(std::initializer_list<std::pair<std::string, compiler::Module>> members) {
    const std::string magic = "!<arch>\n";
    std::vector<std::uint8_t> result(magic.begin(), magic.end());
    for (const auto &[name, module] : members) appendArchiveMember(result, name, compiler::ElfWriter::write(module));
    return result;
  }
} // namespace

TEST(StaticLinkerTesting, LazilyExtractsTransitiveArchiveMembers) {
  const std::vector<std::uint8_t> bytes = archive({{"callee.o", functionModule("callee", "leaf")},
                                                   {"leaf.o", functionModule("leaf")},
                                                   {"unused.o", functionModule("unused")}});
  const std::vector<compiler::ArchiveMember> members = compiler::ArchiveReader::read(bytes, "helpers.a");
  ASSERT_EQ(members.size(), 3u);
  EXPECT_EQ(members[0].name, "callee.o");

  compiler::Module root = functionModule("entry", "callee");
  compiler::StaticLinker linker;
  linker.addArchive(members);
  const compiler::Module linked = linker.link(root);

  ASSERT_NE(linked.findSymbol("callee"), nullptr);
  EXPECT_FALSE(linked.findSymbol("callee")->imported);
  ASSERT_NE(linked.findSymbol("leaf"), nullptr);
  EXPECT_FALSE(linked.findSymbol("leaf")->imported);
  EXPECT_EQ(linked.findSymbol("unused"), nullptr);
  EXPECT_NO_THROW(compiler::ElfWriter::writeExecutable(linked, "entry"));
}

TEST(StaticLinkerTesting, AlwaysIncludesExplicitObjectsAndCanBeCleared) {
  compiler::StaticLinker linker;
  linker.addObject(functionModule("explicit_helper"));
  compiler::Module root = functionModule("entry");
  EXPECT_NE(linker.link(root).findSymbol("explicit_helper"), nullptr);
  EXPECT_FALSE(linker.empty());
  linker.clear();
  EXPECT_TRUE(linker.empty());
  EXPECT_EQ(linker.link(root).findSymbol("explicit_helper"), nullptr);
}

TEST(StaticLinkerTesting, RejectsMalformedArchives) {
  const std::array<std::uint8_t, 8> invalid = {'n', 'o', 't', 'a', 'r', 'c', 'h', '\n'};
  EXPECT_THROW(compiler::ArchiveReader::read(invalid, "broken.a"), Exception);
}
