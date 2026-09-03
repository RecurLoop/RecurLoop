#include <recurloop/SyntaxExtension.hpp>

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/ContextApi.hpp>
#include <utilities/Byte.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cctype>
#include <limits>
#include <numeric>
#include <span>

namespace recurloop {
  namespace {
    constexpr std::size_t MaximumExpansionPasses = 64;

    struct ExpansionFrame {
      context::Context *context = nullptr;
      std::string_view source;
      std::string_view originalSource;
      std::span<const std::size_t> originalOffsets;
      SourceLocation origin;
      std::size_t cursor = 0;
      std::string output;
      std::vector<std::size_t> outputOffsets;
      std::size_t rewriteOffset = 0;
      bool handled = false;
    };

    thread_local ExpansionFrame *currentExpansion = nullptr;

    ExpansionFrame &frame(context::Context &context) {
      if (currentExpansion == nullptr || currentExpansion->context != &context)
        THROW(, "syntax rewrite operation requires an active fn expansion")
      return *currentExpansion;
    }

    bool identifierByte(unsigned char value) {
      return std::isalnum(value) || value == '_';
    }

    bool hasBoundary(std::string_view source, std::size_t offset, std::string_view spelling) {
      if (spelling.empty()) return false;
      if (identifierByte(static_cast<unsigned char>(spelling.front())) && offset != 0 &&
          identifierByte(static_cast<unsigned char>(source[offset - 1])))
        return false;
      const std::size_t end = offset + spelling.size();
      return !identifierByte(static_cast<unsigned char>(spelling.back())) || end == source.size() ||
             !identifierByte(static_cast<unsigned char>(source[end]));
    }

    lexicon::Phrase phraseAt(context::Context &context, std::uint64_t address) {
      if (address == 0 || address >= context.lexicon.memoryUsed()) return lexicon::Phrase(&context.lexicon);
      return lexicon::Phrase(&context.lexicon, address).load();
    }

    lexicon::Phrase longest(lexicon::Phrase dictionary, std::string_view source, std::size_t offset) {
      if (dictionary.isNull() || !dictionary.containsSubdictionary()) return lexicon::Phrase(dictionary.getLexicon());
      lexicon::Match match =
          dictionary.matchLongest(Byte(const_cast<char *>(source.data() + offset)), 0,
                                  (source.size() - offset) * Byte::length, [](radix::Node *, radix::Match *candidate) {
                                    lexicon::Phrase phrase = lexicon::Dictionary(*candidate).getPhrase();
                                    return !phrase.isNull() && phrase.isRewritable();
                                  });
      if (match.isNull()) return lexicon::Phrase(dictionary.getLexicon());
      lexicon::Phrase result = match.getPhrase();
      return hasBoundary(source, offset, result.getKey()) ? result : lexicon::Phrase(dictionary.getLexicon());
    }

    std::size_t protectedEnd(std::string_view source, std::size_t cursor) {
      if (source[cursor] == '"') {
        ++cursor;
        while (cursor < source.size()) {
          if (source[cursor] == '\\' && cursor + 1 < source.size()) {
            cursor += 2;
          } else if (source[cursor++] == '"') {
            break;
          }
        }
        return cursor;
      }
      if (source.substr(cursor).starts_with("//")) {
        while (cursor < source.size() && source[cursor] != '\n') ++cursor;
        return cursor;
      }
      if (source.substr(cursor).starts_with("/*")) {
        cursor += 2;
        while (cursor + 1 < source.size() && !source.substr(cursor).starts_with("*/")) ++cursor;
        return std::min(source.size(), cursor + 2);
      }
      return cursor;
    }

