#include <compiler/ElfWriter.hpp>
#include <compiler/DebugInfo.hpp>

#include <utilities/Exception.hpp>

#include <algorithm>
#include <bit>
#include <cstddef>
#include <cstring>
#include <elf.h>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace compiler {
  namespace {
    static_assert(std::endian::native == std::endian::little, "ELF64 x86-64 writer requires little-endian host data");

    struct OutputSection {
      std::string name;
      std::vector<std::uint8_t> bytes;
      Elf64_Word type = SHT_NULL;
      Elf64_Xword flags = 0;
      Elf64_Xword size = 0;
      Elf64_Xword alignment = 1;
      Elf64_Xword entrySize = 0;
      Elf64_Word link = 0;
      Elf64_Word info = 0;
      SectionId input = std::numeric_limits<SectionId>::max();
    };

    struct ExecutableSection {
      SectionId id = 0;
      Elf64_Word flags = 0;
      std::size_t fileOffset = 0;
      std::size_t address = 0;
    };

    constexpr std::size_t EXECUTABLE_BASE = 0x400000;
    constexpr std::size_t EXECUTABLE_PAGE = 0x1000;

    std::size_t alignUp(std::size_t value, std::size_t alignment) {
      if (alignment == 0 || (alignment & (alignment - 1)) != 0)
        THROW(, "ELF section alignment must be a non-zero power of two")
      if (value > std::numeric_limits<std::size_t>::max() - (alignment - 1))
        THROW(, "ELF object layout overflows its offset")
      return (value + alignment - 1) & ~(alignment - 1);
    }

    std::size_t addChecked(std::size_t left, std::size_t right, std::string_view description) {
      if (right > std::numeric_limits<std::size_t>::max() - left) THROW(, description << " exceeds addressable size")
      return left + right;
    }

    std::size_t extent(const Section &section) {
      return section.type == SectionType::NoBits ? section.memorySize : section.bytes.size();
    }

    template <typename Type> void appendObject(std::vector<std::uint8_t> &destination, const Type &object) {
      const auto *begin = reinterpret_cast<const std::uint8_t *>(&object);
      destination.insert(destination.end(), begin, begin + sizeof(object));
    }

    void writeLittle(std::uint8_t *destination, std::uint64_t value, std::size_t bytes) {
      for (std::size_t index = 0; index < bytes; ++index)
        destination[index] = static_cast<std::uint8_t>(value >> (index * 8));
    }

    Elf64_Word addString(std::vector<std::uint8_t> &table, std::string_view text) {
      if (table.size() > std::numeric_limits<Elf64_Word>::max()) THROW(, "ELF string table exceeds 32-bit offsets")
      const Elf64_Word offset = static_cast<Elf64_Word>(table.size());
      table.insert(table.end(), text.begin(), text.end());
      table.push_back(0);
      return offset;
    }

    Elf64_Word sectionType(SectionType type) {
      switch (type) {
      case SectionType::ProgramBits: return SHT_PROGBITS;
      case SectionType::NoBits: return SHT_NOBITS;
      case SectionType::Note: return SHT_NOTE;
      case SectionType::Dynamic: return SHT_DYNAMIC;
      case SectionType::InitArray: return SHT_INIT_ARRAY;
      case SectionType::FiniArray: return SHT_FINI_ARRAY;
      case SectionType::PreinitArray: return SHT_PREINIT_ARRAY;
      }
      THROW(, "invalid module section type")
    }

    Elf64_Xword sectionFlags(SectionFlag flags) {
      Elf64_Xword result = 0;
      if (hasFlag(flags, SectionFlag::Alloc)) result |= SHF_ALLOC;
      if (hasFlag(flags, SectionFlag::Write)) result |= SHF_WRITE;
      if (hasFlag(flags, SectionFlag::Execute)) result |= SHF_EXECINSTR;
      if (hasFlag(flags, SectionFlag::Merge)) result |= SHF_MERGE;
      if (hasFlag(flags, SectionFlag::Strings)) result |= SHF_STRINGS;
      if (hasFlag(flags, SectionFlag::ThreadLocal)) result |= SHF_TLS;
      return result;
    }

    Elf64_Word relocationType(RelocationKind kind) {
      switch (kind) {
      case RelocationKind::PCRelative32: return R_X86_64_PC32;
      case RelocationKind::PLTRelative32: return R_X86_64_PLT32;
      case RelocationKind::Absolute64: return R_X86_64_64;
      case RelocationKind::Absolute32: return R_X86_64_32;
      case RelocationKind::Absolute32Signed: return R_X86_64_32S;
      }
      THROW(, "unsupported ELF relocation kind")
    }

    std::size_t relocationSize(RelocationKind kind) {
      switch (kind) {
      case RelocationKind::PCRelative32: return sizeof(std::int32_t);
      case RelocationKind::PLTRelative32: return sizeof(std::int32_t);
      case RelocationKind::Absolute64: return sizeof(std::uint64_t);
      case RelocationKind::Absolute32: return sizeof(std::uint32_t);
      case RelocationKind::Absolute32Signed: return sizeof(std::int32_t);
      }
      THROW(, "unsupported ELF relocation kind")
    }

    Elf64_Word executableFlags(const Section &section) {
      Elf64_Word result = PF_R;
      if (hasFlag(section.flags, SectionFlag::Write)) result |= PF_W;
      if (hasFlag(section.flags, SectionFlag::Execute)) result |= PF_X;
      return result;
    }

    const ExecutableSection &executableSection(const std::vector<ExecutableSection> &sections, SectionId id) {
      const auto found =
          std::find_if(sections.begin(), sections.end(), [id](const auto &section) { return section.id == id; });
      if (found == sections.end()) THROW(, "ELF executable symbol belongs to a non-loadable section")
      return *found;
    }

    unsigned char symbolType(const Module &module, const Symbol &symbol) {
      if (symbol.imported || symbol.absolute) return STT_NOTYPE;
      return hasFlag(module.section(symbol.section).flags, SectionFlag::Execute) ? STT_FUNC : STT_OBJECT;
    }

    unsigned char symbolBinding(SymbolBinding binding) {
      switch (binding) {
      case SymbolBinding::Local: return STB_LOCAL;
      case SymbolBinding::Global: return STB_GLOBAL;
      case SymbolBinding::Weak: return STB_WEAK;
      }
      THROW(, "invalid module symbol binding")
    }
  } // namespace

  std::vector<std::uint8_t> ElfWriter::write(const Module &module) {
    std::vector<OutputSection> sections(1);
    std::vector<std::size_t> inputIndices(module.sections().size());
    for (SectionId id = 0; id < module.sections().size(); ++id) {
      const Section &input = module.section(id);
      inputIndices[id] = sections.size();
      sections.push_back({input.name, input.bytes, sectionType(input.type), sectionFlags(input.flags), extent(input),
                          input.alignment, 0, 0, 0, id});
    }

    sections.push_back({".note.GNU-stack", {}, SHT_PROGBITS, 0, 0, 1});

    std::vector<std::vector<const Relocation *>> relocations(module.sections().size());
    for (const Relocation &relocation : module.relocations()) {
      if (relocation.section >= relocations.size()) THROW(, "ELF relocation uses an invalid section")
      relocations[relocation.section].push_back(&relocation);
    }

    std::vector<std::size_t> relocationIndices(module.sections().size(), 0);
    for (SectionId id = 0; id < relocations.size(); ++id) {
      if (relocations[id].empty()) continue;
      relocationIndices[id] = sections.size();
      sections.push_back({".rela" + module.section(id).name, {}, SHT_RELA, 0, 0, alignof(Elf64_Rela),
                          sizeof(Elf64_Rela), 0, static_cast<Elf64_Word>(inputIndices[id])});
    }

    const std::size_t symbolTableIndex = sections.size();
    sections.push_back({".symtab", {}, SHT_SYMTAB, 0, 0, alignof(Elf64_Sym), sizeof(Elf64_Sym)});
    const std::size_t stringTableIndex = sections.size();
    sections.push_back({".strtab", {0}, SHT_STRTAB, 0, 1, 1});
    const std::size_t sectionStringTableIndex = sections.size();
    sections.push_back({".shstrtab", {0}, SHT_STRTAB, 0, 1, 1});

    sections[symbolTableIndex].link = stringTableIndex;
    for (std::size_t index : relocationIndices)
      if (index != 0) sections[index].link = symbolTableIndex;

    std::vector<Elf64_Sym> symbols(1);
    for (std::size_t index : inputIndices) {
      Elf64_Sym sectionSymbol{};
      sectionSymbol.st_info = ELF64_ST_INFO(STB_LOCAL, STT_SECTION);
      sectionSymbol.st_shndx = index;
      symbols.push_back(sectionSymbol);
    }

    std::vector<std::pair<std::string_view, std::size_t>> symbolIndices;
    symbolIndices.reserve(module.symbols().size());
    const auto appendSymbol = [&](const Symbol &symbol) {
      if (symbol.name.find('\0') != std::string::npos) THROW(, "ELF symbol name contains a NUL byte")
      if (symbols.size() > std::numeric_limits<Elf64_Word>::max()) THROW(, "ELF symbol table exceeds 32-bit indices")
      Elf64_Sym output{};
      output.st_name = addString(sections[stringTableIndex].bytes, symbol.name);
      output.st_info = ELF64_ST_INFO(symbolBinding(symbol.binding), symbolType(module, symbol));
      output.st_shndx = symbol.imported ? SHN_UNDEF : symbol.absolute ? SHN_ABS : inputIndices.at(symbol.section);
      output.st_value = symbol.imported ? 0 : symbol.offset;
      const std::size_t index = symbols.size();
      symbols.push_back(output);
      symbolIndices.emplace_back(symbol.name, index);
    };
    for (const Symbol &symbol : module.symbols())
      if (symbol.binding == SymbolBinding::Local) appendSymbol(symbol);
    sections[symbolTableIndex].info = static_cast<Elf64_Word>(symbols.size());
    for (const Symbol &symbol : module.symbols())
      if (symbol.binding != SymbolBinding::Local) appendSymbol(symbol);
    for (const Elf64_Sym &symbol : symbols) appendObject(sections[symbolTableIndex].bytes, symbol);
    sections[symbolTableIndex].size = sections[symbolTableIndex].bytes.size();
    sections[stringTableIndex].size = sections[stringTableIndex].bytes.size();

    for (SectionId id = 0; id < relocations.size(); ++id) {
      if (relocations[id].empty()) continue;
      OutputSection &target = sections[relocationIndices[id]];
      for (const Relocation *relocation : relocations[id]) {
        const auto symbol = std::find_if(symbolIndices.begin(), symbolIndices.end(), [&](const auto &candidate) {
          return candidate.first == relocation->symbol;
        });
        if (symbol == symbolIndices.end())
          THROW(, "ELF relocation references an undeclared symbol: '" << relocation->symbol << "'")
        Elf64_Rela output{};
        output.r_offset = relocation->offset;
        output.r_info = ELF64_R_INFO(symbol->second, relocationType(relocation->kind));
        output.r_addend = relocation->addend;
        appendObject(target.bytes, output);
      }
      target.size = target.bytes.size();
    }

    std::vector<Elf64_Word> sectionNameOffsets(sections.size());
    for (std::size_t index = 1; index < sections.size(); ++index)
      sectionNameOffsets[index] = addString(sections[sectionStringTableIndex].bytes, sections[index].name);
    sections[sectionStringTableIndex].size = sections[sectionStringTableIndex].bytes.size();

    if (sections.size() > std::numeric_limits<Elf64_Half>::max()) THROW(, "ELF object has too many sections")
    Elf64_Ehdr header{};
    std::memcpy(header.e_ident, ELFMAG, SELFMAG);
    header.e_ident[EI_CLASS] = ELFCLASS64;
    header.e_ident[EI_DATA] = ELFDATA2LSB;
    header.e_ident[EI_VERSION] = EV_CURRENT;
    header.e_ident[EI_OSABI] = ELFOSABI_SYSV;
    header.e_type = ET_REL;
    header.e_machine = EM_X86_64;
    header.e_version = EV_CURRENT;
    header.e_ehsize = sizeof(Elf64_Ehdr);
    header.e_shentsize = sizeof(Elf64_Shdr);
    header.e_shnum = static_cast<Elf64_Half>(sections.size());
    header.e_shstrndx = static_cast<Elf64_Half>(sectionStringTableIndex);

    std::vector<std::uint8_t> result(sizeof(header), 0);
    std::vector<Elf64_Shdr> sectionHeaders(sections.size());
    for (std::size_t index = 1; index < sections.size(); ++index) {
      const OutputSection &section = sections[index];
      result.resize(alignUp(result.size(), section.alignment), 0);
      Elf64_Shdr &output = sectionHeaders[index];
      output.sh_name = sectionNameOffsets[index];
      output.sh_type = section.type;
      output.sh_flags = section.flags;
      output.sh_offset = result.size();
      output.sh_size = section.size;
      output.sh_link = section.link;
      output.sh_info = section.info;
      output.sh_addralign = section.alignment;
      output.sh_entsize = section.entrySize;
      if (section.type != SHT_NOBITS) result.insert(result.end(), section.bytes.begin(), section.bytes.end());
    }

    result.resize(alignUp(result.size(), alignof(Elf64_Shdr)), 0);
    header.e_shoff = result.size();
    std::memcpy(result.data(), &header, sizeof(header));
    for (const Elf64_Shdr &section : sectionHeaders) appendObject(result, section);
    return result;
  }

  std::vector<std::uint8_t> ElfWriter::writeExecutable(const Module &module, std::string_view entrySymbol) {
    const Symbol *entry = module.findSymbol(entrySymbol);
    if (entry == nullptr) THROW(, "ELF executable entry symbol is undefined: '" << entrySymbol << "'")
    if (entry->imported) THROW(, "ELF executable entry symbol is imported: '" << entrySymbol << "'")
    if (!hasFlag(module.section(entry->section).flags, SectionFlag::Execute))
      THROW(, "ELF executable entry symbol is not in an executable section")

    for (const Symbol &symbol : module.symbols())
      if (symbol.imported && symbol.binding != SymbolBinding::Weak)
        THROW(, "ELF executable cannot resolve imported symbol: '" << symbol.name << "'")

    std::size_t loadCount = 0;
    for (const Section &section : module.sections())
      if (hasFlag(section.flags, SectionFlag::Alloc) && extent(section) != 0) ++loadCount;
    if (loadCount == 0) THROW(, "ELF executable contains no loadable sections")
    if (loadCount + 1 > std::numeric_limits<Elf64_Half>::max()) THROW(, "ELF executable has too many segments")

    const std::size_t programHeaderCount = loadCount + 1;
    std::size_t fileCursor =
        addChecked(sizeof(Elf64_Ehdr), programHeaderCount * sizeof(Elf64_Phdr), "ELF executable headers");
    std::size_t virtualCursor = EXECUTABLE_BASE;
    std::vector<ExecutableSection> sections;
    sections.reserve(loadCount);
    for (SectionId id = 0; id < module.sections().size(); ++id) {
      const Section &section = module.section(id);
      if (!hasFlag(section.flags, SectionFlag::Alloc) || extent(section) == 0) continue;
      fileCursor = alignUp(fileCursor, EXECUTABLE_PAGE);
      virtualCursor = alignUp(virtualCursor, std::max(EXECUTABLE_PAGE, section.alignment));
      sections.push_back({id, executableFlags(section), fileCursor, virtualCursor});
      if (section.type != SectionType::NoBits)
        fileCursor = addChecked(fileCursor, section.bytes.size(), "ELF executable file layout");
      virtualCursor = addChecked(virtualCursor, extent(section), "ELF executable virtual layout");
    }

    const ExecutableSection &entrySection = executableSection(sections, entry->section);
    if (entry->offset >= extent(module.section(entry->section)))
      THROW(, "ELF executable entry symbol points outside its section")

    Elf64_Ehdr header{};
    std::memcpy(header.e_ident, ELFMAG, SELFMAG);
    header.e_ident[EI_CLASS] = ELFCLASS64;
    header.e_ident[EI_DATA] = ELFDATA2LSB;
    header.e_ident[EI_VERSION] = EV_CURRENT;
    header.e_ident[EI_OSABI] = ELFOSABI_SYSV;
    header.e_type = ET_EXEC;
    header.e_machine = EM_X86_64;
    header.e_version = EV_CURRENT;
    header.e_entry = entrySection.address + entry->offset;
    header.e_phoff = sizeof(Elf64_Ehdr);
    header.e_ehsize = sizeof(Elf64_Ehdr);
    header.e_phentsize = sizeof(Elf64_Phdr);
    header.e_phnum = static_cast<Elf64_Half>(programHeaderCount);

    std::vector<std::uint8_t> result(fileCursor, 0);
    std::memcpy(result.data(), &header, sizeof(header));
    std::size_t programHeaderOffset = sizeof(header);
    for (const ExecutableSection &layout : sections) {
      const Section &input = module.section(layout.id);
      Elf64_Phdr output{};
      output.p_type = PT_LOAD;
      output.p_flags = layout.flags;
      output.p_offset = layout.fileOffset;
      output.p_vaddr = layout.address;
      output.p_paddr = layout.address;
      output.p_filesz = input.type == SectionType::NoBits ? 0 : input.bytes.size();
      output.p_memsz = extent(input);
      output.p_align = EXECUTABLE_PAGE;
      std::memcpy(result.data() + programHeaderOffset, &output, sizeof(output));
      programHeaderOffset += sizeof(output);
      if (input.type != SectionType::NoBits)
        std::copy(input.bytes.begin(), input.bytes.end(), result.begin() + layout.fileOffset);
    }

    Elf64_Phdr stack{};
    stack.p_type = PT_GNU_STACK;
    stack.p_flags = PF_R | PF_W;
    stack.p_align = 16;
    std::memcpy(result.data() + programHeaderOffset, &stack, sizeof(stack));

    const auto symbolAddress = [&](const Symbol &symbol) -> std::size_t {
      if (symbol.imported && symbol.binding == SymbolBinding::Weak) return 0;
      if (symbol.absolute) return symbol.offset;
      const Section &input = module.section(symbol.section);
      if (symbol.offset > extent(input))
        THROW(, "ELF executable symbol points outside its section: '" << symbol.name << "'")
      return addChecked(executableSection(sections, symbol.section).address, symbol.offset,
                        "ELF executable symbol address");
    };

    for (const Relocation &relocation : module.relocations()) {
      const Symbol *target = module.findSymbol(relocation.symbol);
      if (target == nullptr)
        THROW(, "ELF executable relocation references an undeclared symbol: '" << relocation.symbol << "'")
      const Section &patchSection = module.section(relocation.section);
      const std::size_t patchBytes = relocationSize(relocation.kind);
      if (patchSection.type == SectionType::NoBits || relocation.offset > patchSection.bytes.size() ||
          patchBytes > patchSection.bytes.size() - relocation.offset)
        THROW(, "ELF executable relocation points outside its section for symbol: '" << relocation.symbol << "'")

      const ExecutableSection &patchLayout = executableSection(sections, relocation.section);
      std::uint8_t *patch = result.data() + patchLayout.fileOffset + relocation.offset;
      const std::size_t targetAddress = symbolAddress(*target);
      const std::size_t patchAddress = patchLayout.address + relocation.offset;
      switch (relocation.kind) {
      case RelocationKind::PCRelative32:
      case RelocationKind::PLTRelative32: {
        const __int128 value =
            static_cast<__int128>(targetAddress) + relocation.addend - static_cast<__int128>(patchAddress);
        if (value < std::numeric_limits<std::int32_t>::min() || value > std::numeric_limits<std::int32_t>::max())
          THROW(, "ELF executable PC-relative relocation is out of range for symbol: '" << relocation.symbol << "'")
        writeLittle(patch, static_cast<std::uint32_t>(static_cast<std::int32_t>(value)), sizeof(std::int32_t));
        break;
      }
      case RelocationKind::Absolute64: {
        const __int128 value = static_cast<__int128>(targetAddress) + relocation.addend;
        if (value < 0 || value > std::numeric_limits<std::uint64_t>::max())
          THROW(, "ELF executable absolute relocation is out of range for symbol: '" << relocation.symbol << "'")
        writeLittle(patch, static_cast<std::uint64_t>(value), sizeof(std::uint64_t));
        break;
      }
      case RelocationKind::Absolute32: {
        const __int128 value = static_cast<__int128>(targetAddress) + relocation.addend;
        if (value < 0 || value > std::numeric_limits<std::uint32_t>::max())
          THROW(, "ELF executable unsigned 32-bit relocation is out of range for symbol: '"
                      << relocation.symbol << "'")
        writeLittle(patch, static_cast<std::uint32_t>(value), sizeof(std::uint32_t));
        break;
      }
      case RelocationKind::Absolute32Signed: {
        const __int128 value = static_cast<__int128>(targetAddress) + relocation.addend;
        if (value < std::numeric_limits<std::int32_t>::min() || value > std::numeric_limits<std::int32_t>::max())
          THROW(, "ELF executable signed 32-bit relocation is out of range for symbol: '"
                      << relocation.symbol << "'")
        writeLittle(patch, static_cast<std::uint32_t>(static_cast<std::int32_t>(value)), sizeof(std::int32_t));
        break;
      }
      }
    }
    DebugInfo::appendExecutable(result, module, [&](std::string_view name) -> std::optional<std::uint64_t> {
      const Symbol *symbol = module.findSymbol(name);
      if (symbol == nullptr || symbol->imported) return std::nullopt;
      return static_cast<std::uint64_t>(symbolAddress(*symbol));
    });
    return result;
  }
} // namespace compiler
