#include <compiler/Module.hpp>

#include <utilities/Exception.hpp>

#include <algorithm>
#include <limits>

namespace compiler {
  namespace {
    bool isPowerOfTwo(std::size_t value) {
      return value != 0 && (value & (value - 1)) == 0;
    }

    std::size_t alignUp(std::size_t value, std::size_t alignment) {
      if (!isPowerOfTwo(alignment)) THROW(, "section alignment must be a non-zero power of two")
      if (value > std::numeric_limits<std::size_t>::max() - (alignment - 1))
        THROW(, "section alignment overflows its offset")
      return (value + alignment - 1) & ~(alignment - 1);
    }

    std::size_t relocationSize(RelocationKind kind) {
      switch (kind) {
      case RelocationKind::PCRelative32: return sizeof(std::int32_t);
      case RelocationKind::PLTRelative32: return sizeof(std::int32_t);
      case RelocationKind::Absolute64: return sizeof(std::uint64_t);
      case RelocationKind::Absolute32: return sizeof(std::uint32_t);
      case RelocationKind::Absolute32Signed: return sizeof(std::int32_t);
      }
      THROW(, "unsupported relocation kind")
    }

    std::size_t extent(const Section &section) {
      return section.type == SectionType::NoBits ? section.memorySize : section.bytes.size();
    }
  } // namespace

  Module::Module() {
    addSection(".text", SectionType::ProgramBits, SectionFlag::Alloc | SectionFlag::Execute, 1);
    addSection(".rodata", SectionType::ProgramBits, SectionFlag::Alloc, 1);
    addSection(".data", SectionType::ProgramBits, SectionFlag::Alloc | SectionFlag::Write, 1);
    addSection(".bss", SectionType::NoBits, SectionFlag::Alloc | SectionFlag::Write, 1);
  }

  Section &Module::section(SectionId sectionId) {
    if (sectionId >= moduleSections.size()) THROW(, "invalid module section")
    return moduleSections[sectionId];
  }

  const Section &Module::section(SectionId sectionId) const {
    if (sectionId >= moduleSections.size()) THROW(, "invalid module section")
    return moduleSections[sectionId];
  }

  Section &Module::section(std::string_view name) {
    const SectionId *found = findSection(name);
    if (found == nullptr) THROW(, "unknown module section: '" << name << "'")
    return section(*found);
  }

  const Section &Module::section(std::string_view name) const {
    const SectionId *found = findSection(name);
    if (found == nullptr) THROW(, "unknown module section: '" << name << "'")
    return section(*found);
  }

  const std::vector<Section> &Module::sections() const {
    return moduleSections;
  }

  SectionId Module::addSection(std::string name, SectionType type, SectionFlag flags, std::size_t alignment) {
    if (name.empty()) THROW(, "module section name cannot be empty")
    if (name.find('\0') != std::string::npos) THROW(, "module section name contains a NUL byte")
    if (findSection(name) != nullptr) THROW(, "duplicate module section: '" << name << "'")
    if (!isPowerOfTwo(alignment)) THROW(, "section alignment must be a non-zero power of two")
    const SectionId result = moduleSections.size();
    moduleSections.push_back({std::move(name), type, flags, {}, 0, alignment});
    namedSectionIds.push_back(result);
    return result;
  }

  const SectionId *Module::findSection(std::string_view name) const {
    const auto found = std::find_if(namedSectionIds.begin(), namedSectionIds.end(), [&](SectionId candidate) {
      return moduleSections[candidate].name == name;
    });
    return found == namedSectionIds.end() ? nullptr : &*found;
  }

  std::size_t Module::append(SectionId sectionId, std::span<const std::uint8_t> bytes, std::size_t alignment) {
    Section &target = section(sectionId);
    if (target.type == SectionType::NoBits) THROW(, "cannot append initialized bytes to NOBITS section '" << target.name << "'")
    const std::size_t offset = alignUp(target.bytes.size(), alignment);
    target.alignment = std::max(target.alignment, alignment);
    target.bytes.resize(offset, 0);
    target.bytes.insert(target.bytes.end(), bytes.begin(), bytes.end());
    target.memorySize = target.bytes.size();
    return offset;
  }

  std::size_t Module::reserve(SectionId sectionId, std::size_t bytes, std::size_t alignment) {
    Section &target = section(sectionId);
    const std::size_t offset = alignUp(extent(target), alignment);
    if (bytes > std::numeric_limits<std::size_t>::max() - offset) THROW(, "section reservation exceeds addressable size")
    target.alignment = std::max(target.alignment, alignment);
    target.memorySize = offset + bytes;
    if (target.type != SectionType::NoBits) target.bytes.resize(target.memorySize, 0);
    return offset;
  }

