#pragma once

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>

#include <cstddef>
#include <cstdint>
#include <functional>
#include <initializer_list>
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
    std::size_t offset = 0;
  };

  class SyntaxCursor {
  public:
    using Error = std::function<void(const context::Context &, std::size_t, const std::string &)>;

    struct Options {
      bool preserveNewlines = false;
      bool bitStrings = false;
      bool bareWords = false;
    };

    SyntaxCursor(context::Context &context, std::string_view source, std::initializer_list<lexicon::Phrase> grammars,
                 Error error, Options options);

    const SyntaxToken &current() const;
    SyntaxToken lookahead(std::size_t distance = 1) const;
    SyntaxToken take();
    bool accept(std::string_view canonical);
    void expect(std::string_view canonical);
    bool skipNewlines();

  private:
    void advance();
    lexicon::Phrase match(std::size_t offset) const;
    bool hasIdentifierBoundary(const std::string &spelling, std::size_t offset) const;
    [[noreturn]] void fail(std::size_t offset, const std::string &message) const;

    context::Context &context;
    std::string_view source;
    std::vector<lexicon::Phrase> grammars;
    Error error;
    Options options;
    std::size_t cursor = 0;
    SyntaxToken token;
  };
} // namespace recurloop
