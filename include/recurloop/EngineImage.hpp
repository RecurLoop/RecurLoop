#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include <utilities/Size.hpp>

namespace context {
  class Context;
}
namespace lexicon {
  class Phrase;
}

namespace recurloop {
  // A relocatable, flattened image of the phrase engine. The format stores
  // stable action names and phrase ids instead of process pointers and radix
  // addresses.
  class EngineImage {
  public:
    EngineImage() = delete;
    static constexpr std::uint32_t Version = 7;

    static std::vector<std::uint8_t> encode(context::Context &context);
    // Encode only phrases created after the supplied radix checkpoint. The
    // root and any reachable type/prototype/action dependencies are retained.
    static std::vector<std::uint8_t> encode(context::Context &context, Size since);
    static void decode(context::Context &context, std::span<const std::uint8_t> bytes);
    // Materialize an image below an existing dictionary. Existing phrases are
    // reused as graph dependencies; new phrases are appended to the target.
    static void merge(context::Context &context, std::span<const std::uint8_t> bytes, lexicon::Phrase target);
    static void merge(context::Context &context, lexicon::Phrase source, lexicon::Phrase target);
    static std::string source(context::Context &context);
    static void define(context::Context &context, std::string_view manifest);
    static void save(context::Context &context, const std::string &path);
    static void load(context::Context &context, const std::string &path);
  };
} // namespace recurloop