  void Module::define(std::string name, SectionId symbolSection, std::size_t offset, SymbolBinding binding) {
    if (name.empty()) THROW(, "module symbol name cannot be empty")
    if (findSymbol(name) != nullptr) THROW(, "duplicate module symbol: '" << name << "'")
    if (offset > extent(section(symbolSection))) THROW(, "module symbol '" << name << "' points outside its section")
    moduleSymbols.push_back({std::move(name), symbolSection, offset, false, false, binding});
  }

  void Module::defineAbsolute(std::string name, std::size_t value, SymbolBinding binding) {
    if (name.empty()) THROW(, "module symbol name cannot be empty")
    if (findSymbol(name) != nullptr) THROW(, "duplicate module symbol: '" << name << "'")
    moduleSymbols.push_back({std::move(name), id(SectionKind::Text), value, false, true, binding});
  }

  void Module::import(std::string name, SymbolBinding binding) {
    if (name.empty()) THROW(, "imported symbol name cannot be empty")
    if (binding == SymbolBinding::Local) THROW(, "imported symbol cannot have local binding")
    if (findSymbol(name) != nullptr) THROW(, "duplicate module symbol: '" << name << "'")
    moduleSymbols.push_back({std::move(name), id(SectionKind::Text), 0, true, false, binding});
  }

  void Module::relocate(SectionId relocationSection, std::size_t offset, RelocationKind kind, std::string symbol,
                        std::int64_t addend) {
    if (symbol.empty()) THROW(, "relocation symbol name cannot be empty")
    const std::size_t patchBytes = relocationSize(kind);
    const Section &target = section(relocationSection);
    const std::size_t sectionBytes = target.bytes.size();
    if (target.type == SectionType::NoBits || offset > sectionBytes || patchBytes > sectionBytes - offset)
      THROW(, "relocation for symbol '" << symbol << "' points outside its section")
    moduleRelocations.push_back({relocationSection, offset, kind, std::move(symbol), addend});
  }

  const Symbol *Module::findSymbol(std::string_view name) const {
    const auto found = std::find_if(moduleSymbols.begin(), moduleSymbols.end(),
                                    [name](const Symbol &symbol) { return symbol.name == name; });
    return found == moduleSymbols.end() ? nullptr : &*found;
  }

  const std::vector<Symbol> &Module::symbols() const {
    return moduleSymbols;
  }

  const std::vector<Relocation> &Module::relocations() const {
    return moduleRelocations;
  }

  bool Module::removeSymbol(std::string_view name) {
    const auto found = std::find_if(moduleSymbols.begin(), moduleSymbols.end(),
                                    [name](const Symbol &symbol) { return symbol.name == name; });
    if (found == moduleSymbols.end()) return false;
    moduleSymbols.erase(found);
    return true;
  }

  void Module::merge(const Module &other) {
    std::vector<SectionId> targetSections(other.sections().size());
    std::vector<std::size_t> offsets(other.sections().size());
    for (SectionId sourceId = 0; sourceId < other.sections().size(); ++sourceId) {
      const Section &source = other.section(sourceId);
      const SectionId *existing = findSection(source.name);
      SectionId targetId;
      if (existing == nullptr) {
        targetId = addSection(source.name, source.type, source.flags, source.alignment);
      } else {
        targetId = *existing;
        const Section &target = section(targetId);
        if (target.type != source.type || target.flags != source.flags)
          THROW(, "cannot merge incompatible module section '" << source.name << "'")
      }
      targetSections[sourceId] = targetId;
      offsets[sourceId] = source.type == SectionType::NoBits
                              ? reserve(targetId, source.memorySize, source.alignment)
                              : append(targetId, source.bytes, source.alignment);
    }

    for (const Symbol &symbol : other.symbols()) {
      const Symbol *existing = findSymbol(symbol.name);
      if (symbol.imported) {
        if (existing == nullptr) import(symbol.name, symbol.binding);
        continue;
      }
      if (existing != nullptr) {
        if (!existing->imported) {
          if (symbol.binding == SymbolBinding::Weak) continue;
          if (existing->binding != SymbolBinding::Weak)
            THROW(, "duplicate module symbol while merging: '" << symbol.name << "'")
        }
        removeSymbol(symbol.name);
      }
      if (symbol.absolute)
        defineAbsolute(symbol.name, symbol.offset, symbol.binding);
      else
        define(symbol.name, targetSections.at(symbol.section), offsets.at(symbol.section) + symbol.offset,
               symbol.binding);
    }

    for (const Relocation &relocation : other.relocations())
      relocate(targetSections.at(relocation.section), offsets.at(relocation.section) + relocation.offset,
               relocation.kind, relocation.symbol, relocation.addend);
  }
} // namespace compiler
