#include <recurloop/SyntaxPattern.hpp>

#include <recurloop/Execution.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/PhraseNames.hpp>
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
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace recurloop {
  namespace {
    constexpr std::uint32_t PayloadMagic = 0x31584e53; // "SNX1"
    constexpr std::uint16_t PayloadVersion = 1;
    constexpr std::size_t MaximumPatternScan = 16 * 1024 * 1024;
    constexpr std::string_view RecognitionKey{"\0syntax-recognition", 19};
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
      virtual context::Context *language() {
        return nullptr;
      }
      lexicon::Phrase selectedGrammar;
      lexicon::Phrase grammar() {
        return selectedGrammar.isNull() && language() ? language()->lexicon.phrase() : selectedGrammar;
      }
      virtual lexicon::Phrase phrase(std::size_t) {
        return {};
      }
    };

    class StringReader final : public Reader {
    public:
      explicit StringReader(std::string_view source, context::Context *context = nullptr)
          : source(source), context(context) {}

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

      context::Context *language() override {
        return context;
      }
      lexicon::Phrase phrase(std::size_t position) override {
        if (!context || position >= source.size()) return {};
        const auto eligible = [&](lexicon::Phrase candidate) {
          const auto key = candidate.getKey();
          const auto end = position + key.size();
          return !key.empty() && (!identifierByte(static_cast<unsigned char>(key.back())) || end == source.size() ||
                                  !identifierByte(static_cast<unsigned char>(source[end])));
        };
        auto selected = grammar();
        auto matched = LanguageGrammar::matchLongest(selected, source.substr(position), eligible);
        auto root = context->lexicon.phrase();
        if (selected.getAddress() != root.getAddress()) {
          auto native = LanguageGrammar::matchLongest(root, source.substr(position), eligible);
          if (!native.isNull() && (matched.isNull() || native.getKey().size() > matched.getKey().size()))
            matched = native;
        }
        return matched;
      }

    private:
      std::string_view source;
      context::Context *context;
    };

    class ContextReader final : public Reader {
    public:
      explicit ContextReader(context::Context &context) : context(context) {}

      bool available(std::size_t offset) override {
        while (context.source.buffer.bits / Byte::length <= offset && context.source.more)
          context::Source::load(context, true);
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

      context::Context *language() override {
        return &context;
      }
      lexicon::Phrase phrase(std::size_t position) override {
        const auto eligible = [&](lexicon::Phrase candidate) {
          const auto key = candidate.getKey();
          return !key.empty() &&
                 (!identifierByte(static_cast<unsigned char>(key.back())) || !available(position + key.size()) ||
                  !identifierByte(static_cast<unsigned char>(at(position + key.size()))));
        };
        auto selected = grammar();
        auto matched = LanguageGrammar::peekLongest(context, selected, position, eligible);
        auto root = context.lexicon.phrase();
        if (selected.getAddress() != root.getAddress()) {
          auto native = LanguageGrammar::peekLongest(context, root, position, eligible);
          if (!native.isNull() && (matched.isNull() || native.getKey().size() > matched.getKey().size()))
            matched = native;
        }
        return matched;
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

    std::string syntaxAt(Reader &reader, std::size_t position, std::string_view canonical) {
      if (!reader.language()) return startsWith(reader, position, canonical) ? std::string(canonical) : std::string{};
      auto phrase = reader.phrase(position);
      auto prototype = LanguageGrammar::findInherited(reader.grammar(), canonical);
      auto native = LanguageGrammar::find(reader.language()->lexicon.phrase(), canonical);
      return LanguageGrammar::inherits(phrase, prototype) || LanguageGrammar::inherits(phrase, native) ? phrase.getKey()
                                                                                                       : std::string{};
    }

    std::size_t patternEnd(Reader &reader, lexicon::Phrase phrase, std::size_t position);

    // Capture boundaries come from the active phrase graph. This scanner only
    // balances those boundaries; it neither evaluates nor owns a language AST.
    struct CaptureCursor {
      std::vector<std::string_view> closing;
      bool patterns = true;
      char quote = '\0';
      bool escaped = false;
      bool lineComment = false;
      bool blockComment = false;

      bool top() const {
        return closing.empty() && quote == '\0' && !lineComment && !blockComment;
      }

      bool advance(Reader &reader, std::size_t &position) {
        const char ch = reader.at(position);
        if (lineComment) {
          ++position;
          if (ch == '\n' || ch == '\r') lineComment = false;
          return true;
        }
        if (blockComment) {
          auto ending = syntaxAt(reader, position, "*/");
          if (ending.empty() && startsWith(reader, position, "*/")) ending = "*/";
          if (!ending.empty()) {
            position += ending.size();
            blockComment = false;
          } else
            ++position;
          return true;
        }
        if (quote != '\0') {
          ++position;
          if (escaped)
            escaped = false;
          else if (ch == '\\')
            escaped = true;
          else if (ch == quote)
            quote = '\0';
          return true;
        }
        auto phrase = reader.phrase(position);
        if (patterns && !phrase.isNull()) {
          const auto end = patternEnd(reader, phrase, position);
          if (end > position + phrase.getKey().size()) {
            position = end;
            return true;
          }
        }
        const auto syntax = [&](std::string_view canonical) {
          if (!reader.language())
            return startsWith(reader, position, canonical) ? std::string(canonical) : std::string{};
          auto prototype = LanguageGrammar::findInherited(reader.grammar(), canonical);
          auto native = LanguageGrammar::find(reader.language()->lexicon.phrase(), canonical);
          return LanguageGrammar::inherits(phrase, prototype) || LanguageGrammar::inherits(phrase, native)
                     ? phrase.getKey()
                     : std::string{};
        };
        for (const auto &[opening, close] : {std::pair{"(", ")"}, {"[", "]"}, {"{", "}"}}) {
          const auto key = syntax(opening);
          if (!key.empty()) {
            closing.emplace_back(close);
            position += key.size();
            return true;
          }
          const auto end = syntax(close);
          if (!end.empty()) {
            if (closing.empty() || closing.back() != close) return false;
            closing.pop_back();
            position += end.size();
            return true;
          }
        }
        const auto line = syntax("//");
        if (!line.empty()) {
          lineComment = true;
          position += line.size();
          return true;
        }
        const auto block = syntax("/*");
        if (!block.empty()) {
          blockComment = true;
          position += block.size();
          return true;
        }
        if (!phrase.isNull()) {
          position += phrase.getKey().size();
          return true;
        }
        if (ch == '"' || ch == '\'') quote = ch;
        // A native data identifier is one atom. Its suffix must not become a
        // word delimiter merely because no phrase starts at its first byte.
        if (reader.language() && identifierStart(static_cast<unsigned char>(ch))) {
          do {
            ++position;
          } while (reader.available(position) && identifierByte(static_cast<unsigned char>(reader.at(position))));
        } else {
          ++position;
        }
        return true;
      }
    };

    std::size_t skipLayout(Reader &reader, std::size_t position) {
      while (true) {
        while (reader.available(position) && std::isspace(static_cast<unsigned char>(reader.at(position)))) {
          auto registered = reader.phrase(position);
          if (!registered.isNull() && registered.getKey().size() > 1) break;
          ++position;
        }
        const auto line = syntaxAt(reader, position, "//");
        if (!line.empty()) {
          position += line.size();
          while (reader.available(position) && reader.at(position) != '\n') ++position;
          continue;
        }
        const auto block = syntaxAt(reader, position, "/*");
        if (!block.empty()) {
          position += block.size();
          std::string ending;
          while (reader.available(position)) {
            ending = syntaxAt(reader, position, "*/");
            if (ending.empty() && startsWith(reader, position, "*/")) ending = "*/";
            if (!ending.empty()) break;
            ++position;
          }
          if (ending.empty()) THROW(, "syntax matcher: unterminated block comment")
          position += ending.size();
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

    struct Observation {
      std::size_t bytes = 0;
      std::size_t steps = 0;
      std::vector<SyntaxPattern::Expectation> expected;
      std::size_t requiredStart = std::numeric_limits<std::size_t>::max();
      std::string_view requiredLiteral;
      bool reached = false;
      void add(const Node &node, std::size_t start) {
        if (requiredStart != std::numeric_limits<std::size_t>::max()) return;
        expected.push_back({start, node.kind == Node::Kind::Capture ? node.text : "",
                            node.captureType, node.kind == Node::Kind::Literal ? node.text : ""});
      }
    };
    thread_local Observation *observation = nullptr;
    struct ObservationLimit {};
    struct ObservationScope {
      Observation *previous = observation;
      explicit ObservationScope(Observation &state) { observation = &state; }
      ~ObservationScope() { observation = previous; }
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
        if (++items > 512) fail("pattern exceeds 512 items");
        struct Depth {
          std::size_t &value;
          explicit Depth(std::size_t &value) : value(value) { ++value; }
          ~Depth() { --value; }
        } depthScope(depth);
        if (depth > 64) fail("pattern exceeds 64 nested groups");
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
      std::size_t depth = 0;
      std::size_t items = 0;
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
      const auto opening = syntaxAt(reader, position, "{");
      if (opening.empty()) return std::nullopt;
      std::size_t cursor = position + opening.size();
      CaptureCursor scan;
      scan.closing.emplace_back("}");
      while (cursor - position <= MaximumPatternScan && reader.available(cursor)) {
        if (!scan.advance(reader, cursor)) return std::nullopt;
        if (scan.top()) return cursor;
      }
      return std::nullopt;
    }

    std::string captureSlice(Reader &reader, std::size_t begin, std::size_t end, bool preserve = false) {
      std::string value = reader.slice(begin, end);
      return preserve ? value : trim(std::move(value));
    }

    using Captures = std::unordered_map<std::string, std::string>;

    std::optional<std::size_t> matchSequence(const std::vector<Node> &nodes, std::size_t index, Reader &reader,
                                             std::size_t position, Captures &captures, bool opaqueLayout = false);

    std::optional<std::size_t> matchVariableCapture(const std::vector<Node> &nodes, std::size_t index, const Node &node,
                                                    Reader &reader, std::size_t start, Captures &captures) {
      const bool last = index + 1 == nodes.size();
      const bool opaque = node.captureType == "raw" || node.captureType == "code";
      if (last) {
        std::size_t end = start;
        CaptureCursor scan;
        while (end - start <= MaximumPatternScan && reader.available(end)) {
          const char ch = reader.at(end);
          if ((ch == '\n' || ch == '\r') && (opaque || scan.top() || (scan.lineComment && scan.closing.empty()))) break;
          if (opaque)
            ++end;
          else if (!scan.advance(reader, end))
            break;
        }
        if (!opaque && (!scan.closing.empty() || scan.quote != '\0' || scan.blockComment)) {
          if (observation && end == observation->bytes) observation->add(node, start);
          return std::nullopt;
        }
        std::string value = captureSlice(reader, start, end, node.captureType == "code");
        if (observation && end == observation->bytes) observation->add(node, start);
        if (node.captureType == "expr" && value.empty()) return std::nullopt;
        captures[node.text] = std::move(value);
        return end;
      }

      std::size_t cursor = start;
      CaptureCursor scan;
      while (cursor - start <= MaximumPatternScan) {
        if (opaque || scan.top()) {
          Captures trial = captures;
          std::string value = captureSlice(reader, start, cursor, node.captureType == "code");
          if (!(node.captureType == "expr" && value.empty())) {
            trial[node.text] = std::move(value);
            if (const auto finish = matchSequence(nodes, index + 1, reader, cursor, trial, opaque)) {
              captures = std::move(trial);
              return finish;
            }
          }
        }
        if (!reader.available(cursor)) break;
        if (opaque)
          ++cursor;
        else if (!scan.advance(reader, cursor))
          break;
      }
      if (observation && cursor == observation->bytes) observation->add(node, start);
      return std::nullopt;
    }

    std::optional<std::size_t> matchSequence(const std::vector<Node> &nodes, std::size_t index, Reader &reader,
                                             std::size_t position, Captures &captures, bool opaqueLayout) {
      if (observation && ++observation->steps > 65536) throw ObservationLimit{};
      if (index == nodes.size()) return position;
      const Node &node = nodes[index];

      if (node.kind == Node::Kind::Optional) {
        if (observation) {
          Captures skipped = captures;
          matchSequence(nodes, index + 1, reader, position, skipped, opaqueLayout);
        }
        Captures trial = captures;
        if (const auto inside = matchSequence(node.children, 0, reader, position, trial, opaqueLayout)) {
          if (const auto finish = matchSequence(nodes, index + 1, reader, *inside, trial)) {
            captures = std::move(trial);
            return finish;
          }
        }
        return matchSequence(nodes, index + 1, reader, position, captures, opaqueLayout);
      }
      if (node.kind == Node::Kind::Choice) {
        std::optional<std::size_t> result;
        for (const auto &alternative : node.alternatives) {
          Captures trial = captures;
          if (const auto inside = matchSequence(alternative, 0, reader, position, trial, opaqueLayout)) {
            if (const auto finish = matchSequence(nodes, index + 1, reader, *inside, trial)) {
              captures = std::move(trial);
              if (!observation) return finish;
              result = finish;
            }
          }
        }
        return result;
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

      if (opaqueLayout ||
          (node.kind == Node::Kind::Capture && (node.captureType == "raw" || node.captureType == "code"))) {
        while (reader.available(position) && std::isspace(static_cast<unsigned char>(reader.at(position)))) ++position;
      } else {
        position = skipLayout(reader, position);
      }

      if (node.kind == Node::Kind::Literal) {
        if (observation && position <= observation->bytes) {
          const auto remaining = reader.slice(position, observation->bytes);
          if (remaining.size() < node.text.size() && node.text.starts_with(remaining)) observation->add(node, position);
        }
        std::size_t size = node.text.size();
        bool matched = startsWith(reader, position, node.text) && literalBoundary(reader, position, node.text);
        if (reader.language()) {
          auto expected = LanguageGrammar::findInherited(reader.grammar(), node.text);
          if (!expected.isNull()) {
            auto actual = reader.phrase(position);
            matched = LanguageGrammar::inherits(actual, expected);
            if (matched) size = actual.getKey().size();
          }
        }
        if (!matched) return std::nullopt;
        if (observation && position == observation->requiredStart && node.text == observation->requiredLiteral)
          observation->reached = true;
        return matchSequence(nodes, index + 1, reader, position + size, captures);
      }

      if (node.captureType == "ignore") return matchSequence(nodes, index + 1, reader, position, captures);

      if (observation && position == observation->bytes) observation->add(node, position);

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
        if (observation && cursor == observation->bytes) observation->add(node, position);
        return matchSequence(nodes, index + 1, reader, cursor, captures);
      }

      if (node.captureType == "number") {
        std::size_t cursor = position;
        if (reader.available(cursor) && (reader.at(cursor) == '+' || reader.at(cursor) == '-')) ++cursor;
        const std::size_t numberStart = cursor;
        std::string text;
        while (text.size() <= MaximumPatternScan && reader.available(cursor)) {
          const auto ch = static_cast<unsigned char>(reader.at(cursor));
          if (!std::isalnum(ch) && ch != '_' && ch != '.' && ch != '+' && ch != '-') break;
          text.push_back(static_cast<char>(ch));
          ++cursor;
        }
        const auto number = LanguageGrammar::numberLiteral(text);
        if (number.bytes == 0) return std::nullopt;
        cursor = numberStart + number.bytes;
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
        auto phrase = reader.phrase(position);
        if (phrase.isNull() && (reader.at(position) == '"' || reader.at(position) == '\'')) {
          Node stringNode = node;
          stringNode.captureType = "string";
          std::vector<Node> rewritten = nodes;
          rewritten[index] = std::move(stringNode);
          return matchSequence(rewritten, index, reader, position, captures);
        }
        std::size_t cursor = position;
        if (!phrase.isNull())
          cursor += phrase.getKey().size();
        else if (identifierStart(static_cast<unsigned char>(reader.at(cursor))) ||
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
        if (observation && cursor == observation->bytes) observation->add(node, position);
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

    std::size_t patternEnd(Reader &reader, lexicon::Phrase phrase, std::size_t position) {
      const auto start = position + phrase.getKey().size();
      auto owner = patternOwner(phrase);
      bool described = false;
      if (owner.isNull()) {
        owner = LanguageGrammar::findInherited(phrase, RecognitionKey);
        described = !owner.isNull() && hasPatternPayload(owner);
        if (!described) return start;
      }
      struct GrammarScope {
        Reader &reader;
        lexicon::Phrase previous;
        GrammarScope(Reader &reader, lexicon::Phrase grammar) : reader(reader), previous(reader.selectedGrammar) {
          reader.selectedGrammar = grammar;
        }
        ~GrammarScope() {
          reader.selectedGrammar = previous;
        }
      } grammarScope(reader, described && owner.containsPrototype() ? owner.getPrototype() : lexicon::Phrase{});
      static thread_local std::size_t depth = 0;
      if (depth >= 64) return start;
      struct Scope {
        std::size_t &depth;
        Observation *previous = observation;
        explicit Scope(std::size_t &depth) : depth(depth) {
          ++depth;
          observation = nullptr;
        }
        ~Scope() {
          observation = previous;
          --depth;
        }
      } scope(depth);
      const auto payload = loadPayload(owner);
      const auto nodes = PatternParser(payload.pattern).parse();
      Captures captures;
      const auto end = matchSequence(nodes, 0, reader, start, captures);
      return end ? *end : start;
    }

    std::string blockBody(context::Context &context, std::string value) {
      value = trim(std::move(value));
      StringReader reader(value, &context);
      const auto opening = syntaxAt(reader, 0, "{");
      if (!opening.empty()) {
        std::size_t position = opening.size();
        CaptureCursor scan;
        scan.closing.emplace_back("}");
        while (reader.available(position)) {
          const auto before = position;
          if (!scan.advance(reader, position)) break;
          if (scan.top() && position == value.size()) return value.substr(opening.size(), before - opening.size());
        }
      }
      return value;
    }

    std::string renderTemplate(context::Context &context, std::string_view source, const Captures &captures) {
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
        if (modifier == "body")
          value = blockBody(context, std::move(value));
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
        CaptureCursor scan;
        // Captures have not been substituted yet. Balance grammar delimiters
        // without trying to recognize a complete target-language phrase.
        scan.patterns = false;
        while (cursor - begin <= MaximumPatternScan && reader.available(cursor)) {
          const char ch = reader.at(cursor);
          if ((ch == '\n' || ch == '\r') && (scan.top() || scan.lineComment)) break;
          // A rewrite may emit a closing delimiter for its surrounding syntax.
          if (!scan.advance(reader, cursor)) ++cursor;
        }
        return trim(reader.slice(begin, cursor));
      }

      void parseAction(Result &result) {
        skipLayoutLocal();
        const std::size_t signatureBegin = cursor;
        CaptureCursor signature;
        std::string opening;
        while (cursor - signatureBegin <= MaximumPatternScan && reader.available(cursor)) {
          if (signature.top()) {
            opening = syntaxAt(reader, cursor, "{");
            if (!opening.empty()) break;
          }
          if (!signature.advance(reader, cursor)) fail("unbalanced syntax action signature");
        }
        if (opening.empty()) fail("syntax action expects a function body");
        result.actionSignature = trim(reader.slice(signatureBegin, cursor));
        result.signatureOrigin = location(signatureBegin);
        cursor += opening.size();
        const std::size_t bodyBegin = cursor;
        CaptureCursor body;
        body.closing.emplace_back("}");
        while (cursor - bodyBegin <= MaximumPatternScan && reader.available(cursor)) {
          const auto previous = cursor;
          if (!body.advance(reader, cursor)) fail("unbalanced syntax action body");
          if (body.top()) {
            result.actionBody = reader.slice(bodyBegin, previous);
            result.bodyOrigin = location(bodyBegin);
            return;
          }
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
        std::size_t interpolation = 0;
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
          if (ch == '{')
            ++interpolation;
          else if (ch == '}' && interpolation != 0)
            --interpolation;
          if (ch == '>' && interpolation == 0) {
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

    lexicon::Phrase resolveReference(context::Context &context, std::string_view source) {
      auto parsed = PhraseNames::parse(context, source);
      parsed.path.push_back(parsed.name);
      auto current = context.lexicon.phrase();
      for (const auto &component : parsed.path) {
        current = LanguageGrammar::findInherited(current, component);
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
          const std::string rewritten = renderTemplate(context, payload.replacement, frame.captures);
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

  void SyntaxPattern::validate(std::string_view pattern) {
    PatternParser(pattern).parse();
  }

  std::string SyntaxPattern::pattern(lexicon::Phrase phrase) {
    auto owner = patternOwner(phrase);
    return owner.isNull() ? std::string{} : loadPayload(owner).pattern;
  }

  bool SyntaxPattern::accepts(std::string_view matcher, std::string_view value, context::Context *context) {
    const auto nodes = PatternParser("<value:" + std::string(matcher) + ">").parse();
    StringReader reader(value, context);
    const auto matched = matchPattern(nodes, reader);
    return matched && matched->bytes == value.size();
  }

  std::string SyntaxPattern::insertion(std::string_view pattern, std::string_view prefix, const Expectation &item,
                                       context::Context *context) {
    if (item.literal.empty()) return {};
    const auto nodes = PatternParser(pattern).parse();
    const auto before = std::string(prefix.substr(0, item.start));
    const auto reaches = [&](bool space) {
      const auto candidate = before + (space ? " " : "") + item.literal;
      Observation state{candidate.size(), 0, {}};
      state.requiredStart = before.size() + (space ? 1 : 0);
      state.requiredLiteral = item.literal;
      ObservationScope scope(state);
      StringReader reader(candidate, context);
      Captures captures;
      try { matchSequence(nodes, 0, reader, 0, captures); }
      catch (const ObservationLimit &) { return false; }
      return state.reached;
    };
    return !reaches(false) && reaches(true) ? ' ' + item.literal : item.literal;
  }

  std::vector<SyntaxPattern::Expectation> SyntaxPattern::expect(std::string_view pattern, std::string_view prefix,
                                                                context::Context *context) {
    auto nodes = PatternParser(pattern).parse();
    if (prefix.size() > MaximumPatternScan) return {};
    Observation state{prefix.size(), 0, {}};
    ObservationScope scope(state);
    StringReader reader(prefix, context);
    Captures captures;
    try {
      const auto end = matchSequence(nodes, 0, reader, 0, captures);
      if (end && skipLayout(reader, *end) == prefix.size()) state.expected.push_back({prefix.size(), {}, {}, {}});
    }
    catch (const ObservationLimit &) { return {}; }
    std::sort(state.expected.begin(), state.expected.end(), [](const auto &a, const auto &b) {
      return std::tie(a.start, a.name, a.matcher, a.literal) < std::tie(b.start, b.name, b.matcher, b.literal);
    });
    state.expected.erase(std::unique(state.expected.begin(), state.expected.end(), [](const auto &a, const auto &b) {
      return a.start == b.start && a.name == b.name && a.matcher == b.matcher && a.literal == b.literal;
    }), state.expected.end());
    return state.expected;
  }

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
      lexicon::Phrase target =
          definition.aliasTarget == "super" ? previous : resolveReference(context, definition.aliasTarget);
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

  void SyntaxPattern::describe(context::Context &context, lexicon::Phrase phrase, std::string_view pattern,
                               lexicon::Phrase grammar) {
    validate(pattern);
    if (phrase.isNull() || !phrase.containsSubdictionary() || grammar.isNull() || !grammar.containsSubdictionary())
      THROW(, "syntax description requires phrase and grammar dictionaries")
    auto descriptor = phrase.append(std::string(RecognitionKey)).make().setPrototype(grammar).save();
    descriptor.setSerializable(true).save();
    PatternPayload payload;
    payload.pattern = std::string(pattern);
    storePayload(descriptor, payload);
  }

  std::size_t SyntaxPattern::blockExtent(context::Context &context, std::string_view source, std::size_t position) {
    StringReader reader(source, &context);
    const auto end = blockEnd(reader, position);
    return end.value_or(0);
  }

  std::size_t SyntaxPattern::extent(context::Context &context, lexicon::Phrase phrase, std::size_t relative) {
    ContextReader reader(context);
    return patternEnd(reader, phrase, relative) - relative;
  }

  void SyntaxPattern::invoke(context::Context &context, lexicon::Phrase &invoked) {
    lexicon::Phrase owner = patternOwner(invoked);
    if (owner.isNull()) THROW(, "syntax pattern action has no declarative payload")
    const PatternPayload payload = loadPayload(owner);
    if (SyntaxExtension::active(context)) {
      const auto *data = SyntaxExtension::data(context);
      const std::size_t bytes = static_cast<std::size_t>(SyntaxExtension::bytes(context));
      StringReader reader(std::string_view(reinterpret_cast<const char *>(data), bytes), &context);
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
