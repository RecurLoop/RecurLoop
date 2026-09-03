#include <compiler/JitLinker.hpp>

#include <utilities/Exception.hpp>

#include <algorithm>
#include <array>
#include <limits>

namespace compiler {
  namespace {
    struct Layout {
      std::vector<std::size_t> offsets;
      std::size_t end = 0;
    };

    struct ImportStub {
      std::string symbol;
      std::size_t offset = 0;
    };

    constexpr std::size_t ImportStubSize = 16;

    std::size_t alignUp(std::size_t value, std::size_t alignment) {
      if (alignment == 0 || (alignment & (alignment - 1)) != 0)
        THROW(, "module section alignment must be a non-zero power of two")
      if (value > std::numeric_limits<std::size_t>::max() - (alignment - 1))
        THROW(, "JIT module layout overflows its offset")
      return (value + alignment - 1) & ~(alignment - 1);
    }

    std::size_t extent(const Section &section) {
      return section.type == SectionType::NoBits ? section.memorySize : section.bytes.size();
    }

    Layout layout(const Module &module, std::size_t start) {
      Layout result;
      result.offsets.resize(module.sections().size());
      std::size_t cursor = start;
      for (SectionId id = 0; id < module.sections().size(); ++id) {
        const Section &section = module.section(id);
        if (!hasFlag(section.flags, SectionFlag::Alloc)) continue;
        cursor = alignUp(cursor, section.alignment);
        result.offsets[id] = cursor;
        if (extent(section) > std::numeric_limits<std::size_t>::max() - cursor)
          THROW(, "JIT module layout exceeds the addressable size")
        cursor += extent(section);
      }
      result.end = cursor;
      return result;
    }

    std::uintptr_t sectionAddress(const Module &module, const Layout &layout, SectionId id, std::uintptr_t writable,
                                  std::uintptr_t executable) {
      const Section &section = module.section(id);
      if (!hasFlag(section.flags, SectionFlag::Alloc))
        THROW(, "JIT cannot address non-allocated section '" << section.name << "'")
      const std::uintptr_t base = hasFlag(section.flags, SectionFlag::Write) ? writable : executable;
      return base + layout.offsets[id];
    }

    std::size_t relocationSize(RelocationKind kind) {
      switch (kind) {
      case RelocationKind::PCRelative32: return sizeof(std::int32_t);
      case RelocationKind::PLTRelative32: return sizeof(std::int32_t);
      case RelocationKind::Absolute64: return sizeof(std::uint64_t);
      case RelocationKind::Absolute32: return sizeof(std::uint32_t);
      case RelocationKind::Absolute32Signed: return sizeof(std::int32_t);
      }
      THROW(, "unsupported JIT relocation kind")
    }

    void writeLittle(std::uint8_t *destination, std::uint64_t value, std::size_t bytes) {
      for (std::size_t i = 0; i < bytes; ++i) destination[i] = static_cast<std::uint8_t>(value >> (i * 8));
    }
  } // namespace

  std::uintptr_t JitImage::address(std::string_view symbol) const {
    const auto found = std::find_if(resolvedSymbols.begin(), resolvedSymbols.end(),
                                    [symbol](const ResolvedSymbol &candidate) { return candidate.name == symbol; });
    if (found == resolvedSymbols.end()) THROW(, "linked JIT symbol is undefined: '" << symbol << "'")
    return found->address;
  }

  std::size_t JitImage::offset() const {
    return imageOffset;
  }

  std::size_t JitImage::size() const {
    return imageSize;
  }

