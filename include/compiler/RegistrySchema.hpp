#pragma once

#include <utilities/Size.hpp>

#include <cstdint>
#include <span>
#include <vector>

namespace lexicon {
  class Lexicon;
  class Phrase;
}

namespace compiler {
  // Stable host-facing semantic roles. Source core owns the physical keys and
  // hierarchy used to materialize these roles in the shared lexicon.
  enum class RegistryRole : std::uint16_t {
    CallingConventions = 1,
    Functions,
    FunctionSources,
    Modules,
    Settings,
    ModuleSelections,
    LinkObjects,
    LinkArchives,
    LinkPaths,
    SharedLibraries,
    Types,
    TypeIds,
    AbiKinds,
  };

  enum class SlotRole : std::uint16_t {
    TypeNextId = 1,
    AutomaticModules,
    EmbedLanguage,
    SelectionGeneration,
    LinkSequence,
    LinkGeneration,
    ModuleEntry,
  };

  struct Language {
    static constexpr std::uint64_t Magic = 0x524C4C414E475545ull;
    static constexpr std::uint32_t Version = 4;

    std::uint64_t magic = Magic;
    std::uint32_t version = Version;
    std::uint32_t reserved = 0;
  };

  struct RegistryBinding {
    static constexpr std::uint64_t Magic = 0x524C524547495354ull;
    static constexpr std::uint16_t Version = 1;

    std::uint64_t magic = Magic;
    std::uint16_t version = Version;
    RegistryRole role = RegistryRole::CallingConventions;
    std::uint32_t reserved = 0;
  };

  struct SlotBinding {
    static constexpr std::uint64_t Magic = 0x524C534C4F544249ull;
    static constexpr std::uint16_t Version = 1;

    std::uint64_t magic = Magic;
    std::uint16_t version = Version;
    SlotRole role = SlotRole::TypeNextId;
    std::uint32_t reserved = 0;
  };

  class RegistrySchema {
  public:
    static void initializeLanguage(lexicon::Phrase language);
    static lexicon::Phrase language(lexicon::Lexicon &lexicon, Size address = 0);

    static void bindRegistry(lexicon::Phrase registry, RegistryRole role);
    static lexicon::Phrase registry(lexicon::Lexicon &lexicon, Size languageAddress, RegistryRole role);

    static void bindSlot(lexicon::Phrase slot, SlotRole role, std::span<const std::uint8_t> initial = {});
    static lexicon::Phrase slot(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role);
    static std::vector<std::uint8_t> slotData(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role);
    static void setSlotData(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role,
                            std::span<const std::uint8_t> data);
    static std::uint64_t unsignedSlot(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role);
    static void setUnsignedSlot(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role,
                                std::uint64_t value);
  };
} // namespace compiler
