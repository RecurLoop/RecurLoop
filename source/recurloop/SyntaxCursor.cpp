#include <recurloop/SyntaxCursor.hpp>

#include <recurloop/LanguageGrammar.hpp>
#include <utilities/Exception.hpp>

#include <cctype>
#include <cstdlib>

namespace recurloop {
  SyntaxCursor::SyntaxCursor(context::Context &context, std::string_view source,
                             std::initializer_list<lexicon::Phrase> grammars, Error error, Options options)
      : context(context), source(source), grammars(grammars), error(error), options(options) {
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
    if (!accept(canonical)) fail(token.offset, "expected '" + std::string(canonical) + "'");
  }

  bool SyntaxCursor::skipNewlines() {
    bool skipped = false;
    while (token.kind == SyntaxTokenKind::Newline || LanguageGrammar::matches(context, token.text, ";")) {
      skipped = true;
      take();
    }
    return skipped;
  }

  lexicon::Phrase SyntaxCursor::match(std::size_t offset) const {
    lexicon::Phrase result(&context.lexicon);
    std::size_t bytes = 0;
    for (lexicon::Phrase grammar : grammars) {
      for (lexicon::Phrase candidate : {LanguageGrammar::matchLongest(grammar, source.substr(offset)),
                                        LanguageGrammar::matchLongestAlias(context, grammar, source.substr(offset))}) {
        if (!candidate.isNull() && candidate.getKey().size() > bytes) {
          result = candidate;
          bytes = candidate.getKey().size();
        }
      }
    }
    return result;
  }

  bool SyntaxCursor::hasIdentifierBoundary(const std::string &spelling, std::size_t offset) const {
    if (spelling.empty()) return false;
    const auto identifier = [](unsigned char character) { return std::isalnum(character) || character == '_'; };
    const std::size_t end = offset + spelling.size();
    return !identifier(static_cast<unsigned char>(spelling.back())) || end == source.size() ||
           !identifier(static_cast<unsigned char>(source[end]));
  }

  [[noreturn]] void SyntaxCursor::fail(std::size_t offset, const std::string &message) const {
    if (error) error(context, offset, message);
    const SourceLocation location = sourceLocationAt(
        {context.source.path, context.source.line, context.source.position}, source, offset);
    THROW_AT(location, "syntax: " << message)
  }

  void SyntaxCursor::advance() {
    while (cursor < source.size()) {
      const unsigned char character = source[cursor];
      if (character == '\n' && options.preserveNewlines) break;
      if (!std::isspace(character)) break;
      ++cursor;
    }

    token = {SyntaxTokenKind::End, {}, cursor};
    if (cursor == source.size()) return;
    if (source[cursor] == '\n' && options.preserveNewlines) {
      token = {SyntaxTokenKind::Newline, "\n", cursor++};
      return;
    }
    if (source.substr(cursor).starts_with("//")) {
      const std::size_t begin = cursor;
      while (cursor < source.size() && source[cursor] != '\n') ++cursor;
      if (options.preserveNewlines) {
        token = {SyntaxTokenKind::Newline, "\n", begin};
        if (cursor < source.size()) ++cursor;
      } else {
        advance();
      }
      return;
    }
    if (source.substr(cursor).starts_with("/*")) {
      const std::size_t begin = cursor;
      bool newline = false;
      cursor += 2;
      while (cursor + 1 < source.size() && !source.substr(cursor).starts_with("*/")) {
        newline = newline || source[cursor] == '\n';
        ++cursor;
      }
      if (cursor + 1 >= source.size()) fail(begin, "unterminated block comment");
      cursor += 2;
      if (newline && options.preserveNewlines) {
        token = {SyntaxTokenKind::Newline, "\n", begin};
        return;
      }
      advance();
      return;
    }

    const std::size_t begin = cursor;
    const unsigned char first = source[cursor];
    if (options.bitStrings && source.substr(cursor).starts_with("bits\"")) {
      cursor += 5;
      std::string value;
      while (cursor < source.size()) {
        const char character = source[cursor++];
        if (character == '"') {
          token = {SyntaxTokenKind::BitString, std::move(value), begin};
          return;
        }
        if (character == '_') continue;
        if (character != '0' && character != '1') fail(cursor - 1, "bit string literal accepts only '0', '1', and '_'");
        value.push_back(character);
      }
      fail(begin, "unterminated bit string literal");
    }

    if (first == '"') {
      ++cursor;
      std::string value;
      while (cursor < source.size()) {
        char character = source[cursor++];
        if (character == '"') {
          token = {SyntaxTokenKind::String, std::move(value), begin};
          return;
        }
        if (character != '\\') {
          value.push_back(character);
          continue;
        }
        if (cursor == source.size()) fail(begin, "unterminated string escape");
        switch (source[cursor++]) {
        case '0': value.push_back('\0'); break;
        case 'n': value.push_back('\n'); break;
        case 'r': value.push_back('\r'); break;
        case 't': value.push_back('\t'); break;
        case '\\': value.push_back('\\'); break;
        case '"': value.push_back('"'); break;
        default: fail(cursor - 1, "unsupported string escape");
        }
      }
      fail(begin, "unterminated string literal");
    }

    lexicon::Phrase phrase = match(cursor);
    if (!phrase.isNull()) {
      const std::string spelling = phrase.getKey();
      if (hasIdentifierBoundary(spelling, cursor)) {
        cursor += spelling.size();
        token = {SyntaxTokenKind::Symbol, spelling, begin};
        return;
      }
    }

    if (options.bareWords) {
      while (cursor < source.size() && !std::isspace(static_cast<unsigned char>(source[cursor]))) {
        lexicon::Phrase delimiter = match(cursor);
        if (cursor != begin && !delimiter.isNull() && hasIdentifierBoundary(delimiter.getKey(), cursor)) break;
        ++cursor;
      }
      if (cursor == begin) fail(begin, "unexpected character '" + std::string(1, static_cast<char>(first)) + "'");
      token = {SyntaxTokenKind::Word, std::string(source.substr(begin, cursor - begin)), begin};
      return;
    }

    const LanguageGrammar::NumberLiteral number = LanguageGrammar::numberLiteral(source.substr(cursor));
    if (number.bytes != 0) {
      cursor += number.bytes;
      token = {number.real ? SyntaxTokenKind::Real : SyntaxTokenKind::Integer,
               std::string(source.substr(begin, number.bytes)), begin};
      return;
    }

    if (std::isalpha(first) || first == '_') {
      ++cursor;
      while (cursor < source.size()) {
        const unsigned char character = source[cursor];
        if (!std::isalnum(character) && character != '_') break;
        ++cursor;
      }
      token = {SyntaxTokenKind::Identifier, std::string(source.substr(begin, cursor - begin)), begin};
      return;
    }

    fail(begin, "unexpected character '" + std::string(1, static_cast<char>(first)) + "'");
  }
} // namespace recurloop
