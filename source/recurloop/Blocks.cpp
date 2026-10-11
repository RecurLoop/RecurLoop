#include <recurloop/Blocks.hpp>

#include <context/Context.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/SyntaxPattern.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <array>
#include <cctype>
#include <utility>
#include <vector>

namespace recurloop {
  namespace {
    [[noreturn]] void blockFail(const context::Context &context, const std::string &message) {
      const SourceLocation location{context.source.path, context.source.line, context.source.position};
      THROW_AT(location, message)
    }

    bool ensure(context::Context &context, std::size_t relative) {
      while (relative >= context.source.buffer.bits / Byte::length && context.source.more)
        context::Source::load(context, true);
      return relative < context.source.buffer.bits / Byte::length;
    }

    char peek(context::Context &context, std::size_t relative = 0) {
      if (!ensure(context, relative)) return '\0';
      const std::size_t offset = context.source.buffer.offset / Byte::length + relative;
      return context.source.buffer.str[offset];
    }

    char take(context::Context &context) {
      const char result = peek(context);
      if (result != '\0') context::Source::progress(context, Byte::length);
      return result;
    }

    bool identifierCharacter(char character) {
      return std::isalnum(static_cast<unsigned char>(character)) || character == '_';
    }

    lexicon::Phrase phraseAt(context::Context &context, std::size_t relative, lexicon::Phrase grammar = {}) {
      auto root = context.lexicon.phrase();
      if (grammar.isNull()) grammar = root;
      const auto boundary = [&](lexicon::Phrase candidate) {
        const auto key = candidate.getKey();
        return !key.empty() &&
               (!identifierCharacter(key.back()) || !identifierCharacter(peek(context, relative + key.size())));
      };
      auto matched = LanguageGrammar::peekLongest(context, grammar, relative, boundary);
      if (grammar.getAddress() != root.getAddress()) {
        auto native = LanguageGrammar::peekLongest(context, root, relative, boundary);
        if (!native.isNull() && (matched.isNull() || native.getKey().size() > matched.getKey().size()))
          matched = native;
      }
      return matched;
    }

    std::string syntaxAt(context::Context &context, std::size_t relative, std::string_view canonical,
                         lexicon::Phrase grammar = {}) {
      auto matched = phraseAt(context, relative, grammar);
      auto prototype = LanguageGrammar::find(context.lexicon.phrase(), canonical);
      auto local = LanguageGrammar::findInherited(grammar, canonical);
      return LanguageGrammar::inherits(matched, prototype) || LanguageGrammar::inherits(matched, local)
                 ? matched.getKey()
                 : std::string{};
    }

    std::string trim(std::string text) {
      const auto begin =
          std::find_if_not(text.begin(), text.end(), [](unsigned char character) { return std::isspace(character); });
      const auto end = std::find_if_not(text.rbegin(), text.rend(), [](unsigned char character) {
                         return std::isspace(character);
                       }).base();
      return begin < end ? std::string(begin, end) : std::string{};
    }

    struct SourceLine {
      std::string text;
      std::size_t bytes = 0;
      std::size_t content = 0;
      std::size_t indent = 0;
      bool newline = false;
    };

    SourceLine inspectLine(context::Context &context, std::size_t relative = 0) {
      SourceLine result;
      while (ensure(context, relative) && peek(context, relative) != '\n' && peek(context, relative) != '\r') {
        result.text.push_back(peek(context, relative++));
      }
      result.content = 0;
      while (result.content < result.text.size() &&
             (result.text[result.content] == ' ' || result.text[result.content] == '\t')) {
        result.indent += result.text[result.content] == '\t' ? 4 : 1;
        ++result.content;
      }
      result.bytes = relative;
      if (ensure(context, relative)) {
        result.newline = true;
        ++result.bytes;
        if (peek(context, relative) == '\r' && ensure(context, relative + 1) && peek(context, relative + 1) == '\n')
          ++result.bytes;
      }
      return result;
    }

    void consumeLine(context::Context &context, const SourceLine &line) {
      context::Source::progress(context, line.bytes * Byte::length);
    }