  JitImage JitLinker::link(const Module &module, JitMemory &memory, const Resolver &resolver) {
    const std::size_t start = memory.size();
    Layout moduleLayout = layout(module, start);
    std::vector<ImportStub> importStubs;
    for (const Relocation &relocation : module.relocations()) {
      if (relocation.kind != RelocationKind::PLTRelative32) continue;
      const Symbol *symbol = module.findSymbol(relocation.symbol);
      if (symbol == nullptr || !symbol->imported) continue;
      const auto existing = std::find_if(importStubs.begin(), importStubs.end(),
                                         [&](const ImportStub &stub) { return stub.symbol == relocation.symbol; });
      if (existing != importStubs.end()) continue;
      moduleLayout.end = alignUp(moduleLayout.end, alignof(std::uint64_t));
      importStubs.push_back({relocation.symbol, moduleLayout.end});
      if (ImportStubSize > std::numeric_limits<std::size_t>::max() - moduleLayout.end)
        THROW(, "JIT import stubs exceed the addressable size")
      moduleLayout.end += ImportStubSize;
    }
    if (moduleLayout.end >= memory.getCapacity()) THROW(, "JIT module does not fit in executable memory")

    const std::uintptr_t writableBase = reinterpret_cast<std::uintptr_t>(memory.getMemory().toPtr());
    const std::uintptr_t executableBase = reinterpret_cast<std::uintptr_t>(memory.getExecutable().toPtr());
    if (writableBase == 0 || executableBase == 0) THROW(, "JIT memory is not mapped")

    JitImage image;
    image.imageOffset = start;
    image.imageSize = moduleLayout.end - start;
    image.resolvedSymbols.reserve(module.symbols().size());

    for (const Symbol &symbol : module.symbols()) {
      std::uintptr_t address = 0;
      if (symbol.imported) {
        const std::optional<std::uintptr_t> resolved = resolver ? resolver(symbol.name) : std::nullopt;
        if (!resolved.has_value() && symbol.binding != SymbolBinding::Weak)
          THROW(, "unresolved JIT import: '" << symbol.name << "'")
        address = resolved.value_or(0);
      } else if (symbol.absolute) {
        address = symbol.offset;
      } else {
        const Section &section = module.section(symbol.section);
        if (symbol.offset > extent(section)) THROW(, "JIT symbol points outside its section: '" << symbol.name << "'")
        address = sectionAddress(module, moduleLayout, symbol.section, writableBase, executableBase) + symbol.offset;
      }
      image.resolvedSymbols.push_back({symbol.name, address});
    }

    std::vector<std::uint8_t> bytes(image.imageSize, 0);
    for (SectionId id = 0; id < module.sections().size(); ++id) {
      const Section &section = module.section(id);
      if (!hasFlag(section.flags, SectionFlag::Alloc) || section.type == SectionType::NoBits) continue;
      const std::size_t destination = moduleLayout.offsets[id] - start;
      std::copy(section.bytes.begin(), section.bytes.end(), bytes.begin() + destination);
    }

    for (const ImportStub &stub : importStubs) {
      const std::size_t offset = stub.offset - start;
      static constexpr std::array<std::uint8_t, 8> jump = {0xff, 0x25, 0x02, 0x00, 0x00, 0x00, 0x66, 0x90};
      std::copy(jump.begin(), jump.end(), bytes.begin() + offset);
      writeLittle(bytes.data() + offset + jump.size(), image.address(stub.symbol), sizeof(std::uint64_t));
    }

    for (const Relocation &relocation : module.relocations()) {
      const Symbol *symbol = module.findSymbol(relocation.symbol);
      if (symbol == nullptr) THROW(, "relocation references an undeclared symbol: '" << relocation.symbol << "'")

      const std::uintptr_t target = image.address(relocation.symbol);
      const Section &patchSection = module.section(relocation.section);
      const std::size_t patchBytes = relocationSize(relocation.kind);
      if (!hasFlag(patchSection.flags, SectionFlag::Alloc) || relocation.offset > patchSection.bytes.size() ||
          patchBytes > patchSection.bytes.size() - relocation.offset)
        THROW(, "JIT relocation points outside its section for symbol: '" << relocation.symbol << "'")

      const std::size_t patchInImage = moduleLayout.offsets[relocation.section] - start + relocation.offset;
      std::uint8_t *patch = bytes.data() + patchInImage;

      switch (relocation.kind) {
      case RelocationKind::PCRelative32:
      case RelocationKind::PLTRelative32: {
        std::uintptr_t relocationTarget = target;
        if (relocation.kind == RelocationKind::PLTRelative32 && symbol->imported) {
          const auto stub = std::find_if(importStubs.begin(), importStubs.end(), [&](const ImportStub &candidate) {
            return candidate.symbol == relocation.symbol;
          });
          if (stub == importStubs.end()) THROW(, "JIT import stub is missing for symbol: '" << relocation.symbol << "'")
          relocationTarget = executableBase + stub->offset;
        }
        const std::uintptr_t place =
            sectionAddress(module, moduleLayout, relocation.section, writableBase, executableBase) + relocation.offset;
        const __int128 value =
            static_cast<__int128>(relocationTarget) + relocation.addend - static_cast<__int128>(place);
        if (value < std::numeric_limits<std::int32_t>::min() || value > std::numeric_limits<std::int32_t>::max())
          THROW(, "JIT PC-relative relocation is out of range for symbol: '" << relocation.symbol << "'")
        writeLittle(patch, static_cast<std::uint32_t>(static_cast<std::int32_t>(value)), sizeof(std::int32_t));
        break;
      }
      case RelocationKind::Absolute64: {
        const __int128 value = static_cast<__int128>(target) + relocation.addend;
        if (value < 0 || value > std::numeric_limits<std::uint64_t>::max())
          THROW(, "JIT absolute relocation is out of range for symbol: '" << relocation.symbol << "'")
        writeLittle(patch, static_cast<std::uint64_t>(value), sizeof(std::uint64_t));
        break;
      }
      case RelocationKind::Absolute32: {
        const __int128 value = static_cast<__int128>(target) + relocation.addend;
        if (value < 0 || value > std::numeric_limits<std::uint32_t>::max())
          THROW(, "JIT unsigned 32-bit relocation is out of range for symbol: '" << relocation.symbol << "'")
        writeLittle(patch, static_cast<std::uint32_t>(value), sizeof(std::uint32_t));
        break;
      }
      case RelocationKind::Absolute32Signed: {
        const __int128 value = static_cast<__int128>(target) + relocation.addend;
        if (value < std::numeric_limits<std::int32_t>::min() || value > std::numeric_limits<std::int32_t>::max())
          THROW(, "JIT signed 32-bit relocation is out of range for symbol: '" << relocation.symbol << "'")
        writeLittle(patch, static_cast<std::uint32_t>(static_cast<std::int32_t>(value)), sizeof(std::int32_t));
        break;
      }
      }
    }

    memory.append(Byte(bytes.data()), bytes.size());
    return image;
  }
} // namespace compiler