    std::pair<ExpandedSyntax, bool> expandOnce(context::Context &context, lexicon::Phrase rewrites,
                                               std::string_view source, std::string_view originalSource,
                                               std::span<const std::size_t> originalOffsets,
                                               const SourceLocation &origin) {
      ExpandedSyntax expanded;
      expanded.source.reserve(source.size());
      expanded.originalOffsets.reserve(source.size() + 1);
      bool changed = false;
      std::size_t cursor = 0;
      while (cursor < source.size()) {
        const std::size_t protectedCursor = protectedEnd(source, cursor);
        if (protectedCursor != cursor) {
          expanded.source.append(source.substr(cursor, protectedCursor - cursor));
          expanded.originalOffsets.insert(expanded.originalOffsets.end(), originalOffsets.begin() + cursor,
                                          originalOffsets.begin() + protectedCursor);
          cursor = protectedCursor;
          continue;
        }

        lexicon::Phrase rewrite = longest(rewrites, source, cursor);
        if (rewrite.isNull()) {
          expanded.source.push_back(source[cursor]);
          expanded.originalOffsets.push_back(originalOffsets[cursor++]);
          continue;
        }

        const std::string key = rewrite.getKey();
        ExpansionFrame local;
        local.context = &context;
        local.source = source;
        local.originalSource = originalSource;
        local.originalOffsets = originalOffsets;
        local.origin = origin;
        local.cursor = cursor + key.size();
        local.rewriteOffset = originalOffsets[cursor];
        ExpansionFrame *previous = currentExpansion;
        currentExpansion = &local;
        try {
          rewrite.elaborate(context);
        } catch (...) {
          currentExpansion = previous;
          throw;
        }
        currentExpansion = previous;
        if (!local.handled) {
          const SourceLocation location = sourceLocationAt(origin, originalSource, originalOffsets[cursor]);
          THROW_AT(location, "syntax rewrite '" << key << "' did not emit or consume source")
        }
        expanded.source += local.output;
        expanded.originalOffsets.insert(expanded.originalOffsets.end(), local.outputOffsets.begin(),
                                        local.outputOffsets.end());
        cursor = local.cursor;
        changed = true;
      }
      expanded.originalOffsets.push_back(originalOffsets[source.size()]);
      return {std::move(expanded), changed};
    }
  } // namespace

  lexicon::Phrase SyntaxExtension::dictionary(context::Context &context) {
    return context.lexicon.phrase();
  }

  bool SyntaxExtension::active(context::Context &context) {
    return currentExpansion != nullptr && currentExpansion->context == &context;
  }

  ExpandedSyntax SyntaxExtension::expand(context::Context &context, std::string_view source, SourceLocation origin) {
    ExpandedSyntax current{std::string(source), {}};
    lexicon::Phrase rewrites = dictionary(context);
    if (rewrites.isNull()) return current;
    auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
    if (rewrites.fore(populated).isNull()) return current;
    current.originalOffsets.resize(source.size() + 1);
    std::iota(current.originalOffsets.begin(), current.originalOffsets.end(), std::size_t{0});
    for (std::size_t pass = 0; pass < MaximumExpansionPasses; ++pass) {
      auto [next, changed] = expandOnce(context, rewrites, current.source, source, current.originalOffsets, origin);
      if (!changed) return next;
      if (next.source == current.source) return current;
      current = std::move(next);
    }
    THROW_AT(origin, "fn syntax rewrite did not converge after " << MaximumExpansionPasses << " passes")
  }

  const std::uint8_t *SyntaxExtension::data(context::Context &context) {
    ExpansionFrame &current = frame(context);
    return reinterpret_cast<const std::uint8_t *>(current.source.data() + current.cursor);
  }

  std::uint64_t SyntaxExtension::bytes(context::Context &context) {
    ExpansionFrame &current = frame(context);
    return current.source.size() - current.cursor;
  }

  std::uint64_t SyntaxExtension::advance(context::Context &context, std::uint64_t bytes) {
    ExpansionFrame &current = frame(context);
    if (bytes > current.source.size() - current.cursor) THROW(, "syntax rewrite advance is out of bounds")
    current.cursor += static_cast<std::size_t>(bytes);
    current.handled = true;
    return bytes;
  }

  std::uint64_t SyntaxExtension::emit(context::Context &context, const std::uint8_t *source, std::uint64_t offset,
                                      std::uint64_t bytes) {
    ExpansionFrame &current = frame(context);
    if (bytes != 0 && source == nullptr) THROW(, "syntax rewrite emit received a null source")
    if (offset > std::numeric_limits<std::size_t>::max() || bytes > std::numeric_limits<std::size_t>::max() - offset)
      THROW(, "syntax rewrite emit slice is too large")
    if (bytes != 0)
      current.output.append(reinterpret_cast<const char *>(source) + static_cast<std::size_t>(offset),
                            static_cast<std::size_t>(bytes));
    current.outputOffsets.insert(current.outputOffsets.end(), static_cast<std::size_t>(bytes), current.rewriteOffset);
    current.handled = true;
    return bytes;
  }

