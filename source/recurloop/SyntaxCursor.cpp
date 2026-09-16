#include <recurloop/SyntaxCursor.hpp>

#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/SyntaxExtension.hpp>
#include <utilities/Exception.hpp>

#include <cctype>
#include <cstdlib>
#include <limits>
#include <numeric>
#include <set>

namespace recurloop {
  struct SyntaxCursor::RewriteState {
    std::string expanded;
    std::string_view original;
    std::vector<std::size_t> originalOffsets;
    std::set<std::size_t> stableRewriteOffsets;
    SourceLocation origin;
  };

  SyntaxCursor::SyntaxCursor(context::Context &context, std::string_view source,
                             std::initializer_list<lexicon::Phrase> grammars, Error error, Options options,
                             SourceLocation origin)
      : context(context), source(source), grammars(grammars), error(error), options(options) {
    if (options.rewriteSyntax) {
      if (origin.path.empty()) origin = {context.source.path, context.source.line, context.source.position};
      rewrite = std::make_shared<RewriteState>();
      rewrite->expanded.assign(source);
      rewrite->original = source;
      rewrite->origin = std::move(origin);
      rewrite->originalOffsets.resize(source.size() + 1);
      std::iota(rewrite->originalOffsets.begin(), rewrite->originalOffsets.end(), std::size_t{0});
    }
    advance();
  }

  const SyntaxToken &SyntaxCursor::current() const {
    return token;
  }

  SyntaxToken SyntaxCursor::lookahead(std::size_t distance) const {
    SyntaxCursor copy(*this);
    while (distance-- != 0) copy.take();
    return copy.current();
  }

  SyntaxToken SyntaxCursor::take() {
    SyntaxToken result = token;
    advance();
    return result;
  }

  bool SyntaxCursor::accept(std::string_view canonical) {
    if (!LanguageGrammar::matches(context, token.text, canonical)) return false;
    take();
    return true;
  }

  void SyntaxCursor::expect(std::string_view canonical) {
    if (!accept(canonical)) failMapped(token.offset, "expected '" + std::string(canonical) + "'");
  }

  bool SyntaxCursor::skipNewlines() {
    bool skipped = false;
    while (token.kind == SyntaxTokenKind::Newline || LanguageGrammar::matches(context, token.text, ";")) {
      skipped = true;
      take();
    }
    return skipped;
  }

  std::string SyntaxCursor::expandedSlice(std::size_t begin, std::size_t end) const {
    const std::string_view text = input();
    if (begin > end || end > text.size()) THROW(, "syntax expanded slice is out of bounds")
    return std::string(text.substr(begin, end - begin));
  }

  std::string_view SyntaxCursor::input() const {
    return rewrite ? std::string_view(rewrite->expanded) : source;
  }

  std::size_t SyntaxCursor::sourceOffset(std::size_t offset) const {
    if (!rewrite) return offset;
    return rewrite->originalOffsets[std::min(offset, rewrite->originalOffsets.size() - 1)];
  }

  bool SyntaxCursor::rewriteCurrent() {
    if (!rewrite || cursor >= rewrite->expanded.size() || rewrite->stableRewriteOffsets.contains(cursor)) return false;
    const SyntaxRewriteResult result = SyntaxExtension::rewriteAt(
        context, rewrite->expanded, rewrite->originalOffsets, rewrite->original, rewrite->origin, cursor);
    if (result.changed)
      rewrite->stableRewriteOffsets.erase(rewrite->stableRewriteOffsets.lower_bound(cursor),
                                          rewrite->stableRewriteOffsets.end());
    if (result.stable) rewrite->stableRewriteOffsets.insert(cursor);
    return result.changed;
  }

  lexicon::Phrase SyntaxCursor::match(std::size_t offset) const {
    const std::string_view text = input();
    lexicon::Phrase result(&context.lexicon);
    std::size_t bytes = 0;
    for (lexicon::Phrase grammar : grammars) {
      for (lexicon::Phrase candidate : {LanguageGrammar::matchLongest(grammar, text.substr(offset)),
                                        LanguageGrammar::matchLongestAlias(context, grammar, text.substr(offset))}) {
        if (!candidate.isNull() && candidate.getKey().size() > bytes) {
          result = candidate;
          bytes = candidate.getKey().size();
        }
      }
    }
    return result;
  }

  bool SyntaxCursor::hasIdentifierBoundary(const std::string &spelling, std::size_t offset) const {
    const std::string_view text = input();
    if (spelling.empty()) return false;
    const auto identifier = [](unsigned char character) { return std::isalnum(character) || character == '_'; };
    const std::size_t end = offset + spelling.size();
    return !identifier(static_cast<unsigned char>(spelling.back())) || end == text.size() ||
           !identifier(static_cast<unsigned char>(text[end]));
  }

  [[noreturn]] void SyntaxCursor::failSource(std::size_t offset, const std::string &message) const {
    failMapped(sourceOffset(offset), message);
  }

  [[noreturn]] void SyntaxCursor::failMapped(std::size_t offset, const std::string &message) const {
    if (error) error(context, offset, message);
    const std::string_view diagnosticSource = rewrite ? rewrite->original : source;
    const SourceLocation origin = rewrite ? rewrite->origin
                                          : SourceLocation{context.source.path, context.source.line,
                                                           context.source.position};
    const SourceLocation location = sourceLocationAt(origin, diagnosticSource, std::min(offset, diagnosticSource.size()));
    THROW_AT(location, "syntax: " << message)
  }

