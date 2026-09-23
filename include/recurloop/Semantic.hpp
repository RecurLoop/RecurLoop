#pragma once

#include <utilities/Exception.hpp>

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace context { class Context; }
namespace lexicon { class Phrase; }

namespace recurloop {
  struct SemanticMetadata {
    bool hasKind = false;
    bool hasColor = false;
    bool hasDocs = false;
    std::string kind;
    std::string color;
    std::string docs;
  };

  class Semantic {
  public:
    Semantic() = delete;

    // Source-level phrase metadata. Values are stored in a serializable hidden
    // lexicon registry whose phrase reference is relocated by EngineImage.
    static void setKind(context::Context &context, lexicon::Phrase phrase, std::string value);
    static void setColor(context::Context &context, lexicon::Phrase phrase, std::string value);
    static void setDocs(context::Context &context, lexicon::Phrase phrase, std::string value);
    static SemanticMetadata resolve(context::Context &context, lexicon::Phrase phrase);

    // Apply/clear phrase-definition metadata accumulated before the staged
    // phrase receives its final lexicon address.
    static void applyPending(context::Context &context, lexicon::Phrase phrase);
    static void clearPending(context::Context &context);

    class InspectionScope {
    public:
      InspectionScope(context::Context &context, std::string_view source, std::string_view path);
      InspectionScope(const InspectionScope &) = delete;
      InspectionScope &operator=(const InspectionScope &) = delete;
      ~InspectionScope();

      std::string encode(std::string_view diagnostic = {}) const;

    private:
      void *state_ = nullptr;
      void *previous_ = nullptr;
    };

    class OwnerScope {
    public:
      OwnerScope(context::Context &context, std::uint64_t owner, std::uint64_t group = 0);
      OwnerScope(const OwnerScope &) = delete;
      OwnerScope &operator=(const OwnerScope &) = delete;
      ~OwnerScope();

    private:
      void *state_ = nullptr;
      std::uint64_t previous_ = 0;
      std::uint64_t previousGroup_ = 0;
    };

    static bool active(context::Context &context);
    static std::uint64_t owner(context::Context &context);
    static std::uint64_t group(context::Context &context);

    // A root lookup starts a fresh user construct. Non-root lookup dictionaries
    // are continuation states and intentionally retain the previous docs owner.
    static void beginSourceStep(context::Context &context, bool rootLookup);

    // Deterministic fail-safe for inspection-only source execution.  Normal
    // execution pays only the active() branch; an inspection that accidentally
    // re-enters an empty phrase forever is aborted and rolled back instead of
    // blocking the IDE main loop indefinitely.
    static void sourceStep(context::Context &context);

    // Record a source-visible phrase. The returned owner is either the matched
    // phrase (when it defines/inherits docs) or the supplied/current owner.
    static std::uint64_t record(context::Context &context, lexicon::Phrase phrase,
                                const SourceLocation &start, const SourceLocation &end,
                                std::uint64_t fallbackOwner = 0, bool continueOwner = false,
                                std::uint64_t *ownerGroup = nullptr);

    // Convenience for syntax-extension offset maps.
    static std::uint64_t recordMapped(context::Context &context, lexicon::Phrase phrase,
                                      const SourceLocation &origin, std::string_view originalSource,
                                      std::size_t start, std::size_t end,
                                      std::uint64_t fallbackOwner = 0, bool continueOwner = false,
                                      std::uint64_t *ownerGroup = nullptr);
  };
} // namespace recurloop