  std::uint64_t SyntaxExtension::copy(context::Context &context, std::uint64_t bytes) {
    ExpansionFrame &current = frame(context);
    if (bytes > current.source.size() - current.cursor) THROW(, "syntax rewrite copy is out of bounds")
    current.output.append(current.source.substr(current.cursor, static_cast<std::size_t>(bytes)));
    current.outputOffsets.insert(current.outputOffsets.end(), current.originalOffsets.begin() + current.cursor,
                                 current.originalOffsets.begin() + current.cursor + static_cast<std::size_t>(bytes));
    current.cursor += static_cast<std::size_t>(bytes);
    current.handled = true;
    return bytes;
  }

  std::uint64_t SyntaxExtension::match(context::Context &context, std::uint64_t dictionaryAddress, std::uint64_t mode) {
    ExpansionFrame &current = frame(context);
    lexicon::Phrase owner = phraseAt(context, dictionaryAddress);
    if (owner.isNull() || !owner.containsSubdictionary()) THROW(, "syntax rewrite match requires a dictionary")
    const std::size_t remaining = current.source.size() - current.cursor;
    auto populated = [](radix::Node *, radix::Match *candidate) {
      return !lexicon::Dictionary(*candidate).getPhrase().isNull();
    };
    lexicon::Match result;
    Byte input(const_cast<char *>(current.source.data() + current.cursor));
    if (mode == context_phrase::First)
      result = owner.matchFirst(input, 0, remaining * Byte::length, populated);
    else if (mode == context_phrase::Longest)
      result = owner.matchLongest(input, 0, remaining * Byte::length, populated);
    else if (mode == context_phrase::Exact)
      result = owner.matchExact(input, 0, remaining * Byte::length, populated);
    else
      THROW(, "syntax rewrite match received an invalid mode")
    if (result.isNull()) return 0;
    lexicon::Phrase phrase = result.getPhrase();
    current.cursor += phrase.getKey().size();
    current.handled = true;
    return phrase.getAddress();
  }

  std::uint64_t SyntaxExtension::elaborate(context::Context &context, std::uint64_t dictionaryAddress) {
    ExpansionFrame &current = frame(context);
    lexicon::Phrase dictionary = phraseAt(context, dictionaryAddress);
    if (dictionary.isNull() || !dictionary.containsSubdictionary())
      THROW(, "syntax elaboration requires a phrase dictionary")

    while (current.cursor < current.source.size()) {
      const std::size_t cursor = current.cursor;
      const std::uint64_t matchedAddress = match(context, dictionary.getAddress(), context_phrase::Longest);
      lexicon::Phrase matched = phraseAt(context, matchedAddress);
      if (matched.isNull()) THROW(, "syntax phrase graph could not match source")

      lexicon::Phrase successor =
          matched.containsSuccessor() ? matched.getSuccessor() : lexicon::Phrase(&context.lexicon);
      lexicon::phrase::type::action(context, matched);
      if (successor.isNull()) {
        const std::string key = matched.getKey();
        return key.empty() ? 0 : static_cast<unsigned char>(key.front());
      }
      if (current.cursor == cursor && successor.getAddress() == dictionary.getAddress())
        THROW(, "syntax phrase graph did not advance")
      dictionary = successor;
      if (!dictionary.containsSubdictionary()) THROW(, "syntax phrase successor is not a dictionary")
    }
    return 0;
  }

  const std::uint8_t *SyntaxExtension::path(context::Context &context) {
    return reinterpret_cast<const std::uint8_t *>(frame(context).origin.path.c_str());
  }

  std::uint64_t SyntaxExtension::line(context::Context &context) {
    ExpansionFrame &current = frame(context);
    return sourceLocationAt(current.origin, current.originalSource, current.originalOffsets[current.cursor]).line;
  }

  std::uint64_t SyntaxExtension::position(context::Context &context) {
    ExpansionFrame &current = frame(context);
    return sourceLocationAt(current.origin, current.originalSource, current.originalOffsets[current.cursor]).column;
  }
} // namespace recurloop
