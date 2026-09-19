#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <string_view>

namespace context {
  class Context;
}
namespace lexicon {
  class Phrase;
}

namespace recurloop {
  // Helper for source-backed lexicon phrases. Source descriptors remain in
  // the lexicon; compiled fragment images are produced only when requested.
  class TranslationUnitRegistry {
  public:
    explicit TranslationUnitRegistry(context::Context &owner);
    std::vector<std::uint8_t> image(lexicon::Phrase phrase);
    void merge(lexicon::Phrase source, lexicon::Phrase target);
    void merge(const std::string &path, lexicon::Phrase target);
    static void merge(context::Context &context, lexicon::Phrase &invoked);
    static lexicon::Phrase reference(context::Context &context, std::string_view path);

    static std::vector<std::uint8_t> descriptor(std::string_view source);
    static std::string source(lexicon::Phrase phrase);
    static bool isDescriptor(lexicon::Phrase phrase);

  private:
    context::Context &owner;
  };
} // namespace recurloop
