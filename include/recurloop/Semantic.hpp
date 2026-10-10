#pragma once

#include <utilities/Exception.hpp>

#include <cstddef>
#include <cstdint>
#include <functional>
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
    // Engine-image restores during rollback-only inspection can introduce new
    // phrase metadata. Mark the active trace so it refreshes lazily only when a
    // later matched phrase actually needs metadata that was not present before.
    static void markInspectionMetadataDirty(context::Context &context);

    // Keep inspection identities alive across a complete lexicon replacement.
    // Removed phrases retain their last facts; preserved phrases are relocated
    // so later metadata edits still apply to their earlier occurrences.
    class InspectionRelocation {
    public:
      explicit InspectionRelocation(context::Context &context);
      ~InspectionRelocation();
      InspectionRelocation(const InspectionRelocation &) = delete;
      InspectionRelocation &operator=(const InspectionRelocation &) = delete;
      void relocate(const std::function<std::uint64_t(std::uint64_t)> &address);

    private:
      void *state_ = nullptr;
    };

    // Apply/clear phrase-definition metadata accumulated before the staged
    // phrase receives its final lexicon address.
    static void applyPending(context::Context &context, lexicon::Phrase phrase);
    static void clearPending(context::Context &context);

    // Bind a parsed declaration range once its staged phrase has been saved.
    static void stageDefinition(context::Context &context, const SourceLocation &start, const SourceLocation &end);
    static void recordDefinition(context::Context &context, lexicon::Phrase phrase);

    // Reusable console palette: resolve language metadata once, then scan only
    // the edited text. Recreate after the owning session's language changes.
    class ConsoleHighlighter {
    public:
      explicit ConsoleHighlighter(context::Context &context);
      ~ConsoleHighlighter();
      ConsoleHighlighter(const ConsoleHighlighter &) = delete;
      ConsoleHighlighter &operator=(const ConsoleHighlighter &) = delete;
      std::string highlight(std::string_view source);

    private:
      void *state_ = nullptr;
    };

    class InspectionScope {
    public:
      InspectionScope(context::Context &context, std::string_view source, std::string_view path);
      InspectionScope(const InspectionScope &) = delete;
      InspectionScope &operator=(const InspectionScope &) = delete;
      ~InspectionScope();

      std::string encode(std::string_view diagnostic = {}) const;
      // Export actual phrase matches and the current dictionary/type/function
      // catalog. This contains language state only; clients interpret it.
      std::string trace() const;

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

    // Compiler locals have lexical identities, not persistent phrase addresses.
    // Keep their facts in the current inspection and export the same P/R records.
    static std::uint64_t local(context::Context &context, std::string name);
    static void localMetadata(context::Context &context, std::uint64_t local, std::string_view field,
                              std::string value);
    static void recordLocal(context::Context &context, std::uint64_t local, const SourceLocation &origin,
                            std::string_view source, std::size_t start, std::size_t end);

    // A root lookup starts a fresh user construct. Non-root lookup dictionaries
    // are continuation states and intentionally retain the previous docs owner.
    static void beginSourceStep(context::Context &context, bool rootLookup);

    // Deterministic fail-safe for inspection-only source execution.  Normal
    // execution pays only the active() branch; an inspection that accidentally
    // re-enters an empty phrase forever is aborted and rolled back instead of
    // blocking the inspection client indefinitely.
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
