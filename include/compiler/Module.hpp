#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace compiler {
  enum class SectionKind : std::uint8_t { Text, ReadOnlyData, Data, Bss, Count };
  using SectionId = std::size_t;

  enum class SectionType : std::uint8_t {
    ProgramBits,
    NoBits,
    Note,
    Dynamic,
    InitArray,
    FiniArray,
    PreinitArray,
  };

  enum class SectionFlag : std::uint16_t {
    None = 0,
    Alloc = 1 << 0,
    Write = 1 << 1,
    Execute = 1 << 2,
    Merge = 1 << 3,
    Strings = 1 << 4,
    ThreadLocal = 1 << 5,
  };

  constexpr SectionFlag operator|(SectionFlag left, SectionFlag right) {
    return static_cast<SectionFlag>(static_cast<unsigned>(left) | static_cast<unsigned>(right));
  }

  constexpr bool hasFlag(SectionFlag flags, SectionFlag flag) {
    return (static_cast<unsigned>(flags) & static_cast<unsigned>(flag)) != 0;
  }

  enum class RelocationKind : std::uint8_t {
    // Standard ELF-like formulas. PCRelative32 writes S + A - P.
    PCRelative32,
    PLTRelative32,
    Absolute64,
    Absolute32,
    Absolute32Signed,
  };

  enum class SymbolBinding : std::uint8_t { Local, Global, Weak };

  struct Section {
    std::string name;
    SectionType type = SectionType::ProgramBits;
    SectionFlag flags = SectionFlag::None;
    std::vector<std::uint8_t> bytes;
    std::size_t memorySize = 0;
    std::size_t alignment = 1;
  };

  struct Symbol {
    std::string name;
    SectionId section = 0;
    std::size_t offset = 0;
    bool imported = false;
    bool absolute = false;
    SymbolBinding binding = SymbolBinding::Global;
  };

  struct Relocation {
    SectionId section = 0;
    std::size_t offset = 0;
    RelocationKind kind = RelocationKind::PCRelative32;
    std::string symbol;
    std::int64_t addend = 0;
  };

  class Module {
  public:
    Module();

    static constexpr SectionId id(SectionKind kind) {
      return static_cast<SectionId>(kind);
    }

    Section &section(SectionId id);
    const Section &section(SectionId id) const;
    Section &section(SectionKind kind) { return section(id(kind)); }
    const Section &section(SectionKind kind) const { return section(id(kind)); }
    Section &section(std::string_view name);
    const Section &section(std::string_view name) const;
    const std::vector<Section> &sections() const;

    SectionId addSection(std::string name, SectionType type = SectionType::ProgramBits,
                         SectionFlag flags = SectionFlag::None, std::size_t alignment = 1);
    const SectionId *findSection(std::string_view name) const;

    std::size_t append(SectionId section, std::span<const std::uint8_t> bytes, std::size_t alignment = 1);
    std::size_t append(SectionKind kind, std::span<const std::uint8_t> bytes, std::size_t alignment = 1) {
      return append(id(kind), bytes, alignment);
    }
    std::size_t reserve(SectionId section, std::size_t bytes, std::size_t alignment = 1);
    std::size_t reserve(SectionKind kind, std::size_t bytes, std::size_t alignment = 1) {
      return reserve(id(kind), bytes, alignment);
    }

    void define(std::string name, SectionId section, std::size_t offset,
                SymbolBinding binding = SymbolBinding::Global);
    void define(std::string name, SectionKind section, std::size_t offset,
                SymbolBinding binding = SymbolBinding::Global) {
      define(std::move(name), id(section), offset, binding);
    }
    void defineAbsolute(std::string name, std::size_t value, SymbolBinding binding = SymbolBinding::Global);
    void import(std::string name, SymbolBinding binding = SymbolBinding::Global);
    void relocate(SectionId section, std::size_t offset, RelocationKind kind, std::string symbol,
                  std::int64_t addend = 0);
    void relocate(SectionKind section, std::size_t offset, RelocationKind kind, std::string symbol,
                  std::int64_t addend = 0) {
      relocate(id(section), offset, kind, std::move(symbol), addend);
    }

    const Symbol *findSymbol(std::string_view name) const;
    const std::vector<Symbol> &symbols() const;
    const std::vector<Relocation> &relocations() const;

    void merge(const Module &other);
    bool removeSymbol(std::string_view name);

  private:
    std::vector<Section> moduleSections;
    std::vector<SectionId> namedSectionIds;
    std::vector<Symbol> moduleSymbols;
    std::vector<Relocation> moduleRelocations;
  };
} // namespace compiler
