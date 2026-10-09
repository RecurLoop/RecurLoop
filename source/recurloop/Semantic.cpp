#include <recurloop/Semantic.hpp>

#include <context/Context.hpp>
#include <compiler/LanguageState.hpp>
#include <compiler/TypeSystem.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/Assistance.hpp>
#include <recurloop/SyntaxPattern.hpp>
#include <utilities/Byte.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <memory>
#include <array>
#include <cstddef>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <optional>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace recurloop {
  namespace {
    constexpr std::string_view RegistryName{"\0semantic-metadata", 18};
    constexpr std::string_view SchemaName{"\0semantic-metadata-schema", 25};
    // Local versions occupy a separate, exactly representable inspection namespace.
    constexpr std::uint64_t LocalVersionBase = std::uint64_t{1} << 32;
    constexpr std::uint32_t MetadataMagic = 0x53454d31; // SEM1

    enum MetadataFlags : std::uint8_t {
      KindPresent = 1 << 0,
      ColorPresent = 1 << 1,
      DocsPresent = 1 << 2,
    };

    struct MetadataHeader {
      std::uint32_t magic = MetadataMagic;
      std::uint8_t flags = 0;
      std::uint8_t reserved[3]{};
      Size target = 0;
      std::uint32_t kindBytes = 0;
      std::uint32_t colorBytes = 0;
      std::uint32_t docsBytes = 0;
    };

    struct Patch {
      bool kind = false;
      bool color = false;
      bool docs = false;
      std::string kindValue;
      std::string colorValue;
      std::string docsValue;
    };

    struct OwnMetadata {
      std::uint8_t flags = 0;
      std::string kind;
      std::string color;
      std::string docs;
      Size recordAddress = 0;
    };

    struct Span {
      enum class Source { Lexical, Phrase, Local };
      std::size_t start = 0;
      std::size_t end = 0;
      std::string color;
      std::string kind;
      std::string docs;
      std::uint64_t group = 0;
      std::string ownerKey;
      Source source = Source::Lexical;
      Size symbol = 0;
      Size docsOwner = 0;
      bool hasColor = false;
    };

    struct TraceState {
      context::Context *context = nullptr;
      std::string source;
      std::string path;
      std::unordered_map<Size, OwnMetadata> metadata;
      bool metadataDirty = false;
      std::vector<Span> spans;
      std::vector<std::size_t> lineStarts;
      std::vector<std::size_t> characterOffsets;
      std::size_t completionStart = 0;
      Size activeOwner = 0;
      std::uint64_t activeGroup = 0;
      Size continuationOwner = 0;
      std::uint64_t continuationGroup = 0;
      Size lastOwner = 0;
      std::uint64_t lastGroup = 0;
      std::uint64_t nextGroup = 1;
      std::size_t sourceSteps = 0;
      std::size_t sourceStepBudget = 0;
      std::vector<std::string> matches;
      struct LocalFact {
        std::string name;
        SemanticMetadata metadata;
      };
      std::vector<LocalFact> locals;
      std::vector<std::string> localMatches;
      std::unordered_map<std::size_t, std::pair<SourceLocation, SourceLocation>> definitions;
      struct Anchor { Size phrase; std::size_t end; };
      std::vector<Anchor> anchors;
      std::unordered_map<Size, std::string> names;
      bool namesDirty = false;
    };

    thread_local TraceState *currentTrace = nullptr;

    std::unordered_map<Size, std::string> phrasePaths(context::Context &context) {
      std::unordered_map<Size, std::string> names;
      std::unordered_set<Size> visited;
      const auto visit = [&](lexicon::Phrase owner, std::string prefix, const auto &self) -> void {
        if (owner.isNull() || !owner.containsSubdictionary() ||
            !visited.insert(owner.getSubdictionary().getAddress()).second)
          return;
        auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
        for (lexicon::Dictionary node = owner.fore(populated); !node.isNull(); node = node.next(populated)) {
          lexicon::Phrase phrase = node.getPhrase();
          if (phrase.isNull()) continue;
          const std::string key = phrase.getKey();
          const std::string name = prefix.empty() ? key : prefix + ':' + key;
          std::unordered_set<Size> history;
          for (lexicon::Phrase version = phrase; !version.isNull() && history.insert(version.getAddress()).second;
               version = version.older())
            names.try_emplace(version.getAddress(), name);
          if (key.empty() || static_cast<unsigned char>(key.front()) >= 32) self(phrase, name, self);
        }
      };
      visit(context.lexicon.phrase(), {}, visit);
      return names;
    }

    std::string phrasePath(const std::unordered_map<Size, std::string> &names, lexicon::Phrase phrase) {
      if (phrase.isNull()) return {};
      const auto found = names.find(phrase.getAddress());
      return found == names.end() ? phrase.getKey() : found->second;
    }

    std::size_t phraseVersion(lexicon::Phrase phrase) {
      std::size_t version = 0;
      std::unordered_set<Size> visited;
      for (lexicon::Phrase older = phrase.older(); !older.isNull() && visited.insert(older.getAddress()).second;
           older = older.older())
        ++version;
      return version;
    }

    lexicon::Phrase exact(lexicon::Phrase owner, std::string_view key) {
      if (owner.isNull() || !owner.containsSubdictionary()) return lexicon::Phrase(owner.getLexicon());
      lexicon::Match match = owner.matchExact(Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length,
                                              [](radix::Node *, radix::Match *candidate) {
                                                return !lexicon::Dictionary(*candidate).getPhrase().isNull();
                                              });
      return match.isNull() ? lexicon::Phrase(owner.getLexicon()) : match.getPhrase();
    }

    lexicon::Phrase schema(context::Context &context, bool create) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase result = exact(root, SchemaName);
      if (!result.isNull() || !create) return result;
      result = root.append(std::string(SchemaName))
                   .make()
                   .setType(lexicon::phrase::type::getData(root))
                   .save();
      EngineImage::declarePayloadField(context, result, offsetof(MetadataHeader, target),
                                       EngineImage::PayloadFieldKind::PhraseReference);
      return result;
    }

    lexicon::Phrase registry(context::Context &context, bool create) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase result = exact(root, RegistryName);
      if (!result.isNull() || !create) return result;
      return root.append(std::string(RegistryName))
          .make()
          .enableSubdictionary()
          .setType(lexicon::phrase::type::getData(root))
          .save();
    }

    std::string keyFor(Size address) {
      return std::string(reinterpret_cast<const char *>(&address), sizeof(address));
    }

    bool decode(lexicon::Phrase record, Size expectedSchema, Size &target, OwnMetadata &metadata) {
      if (record.isNull() || !record.containsPrototype() || record.getPrototype().getAddress() != expectedSchema ||
          record.payloadSize() < sizeof(MetadataHeader))
        return false;

      MetadataHeader header{};
      std::memcpy(&header, record.content(0, sizeof(header)).toPtr(), sizeof(header));
      if (header.magic != MetadataMagic) return false;
      const std::size_t payloadBytes = record.payloadSize();
      const std::size_t strings = static_cast<std::size_t>(header.kindBytes) + header.colorBytes + header.docsBytes;
      if (strings > payloadBytes - sizeof(MetadataHeader)) return false;

      const auto *bytes = strings == 0 ? nullptr
                                        : reinterpret_cast<const char *>(record.content(sizeof(MetadataHeader), strings).toPtr());
      std::size_t cursor = 0;
      metadata.flags = header.flags;
      if (header.kindBytes != 0) metadata.kind.assign(bytes + cursor, header.kindBytes);
      cursor += header.kindBytes;
      if (header.colorBytes != 0) metadata.color.assign(bytes + cursor, header.colorBytes);
      cursor += header.colorBytes;
      if (header.docsBytes != 0) metadata.docs.assign(bytes + cursor, header.docsBytes);
      metadata.recordAddress = record.getAddress();
      target = header.target;
      return target != 0;
    }

    std::unordered_map<Size, OwnMetadata> catalog(context::Context &context) {
      std::unordered_map<Size, OwnMetadata> result;
      lexicon::Phrase records = registry(context, false);
      lexicon::Phrase recordSchema = schema(context, false);
      if (records.isNull() || recordSchema.isNull() || !records.containsSubdictionary()) return result;

      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      for (lexicon::Dictionary child = records.fore(populated); !child.isNull(); child = child.next(populated)) {
        lexicon::Phrase record = child.getPhrase();
        Size target = 0;
        OwnMetadata value;
        if (!decode(record, recordSchema.getAddress(), target, value)) continue;
        const auto found = result.find(target);
        if (found == result.end() || found->second.recordAddress < value.recordAddress)
          result[target] = std::move(value);
      }
      return result;
    }

    void refreshTraceCatalog(TraceState &trace) {
      trace.metadata = catalog(*trace.context);
      trace.metadataDirty = false;
    }

    OwnMetadata own(context::Context &context, lexicon::Phrase phrase) {
      const auto values = catalog(context);
      const auto found = values.find(phrase.getAddress());
      return found == values.end() ? OwnMetadata{} : found->second;
    }

    SemanticMetadata resolved(const std::unordered_map<Size, OwnMetadata> &values, lexicon::Phrase phrase) {
      SemanticMetadata result;
      std::unordered_set<Size> visited;
      while (!phrase.isNull() && visited.insert(phrase.getAddress()).second) {
        if (const auto found = values.find(phrase.getAddress()); found != values.end()) {
          const OwnMetadata &value = found->second;
          if (!result.hasKind && (value.flags & KindPresent)) {
            result.hasKind = true;
            result.kind = value.kind;
          }
          if (!result.hasColor && (value.flags & ColorPresent)) {
            result.hasColor = true;
            result.color = value.color;
          }
          if (!result.hasDocs && (value.flags & DocsPresent)) {
            result.hasDocs = true;
            result.docs = value.docs;
          }
          if (result.hasKind && result.hasColor && result.hasDocs) break;
        }
        if (!phrase.containsPrototype()) break;
        phrase = phrase.getPrototype();
      }
      return result;
    }

    SemanticMetadata resolvedTrace(TraceState &trace, lexicon::Phrase phrase) {
      if (trace.metadataDirty) refreshTraceCatalog(trace);
      return resolved(trace.metadata, phrase);
    }

    void write(context::Context &context, lexicon::Phrase target, Patch patch) {
      if (target.isNull()) THROW(, "semantic metadata requires a phrase")
      OwnMetadata value = own(context, target);
      if (patch.kind) {
        value.flags |= KindPresent;
        value.kind = std::move(patch.kindValue);
      }
      if (patch.color) {
        value.flags |= ColorPresent;
        value.color = std::move(patch.colorValue);
      }
      if (patch.docs) {
        value.flags |= DocsPresent;
        value.docs = std::move(patch.docsValue);
      }

      lexicon::Phrase owner = registry(context, true);
      lexicon::Phrase recordSchema = schema(context, true);
      lexicon::Phrase root = context.lexicon.phrase();
      MetadataHeader header;
      // MetadataHeader is copied byte-for-byte into an engine-image payload.
      // Zero its complete object representation first so ABI padding cannot
      // leak stack bytes into .rli files and break deterministic self-hosting.
      std::memset(&header, 0, sizeof(header));
      header.magic = MetadataMagic;
      header.flags = value.flags;
      header.target = target.getAddress();
      header.kindBytes = static_cast<std::uint32_t>(value.kind.size());
      header.colorBytes = static_cast<std::uint32_t>(value.color.size());
      header.docsBytes = static_cast<std::uint32_t>(value.docs.size());

      const std::size_t total = sizeof(header) + value.kind.size() + value.color.size() + value.docs.size();
      lexicon::Phrase record = owner.append(keyFor(target.getAddress()))
                                    .make()
                                    .setPrototype(recordSchema)
                                    .setType(lexicon::phrase::type::getData(root))
                                    .save();
      Byte output = record.allocate(total);
      auto *bytes = static_cast<std::uint8_t *>(output.toPtr());
      std::memcpy(bytes, &header, sizeof(header));
      std::size_t cursor = sizeof(header);
      if (!value.kind.empty()) {
        std::memcpy(bytes + cursor, value.kind.data(), value.kind.size());
        cursor += value.kind.size();
      }
      if (!value.color.empty()) {
        std::memcpy(bytes + cursor, value.color.data(), value.color.size());
        cursor += value.color.size();
      }
      if (!value.docs.empty()) std::memcpy(bytes + cursor, value.docs.data(), value.docs.size());
      record.save();

      // A file may define semantic metadata and use the phrase later in the
      // same unsaved buffer. Keep the active inspection catalog coherent with
      // those transactional lexicon writes so the later real phrase match sees
      // the new docs/style immediately.
      if (currentTrace != nullptr && currentTrace->context == &context)
        currentTrace->metadata[target.getAddress()] = value;
    }

    std::optional<std::size_t> sourceOffset(const TraceState &trace, const SourceLocation &location) {
      if (location.path != trace.path || location.line == 0 || location.column == 0 ||
          location.line > trace.lineStarts.size())
        return std::nullopt;

      std::size_t cursor = trace.lineStarts[location.line - 1];
      std::size_t column = 1;
      while (cursor < trace.source.size() && column < location.column) {
        const unsigned char value = static_cast<unsigned char>(trace.source[cursor++]);
        if (value == '\n') return std::nullopt;
        if ((value & 0xc0u) != 0x80u) ++column;
      }
      return column == location.column ? std::optional<std::size_t>(cursor) : std::nullopt;
    }

    std::size_t characterOffset(const TraceState &trace, std::size_t bytes) {
      return trace.characterOffsets[std::min(bytes, trace.characterOffsets.size() - 1)];
    }

    std::string hex(std::string_view text) {
      static constexpr char digits[] = "0123456789abcdef";
      std::string result;
      result.reserve(text.size() * 2);
      for (unsigned char value : text) {
        result.push_back(digits[value >> 4]);
        result.push_back(digits[value & 0xf]);
      }
      return result;
    }

    std::string matchRecord(const TraceState &trace, std::size_t start, std::size_t end, std::size_t line,
                            std::uint64_t version, std::string_view name) {
      std::ostringstream match;
      match << "R\t" << characterOffset(trace, start) << '\t' << characterOffset(trace, end) << '\t' << line << '\t'
            << version << '\t' << hex(name) << '\n';
      return match.str();
    }

    struct DocsAnchor {
      bool specified = false;
      Size owner = 0;
    };

    DocsAnchor docsAnchor(TraceState &trace, lexicon::Phrase phrase) {
      std::unordered_set<Size> visited;
      while (!phrase.isNull() && visited.insert(phrase.getAddress()).second) {
        if (const auto found = trace.metadata.find(phrase.getAddress()); found != trace.metadata.end()) {
          if ((found->second.flags & DocsPresent) != 0)
            return {true, found->second.docs.empty() ? 0 : phrase.getAddress()};
        }
        if (!phrase.containsPrototype()) break;
        phrase = phrase.getPrototype();
      }
      return {};
    }

    lexicon::Phrase phraseAt(TraceState &trace, Size address) {
      if (address == 0 || address >= trace.context->lexicon.memoryUsed()) return lexicon::Phrase(&trace.context->lexicon);
      return lexicon::Phrase(&trace.context->lexicon, address).load();
    }

    void appendStyle(TraceState &trace, std::size_t startByte, std::size_t endByte,
                     std::string_view color, std::string_view kind, std::string_view docs = {},
                     std::string_view ownerKey = {}, std::uint64_t group = 0) {
      if (startByte >= endByte || endByte > trace.source.size()) return;
      Span span;
      span.start = characterOffset(trace, startByte);
      span.end = characterOffset(trace, endByte);
      span.color = std::string(color);
      span.kind = std::string(kind);
      span.docs = std::string(docs);
      span.ownerKey = std::string(ownerKey);
      span.group = group;
      span.hasColor = !color.empty();
      trace.spans.push_back(std::move(span));
    }

    bool identifierCharacter(unsigned char value) {
      return std::isalnum(value) || value == '_';
    }

    bool lexicalBoundary(std::string_view source, std::size_t begin, std::string_view key) {
      if (key.empty() || begin + key.size() > source.size()) return false;
      if (identifierCharacter(static_cast<unsigned char>(key.front())) && begin != 0 &&
          identifierCharacter(static_cast<unsigned char>(source[begin - 1])))
        return false;
      const std::size_t end = begin + key.size();
      if (identifierCharacter(static_cast<unsigned char>(key.back())) && end < source.size() &&
          identifierCharacter(static_cast<unsigned char>(source[end])))
        return false;
      return true;
    }

    struct LexicalPhraseStyle {
      std::string key;
      SemanticMetadata metadata;
      Size address = 0;
    };

    std::vector<LexicalPhraseStyle> lexicalPhraseStyles(TraceState &trace) {
      std::unordered_map<std::string, LexicalPhraseStyle> unique;
      for (const auto &[address, _] : trace.metadata) {
        lexicon::Phrase phrase = phraseAt(trace, address);
        if (phrase.isNull()) continue;
        std::string key = phrase.getKey();
        if (key.empty() || key.front() == '\0') continue;
        SemanticMetadata metadata = resolved(trace.metadata, phrase);
        if ((!metadata.hasColor || metadata.color.empty()) && (!metadata.hasDocs || metadata.docs.empty())) continue;
        auto found = unique.find(key);
        // Assignment evaluates the value before unique[key]. Moving key into
        // that value would put every phrase under the same moved-from key.
        if (found == unique.end() || found->second.address < address)
          unique[key] = {key, std::move(metadata), address};
      }
      std::vector<LexicalPhraseStyle> result;
      result.reserve(unique.size());
      for (auto &[_, value] : unique) result.push_back(std::move(value));
      std::sort(result.begin(), result.end(), [](const LexicalPhraseStyle &left, const LexicalPhraseStyle &right) {
        if (left.key.size() != right.key.size()) return left.key.size() > right.key.size();
        return left.key < right.key;
      });
      return result;
    }

    struct LexicalBaselineCatalog {
      std::vector<LexicalPhraseStyle> phrases;
      std::array<std::vector<std::size_t>, 256> phraseBuckets;
      std::unordered_set<std::string> typeNames;
      std::unordered_set<std::string> functionNames;
    };

    LexicalBaselineCatalog buildLexicalBaselineCatalog(TraceState &trace) {
      LexicalBaselineCatalog result;
      result.phrases = lexicalPhraseStyles(trace);
      for (std::size_t index = 0; index < result.phrases.size(); ++index) {
        const LexicalPhraseStyle &phrase = result.phrases[index];
        if (!phrase.key.empty())
          result.phraseBuckets[static_cast<unsigned char>(phrase.key.front())].push_back(index);
      }
      try {
        compiler::LanguageState language = trace.context->language();
        for (const compiler::TypeDescriptor &type : language.types.types())
          if (!type.name.empty()) result.typeNames.insert(type.name);
        for (const compiler::TypedFunction &function : language.functions())
          if (!function.name.empty()) result.functionNames.insert(function.name);
      } catch (...) {
        // Phrase metadata and literal/comment highlighting remain useful even
        // for a deliberately tiny host that has no typed-language registry.
      }
      return result;
    }

    void recordLexicalBaseline(TraceState &trace, const LexicalBaselineCatalog &catalog) {
      const std::string_view source(trace.source);
      std::size_t cursor = 0;
      while (cursor < source.size()) {
        const unsigned char first = static_cast<unsigned char>(source[cursor]);

        if (source.substr(cursor).starts_with("//")) {
          const std::size_t begin = cursor;
          cursor += 2;
          while (cursor < source.size() && source[cursor] != '\n') ++cursor;
          appendStyle(trace, begin, cursor, "#6A9955", "comment");
          continue;
        }
        if (source.substr(cursor).starts_with("/*")) {
          const std::size_t begin = cursor;
          cursor += 2;
          while (cursor + 1 < source.size() && !source.substr(cursor).starts_with("*/")) ++cursor;
          if (cursor + 1 < source.size()) cursor += 2;
          else cursor = source.size();
          appendStyle(trace, begin, cursor, "#6A9955", "comment");
          continue;
        }
        if (source[cursor] == '"') {
          const std::size_t begin = cursor++;
          bool escaped = false;
          while (cursor < source.size()) {
            const char value = source[cursor++];
            if (escaped) { escaped = false; continue; }
            if (value == '\\') { escaped = true; continue; }
            if (value == '"') break;
          }
          appendStyle(trace, begin, cursor, "#CE9178", "string");
          continue;
        }

        bool phraseMatched = false;
        for (const std::size_t candidateIndex : catalog.phraseBuckets[first]) {
          const LexicalPhraseStyle &candidate = catalog.phrases[candidateIndex];
          if (candidate.key.size() > source.size() - cursor || source.compare(cursor, candidate.key.size(), candidate.key) != 0 ||
              !lexicalBoundary(source, cursor, candidate.key))
            continue;
          const SemanticMetadata &metadata = candidate.metadata;
          appendStyle(trace, cursor, cursor + candidate.key.size(),
                      metadata.hasColor ? std::string_view(metadata.color) : std::string_view{},
                      metadata.hasKind ? std::string_view(metadata.kind) : std::string_view{},
                      metadata.hasDocs ? std::string_view(metadata.docs) : std::string_view{}, candidate.key);
          cursor += candidate.key.size();
          phraseMatched = true;
          break;
        }
        if (phraseMatched) continue;

        if (std::isdigit(first)) {
          const std::size_t begin = cursor++;
          while (cursor < source.size()) {
            const unsigned char value = static_cast<unsigned char>(source[cursor]);
            if (!std::isalnum(value) && value != '_' && value != '.') break;
            ++cursor;
          }
          appendStyle(trace, begin, cursor, "#B5CEA8", "number");
          continue;
        }

        if (std::isalpha(first) || first == '_') {
          const std::size_t begin = cursor++;
          while (cursor < source.size()) {
            const unsigned char value = static_cast<unsigned char>(source[cursor]);
            if (std::isalnum(value) || value == '_') { ++cursor; continue; }
            if (value == ':' && cursor + 1 < source.size() && source[cursor + 1] != ':' &&
                (std::isalpha(static_cast<unsigned char>(source[cursor + 1])) || source[cursor + 1] == '_')) {
              ++cursor;
              continue;
            }
            break;
          }
          const std::string_view name = source.substr(begin, cursor - begin);
          const bool type = catalog.typeNames.contains(std::string(name));
          const bool function = !type && catalog.functionNames.contains(std::string(name));
          if (type) appendStyle(trace, begin, cursor, "#4EC9B0", "type");
          else if (function) appendStyle(trace, begin, cursor, "#DCDCAA", "function");
          else appendStyle(trace, begin, cursor, "#9CDCFE", "identifier");
          continue;
        }

        ++cursor;
      }
    }
    struct ConsoleHighlightState {
      TraceState trace;
      LexicalBaselineCatalog palette;
    };
  } // namespace

  Semantic::ConsoleHighlighter::ConsoleHighlighter(context::Context &context) {
    auto state = std::make_unique<ConsoleHighlightState>();
    state->trace.context = &context;
    state->trace.metadata = catalog(context);
    state->palette = buildLexicalBaselineCatalog(state->trace);
    for (auto &phrase : state->palette.phrases) {
      phrase.metadata.docs.clear();
      phrase.metadata.hasDocs = false;
    }
    // The palette owns strings and colors, so no phrase pointers or lookup
    // maps are needed while typing (or after a request replaces the lexicon).
    state->trace.metadata.clear();
    state_ = state.release();
  }

  Semantic::ConsoleHighlighter::~ConsoleHighlighter() {
    delete static_cast<ConsoleHighlightState *>(state_);
  }

  std::string Semantic::ConsoleHighlighter::highlight(std::string_view source) {
    auto &state = *static_cast<ConsoleHighlightState *>(state_);
    auto &trace = state.trace;
    trace.source.assign(source);
    trace.spans.clear();
    trace.characterOffsets.resize(source.size() + 1);
    std::size_t characters = 0;
    for (std::size_t index = 0; index < source.size(); ++index) {
      trace.characterOffsets[index] = characters;
      if ((static_cast<unsigned char>(source[index]) & 0xc0) != 0x80) ++characters;
    }
    trace.characterOffsets[source.size()] = characters;
    recordLexicalBaseline(trace, state.palette);
    std::ostringstream output;
    // Console rendering consumes colors only. Do not serialize documentation,
    // phrase paths or navigation facts on the per-keystroke transport.
    for (const auto &span : trace.spans)
      if (!span.color.empty())
        output << "S\t" << span.start << '\t' << span.end << "\t0\t" << hex(span.color) << "\t\t\t\n";
    return output.str();
  }

  void Semantic::setKind(context::Context &context, lexicon::Phrase phrase, std::string value) {
    Patch patch;
    patch.kind = true;
    patch.kindValue = std::move(value);
    write(context, phrase, std::move(patch));
  }

  void Semantic::setColor(context::Context &context, lexicon::Phrase phrase, std::string value) {
    Patch patch;
    patch.color = true;
    patch.colorValue = std::move(value);
    write(context, phrase, std::move(patch));
  }

  void Semantic::setDocs(context::Context &context, lexicon::Phrase phrase, std::string value) {
    Patch patch;
    patch.docs = true;
    patch.docsValue = std::move(value);
    write(context, phrase, std::move(patch));
  }

  SemanticMetadata Semantic::resolve(context::Context &context, lexicon::Phrase phrase) {
    if (currentTrace != nullptr && currentTrace->context == &context)
      return resolvedTrace(*currentTrace, phrase);
    return resolved(catalog(context), phrase);
  }

  void Semantic::markInspectionMetadataDirty(context::Context &context) {
    if (currentTrace != nullptr && currentTrace->context == &context) {
      currentTrace->metadataDirty = true;
      currentTrace->namesDirty = true;
    }
  }

  void Semantic::applyPending(context::Context &context, lexicon::Phrase phrase) {
    if (context.exec.hasPendingPhraseKind) setKind(context, phrase, context.exec.pendingPhraseKind);
    if (context.exec.hasPendingPhraseColor) setColor(context, phrase, context.exec.pendingPhraseColor);
    if (context.exec.hasPendingPhraseDocs) setDocs(context, phrase, context.exec.pendingPhraseDocs);
    if (context.exec.hasPendingPhraseHelp)
      Assistance::attach(context, phrase, lexicon::Phrase(&context.lexicon, context.exec.pendingPhraseHelp).load());
    clearPending(context);
  }

  void Semantic::clearPending(context::Context &context) {
    context.exec.pendingPhraseKind.clear();
    context.exec.pendingPhraseColor.clear();
    context.exec.pendingPhraseDocs.clear();
    context.exec.hasPendingPhraseKind = false;
    context.exec.hasPendingPhraseColor = false;
    context.exec.hasPendingPhraseDocs = false;
    context.exec.pendingPhraseHelp = 0;
    context.exec.hasPendingPhraseHelp = false;
  }

  void Semantic::stageDefinition(context::Context &context, const SourceLocation &start, const SourceLocation &end) {
    if (!active(context) || start.path.empty()) return;
    currentTrace->definitions[context.staging.stack.size()] = {start, end};
  }

  void Semantic::recordDefinition(context::Context &context, lexicon::Phrase phrase) {
    if (!active(context)) return;
    auto &definitions = currentTrace->definitions;
    const auto found = definitions.find(context.staging.stack.size());
    if (found == definitions.end()) return;
    record(context, phrase, found->second.first, found->second.second);
    definitions.erase(found);
  }

  Semantic::InspectionScope::InspectionScope(context::Context &context, std::string_view source, std::string_view path) {
    auto *state = new TraceState;
    state->context = &context;
    state->source = std::string(source);
    state->path = path.empty() ? "<ide>" : std::string(path);
    state->lineStarts.push_back(0);
    state->characterOffsets.resize(state->source.size() + 1);
    std::size_t characters = 0;
    for (std::size_t cursor = 0; cursor < state->source.size(); ++cursor) {
      state->characterOffsets[cursor] = characters;
      const unsigned char value = static_cast<unsigned char>(state->source[cursor]);
      if ((value & 0xc0u) != 0x80u) ++characters;
      if (value == '\n') state->lineStarts.push_back(cursor + 1);
    }
    state->characterOffsets[state->source.size()] = characters;
    state->metadata = catalog(context);
    state->names = phrasePaths(context);
    // Source grammars legitimately use empty transition phrases, so the budget
    // is deliberately generous and scales with the inspected buffer.  It is a
    // deterministic safety bound, not a debounce or wall-clock timeout.
    state->sourceStepBudget = std::max<std::size_t>(
        4096, std::min<std::size_t>(4'000'000, state->source.size() * 32 + 4096));
    recordLexicalBaseline(*state, buildLexicalBaselineCatalog(*state));
    state_ = state;
    previous_ = currentTrace;
    currentTrace = state;
  }

  Semantic::InspectionScope::~InspectionScope() {
    if (currentTrace == state_) currentTrace = static_cast<TraceState *>(previous_);
    auto *state = static_cast<TraceState *>(state_);
    delete state;
  }

  std::string Semantic::InspectionScope::encode(std::string_view diagnostic) const {
    auto &state = *static_cast<TraceState *>(state_);
    std::vector<Span> spans = state.spans;
    // Record identities while parsing, then resolve all metadata from the final
    // elaborated state. Declarations and earlier reads follow the same rule as
    // later uses; shadowed bindings retain their own identities.
    if (state.metadataDirty) refreshTraceCatalog(state);
    std::unordered_map<Size, SemanticMetadata> phraseMetadata;
    const auto metadataFor = [&](Size address) -> const SemanticMetadata & {
      auto [entry, inserted] = phraseMetadata.try_emplace(address);
      if (inserted) entry->second = resolvedTrace(state, phraseAt(state, address));
      return entry->second;
    };
    std::uint64_t nextGroup = state.nextGroup;
    std::set<std::pair<std::size_t, std::size_t>> localRanges;
    for (Span &span : spans) {
      if (span.source == Span::Source::Lexical) continue;
      SemanticMetadata style;
      SemanticMetadata hover;
      if (span.source == Span::Source::Local) {
        const auto &local = state.locals.at(static_cast<std::size_t>(span.symbol - LocalVersionBase));
        style = hover = local.metadata;
        span.kind = "local";
        span.ownerKey = local.name;
        localRanges.emplace(span.start, span.end);
      } else {
        style = metadataFor(span.symbol);
        const DocsAnchor anchor = docsAnchor(state, phraseAt(state, span.symbol));
        const Size owner = anchor.specified ? anchor.owner : span.docsOwner;
        if (owner != span.docsOwner) span.group = owner == 0 ? 0 : nextGroup++;
        if (owner != 0) {
          hover = metadataFor(owner);
          span.ownerKey = phraseAt(state, owner).getKey();
        }
        if (hover.hasKind) span.kind = hover.kind;
      }
      span.hasColor = style.hasColor;
      span.color = style.color;
      span.docs = hover.docs;
    }

    // Lexical scopes take precedence over dictionary matches. Explicit empty
    // colors also override the fallback, rather than restoring a stale color.
    std::erase_if(spans, [&](const Span &span) {
      return span.source == Span::Source::Phrase && localRanges.contains({span.start, span.end});
    });
    std::set<std::pair<std::size_t, std::size_t>> semanticColors;
    for (const Span &span : spans)
      if (span.source != Span::Source::Lexical && span.hasColor) semanticColors.emplace(span.start, span.end);
    std::erase_if(spans, [&](const Span &span) {
      return span.source == Span::Source::Lexical && semanticColors.contains({span.start, span.end});
    });

    std::sort(spans.begin(), spans.end(), [](const Span &left, const Span &right) {
      if (left.start != right.start) return left.start < right.start;
      if (left.end != right.end) return left.end < right.end;
      if (left.group != right.group) return left.group < right.group;
      if (left.color != right.color) return left.color < right.color;
      if (left.docs != right.docs) return left.docs < right.docs;
      return left.ownerKey < right.ownerKey;
    });
    spans.erase(std::unique(spans.begin(), spans.end(), [](const Span &left, const Span &right) {
                  return left.start == right.start && left.end == right.end && left.group == right.group &&
                         left.color == right.color && left.kind == right.kind && left.docs == right.docs &&
                         left.ownerKey == right.ownerKey;
                }),
                spans.end());

    std::ostringstream output;
    for (const Span &span : spans) {
      if (span.start >= span.end || (span.color.empty() && span.docs.empty())) continue;
      output << "S\t" << span.start << '\t' << span.end << '\t' << span.group << '\t' << hex(span.color) << '\t'
             << hex(span.kind) << '\t' << hex(span.docs) << '\t' << hex(span.ownerKey) << '\n';
    }
    if (!diagnostic.empty()) output << "E\t" << hex(diagnostic) << '\n';
    return output.str();
  }

  std::string Semantic::InspectionScope::trace() const {
    auto &state = *static_cast<TraceState *>(state_);
    context::Context &context = *state.context;
    std::ostringstream output;
    // Local resolution takes precedence over a same-spelled root phrase.
    for (const std::string &match : state.localMatches) output << match;
    for (std::size_t index = 0; index < state.locals.size(); ++index) {
      const auto &local = state.locals[index];
      output << "P\t" << LocalVersionBase + index << '\t' << hex(local.name) << '\t' << hex("local") << '\t'
             << hex(local.metadata.docs) << "\t\t\t\n";
    }
    for (const std::string &match : state.matches) output << match;

    // Export compiler facts rather than interpreting source spellings. Clients
    // can implement documentation, navigation or other analyses in .rl.
    std::unordered_map<std::string, std::string> signatures;
    std::unordered_set<std::string> types;
    try {
      compiler::LanguageState language = context.language();
      for (const auto &type : language.types.types()) types.insert(type.name);
      for (const auto &function : language.functions()) {
        std::ostringstream signature;
        signature << function.name << '(';
        for (std::size_t i = 0; i < function.parameterTypes.size(); ++i) {
          if (i != 0) signature << ", ";
          signature << language.types.get(function.parameterTypes[i]).name;
        }
        if (function.signature.variadic) {
          if (!function.parameterTypes.empty()) signature << ", ";
          signature << "...";
        }
        signature << ')';
        if (function.resultType != compiler::InvalidType)
          signature << " -> " << language.types.get(function.resultType).name;
        // Keep every overload as its own catalog entry.
        if (!signatures[function.name].empty()) signatures[function.name] += '\n';
        signatures[function.name] += signature.str();
      }
    } catch (...) {
      // A minimal language may have no compiler registry.
    }
    const auto metadata = catalog(context);
    const auto names = phrasePaths(context);
    const Assistance assistance(context);
    std::unordered_map<Size, std::string> patterns;
    struct Candidate { lexicon::Phrase phrase; std::string name; std::string kind; };
    std::vector<Candidate> candidates;
    std::unordered_set<Size> visited;
    std::unordered_set<Size> exported;
    const auto exportFact = [&](lexicon::Phrase phrase) {
      const std::string name = phrasePath(names, phrase);
      const SemanticMetadata style = resolved(metadata, phrase);
      std::string kind = style.hasKind ? style.kind : "phrase";
      if (types.contains(name)) kind = "type";
      if (signatures.contains(name)) kind = "function";
      if (exported.insert(phrase.getAddress()).second) {
        const std::string prototype = phrase.containsPrototype() ? phrasePath(names, phrase.getPrototype()) : "";
        const std::string type = phrase.containsType() ? phrasePath(names, phrase.getType()) : "";
        output << "P\t" << phraseVersion(phrase) << '\t' << hex(name) << '\t' << hex(kind) << '\t' << hex(style.docs)
               << '\t' << hex(prototype) << '\t' << hex(type) << '\t' << hex(signatures[name]) << '\n';
      }
      return kind;
    };
    const auto visit = [&](lexicon::Phrase owner, const auto &self) -> void {
      if (owner.isNull() || !owner.containsSubdictionary() ||
          !visited.insert(owner.getSubdictionary().getAddress()).second)
        return;
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      for (lexicon::Dictionary node = owner.fore(populated); !node.isNull(); node = node.next(populated)) {
        lexicon::Phrase phrase = node.getPhrase();
        if (phrase.isNull()) continue;
        const std::string key = phrase.getKey();
        if (key.empty() || static_cast<unsigned char>(key.front()) < 32) continue;
        const std::string name = phrasePath(names, phrase);
        const std::string kind = exportFact(phrase);
        candidates.push_back({phrase, name, kind});
        auto descriptor = assistance.descriptor(phrase);
        auto pattern = Assistance::child(descriptor, "pattern").isNull()
                         ? SyntaxPattern::pattern(phrase) : Assistance::text(descriptor, "pattern");
        if (!descriptor.isNull() || !pattern.empty()) {
          output << "H\t" << phraseVersion(phrase) << '\t' << hex(name) << '\t' << hex(pattern);
          for (auto field : {"snippet", "example", "summary", "tags"})
            output << '\t' << hex(Assistance::text(descriptor, field));
          output << '\n';
          patterns[phrase.getAddress()] = pattern;
          auto arguments = Assistance::child(descriptor, "arguments");
          if (!arguments.isNull()) {
            for (auto argument : Assistance::children(arguments)) {
              auto dictionary = Assistance::child(argument, "dictionary");
              auto prototype = Assistance::child(argument, "prototype");
              if (!dictionary.isNull() && dictionary.containsPrototype()) dictionary = dictionary.getPrototype();
              if (!prototype.isNull() && prototype.containsPrototype()) prototype = prototype.getPrototype();
              output << "J\t" << phraseVersion(phrase) << '\t' << hex(name) << '\t' << hex(argument.getKey())
                     << '\t' << hex(resolved(metadata, argument).docs)
                     << '\t' << hex(dictionary.isNull() ? "" : phrasePath(names, dictionary))
                     << '\t' << hex(Assistance::text(argument, "kind"))
                     << '\t' << hex(prototype.isNull() ? "" : phrasePath(names, prototype)) << '\n';
            }
          }
        }
        self(phrase, self);
      }
    };
    visit(context.lexicon.phrase(), visit);
    visit(context.lookup.dictionary, visit);
    // Earlier occurrences can refer to a version hidden by a later declaration.
    // Export those exact facts as well, without adding obsolete completions.
    for (const Span &span : state.spans)
      if (span.source == Span::Source::Phrase && !exported.contains(span.symbol))
        exportFact(phraseAt(state, span.symbol));
    // Anchors come from actual phrase matches. Only the innermost matching
    // usage that reaches the cursor supplies argument expectations.
    std::size_t closest = 0;
    std::string expectations;
    for (const auto &anchor : state.anchors) {
      if (anchor.end < closest || anchor.end > state.source.size() || !patterns.contains(anchor.phrase)) continue;
      std::vector<SyntaxPattern::Expectation> expected;
      try { expected = SyntaxPattern::expect(patterns[anchor.phrase], std::string_view(state.source).substr(anchor.end)); }
      catch (...) { continue; } // Incomplete comments and edited contracts are ordinary inspection input.
      if (expected.empty()) continue;
      if (anchor.end > closest) { expectations.clear(); closest = anchor.end; }
      auto phrase = phraseAt(state, anchor.phrase);
      std::ostringstream rows;
      for (const auto &item : expected) {
        const auto insertion = SyntaxPattern::insertion(patterns[anchor.phrase], std::string_view(state.source).substr(anchor.end), item);
        rows << "X\t" << phraseVersion(phrase) << '\t' << hex(phrasePath(names, phrase)) << '\t'
             << characterOffset(state, anchor.end + item.start) << '\t' << hex(item.name) << '\t'
             << hex(item.matcher) << '\t' << hex(item.literal) << '\t' << hex(insertion) << '\n';
        if (item.name.empty()) continue;
        auto argument = Assistance::child(Assistance::child(assistance.descriptor(phrase), "arguments"), item.name);
        auto dictionary = Assistance::child(argument, "dictionary");
        auto prototype = Assistance::child(argument, "prototype");
        if (!dictionary.isNull() && dictionary.containsPrototype()) dictionary = dictionary.getPrototype();
        if (!prototype.isNull() && prototype.containsPrototype()) prototype = prototype.getPrototype();
        const auto kind = Assistance::text(argument, "kind");
        if (dictionary.isNull() && prototype.isNull() && kind.empty()) continue;
        const auto dictionaryName = dictionary.isNull() ? "" : phrasePath(names, dictionary);
        const auto prefix = dictionaryName.empty() ? "" : dictionaryName + ':';
        for (const auto &candidate : candidates) {
          if (!candidate.name.starts_with(prefix)) continue;
          const auto spelling = candidate.name.substr(prefix.size());
          if (!dictionary.isNull() && spelling.find(':') != std::string::npos) continue;
          if (!kind.empty() && candidate.kind != kind) continue;
          if (!prototype.isNull()) {
            auto ancestor = candidate.phrase;
            std::unordered_set<Size> seen;
            while (!ancestor.isNull() && seen.insert(ancestor.getAddress()).second &&
                   ancestor.getAddress() != prototype.getAddress()) {
              if (!ancestor.containsPrototype()) { ancestor = lexicon::Phrase(&context.lexicon); break; }
              ancestor = ancestor.getPrototype();
            }
            if (ancestor.isNull() || ancestor.getAddress() != prototype.getAddress()) continue;
          }
          if (!SyntaxPattern::accepts(item.matcher, spelling)) continue;
          rows << "V\t" << phraseVersion(phrase) << '\t' << hex(phrasePath(names, phrase)) << '\t' << hex(item.name)
               << '\t' << hex(candidate.name) << '\t' << hex(spelling) << '\n';
        }
      }
      expectations += rows.str();
    }
    output << expectations;
    output << "D\t" << hex(phrasePath(names, context.lookup.dictionary)) << '\t'
           << characterOffset(state, state.completionStart) << '\n';
    return output.str();
  }

  Semantic::OwnerScope::OwnerScope(context::Context &context, std::uint64_t owner, std::uint64_t group) {
    if (!active(context)) return;
    auto *state = currentTrace;
    state_ = state;
    previous_ = state->activeOwner;
    previousGroup_ = state->activeGroup;
    state->activeOwner = owner;
    if (group != 0) state->activeGroup = group;
    else if (state->lastOwner == owner) state->activeGroup = state->lastGroup;
    else if (owner == previous_) state->activeGroup = previousGroup_;
    else state->activeGroup = 0;
  }

  Semantic::OwnerScope::~OwnerScope() {
    if (state_ != nullptr) {
      auto *state = static_cast<TraceState *>(state_);
      state->activeOwner = previous_;
      state->activeGroup = previousGroup_;
    }
  }

  bool Semantic::active(context::Context &context) {
    return currentTrace != nullptr && currentTrace->context == &context;
  }

  std::uint64_t Semantic::owner(context::Context &context) {
    return active(context) ? currentTrace->activeOwner : 0;
  }

  std::uint64_t Semantic::group(context::Context &context) {
    return active(context) ? currentTrace->activeGroup : 0;
  }

  void Semantic::beginSourceStep(context::Context &context, bool rootLookup) {
    if (!active(context)) return;
    if (rootLookup) {
      currentTrace->continuationOwner = 0;
      currentTrace->continuationGroup = 0;
    }
  }

  void Semantic::sourceStep(context::Context &context) {
    if (!active(context)) return;
    TraceState &trace = *currentTrace;
    const SourceLocation location{context.source.path, context.source.line, context.source.position};
    if (auto offset = sourceOffset(trace, location)) trace.completionStart = *offset;
    ++trace.sourceSteps;
    if (trace.sourceSteps > trace.sourceStepBudget)
      THROW(, "semantic inspection exceeded the deterministic source-step budget")
  }

  std::uint64_t Semantic::local(context::Context &context, std::string name) {
    if (!active(context)) return 0;
    currentTrace->locals.push_back({std::move(name), {}});
    return LocalVersionBase + currentTrace->locals.size() - 1;
  }

  void Semantic::localMetadata(context::Context &context, std::uint64_t local, std::string_view field,
                               std::string value) {
    if (!active(context) || local < LocalVersionBase) return;
    auto &metadata = currentTrace->locals.at(static_cast<std::size_t>(local - LocalVersionBase)).metadata;
    if (field == "docs") {
      metadata.hasDocs = true;
      metadata.docs = std::move(value);
    } else if (field == "color") {
      metadata.hasColor = true;
      metadata.color = std::move(value);
    }
  }

  void Semantic::recordLocal(context::Context &context, std::uint64_t local, const SourceLocation &origin,
                             std::string_view source, std::size_t start, std::size_t end) {
    if (!active(context) || local < LocalVersionBase) return;
    TraceState &trace = *currentTrace;
    const SourceLocation from = sourceLocationAt(origin, source, start);
    const auto first = sourceOffset(trace, from);
    const auto last = sourceOffset(trace, sourceLocationAt(origin, source, end));
    if (!first || !last || *last <= *first) return;
    auto &fact = trace.locals.at(static_cast<std::size_t>(local - LocalVersionBase));
    Span span;
    span.start = characterOffset(trace, *first);
    span.end = characterOffset(trace, *last);
    span.source = Span::Source::Local;
    span.symbol = local;
    trace.spans.push_back(std::move(span));
    trace.localMatches.push_back(matchRecord(trace, *first, *last, from.line, local, fact.name));
  }

  std::uint64_t Semantic::record(context::Context &context, lexicon::Phrase phrase,
                                 const SourceLocation &start, const SourceLocation &end,
                                 std::uint64_t fallbackOwner, bool continueOwner,
                                 std::uint64_t *ownerGroup) {
    if (!active(context) || phrase.isNull()) return fallbackOwner;
    TraceState &trace = *currentTrace;
    const std::optional<std::size_t> startByte = sourceOffset(trace, start);
    const std::optional<std::size_t> endByte = sourceOffset(trace, end);
    if (!startByte || !endByte || *endByte <= *startByte) return fallbackOwner;

    // A lexical path plus its chronological version identifies the matched
    // phrase independently of arena addresses or later shadow definitions.
    if (trace.namesDirty || !trace.names.contains(phrase.getAddress())) {
      trace.names = phrasePaths(context);
      trace.namesDirty = false;
      trace.names.try_emplace(phrase.getAddress(), phrase.getKey());
    }
    trace.matches.push_back(
        matchRecord(trace, *startByte, *endByte, start.line, phraseVersion(phrase), phrasePath(trace.names, phrase)));
    trace.anchors.push_back({phrase.getAddress(), *endByte});
    const auto key = phrase.getKey();
    if (!key.empty() && std::ranges::all_of(key, [](unsigned char byte) { return std::isspace(byte); }))
      trace.completionStart = *endByte;

    Size fallback = fallbackOwner;
    std::uint64_t fallbackGroup = ownerGroup != nullptr ? *ownerGroup : 0;
    if (fallback != 0 && fallbackGroup == 0 && fallback == trace.activeOwner) fallbackGroup = trace.activeGroup;
    if (fallback == 0 && continueOwner) {
      fallback = trace.continuationOwner;
      fallbackGroup = trace.continuationGroup;
    }
    if (fallback == 0) {
      fallback = trace.activeOwner;
      fallbackGroup = trace.activeGroup;
    }

    // Restored images can introduce metadata needed to track construct ownership.
    if (trace.metadataDirty) refreshTraceCatalog(trace);
    const DocsAnchor anchor = docsAnchor(trace, phrase);
    Size selectedOwner = fallback;
    std::uint64_t selectedGroup = fallbackGroup;
    if (anchor.specified) {
      selectedOwner = anchor.owner;
      selectedGroup = selectedOwner == 0 ? 0 : trace.nextGroup++;
    }

    if (continueOwner) {
      trace.continuationOwner = selectedOwner;
      trace.continuationGroup = selectedGroup;
    }
    if (ownerGroup != nullptr) *ownerGroup = selectedGroup;
    trace.lastOwner = selectedOwner;
    trace.lastGroup = selectedGroup;

    Span span;
    span.start = characterOffset(trace, *startByte);
    span.end = characterOffset(trace, *endByte);
    span.group = selectedGroup;
    span.source = Span::Source::Phrase;
    span.symbol = phrase.getAddress();
    span.docsOwner = selectedOwner;
    trace.spans.push_back(std::move(span));
    return selectedOwner;
  }

  std::uint64_t Semantic::recordMapped(context::Context &context, lexicon::Phrase phrase,
                                       const SourceLocation &origin, std::string_view originalSource,
                                       std::size_t start, std::size_t end,
                                       std::uint64_t fallbackOwner, bool continueOwner,
                                       std::uint64_t *ownerGroup) {
    return record(context, phrase, sourceLocationAt(origin, originalSource, start),
                  sourceLocationAt(origin, originalSource, end), fallbackOwner, continueOwner, ownerGroup);
  }

} // namespace recurloop