    bool endsWithColon(std::string_view text) {
      while (!text.empty() && std::isspace(static_cast<unsigned char>(text.back()))) text.remove_suffix(1);
      if (text.empty() || text.back() != ':') return false;
      char quote = '\0';
      bool escaped = false;
      for (char character : text) {
        if (quote != '\0') {
          if (escaped)
            escaped = false;
          else if (character == '\\')
            escaped = true;
          else if (character == quote)
            quote = '\0';
        } else if (character == '\'' || character == '"') {
          quote = character;
        }
      }
      return quote == '\0';
    }

    std::string withoutTrailingColon(std::string text) {
      text = trim(std::move(text));
      if (!text.empty() && text.back() == ':') text.pop_back();
      return trim(std::move(text));
    }

    struct ValueScope {
      explicit ValueScope(context::Context &context) : context(context) {
        context.values().pushScope();
      }
      ~ValueScope() {
        context.values().popScope();
      }
      context::Context &context;
    };

    void consumeBody(context::Context &context, std::string *body, lexicon::Phrase grammar = {}) {
      const auto append = [&](char character) {
        if (body != nullptr) body->push_back(character);
      };
      const auto appendText = [&](std::string_view text) {
        if (body != nullptr) body->append(text);
      };

      std::size_t depth = 1;
      char quote = '\0';
      bool escaped = false;
      bool lineComment = false;
      bool blockComment = false;
      while (depth != 0) {
        if (blockComment) {
          const auto closing = syntaxAt(context, 0, "*/", grammar);
          if (!closing.empty()) {
            context::Source::progress(context, closing.size() * Byte::length);
            appendText(closing);
            blockComment = false;
            continue;
          }
        }
        if (!lineComment && !blockComment && quote == '\0') {
          auto phrase = phraseAt(context, 0, grammar);
          if (!phrase.isNull()) {
            const auto bytes = SyntaxPattern::extent(context, phrase);
            if (bytes > phrase.getKey().size()) {
              appendText(context.source.buffer.str.substr(context.source.buffer.offset / Byte::length, bytes));
              context::Source::progress(context, bytes * Byte::length);
              continue;
            }
          }
          const std::string opening = syntaxAt(context, 0, "{", grammar);
          if (!opening.empty()) {
            context::Source::progress(context, opening.size() * Byte::length);
            ++depth;
            appendText(opening);
            continue;
          }
          const std::string closing = syntaxAt(context, 0, "}", grammar);
          if (!closing.empty()) {
            context::Source::progress(context, closing.size() * Byte::length);
            if (--depth != 0) appendText(closing);
            continue;
          }
          const auto line = syntaxAt(context, 0, "//", grammar);
          const auto block = syntaxAt(context, 0, "/*", grammar);
          if (!line.empty() || !block.empty()) {
            const auto &key = line.empty() ? block : line;
            context::Source::progress(context, key.size() * Byte::length);
            appendText(key);
            lineComment = !line.empty();
            blockComment = !block.empty();
            continue;
          }
          auto atom = phraseAt(context, 0, grammar);
          if (!atom.isNull()) {
            const auto key = atom.getKey();
            context::Source::progress(context, key.size() * Byte::length);
            appendText(key);
            continue;
          }
          if (std::isalpha(static_cast<unsigned char>(peek(context))) || peek(context) == '_') {
            do {
              append(take(context));
            } while (identifierCharacter(peek(context)));
            continue;
          }
        }

        const char character = take(context);
        if (character == '\0') blockFail(context, "unterminated block; expected '}'");

        if (lineComment) {
          append(character);
          if (character == '\n') lineComment = false;
          continue;
        }
        if (blockComment) {
          append(character);
          if (character == '*' && peek(context) == '/') {
            append(take(context));
            blockComment = false;
          }
          continue;
        }
        if (quote != '\0') {
          append(character);
          if (escaped)
            escaped = false;
          else if (character == '\\')
            escaped = true;
          else if (character == quote)
            quote = '\0';
          continue;
        }
        if (character == '"' || character == '\'') {
          quote = character;
          append(character);
        } else {
          append(character);
        }
      }
    }
  } // namespace

  std::string Blocks::peekLine(context::Context &context) {
    return inspectLine(context).text;
  }