  void SyntaxCursor::advance() {
    std::size_t rewriteCheckedAt = std::numeric_limits<std::size_t>::max();

    while (true) {
      std::string_view text = input();
      while (cursor < text.size()) {
        const unsigned char character = text[cursor];
        if (character == '\n' && options.preserveNewlines) break;
        if (!std::isspace(character)) break;
        ++cursor;
      }

      text = input();
      token = {SyntaxTokenKind::End, {}, sourceOffset(cursor), cursor};
      if (cursor == text.size()) return;
      if (text[cursor] == '\n' && options.preserveNewlines) {
        token = {SyntaxTokenKind::Newline, "\n", sourceOffset(cursor), cursor};
        ++cursor;
        return;
      }
      if (text.substr(cursor).starts_with("//")) {
        const std::size_t begin = cursor;
        while (cursor < text.size() && text[cursor] != '\n') ++cursor;
        if (options.preserveNewlines) {
          token = {SyntaxTokenKind::Newline, "\n", sourceOffset(begin), begin};
          if (cursor < text.size()) ++cursor;
        } else {
          rewriteCheckedAt = std::numeric_limits<std::size_t>::max();
          continue;
        }
        return;
      }
      if (text.substr(cursor).starts_with("/*")) {
        const std::size_t begin = cursor;
        bool newline = false;
        cursor += 2;
        while (cursor + 1 < text.size() && !text.substr(cursor).starts_with("*/")) {
          newline = newline || text[cursor] == '\n';
          ++cursor;
        }
        if (cursor + 1 >= text.size()) failSource(begin, "unterminated block comment");
        cursor += 2;
        if (newline && options.preserveNewlines) {
          token = {SyntaxTokenKind::Newline, "\n", sourceOffset(begin), begin};
          return;
        }
        rewriteCheckedAt = std::numeric_limits<std::size_t>::max();
        continue;
      }

      if (options.rewriteSyntax && rewriteCheckedAt != cursor) {
        rewriteCheckedAt = cursor;
        rewriteCurrent();
        // A replacement may begin with layout or a comment. Re-run only the
        // layout scan at this offset; the guard prevents re-elaborating a
        // stable same-text rewrite twice.
        const std::string_view rewritten = input();
        if (cursor >= rewritten.size() || std::isspace(static_cast<unsigned char>(rewritten[cursor])) ||
            rewritten.substr(cursor).starts_with("//") || rewritten.substr(cursor).starts_with("/*"))
          continue;
      }
      break;
    }

    const std::string_view text = input();
    const std::size_t begin = cursor;
    const std::size_t tokenOffset = sourceOffset(begin);
    const unsigned char first = text[cursor];
    if (options.bitStrings && text.substr(cursor).starts_with("bits\"")) {
      cursor += 5;
      std::string value;
      while (cursor < text.size()) {
        const char character = text[cursor++];
        if (character == '"') {
          token = {SyntaxTokenKind::BitString, std::move(value), tokenOffset, begin};
          return;
        }
        if (character == '_') continue;
        if (character != '0' && character != '1')
          failSource(cursor - 1, "bit string literal accepts only '0', '1', and '_'");
        value.push_back(character);
      }
      failSource(begin, "unterminated bit string literal");
    }

    if (first == '"') {
      ++cursor;
      std::string value;
      while (cursor < text.size()) {
        char character = text[cursor++];
        if (character == '"') {
          token = {SyntaxTokenKind::String, std::move(value), tokenOffset, begin};
          return;
        }
        if (character != '\\') {
          value.push_back(character);
          continue;
        }
        if (cursor == text.size()) failSource(begin, "unterminated string escape");
        switch (text[cursor++]) {
        case '0': value.push_back('\0'); break;
        case 'n': value.push_back('\n'); break;
        case 'r': value.push_back('\r'); break;
        case 't': value.push_back('\t'); break;
        case '\\': value.push_back('\\'); break;
        case '"': value.push_back('"'); break;
        default: failSource(cursor - 1, "unsupported string escape");
        }
      }
      failSource(begin, "unterminated string literal");
    }

    lexicon::Phrase phrase = match(cursor);
    if (!phrase.isNull()) {
      const std::string spelling = phrase.getKey();
      if (hasIdentifierBoundary(spelling, cursor)) {
        cursor += spelling.size();
        token = {SyntaxTokenKind::Symbol, spelling, tokenOffset, begin};
        return;
      }
    }

    if (options.bareWords) {
      while (cursor < text.size() && !std::isspace(static_cast<unsigned char>(text[cursor]))) {
        lexicon::Phrase delimiter = match(cursor);
        if (cursor != begin && !delimiter.isNull() && hasIdentifierBoundary(delimiter.getKey(), cursor)) break;
        ++cursor;
      }
      if (cursor == begin) failSource(begin, "unexpected character '" + std::string(1, static_cast<char>(first)) + "'");
      token = {SyntaxTokenKind::Word, std::string(text.substr(begin, cursor - begin)), tokenOffset, begin};
      return;
    }

    const LanguageGrammar::NumberLiteral number = LanguageGrammar::numberLiteral(text.substr(cursor));
    if (number.bytes != 0) {
      cursor += number.bytes;
      token = {number.real ? SyntaxTokenKind::Real : SyntaxTokenKind::Integer,
               std::string(text.substr(begin, number.bytes)), tokenOffset, begin};
      return;
    }

    if (std::isalpha(first) || first == '_') {
      ++cursor;
      while (cursor < text.size()) {
        const unsigned char character = text[cursor];
        if (!std::isalnum(character) && character != '_') break;
        ++cursor;
      }
      token = {SyntaxTokenKind::Identifier, std::string(text.substr(begin, cursor - begin)), tokenOffset, begin};
      return;
    }

    failSource(begin, "unexpected character '" + std::string(1, static_cast<char>(first)) + "'");
  }
} // namespace recurloop
