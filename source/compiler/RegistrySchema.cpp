#include <compiler/RegistrySchema.hpp>

#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <cstring>

namespace compiler {
  namespace {
    bool languageMetadata(lexicon::Phrase phrase, Language &value) {
      if (phrase.payloadSize() != sizeof(Language)) return false;
      phrase.fetch(0, value);
      return value.magic == Language::Magic && value.version == Language::Version && value.reserved == 0;
    }

    bool registryMetadata(lexicon::Phrase phrase, RegistryBinding &value) {
      if (phrase.payloadSize() != sizeof(RegistryBinding)) return false;
      phrase.fetch(0, value);
      return value.magic == RegistryBinding::Magic && value.version == RegistryBinding::Version && value.reserved == 0;
    }

    bool slotMetadata(lexicon::Phrase phrase, SlotBinding &value) {
      if (phrase.payloadSize() < sizeof(SlotBinding)) return false;
      phrase.fetch(0, value);
      return value.magic == SlotBinding::Magic && value.version == SlotBinding::Version && value.reserved == 0;
    }

    auto populated() {
      return [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
    }

    void storeBytes(lexicon::Phrase phrase, std::span<const std::uint8_t> bytes) {
      if (!bytes.empty()) {
        Byte output = phrase.allocate(bytes.size());
        std::memcpy(output.toPtr(), bytes.data(), bytes.size());
      }
      phrase.save();
    }
  } // namespace

  void RegistrySchema::initializeLanguage(lexicon::Phrase language) {
    if (language.isNull() || !language.containsSubdictionary())
      THROW(, "compiler language schema must be a dictionary phrase")
    if (language.payloadSize() == 0) {
      language.store(Language{}).save();
      return;
    }
    Language metadata;
    if (!languageMetadata(language, metadata)) THROW(, "compiler language phrase has unsupported schema metadata")
  }

  lexicon::Phrase RegistrySchema::language(lexicon::Lexicon &lexicon, Size address) {
    if (address != 0) {
      lexicon::Phrase result(&lexicon, address);
      result.load();
      Language metadata;
      if (result.isNull() || !languageMetadata(result, metadata))
        THROW(, "compiler language phrase is unavailable or has unsupported schema metadata")
      return result;
    }

    lexicon::Phrase root = lexicon.phrase();
    for (lexicon::Dictionary cursor = root.fore(populated()); !cursor.isNull(); cursor = cursor.next(populated())) {
      lexicon::Phrase candidate = cursor.getPhrase();
      Language metadata;
      if (languageMetadata(candidate, metadata)) return candidate;
    }
    THROW(, "compiler language phrase is not initialized")
  }

  void RegistrySchema::bindRegistry(lexicon::Phrase registry, RegistryRole role) {
    if (registry.isNull() || !registry.containsSubdictionary())
      THROW(, "compiler registry schema entry must be a dictionary phrase")
    if (registry.payloadSize() != 0) THROW(, "compiler registry schema entry already has payload")
    registry.store(RegistryBinding{RegistryBinding::Magic, RegistryBinding::Version, role, 0}).save();
  }

  lexicon::Phrase RegistrySchema::registry(lexicon::Lexicon &lexicon, Size languageAddress, RegistryRole role) {
    lexicon::Phrase owner = language(lexicon, languageAddress);
    for (lexicon::Dictionary cursor = owner.fore(populated()); !cursor.isNull(); cursor = cursor.next(populated())) {
      lexicon::Phrase candidate = cursor.getPhrase();
      RegistryBinding binding;
      if (registryMetadata(candidate, binding) && binding.role == role) return candidate;
    }
    THROW(, "compiler registry role is not initialized: " << static_cast<unsigned>(role))
  }

  void RegistrySchema::bindSlot(lexicon::Phrase slot, SlotRole role, std::span<const std::uint8_t> initial) {
    if (slot.isNull()) THROW(, "compiler setting slot phrase is unavailable")
    if (slot.payloadSize() != 0) THROW(, "compiler setting slot already has payload")
    SlotBinding binding{SlotBinding::Magic, SlotBinding::Version, role, 0};
    std::vector<std::uint8_t> bytes(sizeof(binding) + initial.size());
    std::memcpy(bytes.data(), &binding, sizeof(binding));
    if (!initial.empty()) std::memcpy(bytes.data() + sizeof(binding), initial.data(), initial.size());
    storeBytes(slot, bytes);
  }

  lexicon::Phrase RegistrySchema::slot(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role) {
    lexicon::Phrase settings = registry(lexicon, languageAddress, RegistryRole::Settings);
    for (lexicon::Dictionary cursor = settings.fore(populated()); !cursor.isNull(); cursor = cursor.next(populated())) {
      lexicon::Phrase candidate = cursor.getPhrase();
      SlotBinding binding;
      if (slotMetadata(candidate, binding) && binding.role == role) return candidate;
    }
    THROW(, "compiler setting slot role is not initialized: " << static_cast<unsigned>(role))
  }

  std::vector<std::uint8_t> RegistrySchema::slotData(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role) {
    lexicon::Phrase phrase = slot(lexicon, languageAddress, role);
    const std::size_t size = phrase.payloadSize() - sizeof(SlotBinding);
    std::vector<std::uint8_t> result(size);
    if (size != 0) std::memcpy(result.data(), phrase.content(sizeof(SlotBinding), size).toPtr(), size);
    return result;
  }

  void RegistrySchema::setSlotData(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role,
                                   std::span<const std::uint8_t> data) {
    lexicon::Phrase current = slot(lexicon, languageAddress, role);
    lexicon::Phrase settings = registry(lexicon, languageAddress, RegistryRole::Settings);
    lexicon::Phrase phrase = settings.append(current.getKey())
                                  .make()
                                  .setType(lexicon::phrase::type::getData(settings))
                                  .save();
    SlotBinding binding{SlotBinding::Magic, SlotBinding::Version, role, 0};
    std::vector<std::uint8_t> bytes(sizeof(binding) + data.size());
    std::memcpy(bytes.data(), &binding, sizeof(binding));
    if (!data.empty()) std::memcpy(bytes.data() + sizeof(binding), data.data(), data.size());
    storeBytes(phrase, bytes);
  }

  std::uint64_t RegistrySchema::unsignedSlot(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role) {
    const std::vector<std::uint8_t> data = slotData(lexicon, languageAddress, role);
    if (data.size() != sizeof(std::uint64_t)) THROW(, "compiler unsigned slot has invalid payload size")
    std::uint64_t value = 0;
    std::memcpy(&value, data.data(), sizeof(value));
    return value;
  }

  void RegistrySchema::setUnsignedSlot(lexicon::Lexicon &lexicon, Size languageAddress, SlotRole role,
                                       std::uint64_t value) {
    setSlotData(lexicon, languageAddress, role,
                std::span<const std::uint8_t>(reinterpret_cast<const std::uint8_t *>(&value), sizeof(value)));
  }
} // namespace compiler