  bool Blocks::hasOpeningBrace(context::Context &context, bool followingLine) {
    char quote = '\0';
    bool escaped = false;
    bool afterLine = false;
    std::size_t groupDepth = 0;
    for (std::size_t cursor = 0; ensure(context, cursor); ++cursor) {
      const char character = peek(context, cursor);
      if (quote != '\0') {
        if (escaped)
          escaped = false;
        else if (character == '\\')
          escaped = true;
        else if (character == quote)
          quote = '\0';
        continue;
      }
      if (character == '\n' || character == '\r') {
        if (groupDepth != 0) continue;
        if (!followingLine) return false;
        afterLine = true;
        continue;
      }
      if (afterLine) {
        if (std::isspace(static_cast<unsigned char>(character))) continue;
        return !syntaxAt(context, cursor, "{").empty();
      }
      if (character == '"' || character == '\'')
        quote = character;
      else {
        const std::string group = syntaxAt(context, cursor, "(");
        if (!group.empty()) {
          ++groupDepth;
          cursor += group.size() - 1;
          continue;
        }
        const std::string ungroup = syntaxAt(context, cursor, ")");
        if (!ungroup.empty()) {
          if (groupDepth != 0) --groupDepth;
          cursor += ungroup.size() - 1;
          continue;
        }
        if (!syntaxAt(context, cursor, "{").empty()) return true;
      }
    }
    return false;
  }

  bool Blocks::hasIndentedBody(context::Context &context) {
    const SourceLine header = inspectLine(context);
    if (!header.newline || !endsWithColon(header.text)) return false;
    std::size_t relative = header.bytes;
    while (true) {
      const SourceLine line = inspectLine(context, relative);
      if (line.text.empty() && !line.newline) return false;
      if (!line.text.empty() && line.content != line.text.size()) return line.indent > 0;
      if (!line.newline) return false;
      relative += line.bytes;
    }
  }

  std::string Blocks::captureExpression(context::Context &context, SourceLocation *origin) {
    SourceLocation expressionOrigin{context.source.path, context.source.line, context.source.position};
    std::string result;
    std::vector<std::string> closing;
    char quote = '\0';
    bool escaped = false;
    bool lineComment = false;
    bool blockComment = false;

    while (true) {
      const char character = peek(context);
      if (character == '\0') break;
      if (lineComment) {
        if (character == '\n' || character == '\r') {
          lineComment = false;
          if (closing.empty()) break;
        }
        result.push_back(take(context));
        continue;
      }
      if (blockComment) {
        result.push_back(take(context));
        if (character == '*' && peek(context) == '/') {
          result.push_back(take(context));
          blockComment = false;
        }
        continue;
      }
      if (quote != '\0') {
        result.push_back(take(context));
        if (escaped)
          escaped = false;
        else if (character == '\\')
          escaped = true;
        else if (character == quote)
          quote = '\0';
        continue;
      }
      auto phrase = phraseAt(context, 0);
      if (!phrase.isNull()) {
        const auto bytes = SyntaxPattern::extent(context, phrase);
        if (bytes > phrase.getKey().size()) {
          result += context.source.buffer.str.substr(context.source.buffer.offset / Byte::length, bytes);
          context::Source::progress(context, bytes * Byte::length);
          continue;
        }
      }
      const auto line = syntaxAt(context, 0, "//");
      const auto block = syntaxAt(context, 0, "/*");
      if (!line.empty() || !block.empty()) {
        const auto &key = line.empty() ? block : line;
        result += key;
        context::Source::progress(context, key.size() * Byte::length);
        lineComment = !line.empty();
        blockComment = !block.empty();
        continue;
      }
      if (character == '"' || character == '\'') {
        auto atom = phraseAt(context, 0);
        if (!atom.isNull()) {
          const auto key = atom.getKey();
          result += key;
          context::Source::progress(context, key.size() * Byte::length);
          continue;
        }
      }
      if (character == '"' || character == '\'') {
        quote = character;
        result.push_back(take(context));
        continue;
      }
      if ((character == '\n' || character == '\r') && closing.empty()) break;

      // A live streamed block keeps its outer closing delimiter in Source.
      // Historically captureExpression() only saw SourceBlock::body, where
      // that delimiter had already been removed.  Treat an unmatched block
      // close as the end of the current expression without consuming it so
      // executeCurrentBlock() can own and consume the boundary.  Nested `{}`
      // expression groups are still handled by the closing stack below.
      if (closing.empty() && !syntaxAt(context, 0, "}").empty()) break;

      bool structural = false;
      for (const auto &[opening, close] :
           std::array<std::pair<std::string_view, std::string_view>, 3>{{{"(", ")"}, {"[", "]"}, {"{", "}"}}}) {
        const std::string spelling = syntaxAt(context, 0, opening);
        if (spelling.empty()) continue;
        result += spelling;
        context::Source::progress(context, spelling.size() * Byte::length);
        closing.emplace_back(close);
        structural = true;
        break;
      }
      if (structural) continue;
      if (!closing.empty()) {
        const std::string spelling = syntaxAt(context, 0, closing.back());
        if (!spelling.empty()) {
          result += spelling;
          context::Source::progress(context, spelling.size() * Byte::length);
          closing.pop_back();
          continue;
        }
      }
      auto atom = phraseAt(context, 0);
      if (!atom.isNull()) {
        const auto key = atom.getKey();
        result += key;
        context::Source::progress(context, key.size() * Byte::length);
        continue;
      }
      if (std::isalpha(static_cast<unsigned char>(character)) || character == '_') {
        do {
          result.push_back(take(context));
        } while (identifierCharacter(peek(context)));
      } else {
        result.push_back(take(context));
      }
    }
    if (!closing.empty()) blockFail(context, "unterminated expression group; expected '" + closing.back() + "'");
    const auto begin = std::find_if_not(result.begin(), result.end(), [](unsigned char character) {
      return std::isspace(character);
    });
    const auto end = std::find_if_not(result.rbegin(), result.rend(), [](unsigned char character) {
                       return std::isspace(character);
                     }).base();
    const std::size_t leading = static_cast<std::size_t>(begin - result.begin());
    if (origin != nullptr) *origin = sourceLocationAt(std::move(expressionOrigin), result, leading);
    return begin < end ? std::string(begin, end) : std::string{};
  }

