#pragma once

#include <cstdint>
#include <span>
#include <cstddef>
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

    // Generic payload layout metadata used by .rl-defined semantic objects.
    // A layout is attached to a schema phrase; phrases whose direct prototype
    // is that schema use the declared payload field semantics during image
    // capture, relocation and semantic promotion.
    enum class PayloadFieldKind : std::uint8_t { PhraseReference = 1, NativePointer = 2 };

    static std::vector<std::uint8_t> encode(context::Context &context);
    // Encode only phrases created after the supplied radix checkpoint. The
    // root and any reachable type/prototype/action dependencies are retained.
    static std::vector<std::uint8_t> encode(context::Context &context, Size since);
    static void decode(context::Context &context, std::span<const std::uint8_t> bytes);
    // Restore exactly the serialized semantic graph without injecting the
    // compatibility compiler/value defaults normally supplied by decode().
    // This is used by the private seed/core build pipeline so the minimal seed
    // cannot receive hidden language/compiler state from C++ before core.rl.
    static void decodeExact(context::Context &context, std::span<const std::uint8_t> bytes);
    // Materialize an image below an existing dictionary. Existing phrases are
    // reused as graph dependencies; new phrases are appended to the target.
    static void merge(context::Context &context, std::span<const std::uint8_t> bytes, lexicon::Phrase target);
    static void merge(context::Context &context, lexicon::Phrase source, lexicon::Phrase target);

    // Declare image semantics for one payload field of instances whose direct
    // prototype is `schema`. PhraseReference fields are relocated through
    // .rli images; NativePointer fields are explicitly process-local and make
    // serialization fail while non-zero. The declaration itself lives in the
    // lexicon and therefore survives normal image round trips.
    static void declarePayloadField(context::Context &context, lexicon::Phrase schema, std::size_t offset,
                                    PayloadFieldKind kind);

    // Selectively preserve semantic state created after `checkpoint`. The
    // selected roots and their visible descendants are captured, the lexicon
    // is restored to the checkpoint, and only the selected graph is replayed.
    // References may target another selected phrase or a phrase that predates
    // the checkpoint; dependencies on unselected post-checkpoint phrases are
    // rejected.
    static void promote(context::Context &context, Size checkpoint, std::span<const lexicon::Phrase> roots);
    static std::string source(context::Context &context);
    static void define(context::Context &context, std::string_view source, std::string_view sourcePath = {});
    static void save(context::Context &context, const std::string &path);
    static void load(context::Context &context, const std::string &path);
  };
} // namespace recurloop
