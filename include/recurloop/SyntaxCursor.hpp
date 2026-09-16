#pragma once

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <cstddef>
#include <cstdint>
#include <functional>
#include <initializer_list>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace recurloop {
  enum class SyntaxTokenKind : std::uint8_t {
    End,
    Newline,
    Identifier,
    Integer,
    Real,
    String,
    BitString,
    Symbol,
    Word
  };

  struct SyntaxToken {
    SyntaxTokenKind kind = SyntaxTokenKind::End;
    std::string text;
    // Offset in the original source, used by diagnostics and AST locations.
    std::size_t offset = 0;
    // Offset in the lazily rewritten source consumed by the parser. Generated
    // syntax can map many bytes back to one original source position, so this
    // must remain distinct from the diagnostic offset.
    std::size_t expandedOffset = 0;
  };

  class SyntaxCursor {
  public:
    using Error = std::function<void(const context::Context &, std::size_t, const std::string &)>;

    struct Options {
      bool preserveNewlines = false;
      bool bitStrings = false;
      bool bareWords = false;
      bool rewriteSyntax = false;
    };

    SyntaxCursor(context::Context &context, std::string_view source, std::initializer_list<lexicon::Phrase> grammars,
                 Error error, Options options, SourceLocation origin = {});

    const SyntaxToken &current() const;
    SyntaxToken lookahead(std::size_t distance = 1) const;
    SyntaxToken take();
    bool accept(std::string_view canonical);
    void expect(std::string_view canonical);
    bool skipNewlines();
    std::string expandedSlice(std::size_t begin, std::size_t end) const;

  private:
    struct RewriteState;

    void advance();
    std::string_view input() const;
    std::size_t sourceOffset(std::size_t offset) const;
    bool rewriteCurrent();
    lexicon::Phrase match(std::size_t offset) const;
    bool hasIdentifierBoundary(const std::string &spelling, std::size_t offset) const;
    [[noreturn]] void failSource(std::size_t offset, const std::string &message) const;
    [[noreturn]] void failMapped(std::size_t offset, const std::string &message) const;

    context::Context &context;
    std::string_view source;
    std::shared_ptr<RewriteState> rewrite;
    std::vector<lexicon::Phrase> grammars;
    Error error;
    Options options;
    std::size_t cursor = 0;
    SyntaxToken token;
  };
} // namespace recurloop