  SourceBlock Blocks::begin(context::Context &context) {
    return begin(context, context.lexicon.phrase());
  }

  SourceBlock Blocks::begin(context::Context &context, lexicon::Phrase grammar) {
    SourceBlock result;
    result.path = context.source.path;
    result.headerLine = context.source.line;
    result.headerPosition = context.source.position;

    char quote = '\0';
    bool escaped = false;
    bool lineComment = false;
    bool blockComment = false;
    while (true) {
      if (!lineComment && !blockComment && quote == '\0') {
        const std::string opening = syntaxAt(context, 0, "{", grammar);
        if (!opening.empty()) {
          context::Source::progress(context, opening.size() * Byte::length);
          break;
        }
      }
      if (!lineComment && !blockComment && quote == '\0') {
        const auto line = syntaxAt(context, 0, "//", grammar);
        const auto block = syntaxAt(context, 0, "/*", grammar);
        if (!line.empty() || !block.empty()) {
          const auto &key = line.empty() ? block : line;
          result.header += key;
          context::Source::progress(context, key.size() * Byte::length);
          lineComment = !line.empty();
          blockComment = !block.empty();
          continue;
        }
        auto atom = phraseAt(context, 0, grammar);
        if (!atom.isNull()) {
          const auto key = atom.getKey();
          result.header += key;
          context::Source::progress(context, key.size() * Byte::length);
          continue;
        }
        if (std::isalpha(static_cast<unsigned char>(peek(context))) || peek(context) == '_') {
          do {
            result.header.push_back(take(context));
          } while (identifierCharacter(peek(context)));
          continue;
        }
      }
      if (blockComment) {
        auto closing = syntaxAt(context, 0, "*/", grammar);
        if (closing.empty() && peek(context) == '*' && peek(context, 1) == '/') closing = "*/";
        if (!closing.empty()) {
          result.header += closing;
          context::Source::progress(context, closing.size() * Byte::length);
          blockComment = false;
          continue;
        }
      }
      const char character = take(context);
      if (character == '\0') blockFail(context, "expected '{'");
      result.header.push_back(character);
      if (lineComment) {
        if (character == '\n' || character == '\r') lineComment = false;
        continue;
      }
      if (blockComment) continue;
      if (quote != '\0') {
        if (escaped)
          escaped = false;
        else if (character == '\\')
          escaped = true;
        else if (character == quote)
          quote = '\0';
        continue;
      }
      if (character == '"' || character == '\'') quote = character;
    }

    result.line = context.source.line;
    result.position = context.source.position;
    return result;
  }

