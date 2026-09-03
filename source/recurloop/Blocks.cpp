#include <recurloop/Blocks.hpp>

#include <context/Context.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/LanguageGrammar.hpp>
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
        context::Source::load(context, false);
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

    std::string syntaxAt(context::Context &context, std::size_t relative, std::string_view canonical) {
      if (!ensure(context, relative)) return {};
      const std::size_t offset = context.source.buffer.offset / Byte::length + relative;
      const std::size_t bytes = context.source.buffer.bits / Byte::length - relative;
      const std::string_view source(context.source.buffer.str.data() + offset, bytes);
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase matched = LanguageGrammar::matchLongest(root, source);
      lexicon::Phrase prototype = LanguageGrammar::find(root, canonical);
      if (matched.isNull() || prototype.isNull() || !LanguageGrammar::inherits(matched, prototype)) return {};
      const std::string key = matched.getKey();
      if (!key.empty() && identifierCharacter(key.back()) && identifierCharacter(peek(context, relative + key.size())))
        return {};
      return key;
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
  } // namespace

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
      if (character == '/' && peek(context, 1) == '/') {
        result.push_back(take(context));
        result.push_back(take(context));
        lineComment = true;
        continue;
      }
      if (character == '/' && peek(context, 1) == '*') {
        result.push_back(take(context));
        result.push_back(take(context));
        blockComment = true;
        continue;
      }
      if (character == '"' || character == '\'') {
        quote = character;
        result.push_back(take(context));
        continue;
      }
      if ((character == '\n' || character == '\r') && closing.empty()) break;

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
      result.push_back(take(context));
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

  SourceBlock Blocks::capture(context::Context &context) {
    SourceBlock result;
    result.path = context.source.path;
    result.headerLine = context.source.line;
    result.headerPosition = context.source.position;

    char quote = '\0';
    bool escaped = false;
    while (true) {
      if (quote == '\0') {
        const std::string opening = syntaxAt(context, 0, "{");
        if (!opening.empty()) {
          context::Source::progress(context, opening.size() * Byte::length);
          break;
        }
      }
      const char character = take(context);
      if (character == '\0') blockFail(context, "expected '{'");
      if (quote != '\0') {
        result.header.push_back(character);
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
        result.header.push_back(character);
      } else {
        result.header.push_back(character);
      }
    }

    result.line = context.source.line;
    result.position = context.source.position;
    std::size_t depth = 1;
    quote = '\0';
    escaped = false;
    bool lineComment = false;
    bool blockComment = false;
    while (depth != 0) {
      if (!lineComment && !blockComment && quote == '\0') {
        const std::string opening = syntaxAt(context, 0, "{");
        if (!opening.empty()) {
          context::Source::progress(context, opening.size() * Byte::length);
          ++depth;
          result.body += opening;
          continue;
        }
        const std::string closing = syntaxAt(context, 0, "}");
        if (!closing.empty()) {
          context::Source::progress(context, closing.size() * Byte::length);
          if (--depth != 0) result.body += closing;
          continue;
        }
      }
      const char character = take(context);
      if (character == '\0') blockFail(context, "unterminated block; expected '}'");

      if (lineComment) {
        result.body.push_back(character);
        if (character == '\n') lineComment = false;
        continue;
      }
      if (blockComment) {
        result.body.push_back(character);
        if (character == '*' && peek(context) == '/') {
          result.body.push_back(take(context));
          blockComment = false;
        }
        continue;
      }
      if (quote != '\0') {
        result.body.push_back(character);
        if (escaped)
          escaped = false;
        else if (character == '\\')
          escaped = true;
        else if (character == quote)
          quote = '\0';
        continue;
      }
      if (character == '/' && peek(context) == '/') {
        result.body.push_back(character);
        result.body.push_back(take(context));
        lineComment = true;
      } else if (character == '/' && peek(context) == '*') {
        result.body.push_back(character);
        result.body.push_back(take(context));
        blockComment = true;
      } else if (character == '"' || character == '\'') {
        quote = character;
        result.body.push_back(character);
      } else {
        result.body.push_back(character);
      }
    }
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
      while (ensure(context, cursor) && std::isspace(static_cast<unsigned char>(peek(context, cursor)))) ++cursor;
      if (peek(context, cursor) == '/' && peek(context, cursor + 1) == '/') {
        cursor += 2;
        while (ensure(context, cursor) && peek(context, cursor) != '\n') ++cursor;
        continue;
      }
      if (peek(context, cursor) == '/' && peek(context, cursor + 1) == '*') {
        cursor += 2;
        while (ensure(context, cursor + 1) && !(peek(context, cursor) == '*' && peek(context, cursor + 1) == '/'))
          ++cursor;
        if (!ensure(context, cursor + 1)) blockFail(context, "unterminated comment");
        cursor += 2;
        continue;
      }
      break;
    }

    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase prototype = LanguageGrammar::find(root, keyword);
    if (prototype.isNull()) return false;

    context::Source::progress(context, cursor * Byte::length);
    std::size_t available = 0;
    while (ensure(context, available) && peek(context, available) != '\n' && peek(context, available) != '\r')
      ++available;
    const std::size_t offset = context.source.buffer.offset / Byte::length;
    lexicon::Phrase matched =
        LanguageGrammar::matchLongest(root, std::string_view(context.source.buffer.str).substr(offset, available));
    if (matched.isNull() || !LanguageGrammar::inherits(matched, prototype)) return false;
    const std::string key = matched.getKey();
    if (!key.empty() && identifierCharacter(key.back()) && identifierCharacter(peek(context, key.size()))) return false;
    context::Source::progress(context, key.size() * Byte::length);
    return true;
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
