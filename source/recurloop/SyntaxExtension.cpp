#include <recurloop/SyntaxExtension.hpp>

#include <compiler/LanguageState.hpp>
#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/ContextApi.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/Semantic.hpp>
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
      std::uint64_t semanticOwner = 0;
      std::uint64_t semanticGroup = 0;
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

    bool qualifiedIdentifierByte(unsigned char value) {
      return identifierByte(value) || value == '.';
    }

    bool qualifiedMember(context::Context &context, std::string_view source, std::size_t offset,
                         std::string_view spelling) {
      if (offset == 0 || source[offset - 1] != ':') return false;
      std::size_t begin = offset - 1;
      while (begin != 0 && (identifierByte(static_cast<unsigned char>(source[begin - 1])) || source[begin - 1] == ':' ||
                            source[begin - 1] == '-'))
        --begin;
      const auto qualified = source.substr(begin, offset + spelling.size() - begin);
      if (!LanguageGrammar::findQualified(context.lexicon.phrase(), qualified).isNull() ||
          !context.language().findFunctions(qualified).empty())
        return true;
      auto owner = LanguageGrammar::findQualified(context.lexicon.phrase(), source.substr(begin, offset - begin - 1));
      // A colon also introduces a type annotation. Only an existing phrase
      // member or native function establishes namespace qualification here.
      return !LanguageGrammar::findInherited(owner, spelling).isNull();
    }

    bool hasBoundary(context::Context &context, std::string_view source, std::size_t offset,
                     std::string_view spelling) {
      if (spelling.empty()) return false;
      if (identifierByte(static_cast<unsigned char>(spelling.front())) &&
          ((offset != 0 && qualifiedIdentifierByte(static_cast<unsigned char>(source[offset - 1]))) ||
           qualifiedMember(context, source, offset, spelling)))
        return false;
      const std::size_t end = offset + spelling.size();
      return !identifierByte(static_cast<unsigned char>(spelling.back())) || end == source.size() ||
             !(qualifiedIdentifierByte(static_cast<unsigned char>(source[end])) || source[end] == ':');
    }

    lexicon::Phrase phraseAt(context::Context &context, std::uint64_t address) {
      if (address == 0 || address >= context.lexicon.memoryUsed()) return lexicon::Phrase(&context.lexicon);
      return lexicon::Phrase(&context.lexicon, address).load();
    }

    lexicon::Phrase longest(context::Context &context, lexicon::Phrase dictionary, std::string_view source,
                            std::size_t offset) {
      if (dictionary.isNull() || !dictionary.containsSubdictionary()) return lexicon::Phrase(dictionary.getLexicon());
      auto result = LanguageGrammar::matchLongest(dictionary, source.substr(offset), [&](lexicon::Phrase phrase) {
        return hasBoundary(context, source, offset, phrase.getKey());
      });
      return !result.isNull() && result.isRewritable() ? result : lexicon::Phrase(dictionary.getLexicon());
    }

    std::size_t protectedEnd(context::Context &context, std::string_view source, std::size_t cursor) {
      auto matched = LanguageGrammar::matchLongest(
          context.lexicon.phrase(), source.substr(cursor),
          [&](lexicon::Phrase candidate) { return hasBoundary(context, source, cursor, candidate.getKey()); });
      if (!matched.isNull() && matched.isRewritable() && hasBoundary(context, source, cursor, matched.getKey()))
        return cursor;
      const auto comment = [&](std::string_view canonical) {
        return LanguageGrammar::inherits(matched, LanguageGrammar::find(context.lexicon.phrase(), canonical));
      };
      if (source[cursor] == '"' && matched.isNull()) {
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
      if (comment("//")) {
        while (cursor < source.size() && source[cursor] != '\n') ++cursor;
        return cursor;
      }
      if (comment("/*")) {
        cursor += matched.getKey().size();
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
        const std::size_t protectedCursor = protectedEnd(context, source, cursor);
        if (protectedCursor != cursor) {
          expanded.source.append(source.substr(cursor, protectedCursor - cursor));
          expanded.originalOffsets.insert(expanded.originalOffsets.end(), originalOffsets.begin() + cursor,
                                          originalOffsets.begin() + protectedCursor);
          cursor = protectedCursor;
          continue;
        }

        lexicon::Phrase rewrite = longest(context, rewrites, source, cursor);
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
        local.semanticGroup = Semantic::group(context);
        local.semanticOwner = Semantic::recordMapped(context, rewrite, origin, originalSource, originalOffsets[cursor],
                                                     originalOffsets[cursor + key.size()], Semantic::owner(context), false,
                                                     &local.semanticGroup);
        ExpansionFrame *previous = currentExpansion;
        currentExpansion = &local;
        Semantic::OwnerScope semanticScope(context, local.semanticOwner, local.semanticGroup);
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

  SyntaxRewriteResult SyntaxExtension::rewriteAt(context::Context &context, std::string &source,
                                                  std::vector<std::size_t> &originalOffsets,
                                                  std::string_view originalSource, SourceLocation origin,
                                                  std::size_t offset) {
    if (originalOffsets.empty()) {
      originalOffsets.resize(source.size() + 1);
      std::iota(originalOffsets.begin(), originalOffsets.end(), std::size_t{0});
    }
    if (originalOffsets.size() != source.size() + 1) THROW(, "syntax rewrite offset map is inconsistent")
    if (offset >= source.size()) return {};

    lexicon::Phrase rewrites = dictionary(context);
    if (rewrites.isNull() || !rewrites.containsSubdictionary()) return {};

    bool changed = false;
    for (std::size_t pass = 0; pass < MaximumExpansionPasses; ++pass) {
      if (offset >= source.size() || protectedEnd(context, source, offset) != offset) return {changed, false};

      lexicon::Phrase rewrite = longest(context, rewrites, source, offset);
      if (rewrite.isNull()) return {changed, false};

      const std::string key = rewrite.getKey();
      ExpansionFrame local;
      local.context = &context;
      local.source = source;
      local.originalSource = originalSource;
      local.originalOffsets = originalOffsets;
      local.origin = origin;
      local.cursor = offset + key.size();
      local.rewriteOffset = originalOffsets[offset];
      local.semanticGroup = Semantic::group(context);
      local.semanticOwner = Semantic::recordMapped(context, rewrite, origin, originalSource, originalOffsets[offset],
                                                   originalOffsets[offset + key.size()], Semantic::owner(context), false,
                                                   &local.semanticGroup);

      ExpansionFrame *previous = currentExpansion;
      currentExpansion = &local;
      Semantic::OwnerScope semanticScope(context, local.semanticOwner, local.semanticGroup);
      try {
        rewrite.elaborate(context);
      } catch (...) {
        currentExpansion = previous;
        throw;
      }
      currentExpansion = previous;

      if (!local.handled) {
        const SourceLocation location = sourceLocationAt(origin, originalSource, originalOffsets[offset]);
        THROW_AT(location, "syntax rewrite '" << key << "' did not emit or consume source")
      }
      if (local.cursor < offset || local.cursor > source.size()) THROW(, "syntax rewrite consumed an invalid source range")

      const std::size_t consumed = local.cursor - offset;
      if (local.output == source.substr(offset, consumed)) return {changed, true};

      source.replace(offset, consumed, local.output);
      originalOffsets.erase(originalOffsets.begin() + static_cast<std::ptrdiff_t>(offset),
                            originalOffsets.begin() + static_cast<std::ptrdiff_t>(local.cursor));
      originalOffsets.insert(originalOffsets.begin() + static_cast<std::ptrdiff_t>(offset),
                             local.outputOffsets.begin(), local.outputOffsets.end());
      changed = true;
    }

    const std::size_t mapped = originalOffsets[std::min(offset, originalOffsets.size() - 1)];
    THROW_AT(sourceLocationAt(origin, originalSource, mapped),
             "fn syntax rewrite did not converge after " << MaximumExpansionPasses << " local rewrites")
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
    const std::size_t begin = current.cursor;
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
    if (!current.originalOffsets.empty() && current.cursor < current.originalOffsets.size()) {
      current.semanticOwner = Semantic::recordMapped(context, phrase, current.origin, current.originalSource,
                                                     current.originalOffsets[begin], current.originalOffsets[current.cursor],
                                                     current.semanticOwner, false, &current.semanticGroup);
    }
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
      Semantic::OwnerScope semanticScope(context, current.semanticOwner, current.semanticGroup);
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
    if (!active(context)) return reinterpret_cast<const std::uint8_t *>(context.source.path.c_str());
    return reinterpret_cast<const std::uint8_t *>(frame(context).origin.path.c_str());
  }

  std::uint64_t SyntaxExtension::line(context::Context &context) {
    if (!active(context)) return context.source.line;
    ExpansionFrame &current = frame(context);
    return sourceLocationAt(current.origin, current.originalSource, current.originalOffsets[current.cursor]).line;
  }

  std::uint64_t SyntaxExtension::position(context::Context &context) {
    if (!active(context)) return context.source.position;
    ExpansionFrame &current = frame(context);
    return sourceLocationAt(current.origin, current.originalSource, current.originalOffsets[current.cursor]).column;
  }
} // namespace recurloop