  SourceBlock Blocks::capture(context::Context &context) {
    return capture(context, context.lexicon.phrase());
  }

  SourceBlock Blocks::capture(context::Context &context, lexicon::Phrase grammar) {
    SourceBlock result = begin(context, grammar);
    consumeBody(context, &result.body, grammar);
    return result;
  }

  SourceBlock Blocks::captureIndented(context::Context &context) {
    SourceBlock result;
    result.path = context.source.path;
    result.headerLine = context.source.line;
    result.headerPosition = context.source.position;

    const SourceLine header = inspectLine(context);
    if (!header.newline || !endsWithColon(header.text)) blockFail(context, "expected ':' after an indented header");
    result.header = withoutTrailingColon(header.text);
    consumeLine(context, header);
    result.line = context.source.line;
    result.position = context.source.position;

    std::size_t baseIndent = 0;
    std::vector<std::size_t> openBlocks;
    while (true) {
      const SourceLine line = inspectLine(context);
      const bool blank = line.content == line.text.size();
      if (!blank && baseIndent == 0) baseIndent = line.indent;
      if (!blank && line.indent < baseIndent) break;
      if (!line.newline && line.text.empty()) break;

      consumeLine(context, line);
      if (blank) {
        result.body.push_back('\n');
        if (!line.newline) break;
        continue;
      }

      while (!openBlocks.empty() && line.indent <= openBlocks.back()) {
        result.body += "}\n";
        openBlocks.pop_back();
      }

      std::string content = line.text.substr(line.content);
      if (endsWithColon(content)) {
        content = withoutTrailingColon(std::move(content));
        result.body += content + " {\n";
        openBlocks.push_back(line.indent);
      } else {
        result.body += content + "\n";
      }
      if (!line.newline) break;
    }

    while (!openBlocks.empty()) {
      result.body += "}\n";
      openBlocks.pop_back();
    }
    return result;
  }

  bool Blocks::consume(context::Context &context, std::string_view keyword) {
    std::size_t cursor = 0;
    while (true) {
      auto phrase = phraseAt(context, cursor);
      const auto line = syntaxAt(context, cursor, "//");
      const auto block = syntaxAt(context, cursor, "/*");
      if (!line.empty()) {
        cursor += line.size();
        while (ensure(context, cursor) && peek(context, cursor) != '\n' && peek(context, cursor) != '\r') ++cursor;
        continue;
      }
      if (!block.empty()) {
        cursor += block.size();
        while (ensure(context, cursor + 1) && !(peek(context, cursor) == '*' && peek(context, cursor + 1) == '/'))
          ++cursor;
        if (!ensure(context, cursor + 1)) blockFail(context, "unterminated comment");
        cursor += 2;
        continue;
      }
      if (ensure(context, cursor) && std::isspace(static_cast<unsigned char>(peek(context, cursor))) &&
          (phrase.isNull() || phrase.getKey().size() == 1)) {
        ++cursor;
        continue;
      }
      break;
    }
    auto prototype = LanguageGrammar::find(context.lexicon.phrase(), keyword);
    auto matched = phraseAt(context, cursor);
    if (matched.isNull() || !LanguageGrammar::inherits(matched, prototype)) return false;
    context::Source::progress(context, (cursor + matched.getKey().size()) * Byte::length);
    return true;
  }

  void Blocks::skip(context::Context &context) {
    consumeBody(context, nullptr);
  }

  void Blocks::executeCurrent(context::Context &context, bool scoped) {
    executeCurrentBlock(context, scoped);
  }

  void Blocks::execute(context::Context &context, const SourceBlock &block, bool scoped) {
    if (!scoped) {
      executeSource(context, block.body, block.path, block.line, block.position);
      return;
    }
    ValueScope scope(context);
    executeSource(context, block.body, block.path, block.line, block.position);
  }
} // namespace recurloop
