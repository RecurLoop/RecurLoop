#include <compiler/ElfReader.hpp>
#include <compiler/DebugInfo.hpp>

#include <utilities/Exception.hpp>

#include <algorithm>
#include <array>
#include <bit>
#include <cstring>
#include <elf.h>
#include <iomanip>
#include <limits>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace compiler {
  namespace {
    static_assert(std::endian::native == std::endian::little, "ELF64 x86-64 reader requires a little-endian host");

    template <typename Type> Type object(std::span<const std::uint8_t> bytes, std::size_t offset,
                                         std::string_view origin, std::string_view description) {
      if (offset > bytes.size() || sizeof(Type) > bytes.size() - offset)
        THROW(, "ELF object '" << origin << "' has a truncated " << description)
      Type result;
      std::memcpy(&result, bytes.data() + offset, sizeof(result));
      return result;
    }

    std::span<const std::uint8_t> range(std::span<const std::uint8_t> bytes, std::size_t offset, std::size_t size,
                                        std::string_view origin, std::string_view description) {
      if (offset > bytes.size() || size > bytes.size() - offset)
        THROW(, "ELF object '" << origin << "' has a truncated " << description)
      return bytes.subspan(offset, size);
    }

    std::string stringAt(std::span<const std::uint8_t> table, std::size_t offset, std::string_view origin,
                         std::string_view description) {
      if (offset >= table.size()) THROW(, "ELF object '" << origin << "' has an invalid " << description << " offset")
      const char *begin = reinterpret_cast<const char *>(table.data() + offset);
      const void *end = std::memchr(begin, 0, table.size() - offset);
      if (end == nullptr) THROW(, "ELF object '" << origin << "' has an unterminated " << description)
      return std::string(begin, static_cast<const char *>(end));
    }

    std::size_t extent(const Section &section) {
      return section.type == SectionType::NoBits ? section.memorySize : section.bytes.size();
    }

    SectionType sectionType(Elf64_Word type, std::string_view origin, std::string_view name) {
      switch (type) {
      case SHT_PROGBITS: return SectionType::ProgramBits;
#ifdef SHT_X86_64_UNWIND
      case SHT_X86_64_UNWIND: return SectionType::ProgramBits;
#endif
      case SHT_NOBITS: return SectionType::NoBits;
      case SHT_NOTE: return SectionType::Note;
      case SHT_INIT_ARRAY: return SectionType::InitArray;
      case SHT_FINI_ARRAY: return SectionType::FiniArray;
      case SHT_PREINIT_ARRAY: return SectionType::PreinitArray;
      default: THROW(, "ELF object '" << origin << "' uses unsupported allocated section type " << type
                                       << " for '" << name << "'")
      }
    }

    SectionFlag sectionFlags(Elf64_Xword flags) {
      SectionFlag result = SectionFlag::None;
      if ((flags & SHF_ALLOC) != 0) result = result | SectionFlag::Alloc;
      if ((flags & SHF_WRITE) != 0) result = result | SectionFlag::Write;
      if ((flags & SHF_EXECINSTR) != 0) result = result | SectionFlag::Execute;
      if ((flags & SHF_MERGE) != 0) result = result | SectionFlag::Merge;
      if ((flags & SHF_STRINGS) != 0) result = result | SectionFlag::Strings;
      if ((flags & SHF_TLS) != 0) result = result | SectionFlag::ThreadLocal;
      return result;
    }

    SymbolBinding symbolBinding(unsigned binding, std::string_view origin, std::string_view name) {
      switch (binding) {
      case STB_LOCAL: return SymbolBinding::Local;
      case STB_GLOBAL: return SymbolBinding::Global;
      case STB_WEAK: return SymbolBinding::Weak;
      default: THROW(, "ELF object '" << origin << "' uses unsupported binding " << binding << " for symbol '"
                                       << name << "'")
      }
    }

    RelocationKind relocationKind(Elf64_Xword type, std::string_view origin) {
      switch (type) {
      case R_X86_64_PC32: return RelocationKind::PCRelative32;
      case R_X86_64_PLT32: return RelocationKind::PLTRelative32;
      case R_X86_64_64: return RelocationKind::Absolute64;
      case R_X86_64_32: return RelocationKind::Absolute32;
      case R_X86_64_32S: return RelocationKind::Absolute32Signed;
      default: THROW(, "ELF object '" << origin << "' uses unsupported x86-64 relocation " << type)
      }
    }

    bool gotRelative(Elf64_Xword type) {
      return type == R_X86_64_GOTPCREL || type == R_X86_64_GOTPCRELX || type == R_X86_64_REX_GOTPCRELX;
    }

    std::size_t relocationSize(RelocationKind kind) {
      switch (kind) {
      case RelocationKind::PCRelative32:
      case RelocationKind::PLTRelative32:
      case RelocationKind::Absolute32:
      case RelocationKind::Absolute32Signed: return sizeof(std::uint32_t);
      case RelocationKind::Absolute64: return sizeof(std::uint64_t);
      }
      THROW(, "invalid ELF relocation kind")
    }

    std::int64_t implicitAddend(std::span<const std::uint8_t> bytes, std::size_t offset, RelocationKind kind,
                                std::string_view origin) {
      const std::size_t size = relocationSize(kind);
      const auto source = range(bytes, offset, size, origin, "implicit relocation addend");
      std::uint64_t value = 0;
      for (std::size_t index = 0; index < size; ++index) value |= std::uint64_t{source[index]} << (index * 8);
      if (kind == RelocationKind::Absolute32) return static_cast<std::int64_t>(value);
      if (size == sizeof(std::uint32_t)) return static_cast<std::int32_t>(value);
      return static_cast<std::int64_t>(value);
    }

    std::string localPrefix(std::span<const std::uint8_t> bytes, std::string_view origin) {
      std::uint64_t hash = 1469598103934665603ull;
      const auto add = [&](std::uint8_t byte) {
        hash ^= byte;
        hash *= 1099511628211ull;
      };
      for (char character : origin) add(static_cast<std::uint8_t>(character));
      for (std::uint8_t byte : bytes) add(byte);
      std::ostringstream result;
      result << ".Lrecurloop." << std::hex << hash << ".";
      return result.str();
    }
  } // namespace

  Module ElfReader::read(std::span<const std::uint8_t> bytes, std::string_view origin) {
    const Elf64_Ehdr header = object<Elf64_Ehdr>(bytes, 0, origin, "ELF header");
    if (std::memcmp(header.e_ident, ELFMAG, SELFMAG) != 0) THROW(, "file '" << origin << "' is not ELF")
    if (header.e_ident[EI_CLASS] != ELFCLASS64 || header.e_ident[EI_DATA] != ELFDATA2LSB)
      THROW(, "ELF object '" << origin << "' is not little-endian ELF64")
    if (header.e_ident[EI_VERSION] != EV_CURRENT || header.e_version != EV_CURRENT)
      THROW(, "ELF object '" << origin << "' has an unsupported version")
    if (header.e_type != ET_REL) THROW(, "ELF input '" << origin << "' is not a relocatable object")
    if (header.e_machine != EM_X86_64) THROW(, "ELF object '" << origin << "' is not x86-64")
    if (header.e_shentsize != sizeof(Elf64_Shdr) || header.e_shnum == 0 || header.e_shstrndx >= header.e_shnum)
      THROW(, "ELF object '" << origin << "' has an unsupported section table")

    std::vector<Elf64_Shdr> sections;
    sections.reserve(header.e_shnum);
    for (std::size_t index = 0; index < header.e_shnum; ++index)
      sections.push_back(object<Elf64_Shdr>(bytes, header.e_shoff + index * header.e_shentsize, origin,
                                            "section header"));
    const Elf64_Shdr &sectionNamesHeader = sections[header.e_shstrndx];
    const auto sectionNames = range(bytes, sectionNamesHeader.sh_offset, sectionNamesHeader.sh_size, origin,
                                    "section-name table");

    Module module;
    const SectionId invalidSection = std::numeric_limits<SectionId>::max();
    std::vector<SectionId> mappedSections(sections.size(), invalidSection);
    std::vector<std::size_t> sectionOffsets(sections.size(), 0);
    for (std::size_t index = 1; index < sections.size(); ++index) {
      const Elf64_Shdr &input = sections[index];
      const std::string name = stringAt(sectionNames, input.sh_name, origin, "section name");
      if ((input.sh_flags & SHF_ALLOC) == 0 && name != DebugInfo::SectionName) continue;
      if (name.empty()) THROW(, "ELF object '" << origin << "' has an allocated section without a name")
      // A linked RecurLoop image describes its original standalone module.
      // The final output receives a fresh image from the current language
      // state, so carrying this section forward would create two authorities.
      if (name == ".recurloop.language") continue;
      const std::size_t alignment = input.sh_addralign == 0 ? 1 : input.sh_addralign;
      SectionId output;
      const SectionId *known = module.findSection(name);
      if (known != nullptr) {
        output = *known;
        const Section &existing = module.section(output);
        if (existing.type != sectionType(input.sh_type, origin, name) ||
            existing.flags != sectionFlags(input.sh_flags))
          THROW(, "ELF object '" << origin << "' has incompatible duplicate section '" << name << "'")
      } else {
        output = module.addSection(name, sectionType(input.sh_type, origin, name), sectionFlags(input.sh_flags),
                                   alignment);
      }
      mappedSections[index] = output;
      if (input.sh_type == SHT_NOBITS) {
        sectionOffsets[index] = module.reserve(output, input.sh_size, alignment);
      } else {
        const auto contents = range(bytes, input.sh_offset, input.sh_size, origin, "section '" + name + "'");
        sectionOffsets[index] = module.append(output, contents, alignment);
      }
    }

    std::size_t symbolTableIndex = 0;
    for (std::size_t index = 1; index < sections.size(); ++index)
      if (sections[index].sh_type == SHT_SYMTAB) {
        if (symbolTableIndex != 0) THROW(, "ELF object '" << origin << "' contains multiple symbol tables")
        symbolTableIndex = index;
      }
    if (symbolTableIndex == 0) THROW(, "ELF object '" << origin << "' has no symbol table")
    const Elf64_Shdr &symbolTable = sections[symbolTableIndex];
    if (symbolTable.sh_entsize != sizeof(Elf64_Sym) || symbolTable.sh_link >= sections.size() ||
        symbolTable.sh_size % sizeof(Elf64_Sym) != 0)
      THROW(, "ELF object '" << origin << "' has an invalid symbol table")
    const Elf64_Shdr &stringTableHeader = sections[symbolTable.sh_link];
    const auto strings = range(bytes, stringTableHeader.sh_offset, stringTableHeader.sh_size, origin, "string table");
    const std::size_t symbolCount = symbolTable.sh_size / sizeof(Elf64_Sym);
    std::vector<std::string> symbolNames(symbolCount);
    const std::string prefix = localPrefix(bytes, origin);
    for (std::size_t index = 1; index < symbolCount; ++index) {
      const Elf64_Sym symbol = object<Elf64_Sym>(bytes, symbolTable.sh_offset + index * sizeof(Elf64_Sym), origin,
                                                 "symbol table entry");
      const unsigned type = ELF64_ST_TYPE(symbol.st_info);
      if (type == STT_FILE) continue;
      std::string name = symbol.st_name == 0 ? std::string() : stringAt(strings, symbol.st_name, origin, "symbol name");
      const SymbolBinding binding = symbolBinding(ELF64_ST_BIND(symbol.st_info), origin, name);
      if (type == STT_SECTION && name.empty()) name = "section." + std::to_string(symbol.st_shndx);
      if (name.empty()) continue;
      if (binding == SymbolBinding::Local) name = prefix + std::to_string(index) + "." + name;
      symbolNames[index] = name;

      if (symbol.st_shndx == SHN_UNDEF) {
        module.import(name, binding);
      } else if (symbol.st_shndx == SHN_ABS) {
        module.defineAbsolute(name, symbol.st_value, binding);
      } else if (symbol.st_shndx == SHN_COMMON) {
        const std::size_t alignment = symbol.st_value == 0 ? 1 : symbol.st_value;
        const std::size_t offset = module.reserve(SectionKind::Bss, symbol.st_size, alignment);
        module.define(name, SectionKind::Bss, offset, binding);
      } else {
        if (symbol.st_shndx >= mappedSections.size() || mappedSections[symbol.st_shndx] == invalidSection) {
          symbolNames[index].clear();
          continue;
        }
        const SectionId section = mappedSections[symbol.st_shndx];
        if (!hasFlag(module.section(section).flags, SectionFlag::Alloc)) {
          symbolNames[index].clear();
          continue;
        }
        if (symbol.st_value > extent(module.section(section)) - sectionOffsets[symbol.st_shndx])
          THROW(, "ELF object '" << origin << "' has symbol '" << name << "' outside its section")
        module.define(name, section, sectionOffsets[symbol.st_shndx] + symbol.st_value, binding);
      }
    }

    SectionId gotSection = invalidSection;
    std::unordered_map<std::size_t, std::string> gotSymbols;
    const auto gotSymbol = [&](std::size_t symbolIndex) -> const std::string & {
      const auto existing = gotSymbols.find(symbolIndex);
      if (existing != gotSymbols.end()) return existing->second;
      if (gotSection == invalidSection) {
        const SectionId *known = module.findSection(".got");
        gotSection = known == nullptr
                         ? module.addSection(".got", SectionType::ProgramBits,
                                             SectionFlag::Alloc | SectionFlag::Write, alignof(std::uint64_t))
                         : *known;
      }
      const std::array<std::uint8_t, sizeof(std::uint64_t)> empty = {};
      const std::size_t offset = module.append(gotSection, empty, alignof(std::uint64_t));
      const std::string name = prefix + "got." + std::to_string(symbolIndex);
      module.define(name, gotSection, offset, SymbolBinding::Local);
      module.relocate(gotSection, offset, RelocationKind::Absolute64, symbolNames[symbolIndex]);
      return gotSymbols.emplace(symbolIndex, name).first->second;
    };

    for (std::size_t sectionIndex = 1; sectionIndex < sections.size(); ++sectionIndex) {
      const Elf64_Shdr &relocations = sections[sectionIndex];
      if (relocations.sh_type != SHT_RELA && relocations.sh_type != SHT_REL) continue;
      if (relocations.sh_info >= mappedSections.size() || mappedSections[relocations.sh_info] == invalidSection)
        continue;
      if (relocations.sh_link != symbolTableIndex)
        THROW(, "ELF object '" << origin << "' has relocations using an unexpected symbol table")
      const std::size_t entrySize = relocations.sh_type == SHT_RELA ? sizeof(Elf64_Rela) : sizeof(Elf64_Rel);
      if (relocations.sh_entsize != entrySize || relocations.sh_size % entrySize != 0)
        THROW(, "ELF object '" << origin << "' has an invalid relocation table")
      const std::size_t count = relocations.sh_size / entrySize;
      for (std::size_t index = 0; index < count; ++index) {
        Elf64_Addr offset = 0;
        Elf64_Xword info = 0;
        std::int64_t addend = 0;
        if (relocations.sh_type == SHT_RELA) {
          const Elf64_Rela relocation = object<Elf64_Rela>(bytes, relocations.sh_offset + index * entrySize, origin,
                                                           "RELA entry");
          offset = relocation.r_offset;
          info = relocation.r_info;
          addend = relocation.r_addend;
        } else {
          const Elf64_Rel relocation = object<Elf64_Rel>(bytes, relocations.sh_offset + index * entrySize, origin,
                                                         "REL entry");
          offset = relocation.r_offset;
          info = relocation.r_info;
        }
        if (ELF64_R_TYPE(info) == R_X86_64_NONE) continue;
        const Elf64_Xword inputKind = ELF64_R_TYPE(info);
        const RelocationKind kind = gotRelative(inputKind) ? RelocationKind::PCRelative32
                                                           : relocationKind(inputKind, origin);
        const std::size_t symbolIndex = ELF64_R_SYM(info);
        if (symbolIndex >= symbolNames.size() || symbolNames[symbolIndex].empty())
          THROW(, "ELF object '" << origin << "' has a relocation to an unavailable symbol")
        const Elf64_Shdr &targetSection = sections[relocations.sh_info];
        if (offset > targetSection.sh_size || relocationSize(kind) > targetSection.sh_size - offset)
          THROW(, "ELF object '" << origin << "' has a relocation outside its target section")
        if (relocations.sh_type == SHT_REL)
          addend = implicitAddend(bytes, targetSection.sh_offset + offset, kind, origin);
        const std::string &targetSymbol =
            gotRelative(inputKind) ? gotSymbol(symbolIndex) : symbolNames[symbolIndex];
        module.relocate(mappedSections[relocations.sh_info], sectionOffsets[relocations.sh_info] + offset, kind,
                        targetSymbol, addend);
      }
    }
    return module;
  }

  std::vector<std::string> ElfReader::definitions(std::span<const std::uint8_t> bytes, std::string_view origin) {
    const Elf64_Ehdr header = object<Elf64_Ehdr>(bytes, 0, origin, "ELF header");
    if (std::memcmp(header.e_ident, ELFMAG, SELFMAG) != 0) THROW(, "file '" << origin << "' is not ELF")
    if (header.e_ident[EI_CLASS] != ELFCLASS64 || header.e_ident[EI_DATA] != ELFDATA2LSB ||
        header.e_type != ET_REL || header.e_machine != EM_X86_64 || header.e_shentsize != sizeof(Elf64_Shdr) ||
        header.e_shnum == 0)
      THROW(, "archive member '" << origin << "' is not a supported x86-64 ELF64 relocatable object")

    std::vector<Elf64_Shdr> sections;
    sections.reserve(header.e_shnum);
    for (std::size_t index = 0; index < header.e_shnum; ++index)
      sections.push_back(object<Elf64_Shdr>(bytes, header.e_shoff + index * header.e_shentsize, origin,
                                            "section header"));
    const auto symbolTable = std::find_if(sections.begin(), sections.end(),
                                          [](const Elf64_Shdr &section) { return section.sh_type == SHT_SYMTAB; });
    if (symbolTable == sections.end()) return {};
    if (symbolTable->sh_entsize != sizeof(Elf64_Sym) || symbolTable->sh_link >= sections.size() ||
        symbolTable->sh_size % sizeof(Elf64_Sym) != 0)
      THROW(, "ELF object '" << origin << "' has an invalid symbol table")
    const Elf64_Shdr &stringTable = sections[symbolTable->sh_link];
    const auto strings = range(bytes, stringTable.sh_offset, stringTable.sh_size, origin, "string table");

    std::vector<std::string> result;
    const std::size_t count = symbolTable->sh_size / sizeof(Elf64_Sym);
    for (std::size_t index = 1; index < count; ++index) {
      const Elf64_Sym symbol = object<Elf64_Sym>(bytes, symbolTable->sh_offset + index * sizeof(Elf64_Sym), origin,
                                                 "symbol table entry");
      const unsigned binding = ELF64_ST_BIND(symbol.st_info);
      if ((binding != STB_GLOBAL && binding != STB_WEAK) || symbol.st_shndx == SHN_UNDEF || symbol.st_name == 0)
        continue;
      result.push_back(stringAt(strings, symbol.st_name, origin, "symbol name"));
    }
    return result;
  }
} // namespace compiler
