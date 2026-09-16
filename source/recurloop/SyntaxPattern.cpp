#include <recurloop/SyntaxPattern.hpp>

#include <recurloop/Execution.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/SyntaxExtension.hpp>

#include <context/Context.hpp>
#include <context/Source.hpp>
#include <lexicon/Draft.hpp>
#include <lexicon/Lexicon.hpp>
#include <utilities/Byte.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace recurloop {
  namespace {
    constexpr std::uint32_t PayloadMagic = 0x31584e53; // "SNX1"
    constexpr std::uint16_t PayloadVersion = 1;
    constexpr std::size_t MaximumPatternScan = 16 * 1024 * 1024;
    constexpr std::string_view ActionDictionary{"\0syntax-actions", 15};

    enum class Behavior : std::uint16_t { Rewrite = 1, Action = 2, Alias = 3 };
    constexpr std::uint16_t BehaviorMask = 0x00ff;
    constexpr std::uint16_t FallbackFlag = 0x0100;

    struct PayloadHeader {
      std::uint32_t magic = PayloadMagic;
      std::uint16_t version = PayloadVersion;
      std::uint16_t behavior = 0;
      std::uint32_t patternBytes = 0;
      std::uint32_t replacementBytes = 0;
      std::uint32_t targetBytes = 0;
    };

    static_assert(sizeof(PayloadHeader) == 20);

    struct PatternPayload {
      Behavior behavior = Behavior::Rewrite;
      bool fallback = false;
      std::string pattern;
      std::string replacement;
      std::string targetSpelling;
    };

    struct MatchFrame {
      context::Context *context = nullptr;
      std::unordered_map<std::string, std::string> captures;
    };

    thread_local MatchFrame *currentMatch = nullptr;

    bool identifierStart(unsigned char value) {
      return std::isalpha(value) || value == '_';
    }

    bool identifierByte(unsigned char value) {
      return std::isalnum(value) || value == '_';
    }

    std::string trim(std::string value) {
      const auto begin = std::find_if_not(value.begin(), value.end(), [](unsigned char character) {
        return std::isspace(character);
      });
      const auto end = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char character) {
                         return std::isspace(character);
                       }).base();
      return begin < end ? std::string(begin, end) : std::string{};
    }

    lexicon::Phrase exact(lexicon::Phrase dictionary, std::string_view key) {
      if (dictionary.isNull() || !dictionary.containsSubdictionary()) return lexicon::Phrase(dictionary.getLexicon());
      lexicon::Match match = dictionary.matchExact(Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length,
                                                   [](radix::Node *, radix::Match *candidate) {
                                                     return !lexicon::Dictionary(*candidate).getPhrase().isNull();
                                                   });
      return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
    }

    void storePayload(lexicon::Phrase &phrase, const PatternPayload &payload) {
      if (payload.pattern.size() > std::numeric_limits<std::uint32_t>::max() ||
          payload.replacement.size() > std::numeric_limits<std::uint32_t>::max() ||
          payload.targetSpelling.size() > std::numeric_limits<std::uint32_t>::max())
        THROW(, "syntax definition is too large")

      PayloadHeader header;
      header.behavior = static_cast<std::uint16_t>(payload.behavior) | (payload.fallback ? FallbackFlag : 0);
      header.patternBytes = static_cast<std::uint32_t>(payload.pattern.size());
      header.replacementBytes = static_cast<std::uint32_t>(payload.replacement.size());
      header.targetBytes = static_cast<std::uint32_t>(payload.targetSpelling.size());
      const std::size_t bytes = sizeof(header) + payload.pattern.size() + payload.replacement.size() + payload.targetSpelling.size();
      auto *target = static_cast<std::uint8_t *>(phrase.allocate(bytes).toPtr());
      std::memcpy(target, &header, sizeof(header));
      std::size_t offset = sizeof(header);
      if (!payload.pattern.empty()) {
        std::memcpy(target + offset, payload.pattern.data(), payload.pattern.size());
        offset += payload.pattern.size();
      }
      if (!payload.replacement.empty()) {
        std::memcpy(target + offset, payload.replacement.data(), payload.replacement.size());
        offset += payload.replacement.size();
      }
      if (!payload.targetSpelling.empty()) std::memcpy(target + offset, payload.targetSpelling.data(), payload.targetSpelling.size());
      phrase.save();
    }

    bool hasPatternPayload(lexicon::Phrase phrase) {
      if (phrase.isNull() || phrase.payloadSize() < sizeof(PayloadHeader)) return false;
      PayloadHeader header{};
      std::memcpy(&header, phrase.content(0, sizeof(header)).toPtr(), sizeof(header));
      return header.magic == PayloadMagic && header.version == PayloadVersion;
    }

    PatternPayload loadPayload(lexicon::Phrase phrase) {
      if (phrase.payloadSize() < sizeof(PayloadHeader)) THROW(, "syntax phrase has an invalid payload")
      PayloadHeader header{};
      phrase.fetch(0, header);
      if (header.magic != PayloadMagic || header.version != PayloadVersion)
        THROW(, "syntax phrase has an unsupported payload version")
      const std::uint16_t behavior = header.behavior & BehaviorMask;
      if (behavior != static_cast<std::uint16_t>(Behavior::Rewrite) &&
          behavior != static_cast<std::uint16_t>(Behavior::Action) &&
          behavior != static_cast<std::uint16_t>(Behavior::Alias))
        THROW(, "syntax phrase has an invalid behavior")
      if ((header.behavior & ~(BehaviorMask | FallbackFlag)) != 0) THROW(, "syntax phrase has invalid behavior flags")
      const std::size_t total = sizeof(header) + static_cast<std::size_t>(header.patternBytes) +
                                static_cast<std::size_t>(header.replacementBytes) +
                                static_cast<std::size_t>(header.targetBytes);
      if (total != phrase.payloadSize()) THROW(, "syntax phrase payload is truncated")
      const auto *data = reinterpret_cast<const char *>(phrase.content(sizeof(header), total - sizeof(header)).toPtr());
      std::size_t offset = 0;
      PatternPayload result;
      result.behavior = static_cast<Behavior>(behavior);
      result.fallback = (header.behavior & FallbackFlag) != 0;
      result.pattern.assign(data + offset, header.patternBytes);
      offset += header.patternBytes;
      result.replacement.assign(data + offset, header.replacementBytes);
      offset += header.replacementBytes;
      result.targetSpelling.assign(data + offset, header.targetBytes);
      return result;
    }

    lexicon::Phrase patternOwner(lexicon::Phrase phrase) {
      std::unordered_set<Size> visited;
      for (std::size_t depth = 0; !phrase.isNull() && depth < 64; ++depth) {
        if (!visited.insert(phrase.getAddress()).second) break;
        if (hasPatternPayload(phrase)) return phrase;
        if (!phrase.containsPrototype()) break;
        phrase = phrase.getPrototype();
      }
      return lexicon::Phrase(phrase.getLexicon());
    }

    class Reader {
    public:
      virtual ~Reader() = default;
      virtual bool available(std::size_t offset) = 0;
      virtual char at(std::size_t offset) = 0;
      virtual std::string slice(std::size_t begin, std::size_t end) = 0;
    };

    class StringReader final : public Reader {
    public:
      explicit StringReader(std::string_view source) : source(source) {}

      bool available(std::size_t offset) override {
        return offset < source.size();
      }
      char at(std::size_t offset) override {
        return offset < source.size() ? source[offset] : '\0';
      }
      std::string slice(std::size_t begin, std::size_t end) override {
        if (begin > end || end > source.size()) THROW(, "syntax matcher slice is out of bounds")
        return std::string(source.substr(begin, end - begin));
      }

    private:
      std::string_view source;
    };

    class ContextReader final : public Reader {
    public:
      explicit ContextReader(context::Context &context) : context(context) {}

      bool available(std::size_t offset) override {
        while (context.source.buffer.bits / Byte::length <= offset && context.source.more)
          context::Source::load(context, false);
        return context.source.buffer.bits / Byte::length > offset;
      }
      char at(std::size_t offset) override {
        if (!available(offset)) return '\0';
        const std::size_t start = context.source.buffer.offset / Byte::length;
        return context.source.buffer.str[start + offset];
      }
      std::string slice(std::size_t begin, std::size_t end) override {
        if (begin > end) THROW(, "syntax matcher slice is out of bounds")
        if (end != 0 && !available(end - 1)) THROW(, "syntax matcher slice reaches past input")
        const std::size_t start = context.source.buffer.offset / Byte::length;
        return context.source.buffer.str.substr(start + begin, end - begin);
      }

    private:
      context::Context &context;
    };

    bool startsWith(Reader &reader, std::size_t position, std::string_view text) {
      for (std::size_t i = 0; i < text.size(); ++i) {
        if (!reader.available(position + i) || reader.at(position + i) != text[i]) return false;
      }
      return true;
    }

    std::size_t skipLayout(Reader &reader, std::size_t position) {
      while (true) {
        while (reader.available(position) && std::isspace(static_cast<unsigned char>(reader.at(position)))) ++position;
        if (startsWith(reader, position, "//")) {
          position += 2;
          while (reader.available(position) && reader.at(position) != '\n') ++position;
          continue;
        }
        if (startsWith(reader, position, "/*")) {
          position += 2;
          while (reader.available(position) && !startsWith(reader, position, "*/")) ++position;
          if (!startsWith(reader, position, "*/")) THROW(, "syntax matcher: unterminated block comment")
          position += 2;
          continue;
        }
        return position;
      }
    }

    struct Node {
      enum class Kind { Literal, Capture, Optional, Choice } kind = Kind::Literal;
      std::string text;
      std::string captureType;
      std::vector<Node> children;
      std::vector<std::vector<Node>> alternatives;
    };

    class PatternParser {
    public:
      explicit PatternParser(std::string_view source) : source(source) {}

      std::vector<Node> parse() {
        std::vector<Node> result = sequence("", false);
        skip();
        if (cursor != source.size()) fail("unexpected pattern token");
        return result;
      }

    private:
      std::vector<Node> sequence(std::string_view stops, bool choice) {
        std::vector<Node> result;
        while (true) {
          skip();
          if (cursor >= source.size()) return result;
          if (stops.find(source[cursor]) != std::string_view::npos) return result;
          if (source[cursor] == '|') {
            if (choice) return result;
            fail("'|' is only valid inside '(...)'");
          }
          result.push_back(node());
        }
      }

      Node node() {
        skip();
        if (cursor >= source.size()) fail("expected a pattern item");
        if (source[cursor] == '<') return capture();
        if (source[cursor] == '[') {
          ++cursor;
          Node result;
          result.kind = Node::Kind::Optional;
          result.children = sequence("]", false);
          skip();
          if (cursor >= source.size() || source[cursor] != ']') fail("unterminated optional group");
          ++cursor;
          return result;
        }
        if (source[cursor] == '(') {
          ++cursor;
          Node result;
          result.kind = Node::Kind::Choice;
          while (true) {
            result.alternatives.push_back(sequence("|)", true));
            skip();
            if (cursor >= source.size()) fail("unterminated choice group");
            if (source[cursor] == ')') {
              ++cursor;
              break;
            }
            if (source[cursor] != '|') fail("expected '|' or ')' in choice group");
            ++cursor;
          }
          if (result.alternatives.size() < 2) fail("choice group requires at least two alternatives");
          return result;
        }
        Node result;
        result.kind = Node::Kind::Literal;
        result.text = literal();
        if (result.text.empty()) fail("empty literal is not allowed");
        return result;
      }

      Node capture() {
        const std::size_t begin = ++cursor;
        while (cursor < source.size() && source[cursor] != '>') ++cursor;
        if (cursor == source.size()) fail("unterminated capture");
        std::string descriptor = trim(std::string(source.substr(begin, cursor - begin)));
        ++cursor;
        if (descriptor.empty()) fail("empty capture is not allowed");

        Node result;
        result.kind = Node::Kind::Capture;
        const std::size_t colon = descriptor.find(':');
        if (colon == std::string::npos) {
          result.text = descriptor;
          if (descriptor == "condition" || descriptor == "expression" || descriptor == "expr")
            result.captureType = "expr";
          else if (descriptor == "code" || descriptor == "body")
            result.captureType = "raw";
          else
            result.captureType = "raw";
        } else {
          result.text = trim(descriptor.substr(0, colon));
          result.captureType = trim(descriptor.substr(colon + 1));
        }
        if (result.text.empty() || result.captureType.empty()) fail("capture requires a name and matcher type");
        static const std::unordered_set<std::string> supported{
            "expr", "raw", "code", "block", "id", "qualified-id", "token", "string", "number", "rest",
            "ignore", "required", "none", "newline"};
        if (!supported.contains(result.captureType))
          fail("unknown capture matcher '" + result.captureType + "'");
        return result;
      }

      std::string literal() {
        if (source[cursor] == '"' || source[cursor] == '\'') {
          const char quote = source[cursor++];
          std::string result;
          while (cursor < source.size()) {
            const char value = source[cursor++];
            if (value == quote) return result;
            if (value != '\\') {
              result.push_back(value);
              continue;
            }
            if (cursor >= source.size()) fail("unterminated literal escape");
            switch (source[cursor++]) {
            case 'n': result.push_back('\n'); break;
            case 'r': result.push_back('\r'); break;
            case 't': result.push_back('\t'); break;
            case '\\': result.push_back('\\'); break;
            case '\'': result.push_back('\''); break;
            case '"': result.push_back('"'); break;
            default: fail("unsupported literal escape");
            }
          }
          fail("unterminated quoted literal");
        }
        const std::size_t begin = cursor;
        while (cursor < source.size() && !std::isspace(static_cast<unsigned char>(source[cursor])) &&
               source[cursor] != '<' && source[cursor] != '[' && source[cursor] != ']' && source[cursor] != '(' &&
               source[cursor] != ')' && source[cursor] != '|')
          ++cursor;
        return std::string(source.substr(begin, cursor - begin));
      }

      void skip() {
        while (cursor < source.size() && std::isspace(static_cast<unsigned char>(source[cursor]))) ++cursor;
      }

      [[noreturn]] void fail(const std::string &message) const {
        THROW(, "syntax pattern: " << message << " at byte " << cursor)
      }

      std::string_view source;
      std::size_t cursor = 0;
    };

    void collectCaptureNames(const std::vector<Node> &nodes, std::unordered_set<std::string> &names) {
      for (const Node &node : nodes) {
        if (node.kind == Node::Kind::Capture) {
          if (node.captureType != "ignore" && node.captureType != "required" && node.captureType != "none" &&
              node.captureType != "newline")
            names.insert(node.text);
        } else if (node.kind == Node::Kind::Optional) {
          collectCaptureNames(node.children, names);
        } else if (node.kind == Node::Kind::Choice) {
          for (const auto &alternative : node.alternatives) collectCaptureNames(alternative, names);
        }
      }
    }

    bool literalBoundary(Reader &reader, std::size_t position, std::string_view literal) {
      if (literal.empty() || !identifierByte(static_cast<unsigned char>(literal.back()))) return true;
      const std::size_t end = position + literal.size();
      return !reader.available(end) || !identifierByte(static_cast<unsigned char>(reader.at(end)));
    }

    std::optional<std::size_t> blockEnd(Reader &reader, std::size_t position) {
      if (!reader.available(position) || reader.at(position) != '{') return std::nullopt;
      std::size_t cursor = position + 1;
      std::size_t depth = 1;
      char quote = '\0';
      bool escaped = false;
      bool lineComment = false;
      bool blockComment = false;
      while (cursor - position <= MaximumPatternScan && reader.available(cursor)) {
        const char ch = reader.at(cursor);
        if (lineComment) {
          ++cursor;
          if (ch == '\n') lineComment = false;
          continue;
        }
        if (blockComment) {
          if (ch == '*' && reader.available(cursor + 1) && reader.at(cursor + 1) == '/') {
            cursor += 2;
            blockComment = false;
          } else {
            ++cursor;
          }
          continue;
        }
        if (quote != '\0') {
          ++cursor;
          if (escaped)
            escaped = false;
          else if (ch == '\\')
            escaped = true;
          else if (ch == quote)
            quote = '\0';
          continue;
        }
        if (ch == '/' && reader.available(cursor + 1) && reader.at(cursor + 1) == '/') {
          cursor += 2;
          lineComment = true;
          continue;
        }
        if (ch == '/' && reader.available(cursor + 1) && reader.at(cursor + 1) == '*') {
          cursor += 2;
          blockComment = true;
          continue;
        }
        if (ch == '"' || ch == '\'') {
          quote = ch;
          ++cursor;
          continue;
        }
        if (ch == '{') {
          ++depth;
          ++cursor;
          continue;
        }
        if (ch == '}') {
          ++cursor;
          if (--depth == 0) return cursor;
          continue;
        }
        ++cursor;
      }
      return std::nullopt;
    }

    std::string captureSlice(Reader &reader, std::size_t begin, std::size_t end, bool preserve = false) {
      std::string value = reader.slice(begin, end);
      return preserve ? value : trim(std::move(value));
    }

    using Captures = std::unordered_map<std::string, std::string>;

    std::optional<std::size_t> matchSequence(const std::vector<Node> &nodes, std::size_t index, Reader &reader,
                                             std::size_t position, Captures &captures);

    std::optional<std::size_t> matchVariableCapture(const std::vector<Node> &nodes, std::size_t index, const Node &node,
                                                    Reader &reader, std::size_t start, Captures &captures) {
      const bool last = index + 1 == nodes.size();
      if (last) {
        std::size_t end = start;
        std::size_t parens = 0, brackets = 0, braces = 0;
        char quote = '\0';
        bool escaped = false, lineComment = false, blockComment = false;
        while (end - start <= MaximumPatternScan && reader.available(end)) {
          const char ch = reader.at(end);
          if (lineComment) {
            if (ch == '\n') break;
            ++end;
            continue;
          }
          if (blockComment) {
            if (ch == '*' && reader.available(end + 1) && reader.at(end + 1) == '/') {
              end += 2;
              blockComment = false;
            } else {
              ++end;
            }
            continue;
          }
          if (quote != '\0') {
            ++end;
            if (escaped)
              escaped = false;
            else if (ch == '\\')
              escaped = true;
            else if (ch == quote)
              quote = '\0';
            continue;
          }
          if (ch == '/' && reader.available(end + 1) && reader.at(end + 1) == '/') {
            lineComment = true;
            end += 2;
            continue;
          }
          if (ch == '/' && reader.available(end + 1) && reader.at(end + 1) == '*') {
            blockComment = true;
            end += 2;
            continue;
          }
          if (ch == '"' || ch == '\'') {
            quote = ch;
            ++end;
            continue;
          }
          if (ch == '(') ++parens;
          else if (ch == ')' && parens != 0) --parens;
          else if (ch == '[') ++brackets;
          else if (ch == ']' && brackets != 0) --brackets;
          else if (ch == '{') ++braces;
          else if (ch == '}' && braces != 0) --braces;
          if ((ch == '\n' || ch == '\r') && parens == 0 && brackets == 0 && braces == 0) break;
          ++end;
        }
        std::string value = captureSlice(reader, start, end, node.captureType == "code");
        if (node.captureType == "expr" && value.empty()) return std::nullopt;
        captures[node.text] = std::move(value);
        return end;
      }

      std::size_t cursor = start;
      std::size_t parens = 0, brackets = 0, braces = 0;
      char quote = '\0';
      bool escaped = false, lineComment = false, blockComment = false;
      while (cursor - start <= MaximumPatternScan) {
        const bool top = quote == '\0' && !lineComment && !blockComment && parens == 0 && brackets == 0 && braces == 0;
        if (top) {
          Captures trial = captures;
          std::string value = captureSlice(reader, start, cursor, node.captureType == "code");
          if (!(node.captureType == "expr" && value.empty())) {
            trial[node.text] = std::move(value);
            if (const auto finish = matchSequence(nodes, index + 1, reader, cursor, trial)) {
              captures = std::move(trial);
              return finish;
            }
          }
        }
        if (!reader.available(cursor)) break;
        const char ch = reader.at(cursor);
        if (lineComment) {
          ++cursor;
          if (ch == '\n') lineComment = false;
          continue;
        }
        if (blockComment) {
          if (ch == '*' && reader.available(cursor + 1) && reader.at(cursor + 1) == '/') {
            cursor += 2;
            blockComment = false;
          } else {
            ++cursor;
          }
          continue;
        }
        if (quote != '\0') {
          ++cursor;
          if (escaped)
            escaped = false;
          else if (ch == '\\')
            escaped = true;
          else if (ch == quote)
            quote = '\0';
          continue;
        }
        if (ch == '/' && reader.available(cursor + 1) && reader.at(cursor + 1) == '/') {
          lineComment = true;
          cursor += 2;
          continue;
        }
        if (ch == '/' && reader.available(cursor + 1) && reader.at(cursor + 1) == '*') {
          blockComment = true;
          cursor += 2;
          continue;
        }
        if (ch == '"' || ch == '\'') {
          quote = ch;
          ++cursor;
          continue;
        }
        if (ch == '(') ++parens;
        else if (ch == ')') {
          if (parens == 0) break;
          --parens;
        } else if (ch == '[') ++brackets;
        else if (ch == ']') {
          if (brackets == 0) break;
          --brackets;
        } else if (ch == '{') {
          ++braces;
        } else if (ch == '}') {
          if (braces == 0) break;
          --braces;
        }
        ++cursor;
      }
      return std::nullopt;
    }

    std::optional<std::size_t> matchSequence(const std::vector<Node> &nodes, std::size_t index, Reader &reader,
                                             std::size_t position, Captures &captures) {
      if (index == nodes.size()) return position;
      const Node &node = nodes[index];

      if (node.kind == Node::Kind::Optional) {
        Captures trial = captures;
        if (const auto inside = matchSequence(node.children, 0, reader, position, trial)) {
          if (const auto finish = matchSequence(nodes, index + 1, reader, *inside, trial)) {
            captures = std::move(trial);
            return finish;
          }
        }
        return matchSequence(nodes, index + 1, reader, position, captures);
      }
      if (node.kind == Node::Kind::Choice) {
        for (const auto &alternative : node.alternatives) {
          Captures trial = captures;
          if (const auto inside = matchSequence(alternative, 0, reader, position, trial)) {
            if (const auto finish = matchSequence(nodes, index + 1, reader, *inside, trial)) {
              captures = std::move(trial);
              return finish;
            }
          }
        }
        return std::nullopt;
      }

      if (node.kind == Node::Kind::Capture && node.captureType == "none") {
        if (reader.available(position) && std::isspace(static_cast<unsigned char>(reader.at(position)))) return std::nullopt;
        return matchSequence(nodes, index + 1, reader, position, captures);
      }
      if (node.kind == Node::Kind::Capture && node.captureType == "required") {
        std::size_t cursor = position;
        bool found = false;
        while (reader.available(cursor) && std::isspace(static_cast<unsigned char>(reader.at(cursor)))) {
          found = true;
          ++cursor;
        }
        if (!found) return std::nullopt;
        return matchSequence(nodes, index + 1, reader, cursor, captures);
      }
      if (node.kind == Node::Kind::Capture && node.captureType == "newline") {
        std::size_t cursor = position;
        while (reader.available(cursor) && (reader.at(cursor) == ' ' || reader.at(cursor) == '\t')) ++cursor;
        if (!reader.available(cursor) || (reader.at(cursor) != '\n' && reader.at(cursor) != '\r')) return std::nullopt;
        if (reader.at(cursor) == '\r' && reader.available(cursor + 1) && reader.at(cursor + 1) == '\n') cursor += 2;
        else ++cursor;
        return matchSequence(nodes, index + 1, reader, cursor, captures);
      }

      position = skipLayout(reader, position);

      if (node.kind == Node::Kind::Literal) {
        if (!startsWith(reader, position, node.text) || !literalBoundary(reader, position, node.text)) return std::nullopt;
        return matchSequence(nodes, index + 1, reader, position + node.text.size(), captures);
      }

      if (node.captureType == "ignore") return matchSequence(nodes, index + 1, reader, position, captures);

      if (node.captureType == "block") {
        const auto end = blockEnd(reader, position);
        if (!end) return std::nullopt;
        captures[node.text] = reader.slice(position, *end);
        return matchSequence(nodes, index + 1, reader, *end, captures);
      }

      if (node.captureType == "id" || node.captureType == "qualified-id") {
        if (!reader.available(position) || !identifierStart(static_cast<unsigned char>(reader.at(position)))) return std::nullopt;
        std::size_t cursor = position + 1;
        while (reader.available(cursor)) {
          const unsigned char ch = static_cast<unsigned char>(reader.at(cursor));
          if (identifierByte(ch) || (node.captureType == "qualified-id" && (ch == ':' || ch == '.')))
            ++cursor;
          else
            break;
        }
        captures[node.text] = reader.slice(position, cursor);
        return matchSequence(nodes, index + 1, reader, cursor, captures);
      }

      if (node.captureType == "number") {
        std::size_t cursor = position;
        if (reader.available(cursor) && (reader.at(cursor) == '+' || reader.at(cursor) == '-')) ++cursor;
        const std::size_t digits = cursor;
        while (reader.available(cursor) && std::isdigit(static_cast<unsigned char>(reader.at(cursor)))) ++cursor;
        if (cursor == digits) return std::nullopt;
        captures[node.text] = reader.slice(position, cursor);
        return matchSequence(nodes, index + 1, reader, cursor, captures);
      }

      if (node.captureType == "string") {
        if (!reader.available(position) || (reader.at(position) != '"' && reader.at(position) != '\'')) return std::nullopt;
        const char quote = reader.at(position);
        std::size_t cursor = position + 1;
        bool escaped = false;
        while (reader.available(cursor)) {
          const char ch = reader.at(cursor++);
          if (escaped) escaped = false;
          else if (ch == '\\') escaped = true;
          else if (ch == quote) {
            captures[node.text] = reader.slice(position, cursor);
            return matchSequence(nodes, index + 1, reader, cursor, captures);
          }
        }
        return std::nullopt;
      }

      if (node.captureType == "token") {
        if (!reader.available(position)) return std::nullopt;
        if (reader.at(position) == '"' || reader.at(position) == '\'') {
          Node stringNode = node;
          stringNode.captureType = "string";
          std::vector<Node> rewritten = nodes;
          rewritten[index] = std::move(stringNode);
          return matchSequence(rewritten, index, reader, position, captures);
        }
        std::size_t cursor = position;
        if (identifierStart(static_cast<unsigned char>(reader.at(cursor))) ||
            std::isdigit(static_cast<unsigned char>(reader.at(cursor)))) {
          ++cursor;
          while (reader.available(cursor) && identifierByte(static_cast<unsigned char>(reader.at(cursor)))) ++cursor;
        } else {
          ++cursor;
        }
        captures[node.text] = reader.slice(position, cursor);
        return matchSequence(nodes, index + 1, reader, cursor, captures);
      }

      if (node.captureType == "rest") {
        std::size_t cursor = position;
        while (reader.available(cursor) && reader.at(cursor) != '\n' && reader.at(cursor) != '\r') ++cursor;
        captures[node.text] = captureSlice(reader, position, cursor);
        return matchSequence(nodes, index + 1, reader, cursor, captures);
      }

      return matchVariableCapture(nodes, index, node, reader, position, captures);
    }

    struct MatchResult {
      std::size_t bytes = 0;
      Captures captures;
    };

    std::optional<MatchResult> matchPattern(const std::vector<Node> &pattern, Reader &reader) {
      Captures captures;
      if (const auto end = matchSequence(pattern, 0, reader, 0, captures)) return MatchResult{*end, std::move(captures)};
      return std::nullopt;
    }

    std::string blockBody(std::string value) {
      value = trim(std::move(value));
      if (value.size() >= 2 && value.front() == '{' && value.back() == '}') return value.substr(1, value.size() - 2);
      return value;
    }

    std::string renderTemplate(std::string_view source, const Captures &captures) {
      std::string result;
      for (std::size_t cursor = 0; cursor < source.size();) {
        if (source[cursor] != '$' || cursor + 1 >= source.size()) {
          result.push_back(source[cursor++]);
          continue;
        }
        if (source[cursor + 1] == '$') {
          result.push_back('$');
          cursor += 2;
          continue;
        }
        if (source[cursor + 1] != '{') {
          result.push_back(source[cursor++]);
          continue;
        }
        const std::size_t close = source.find('}', cursor + 2);
        if (close == std::string_view::npos) THROW(, "syntax rewrite template has an unterminated placeholder")
        std::string selector(source.substr(cursor + 2, close - cursor - 2));
        std::string modifier;
        const std::size_t dot = selector.find('.');
        if (dot != std::string::npos) {
          modifier = selector.substr(dot + 1);
          selector.resize(dot);
        }
        std::string value;
        const auto found = captures.find(selector);
        if (found != captures.end()) value = found->second;
        if (modifier == "body") value = blockBody(std::move(value));
        else if (modifier == "trim" || modifier.empty()) value = modifier == "trim" ? trim(std::move(value)) : value;
        else THROW(, "syntax rewrite template uses unknown placeholder modifier '" << modifier << "'")
        result += value;
        cursor = close + 1;
      }
      return result;
    }

    void validateTemplate(std::string_view source, const std::unordered_set<std::string> &captures) {
      for (std::size_t cursor = 0; cursor < source.size();) {
        const std::size_t open = source.find("${", cursor);
        if (open == std::string_view::npos) return;
        const std::size_t close = source.find('}', open + 2);
        if (close == std::string_view::npos) THROW(, "syntax rewrite template has an unterminated placeholder")
        std::string selector(source.substr(open + 2, close - open - 2));
        const std::size_t dot = selector.find('.');
        const std::string name = selector.substr(0, dot);
        if (!captures.contains(name)) THROW(, "syntax rewrite template references unknown capture '" << name << "'")
        if (dot != std::string::npos) {
          const std::string modifier = selector.substr(dot + 1);
          if (modifier != "body" && modifier != "trim")
            THROW(, "syntax rewrite template uses unknown placeholder modifier '" << modifier << "'")
        }
        cursor = close + 1;
      }
    }

    class DefinitionParser {
    public:
      DefinitionParser(context::Context &context, Reader &reader)
          : reader(reader), origin{context.source.path, context.source.line, context.source.position} {}

      struct Result {
        bool replace = false;
        bool extend = false;
        std::string name;
        PatternPayload payload;
        std::string actionSignature;
        std::string actionBody;
        SourceLocation signatureOrigin;
        SourceLocation bodyOrigin;
        std::string aliasTarget;
        std::size_t consumed = 0;
      };

      Result parse() {
        Result result;
        skipLayoutLocal();
        if (acceptWord("replace")) {
          result.replace = true;
          skipLayoutLocal();
        } else if (acceptWord("extend")) {
          result.extend = true;
          result.payload.fallback = true;
          skipLayoutLocal();
        }
        result.name = syntaxName();
        if (result.name.empty()) fail("expected the syntax root spelling");
        const std::size_t patternStart = cursor;
        const Terminator terminator = findTerminator();
        result.payload.pattern = trim(reader.slice(patternStart, terminator.position));
        cursor = terminator.position;
        if (result.payload.pattern.empty()) fail("syntax pattern cannot be empty");

        if (terminator.kind == TerminatorKind::Rewrite) {
          cursor += 2;
          result.payload.behavior = Behavior::Rewrite;
          result.payload.replacement = rewriteTemplate();
          if (result.payload.replacement.empty()) fail("syntax rewrite template cannot be empty");
        } else if (terminator.kind == TerminatorKind::Alias) {
          cursor += 2;
          skipLayoutLocal();
          result.aliasTarget = phraseReference();
          result.payload.behavior = Behavior::Alias;
        } else {
          cursor += 6;
          skipLayoutLocal();
          if (!acceptWord("fn")) fail("syntax action expects 'fn'");
          parseAction(result);
          result.payload.behavior = Behavior::Action;
        }
        while (reader.available(cursor) && (reader.at(cursor) == ' ' || reader.at(cursor) == '\t')) ++cursor;
        if (reader.available(cursor) && (reader.at(cursor) == '\r' || reader.at(cursor) == '\n')) {
          if (reader.at(cursor) == '\r' && reader.available(cursor + 1) && reader.at(cursor + 1) == '\n') cursor += 2;
          else ++cursor;
        }
        result.consumed = cursor;
        return result;
      }

    private:
      enum class TerminatorKind { Rewrite, Action, Alias };
      struct Terminator {
        TerminatorKind kind;
        std::size_t position;
      };

      Terminator findTerminator() {
        std::size_t position = cursor;
        char quote = '\0';
        bool escaped = false;
        bool angle = false;
        while (position - cursor <= MaximumPatternScan && reader.available(position)) {
          const char ch = reader.at(position);
          if (quote != '\0') {
            if (escaped)
              escaped = false;
            else if (ch == '\\')
              escaped = true;
            else if (ch == quote)
              quote = '\0';
            ++position;
            continue;
          }
          if (ch == '"' || ch == '\'') {
            quote = ch;
            ++position;
            continue;
          }
          if (ch == '<') {
            angle = true;
            ++position;
            continue;
          }
          if (angle) {
            if (ch == '>') angle = false;
            ++position;
            continue;
          }
          if (ch == '=' && reader.available(position + 1) && reader.at(position + 1) == '>')
            return {TerminatorKind::Rewrite, position};
          if (startsWith(reader, position, "action") &&
              (position == cursor || !identifierByte(static_cast<unsigned char>(reader.at(position - 1)))) &&
              (!reader.available(position + 6) || !identifierByte(static_cast<unsigned char>(reader.at(position + 6)))))
            return {TerminatorKind::Action, position};
          if (startsWith(reader, position, "as") &&
              (position == cursor || !identifierByte(static_cast<unsigned char>(reader.at(position - 1)))) &&
              (!reader.available(position + 2) || !identifierByte(static_cast<unsigned char>(reader.at(position + 2)))))
            return {TerminatorKind::Alias, position};
          ++position;
        }
        fail("expected '=>', 'as <phrase>', or 'action' after the syntax pattern");
      }

      std::string rewriteTemplate() {
        while (reader.available(cursor) && (reader.at(cursor) == ' ' || reader.at(cursor) == '\t')) ++cursor;
        if (startsWith(reader, cursor, "\"\"\"")) {
          cursor += 3;
          const std::size_t begin = cursor;
          while (cursor - begin <= MaximumPatternScan && !startsWith(reader, cursor, "\"\"\"")) {
            if (!reader.available(cursor)) fail("unterminated triple-quoted rewrite template");
            ++cursor;
          }
          std::string result = reader.slice(begin, cursor);
          cursor += 3;
          return trim(std::move(result));
        }

        const std::size_t begin = cursor;
        std::size_t braces = 0, parens = 0, brackets = 0;
        char quote = '\0';
        bool escaped = false, lineComment = false, blockComment = false;
        while (cursor - begin <= MaximumPatternScan && reader.available(cursor)) {
          const char ch = reader.at(cursor);
          if (lineComment) {
            if (ch == '\n' || ch == '\r') break;
            ++cursor;
            continue;
          }
          if (blockComment) {
            if (ch == '*' && reader.available(cursor + 1) && reader.at(cursor + 1) == '/') {
              cursor += 2;
              blockComment = false;
            } else {
              ++cursor;
            }
            continue;
          }
          if (quote != '\0') {
            ++cursor;
            if (escaped)
              escaped = false;
            else if (ch == '\\')
              escaped = true;
            else if (ch == quote)
              quote = '\0';
            continue;
          }
          if (ch == '/' && reader.available(cursor + 1) && reader.at(cursor + 1) == '/') {
            lineComment = true;
            cursor += 2;
            continue;
          }
          if (ch == '/' && reader.available(cursor + 1) && reader.at(cursor + 1) == '*') {
            blockComment = true;
            cursor += 2;
            continue;
          }
          if (ch == '"' || ch == '\'') {
            quote = ch;
            ++cursor;
            continue;
          }
          if (ch == '{') ++braces;
          else if (ch == '}' && braces != 0) --braces;
          else if (ch == '(') ++parens;
          else if (ch == ')' && parens != 0) --parens;
          else if (ch == '[') ++brackets;
          else if (ch == ']' && brackets != 0) --brackets;
          if ((ch == '\n' || ch == '\r') && braces == 0 && parens == 0 && brackets == 0) break;
          ++cursor;
        }
        return trim(reader.slice(begin, cursor));
      }

      void parseAction(Result &result) {
        skipLayoutLocal();
        const std::size_t signatureBegin = cursor;
        char quote = '\0';
        bool escaped = false;
        std::size_t parens = 0;
        while (reader.available(cursor)) {
          const char ch = reader.at(cursor);
          if (quote != '\0') {
            ++cursor;
            if (escaped)
              escaped = false;
            else if (ch == '\\')
              escaped = true;
            else if (ch == quote)
              quote = '\0';
            continue;
          }
          if (ch == '"' || ch == '\'') {
            quote = ch;
            ++cursor;
            continue;
          }
          if (ch == '(') ++parens;
          else if (ch == ')' && parens != 0) --parens;
          else if (ch == '{' && parens == 0) break;
          ++cursor;
        }
        if (!reader.available(cursor) || reader.at(cursor) != '{') fail("syntax action expects a function body");
        result.actionSignature = trim(reader.slice(signatureBegin, cursor));
        result.signatureOrigin = location(signatureBegin);
        ++cursor;
        const std::size_t bodyBegin = cursor;
        std::size_t depth = 1;
        quote = '\0';
        escaped = false;
        bool lineComment = false, blockComment = false;
        while (reader.available(cursor)) {
          const char ch = reader.at(cursor);
          if (lineComment) {
            ++cursor;
            if (ch == '\n') lineComment = false;
            continue;
          }
          if (blockComment) {
            if (ch == '*' && reader.available(cursor + 1) && reader.at(cursor + 1) == '/') {
              cursor += 2;
              blockComment = false;
            } else {
              ++cursor;
            }
            continue;
          }
          if (quote != '\0') {
            ++cursor;
            if (escaped)
              escaped = false;
            else if (ch == '\\')
              escaped = true;
            else if (ch == quote)
              quote = '\0';
            continue;
          }
          if (ch == '/' && reader.available(cursor + 1) && reader.at(cursor + 1) == '/') {
            cursor += 2;
            lineComment = true;
            continue;
          }
          if (ch == '/' && reader.available(cursor + 1) && reader.at(cursor + 1) == '*') {
            cursor += 2;
            blockComment = true;
            continue;
          }
          if (ch == '"' || ch == '\'') {
            quote = ch;
            ++cursor;
            continue;
          }
          if (ch == '{') {
            ++depth;
            ++cursor;
            continue;
          }
          if (ch == '}') {
            if (--depth == 0) {
              result.actionBody = reader.slice(bodyBegin, cursor);
              result.bodyOrigin = location(bodyBegin);
              ++cursor;
              return;
            }
          }
          ++cursor;
        }
        fail("unterminated syntax action body");
      }

      SourceLocation location(std::size_t offset) {
        return sourceLocationAt(origin, reader.slice(0, offset), offset);
      }

      std::string phraseReference() {
        if (!reader.available(cursor) || reader.at(cursor) != '<') fail("syntax alias expects a phrase reference");
        ++cursor;
        const std::size_t begin = cursor;
        char quote = '\0';
        bool escaped = false;
        while (reader.available(cursor)) {
          const char ch = reader.at(cursor);
          if (quote != '\0') {
            ++cursor;
            if (escaped)
              escaped = false;
            else if (ch == '\\')
              escaped = true;
            else if (ch == quote)
              quote = '\0';
            continue;
          }
          if (ch == '"' || ch == '\'') {
            quote = ch;
            ++cursor;
            continue;
          }
          if (ch == '>') {
            std::string result = trim(reader.slice(begin, cursor));
            ++cursor;
            if (result.empty()) fail("syntax alias phrase reference cannot be empty");
            return result;
          }
          ++cursor;
        }
        fail("unterminated syntax alias phrase reference");
      }

      std::string syntaxName() {
        if (!reader.available(cursor)) return {};
        if (reader.at(cursor) == '"' || reader.at(cursor) == '\'') {
          const char quote = reader.at(cursor++);
          std::string result;
          bool escaped = false;
          while (reader.available(cursor)) {
            const char ch = reader.at(cursor++);
            if (escaped) {
              result.push_back(ch);
              escaped = false;
            } else if (ch == '\\') {
              escaped = true;
            } else if (ch == quote) {
              return result;
            } else {
              result.push_back(ch);
            }
          }
          fail("unterminated quoted syntax name");
        }
        const std::size_t begin = cursor;
        while (reader.available(cursor) && !std::isspace(static_cast<unsigned char>(reader.at(cursor)))) {
          const char ch = reader.at(cursor);
          if (ch == '<' || ch == '[' || ch == '(' || (ch == '=' && reader.available(cursor + 1) && reader.at(cursor + 1) == '>'))
            break;
          ++cursor;
        }
        return reader.slice(begin, cursor);
      }

      bool acceptWord(std::string_view word) {
        if (!startsWith(reader, cursor, word)) return false;
        if (cursor != 0 && identifierByte(static_cast<unsigned char>(reader.at(cursor - 1)))) return false;
        if (reader.available(cursor + word.size()) &&
            identifierByte(static_cast<unsigned char>(reader.at(cursor + word.size()))))
          return false;
        cursor += word.size();
        return true;
      }

      void skipLayoutLocal() {
        cursor = skipLayout(reader, cursor);
      }

      [[noreturn]] void fail(const std::string &message) {
        THROW_AT(location(cursor), "syntax definition: " << message)
      }

      Reader &reader;
      SourceLocation origin;
      std::size_t cursor = 0;
    };

    std::vector<std::string> referencePath(std::string_view source) {
      std::vector<std::string> result;
      std::string current;
      char quote = '\0';
      bool escaped = false;
      for (char ch : source) {
        if (quote != '\0') {
          if (escaped) {
            current.push_back(ch);
            escaped = false;
          } else if (ch == '\\') {
            escaped = true;
          } else if (ch == quote) {
            quote = '\0';
          } else {
            current.push_back(ch);
          }
          continue;
        }
        if (ch == '"' || ch == '\'') {
          quote = ch;
          continue;
        }
        if (ch == ':') {
          if (current.empty()) THROW(, "syntax alias contains an empty phrase path component")
          result.push_back(current);
          current.clear();
        } else {
          current.push_back(ch);
        }
      }
      if (quote != '\0') THROW(, "syntax alias contains an unterminated quoted path component")
      if (current.empty()) THROW(, "syntax alias contains an empty phrase path component")
      result.push_back(current);
      return result;
    }

    lexicon::Phrase resolveReference(lexicon::Phrase root, std::string_view source) {
      lexicon::Phrase current = root;
      for (const std::string &component : referencePath(source)) {
        current = exact(current, component);
        if (current.isNull()) return current;
      }
      return current;
    }

    lexicon::Phrase actionDictionary(context::Context &context) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase dictionary = exact(root, ActionDictionary);
      if (!dictionary.isNull()) return dictionary;
      return root.append(Byte(const_cast<char *>(ActionDictionary.data())), 0, ActionDictionary.size() * Byte::length)
          .make()
          .enableSubdictionary()
          .setType(lexicon::phrase::type::getData(root))
          .save();
    }

    lexicon::Phrase makeActionCarrier(context::Context &context, lexicon::Phrase implementation, std::string_view name) {
      lexicon::Phrase dictionary = actionDictionary(context);
      std::string key(name);
      if (key.empty()) key = "action";
      std::size_t suffix = 0;
      std::string candidate = key;
      while (!exact(dictionary, candidate).isNull()) candidate = key + "#" + std::to_string(++suffix);
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Draft draft = dictionary.append(candidate).make().setType(lexicon::phrase::type::getCallable(root));
      Functions::bindAction(draft, implementation);
      lexicon::Phrase carrier = draft.save();
      carrier.setSerializable(true).save();
      return carrier;
    }

    void runPattern(context::Context &context, lexicon::Phrase invoked, const PatternPayload &payload, Reader &reader,
                    bool expansion) {
      const std::vector<Node> pattern = PatternParser(payload.pattern).parse();
      const auto matched = matchPattern(pattern, reader);
      if (!matched) {
        if (!payload.fallback || !invoked.containsPrototype())
          THROW(, "syntax '" << invoked.getKey() << "' does not match its declared pattern")
        lexicon::Phrase fallback = invoked.getPrototype();
        if (fallback.isNull()) THROW(, "extended syntax has no previous definition")
        if (expansion) {
          if (fallback.isRewritable()) {
            fallback.elaborate(context);
          } else {
            const std::string spelling = invoked.getKey();
            SyntaxExtension::emit(context, reinterpret_cast<const std::uint8_t *>(spelling.data()), 0, spelling.size());
          }
        } else {
          fallback.elaborate(context);
        }
        return;
      }
      const std::string matchedSource = payload.behavior == Behavior::Alias ? reader.slice(0, matched->bytes) : std::string{};
      const SourceLocation origin{context.source.path, context.source.line, context.source.position};

      // Alias mode deliberately keeps the top-level source in place. The target
      // phrase then consumes the same tail that was validated by the declarative
      // pattern. During fn expansion the target spelling plus that tail is emitted
      // instead, allowing the ordinary function grammar to handle the semantics.
      if (expansion) {
        SyntaxExtension::advance(context, matched->bytes);
      } else if (payload.behavior != Behavior::Alias) {
        context::Source::progress(context, matched->bytes * Byte::length);
      }

      MatchFrame frame{&context, matched->captures};
      MatchFrame *previous = currentMatch;
      currentMatch = &frame;
      try {
        if (payload.behavior == Behavior::Rewrite) {
          const std::string rewritten = renderTemplate(payload.replacement, frame.captures);
          if (expansion) {
            SyntaxExtension::emit(context, reinterpret_cast<const std::uint8_t *>(rewritten.data()), 0, rewritten.size());
          } else if (!rewritten.empty()) {
            executeSource(context, rewritten, origin.path, origin.line, origin.column);
          }
        } else if (payload.behavior == Behavior::Alias) {
          if (payload.targetSpelling.empty()) THROW(, "syntax alias has no target spelling")
          if (!invoked.containsSuccessor()) THROW(, "syntax alias has no target phrase")
          lexicon::Phrase target = invoked.getSuccessor();
          if (target.isNull()) THROW(, "syntax alias target is unavailable")
          if (expansion) {
            const std::string rewritten = payload.targetSpelling + matchedSource;
            SyntaxExtension::emit(context, reinterpret_cast<const std::uint8_t *>(rewritten.data()), 0, rewritten.size());
          } else {
            target.elaborate(context);
          }
        } else {
          if (!invoked.containsSuccessor()) THROW(, "syntax action has no handler")
          lexicon::Phrase handler = invoked.getSuccessor();
          if (handler.isNull() || !handler.isInvokable()) THROW(, "syntax action handler is not callable")
          handler.invoke(context);
        }
      } catch (...) {
        currentMatch = previous;
        throw;
      }
      currentMatch = previous;
    }
  } // namespace

  void SyntaxPattern::registerActions(context::Context &context) {
    context.actions().define("syntax.define", define);
    context.actions().define("syntax.pattern", invoke);
  }

  void SyntaxPattern::define(context::Context &context, lexicon::Phrase &) {
    ContextReader reader(context);
    DefinitionParser parser(context, reader);
    DefinitionParser::Result definition = parser.parse();
    const std::vector<Node> pattern = PatternParser(definition.payload.pattern).parse();
    std::unordered_set<std::string> captures;
    collectCaptureNames(pattern, captures);

    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase previous = exact(root, definition.name);
    if (!definition.replace && !definition.extend && !previous.isNull())
      THROW(, "syntax '" << definition.name << "' already exists; use 'syntax extend " << definition.name
                         << " ...' or 'syntax replace " << definition.name << " ...'")
    if ((definition.replace || definition.extend) && previous.isNull())
      THROW(, "syntax " << (definition.extend ? "extend" : "replace")
                         << " cannot find an existing phrase named '" << definition.name << "'")

    if (definition.payload.behavior == Behavior::Rewrite)
      validateTemplate(definition.payload.replacement, captures);

    lexicon::Phrase handler(&context.lexicon);
    if (definition.payload.behavior == Behavior::Alias) {
      lexicon::Phrase target = definition.aliasTarget == "super" ? previous : resolveReference(root, definition.aliasTarget);
      if (target.isNull()) THROW(, "syntax alias cannot find phrase '<" << definition.aliasTarget << ">'" )
      definition.payload.targetSpelling = target.getKey();
      handler = target;
    } else if (definition.payload.behavior == Behavior::Action) {
      lexicon::Phrase implementation = Functions::compileAction(context, definition.actionSignature, definition.actionBody,
                                                                 "syntax." + definition.name,
                                                                 definition.signatureOrigin, definition.bodyOrigin);
      handler = makeActionCarrier(context, implementation, definition.name);
    }

    lexicon::Draft draft = root.append(definition.name).make(invoke).setType(lexicon::phrase::type::getElaborate(root));
    if (!previous.isNull()) draft.setPrototype(previous);
    if ((definition.payload.behavior == Behavior::Action || definition.payload.behavior == Behavior::Alias) &&
        !handler.isNull())
      draft.setSuccessor(handler);
    lexicon::Phrase syntax = draft.save();
    syntax.setSerializable(true).setRewritable(true).save();
    storePayload(syntax, definition.payload);

    context::Source::progress(context, definition.consumed * Byte::length);
  }

  void SyntaxPattern::invoke(context::Context &context, lexicon::Phrase &invoked) {
    lexicon::Phrase owner = patternOwner(invoked);
    if (owner.isNull()) THROW(, "syntax pattern action has no declarative payload")
    const PatternPayload payload = loadPayload(owner);
    if (SyntaxExtension::active(context)) {
      const auto *data = SyntaxExtension::data(context);
      const std::size_t bytes = static_cast<std::size_t>(SyntaxExtension::bytes(context));
      StringReader reader(std::string_view(reinterpret_cast<const char *>(data), bytes));
      runPattern(context, owner, payload, reader, true);
      return;
    }
    ContextReader reader(context);
    runPattern(context, owner, payload, reader, false);
  }

  const std::uint8_t *SyntaxPattern::capture(context::Context &context, std::string_view name) {
    if (currentMatch == nullptr || currentMatch->context != &context) return nullptr;
    const auto found = currentMatch->captures.find(std::string(name));
    if (found == currentMatch->captures.end()) return nullptr;
    return reinterpret_cast<const std::uint8_t *>(found->second.c_str());
  }

  bool SyntaxPattern::captureExists(context::Context &context, std::string_view name) {
    return capture(context, name) != nullptr;
  }
} // namespace recurloop
