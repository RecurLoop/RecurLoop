#include <recurloop/EngineImage.hpp>

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <array>
#include <charconv>
#include <cctype>
#include <cstring>
#include <fstream>
#include <iterator>
#include <limits>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

namespace recurloop {
  namespace {
    constexpr std::array<std::uint8_t, 8> Magic = {'R', 'L', 'E', 'N', 'G', 0, 1, 0};
    enum class RelocationKind : std::uint8_t { Phrase, Action };

    struct Relocation {
      RelocationKind kind = RelocationKind::Phrase;
      std::size_t offset = 0;
      std::uint64_t phrase = 0;
      std::string action;
    };

    struct Record {
      std::uint64_t id = 0;
      std::uint64_t parent = 0;
      std::string key;
      std::uint64_t keyBits = 0;
      bool subdictionary = false;
      bool prototype = false;
      bool type = false;
      bool action = false;
      bool successor = false;
      bool permanent = false;
      bool rewritable = false;
      std::uint64_t prototypeId = 0;
      std::uint64_t typeId = 0;
      std::uint64_t successorId = 0;
      std::uint64_t actionImplementationId = 0;
      std::string actionName;
      std::vector<std::uint8_t> payload;
      std::vector<Relocation> relocations;
      Size sourceAddress = 0;
      Size parentAddress = 0;
      std::size_t depth = 0;
    };

    struct Snapshot {
      std::vector<Record> phrases;
    };

    class Writer {
    public:
      std::vector<std::uint8_t> bytes;

      void number(std::uint64_t value, std::size_t width) {
        for (std::size_t index = 0; index < width; ++index) bytes.push_back(value >> (index * 8));
      }
      void data(std::span<const std::uint8_t> value) {
        if (value.size() > std::numeric_limits<std::uint32_t>::max()) THROW(, "engine image field is too large")
        number(value.size(), 4);
        bytes.insert(bytes.end(), value.begin(), value.end());
      }
      void text(const std::string &value) {
        data(std::span<const std::uint8_t>(reinterpret_cast<const std::uint8_t *>(value.data()), value.size()));
      }
    };

    class Reader {
    public:
      explicit Reader(std::span<const std::uint8_t> bytes) : bytes(bytes) {}

      std::uint64_t number(std::size_t width) {
        if (cursor > bytes.size() || width > bytes.size() - cursor) THROW(, "truncated engine image")
        std::uint64_t result = 0;
        for (std::size_t index = 0; index < width; ++index) result |= std::uint64_t{bytes[cursor++]} << (index * 8);
        return result;
      }
      std::vector<std::uint8_t> data() {
        const std::size_t size = number(4);
        if (cursor > bytes.size() || size > bytes.size() - cursor) THROW(, "truncated engine image field")
        std::vector<std::uint8_t> result(bytes.begin() + cursor, bytes.begin() + cursor + size);
        cursor += size;
        return result;
      }
      std::string text() {
        const std::vector<std::uint8_t> value = data();
        return {reinterpret_cast<const char *>(value.data()), value.size()};
      }
      bool done() const {
        return cursor == bytes.size();
      }

    private:
      std::span<const std::uint8_t> bytes;
      std::size_t cursor = 0;
    };

    lexicon::Phrase exact(lexicon::Phrase dictionary, const std::string &key) {
      lexicon::Match match = dictionary.matchExact(Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length);
      return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
    }

    lexicon::Phrase exact(lexicon::Phrase dictionary, const std::string &key, Size bits) {
      lexicon::Match match = dictionary.matchExact(Byte(const_cast<char *>(key.data())), 0, bits);
      return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
    }

    Size dictionaryRoot(lexicon::Phrase phrase) {
      radix::Node node = phrase.getNode();
      while (true) {
        radix::Node parent = node.predecessor();
        if (parent.isNull()) return node.getAddress();
        node = parent;
      }
    }

    std::vector<Record> capture(context::Context &context, Size since = 0) {
      lexicon::Phrase root = context.lexicon.phrase();
      if (root.isNull()) THROW(, "cannot export an empty lexicon")

      std::unordered_map<Size, lexicon::Phrase> all;
      std::unordered_map<Size, Size> dictionaryOwners;
      for (radix::Item item = context.lexicon.lastItem(); !item.isNull(); item = item.earlier()) {
        lexicon::Phrase phrase(item);
        phrase.load();
        all.emplace(phrase.getAddress(), phrase);
        if (phrase.containsSubdictionary())
          dictionaryOwners[phrase.getSubdictionary().getAddress()] = phrase.getAddress();
      }

      struct Pending {
        lexicon::Phrase phrase;
        Size parent = 0;
        Size address = 0;
        std::string key;
        Size keyBits = 0;
        std::size_t depth = 0;
      };
      std::vector<Pending> pending;
      std::unordered_map<Size, std::size_t> indices;

      lexicon::Phrase types = exact(root, "phrase-types");
      lexicon::Phrase dataType = types.isNull() ? lexicon::Phrase(&context.lexicon) : exact(types, "data");
      const std::unordered_set<Size> behaviorTypes =
          types.isNull()
              ? std::unordered_set<Size>{}
              : std::unordered_set<Size>{exact(types, "elaborate").getAddress(), exact(types, "callable").getAddress(),
                                         exact(types, "scoped-callable").getAddress()};

      const auto payload = [](lexicon::Phrase phrase) {
        std::vector<std::uint8_t> result(phrase.payloadSize());
        if (!result.empty()) std::memcpy(result.data(), phrase.content(0, result.size()).toPtr(), result.size());
        return result;
      };

      const auto payloadTargets = [&](lexicon::Phrase phrase) {
        const std::vector<std::uint8_t> bytes = payload(phrase);
        std::vector<Size> result;
        if (bytes.size() >= sizeof(compiler::LanguageBinding)) {
          compiler::LanguageBinding binding;
          std::memcpy(&binding, bytes.data() + bytes.size() - sizeof(binding), sizeof(binding));
          if (binding.magic == compiler::LanguageBinding::Magic) result.push_back(binding.language);
        }
        if (phrase.getAddress() == dataType.getAddress()) {
          const std::size_t base = sizeof(lexicon::phrase::type::Behavior);
          if (bytes.size() < base + sizeof(lexicon::phrase::type::Core))
            THROW(, "phrase data type has a truncated core payload")
          lexicon::phrase::type::Core core;
          std::memcpy(&core, bytes.data() + base, sizeof(core));
          result.insert(result.end(), {core.elaborate, core.callable, core.scopedCallable});
        } else if (behaviorTypes.contains(phrase.getAddress()) &&
                   bytes.size() < sizeof(lexicon::phrase::type::Behavior)) {
          THROW(, "phrase behavior type has a truncated payload")
        }
        return result;
      };

      const auto add = [&](lexicon::Phrase phrase, Size parent) {
        if (phrase.isNull() || indices.contains(phrase.getAddress())) return false;
        indices.emplace(phrase.getAddress(), pending.size());
        pending.push_back({phrase, parent, phrase.getAddress(), phrase.getKey(), phrase.getNode().keyBits(), 0});
        return true;
      };

      const auto ensure = [&](Size address, auto &self) -> void {
        if (address == 0 || indices.contains(address)) return;
        auto found = all.find(address);
        if (found == all.end()) {
          for (radix::Item item = context.lexicon.lastItem(); !item.isNull(); item = item.earlier()) {
            lexicon::Phrase phrase(item);
            phrase.load();
            if (phrase.getAddress() == address) {
              found = all.emplace(address, phrase).first;
              break;
            }
          }
        }
        if (found == all.end()) THROW(, "phrase graph references an item outside the lexicon")
        lexicon::Phrase phrase = found->second;
        const Size rootAddress = dictionaryRoot(phrase);
        const auto owner = dictionaryOwners.find(rootAddress);
        if (owner == dictionaryOwners.end()) THROW(, "cannot determine the owner of a referenced phrase")
        self(owner->second, self);
        add(phrase, owner->second);
      };

      add(root, 0);
      for (std::size_t cursor = 0; cursor < pending.size(); ++cursor) {
        lexicon::Phrase phrase = pending[cursor].phrase;
        if (!phrase.isSerializable()) THROW(, "engine image cannot serialize phrase '" << phrase.getKeyEscaped() << "'")
        if (phrase.containsSubdictionary()) {
          auto filter = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
          for (lexicon::Dictionary child = phrase.fore(filter); !child.isNull(); child = child.next(filter)) {
            lexicon::Phrase candidate = child.getPhrase();
            if (!candidate.isSerializable()) continue;
            if (since == 0 || candidate.getAddress() >= since) add(candidate, phrase.getAddress());
          }
        }
        if (phrase.containsPrototype()) ensure(phrase.getPrototype().getAddress(), ensure);
        if (phrase.containsType()) ensure(phrase.getType().getAddress(), ensure);
        if (phrase.containsSuccessor()) ensure(phrase.getSuccessor().getAddress(), ensure);
        if (phrase.containsAction()) ensure(phrase.getActionImplementation().getAddress(), ensure);
        for (Size target : payloadTargets(phrase)) ensure(target, ensure);
      }

      std::unordered_map<Size, std::size_t> depths{{root.getAddress(), 0}};
      const auto depth = [&](Size address, auto &self) -> std::size_t {
        if (const auto found = depths.find(address); found != depths.end()) return found->second;
        const Pending &item = pending.at(indices.at(address));
        const std::size_t value = self(item.parent, self) + 1;
        depths.emplace(address, value);
        return value;
      };
      for (Pending &item : pending) item.depth = depth(item.address, depth);

      // Assign children by their already-canonical parent rank. Raw radix
      // addresses change after a restore and therefore cannot participate in
      // ordering phrases that belong to different dictionaries.
      std::vector<Pending> ordered;
      ordered.reserve(pending.size());
      std::unordered_map<Size, std::size_t> ranks{{root.getAddress(), 0}};
      const std::size_t maximumDepth =
          std::max_element(pending.begin(), pending.end(), [](const auto &left, const auto &right) {
            return left.depth < right.depth;
          })->depth;
      for (std::size_t currentDepth = 0; currentDepth <= maximumDepth; ++currentDepth) {
        std::vector<Pending> layer;
        for (const Pending &item : pending)
          if (item.depth == currentDepth) layer.push_back(item);
        std::sort(layer.begin(), layer.end(), [&](const Pending &left, const Pending &right) {
          const std::size_t leftParent = left.parent == 0 ? 0 : ranks.at(left.parent);
          const std::size_t rightParent = right.parent == 0 ? 0 : ranks.at(right.parent);
          if (leftParent != rightParent) return leftParent < rightParent;
          if (left.key != right.key) return left.key < right.key;
          if (left.keyBits != right.keyBits) return left.keyBits < right.keyBits;
          return left.address < right.address;
        });
        for (Pending &item : layer) {
          ranks[item.address] = ordered.size();
          ordered.push_back(std::move(item));
        }
      }
      pending = std::move(ordered);

      std::unordered_map<Size, std::uint64_t> ids;
      for (std::size_t index = 0; index < pending.size(); ++index) ids[pending[index].address] = index + 1;

      std::vector<Record> records;
      records.reserve(pending.size());
      for (std::size_t index = 0; index < pending.size(); ++index) {
        lexicon::Phrase phrase = pending[index].phrase;
        Record record;
        record.id = index + 1;
        record.parent = pending[index].parent == 0 ? 0 : ids.at(pending[index].parent);
        record.key = phrase.getKey();
        record.keyBits = phrase.getNode().keyBits();
        if (record.keyBits % Byte::length != 0 && !record.key.empty())
          record.key.back() &= static_cast<char>(0xffu << (Byte::length - record.keyBits % Byte::length));
        record.subdictionary = phrase.containsSubdictionary();
        record.prototype = phrase.containsPrototype();
        record.type = phrase.containsType();
        record.action = phrase.containsAction();
        record.successor = phrase.containsSuccessor();
        record.permanent = phrase.isPermanent();
        record.rewritable = phrase.isRewritable();
        record.prototypeId =
            record.prototype && !phrase.getPrototype().isNull() ? ids.at(phrase.getPrototype().getAddress()) : 0;
        record.typeId = record.type && !phrase.getType().isNull() ? ids.at(phrase.getType().getAddress()) : 0;
        record.successorId =
            record.successor && !phrase.getSuccessor().isNull() ? ids.at(phrase.getSuccessor().getAddress()) : 0;
        if (record.action) {
          record.actionName = context.actions().name(phrase.getAction());
          lexicon::Phrase implementation = phrase.getActionImplementation();
          if (!implementation.isNull()) record.actionImplementationId = ids.at(implementation.getAddress());
        }
        record.payload = payload(phrase);
        record.sourceAddress = pending[index].address;
        record.parentAddress = pending[index].parent;
        record.depth = pending[index].depth;
        records.push_back(std::move(record));
      }

      for (Record &record : records) {
        if (record.payload.size() >= sizeof(compiler::LanguageBinding)) {
          const std::size_t bindingOffset = record.payload.size() - sizeof(compiler::LanguageBinding);
          compiler::LanguageBinding binding;
          std::memcpy(&binding, record.payload.data() + bindingOffset, sizeof(binding));
          if (binding.magic == compiler::LanguageBinding::Magic) {
            const auto target = ids.find(binding.language);
            if (target == ids.end()) THROW(, "language binding references a phrase outside the engine image")
            const std::size_t addressOffset = bindingOffset + offsetof(compiler::LanguageBinding, language);
            record.relocations.push_back({RelocationKind::Phrase, addressOffset, target->second, {}});
            std::memset(record.payload.data() + addressOffset, 0, sizeof(Size));
          }
        }
        if (record.sourceAddress == dataType.getAddress()) {
          const std::size_t base = sizeof(lexicon::phrase::type::Behavior);
          if (record.payload.size() < base + sizeof(lexicon::phrase::type::Core))
            THROW(, "phrase data type has a truncated core payload")
          lexicon::phrase::type::Core core;
          std::memcpy(&core, record.payload.data() + base, sizeof(core));
          const Size targets[] = {core.elaborate, core.callable, core.scopedCallable};
          for (std::size_t field = 0; field < 3; ++field) {
            const std::size_t offset = base + field * sizeof(Size);
            record.relocations.push_back(
                {RelocationKind::Phrase, offset, targets[field] == 0 ? 0 : ids.at(targets[field]), {}});
            std::memset(record.payload.data() + offset, 0, sizeof(Size));
          }
        } else if (behaviorTypes.contains(record.sourceAddress)) {
          if (record.payload.size() < sizeof(lexicon::phrase::type::Behavior))
            THROW(, "phrase behavior type has a truncated payload")
          lexicon::phrase::type::Behavior behavior;
          std::memcpy(&behavior, record.payload.data(), sizeof(behavior));
          const lexicon::Phrase::Action actions[] = {behavior.elaborate, behavior.invoke};
          for (std::size_t field = 0; field < 2; ++field) {
            const std::size_t offset = field * sizeof(lexicon::Phrase::Action);
            record.relocations.push_back({RelocationKind::Action, offset, 0, context.actions().name(actions[field])});
            std::memset(record.payload.data() + offset, 0, sizeof(lexicon::Phrase::Action));
          }
        }
      }
      return records;
    }

    std::vector<std::uint8_t> encodeRecords(const std::vector<Record> &records) {
      Writer writer;
      writer.bytes.insert(writer.bytes.end(), Magic.begin(), Magic.end());
      writer.number(EngineImage::Version, 4);
      writer.number(sizeof(Size), 1);
      writer.number(sizeof(void *), 1);
      writer.number(records.size(), 8);
      for (const Record &record : records) {
        writer.number(record.id, 8);
        writer.number(record.parent, 8);
        writer.text(record.key);
        writer.number(record.keyBits, 8);
        std::uint8_t flags = record.subdictionary ? 1 : 0;
        flags |= record.prototype ? 2 : 0;
        flags |= record.type ? 4 : 0;
        flags |= record.action ? 8 : 0;
        flags |= record.successor ? 16 : 0;
        flags |= record.permanent ? 32 : 0;
        flags |= record.rewritable ? 64 : 0;
        writer.number(flags, 1);
        writer.number(record.prototypeId, 8);
        writer.number(record.typeId, 8);
        writer.number(record.successorId, 8);
        writer.number(record.actionImplementationId, 8);
        writer.text(record.actionName);
        writer.data(record.payload);
        writer.number(record.relocations.size(), 4);
        for (const Relocation &relocation : record.relocations) {
          writer.number(static_cast<std::uint8_t>(relocation.kind), 1);
          writer.number(relocation.offset, 8);
          writer.number(relocation.phrase, 8);
          writer.text(relocation.action);
        }
      }
      // Kept as a zero count in the version-6 wire format. Source routines are
      // deliberately unsupported now that every function is compiled.
      writer.number(0, 4);
      return writer.bytes;
    }

    Snapshot decodeRecords(context::Context &context, std::span<const std::uint8_t> bytes) {
      Reader reader(bytes);
      for (std::uint8_t expected : Magic)
        if (reader.number(1) != expected) THROW(, "invalid engine image magic")
      if (reader.number(4) != EngineImage::Version) THROW(, "unsupported engine image version")
      if (reader.number(1) != sizeof(Size) || reader.number(1) != sizeof(void *))
        THROW(, "engine image ABI does not match this runtime")
      const std::size_t count = reader.number(8);
      if (count == 0) THROW(, "engine image contains no root phrase")
      std::vector<Record> records;
      records.reserve(count);
      std::unordered_set<std::uint64_t> ids;
      std::unordered_map<std::uint64_t, bool> dictionaries;
      for (std::size_t index = 0; index < count; ++index) {
        Record record;
        record.id = reader.number(8);
        record.parent = reader.number(8);
        record.key = reader.text();
        record.keyBits = reader.number(8);
        if (record.keyBits > record.key.size() * Byte::length || record.key.size() != Bit::bytes(record.keyBits))
          THROW(, "engine image phrase key size does not match its bit length")
        if (record.keyBits % Byte::length != 0 && (static_cast<std::uint8_t>(record.key.back()) &
                                                   ((1u << (Byte::length - record.keyBits % Byte::length)) - 1)) != 0)
          THROW(, "engine image phrase key has non-zero padding bits")
        const std::uint8_t flags = reader.number(1);
        if ((flags & ~std::uint8_t{127}) != 0) THROW(, "engine image phrase has unknown flags")
        record.subdictionary = flags & 1;
        record.prototype = flags & 2;
        record.type = flags & 4;
        record.action = flags & 8;
        record.successor = flags & 16;
        record.permanent = flags & 32;
        record.rewritable = flags & 64;
        record.prototypeId = reader.number(8);
        record.typeId = reader.number(8);
        record.successorId = reader.number(8);
        record.actionImplementationId = reader.number(8);
        record.actionName = reader.text();
        record.payload = reader.data();
        const std::size_t relocations = reader.number(4);
        record.relocations.reserve(relocations);
        for (std::size_t relocationIndex = 0; relocationIndex < relocations; ++relocationIndex) {
          Relocation relocation;
          relocation.kind = static_cast<RelocationKind>(reader.number(1));
          if (relocation.kind != RelocationKind::Phrase && relocation.kind != RelocationKind::Action)
            THROW(, "engine image contains an unknown relocation kind")
          relocation.offset = reader.number(8);
          relocation.phrase = reader.number(8);
          relocation.action = reader.text();
          const std::size_t width =
              relocation.kind == RelocationKind::Phrase ? sizeof(Size) : sizeof(lexicon::Phrase::Action);
          if (relocation.offset > record.payload.size() || width > record.payload.size() - relocation.offset)
            THROW(, "engine image relocation points outside phrase payload")
          if (relocation.kind == RelocationKind::Action && !relocation.action.empty())
            (void)context.actions().get(relocation.action);
          record.relocations.push_back(std::move(relocation));
        }
        if (record.id == 0 || !ids.insert(record.id).second) THROW(, "engine image contains a duplicate phrase id")
        dictionaries.emplace(record.id, record.subdictionary);
        if (record.action && !record.actionName.empty()) (void)context.actions().get(record.actionName);
        records.push_back(std::move(record));
      }
      const std::size_t routineCount = reader.number(4);
      if (routineCount != 0) THROW(, "engine image contains unsupported source routines")
      if (!reader.done()) THROW(, "engine image contains trailing bytes")
      if (records.front().parent != 0) THROW(, "engine image root phrase has a parent")
      std::unordered_set<std::uint64_t> available;
      std::size_t roots = 0;
      for (const Record &record : records) {
        const auto valid = [&](std::uint64_t id) { return id == 0 || ids.contains(id); };
        if (!valid(record.parent) || !valid(record.prototypeId) || !valid(record.typeId) ||
            !valid(record.successorId) || !valid(record.actionImplementationId))
          THROW(, "engine image contains an unresolved phrase id")
        if ((!record.prototype && record.prototypeId != 0) || (!record.type && record.typeId != 0) ||
            (!record.successor && record.successorId != 0))
          THROW(, "engine image assigns a reference to a phrase without the corresponding slot")
        if (!record.action && (!record.actionName.empty() || record.actionImplementationId != 0))
          THROW(, "engine image assigns an action to a phrase without an action slot")
        if (record.parent == 0) {
          if (++roots != 1) THROW(, "engine image contains more than one root phrase")
        } else {
          if (!available.contains(record.parent)) THROW(, "engine image phrase is declared before its dictionary owner")
          if (!dictionaries.at(record.parent)) THROW(, "engine image phrase owner has no subdictionary")
        }
        for (const Relocation &relocation : record.relocations)
          if (relocation.kind == RelocationKind::Phrase) {
            if (!relocation.action.empty()) THROW(, "engine image phrase relocation contains an action name")
            if (!valid(relocation.phrase)) THROW(, "engine image contains an unresolved payload phrase id")
          } else if (relocation.phrase != 0) {
            THROW(, "engine image action relocation contains a phrase id")
          }
        available.insert(record.id);
      }
      return {std::move(records)};
    }

    std::string quote(std::string_view value) {
      static constexpr char digits[] = "0123456789abcdef";
      std::string result = "\"";
      for (unsigned char character : value) {
        switch (character) {
        case '\\': result += "\\\\"; break;
        case '"': result += "\\\""; break;
        case '\n': result += "\\n"; break;
        case '\r': result += "\\r"; break;
        case '\t': result += "\\t"; break;
        case '\0': result += "\\0"; break;
        default:
          if (character >= 0x20 && character != 0x7f) {
            result.push_back(static_cast<char>(character));
          } else {
            result += "\\x";
            result.push_back(digits[character >> 4]);
            result.push_back(digits[character & 15]);
          }
        }
      }
      result.push_back('"');
      return result;
    }

    std::string hexadecimal(std::span<const std::uint8_t> bytes) {
      static constexpr char digits[] = "0123456789abcdef";
      std::string result;
      result.reserve(bytes.size() * 2);
      for (std::uint8_t byte : bytes) {
        result.push_back(digits[byte >> 4]);
        result.push_back(digits[byte & 15]);
      }
      return result;
    }

    unsigned nibble(char character) {
      if (character >= '0' && character <= '9') return character - '0';
      if (character >= 'a' && character <= 'f') return character - 'a' + 10;
      if (character >= 'A' && character <= 'F') return character - 'A' + 10;
      THROW(, "engine manifest contains an invalid hexadecimal digit")
    }

    std::vector<std::uint8_t> unhex(std::string_view text) {
      if (text.size() % 2 != 0) THROW(, "engine manifest payload has an odd number of hexadecimal digits")
      std::vector<std::uint8_t> result(text.size() / 2);
      for (std::size_t index = 0; index < result.size(); ++index)
        result[index] = static_cast<std::uint8_t>((nibble(text[index * 2]) << 4) | nibble(text[index * 2 + 1]));
      return result;
    }

    std::vector<std::string> tokens(std::string_view line, std::size_t lineNumber) {
      std::vector<std::string> result;
      for (std::size_t cursor = 0; cursor < line.size();) {
        while (cursor < line.size() && std::isspace(static_cast<unsigned char>(line[cursor]))) ++cursor;
        if (cursor == line.size() || line.substr(cursor).starts_with("//")) break;
        if (line[cursor] != '"') {
          const std::size_t begin = cursor;
          while (cursor < line.size() && !std::isspace(static_cast<unsigned char>(line[cursor]))) ++cursor;
          result.emplace_back(line.substr(begin, cursor - begin));
          continue;
        }
        ++cursor;
        std::string value;
        bool closed = false;
        while (cursor < line.size()) {
          char character = line[cursor++];
          if (character == '"') {
            closed = true;
            break;
          }
          if (character != '\\') {
            value.push_back(character);
            continue;
          }
          if (cursor == line.size()) THROW(, "engine manifest line " << lineNumber << ": unterminated escape")
          character = line[cursor++];
          switch (character) {
          case '\\': value.push_back('\\'); break;
          case '"': value.push_back('"'); break;
          case 'n': value.push_back('\n'); break;
          case 'r': value.push_back('\r'); break;
          case 't': value.push_back('\t'); break;
          case '0': value.push_back('\0'); break;
          case 'x':
            if (cursor + 2 > line.size()) THROW(, "engine manifest line " << lineNumber << ": truncated hex escape")
            value.push_back(static_cast<char>((nibble(line[cursor]) << 4) | nibble(line[cursor + 1])));
            cursor += 2;
            break;
          default: THROW(, "engine manifest line " << lineNumber << ": unknown escape")
          }
        }
        if (!closed) THROW(, "engine manifest line " << lineNumber << ": unterminated string")
        result.push_back(std::move(value));
      }
      return result;
    }

    std::uint64_t integer(const std::string &token, std::size_t line) {
      std::uint64_t result = 0;
      const auto [end, error] = std::from_chars(token.data(), token.data() + token.size(), result);
      if (error != std::errc() || end != token.data() + token.size())
        THROW(, "engine manifest line " << line << ": invalid integer '" << token << "'")
      return result;
    }

    Snapshot parseManifest(context::Context &context, std::string_view manifest) {
      std::vector<Record> records;
      std::unordered_map<std::uint64_t, std::size_t> indices;
      std::istringstream input{std::string(manifest)};
      std::string line;
      for (std::size_t lineNumber = 1; std::getline(input, line); ++lineNumber) {
        const std::vector<std::string> fields = tokens(line, lineNumber);
        if (fields.empty()) continue;
        if (fields[0] == "phrase") {
          if (fields.size() != 22 || fields[2] != "parent" || fields[4] != "key" || fields[6] != "bits" ||
              fields[8] != "flags" || fields[10] != "prototype" || fields[12] != "type" || fields[14] != "successor" ||
              fields[16] != "action" || fields[18] != "action-target" || fields[20] != "payload")
            THROW(, "engine manifest line " << lineNumber << ": malformed phrase declaration")
          Record record;
          record.id = integer(fields[1], lineNumber);
          record.parent = integer(fields[3], lineNumber);
          record.key = fields[5];
          record.keyBits = integer(fields[7], lineNumber);
          const std::uint64_t flags = integer(fields[9], lineNumber);
          if (flags > 127) THROW(, "engine manifest line " << lineNumber << ": unknown phrase flags")
          record.subdictionary = flags & 1;
          record.prototype = flags & 2;
          record.type = flags & 4;
          record.action = flags & 8;
          record.successor = flags & 16;
          record.permanent = flags & 32;
          record.rewritable = flags & 64;
          record.prototypeId = integer(fields[11], lineNumber);
          record.typeId = integer(fields[13], lineNumber);
          record.successorId = integer(fields[15], lineNumber);
          record.actionName = fields[17];
          record.actionImplementationId = integer(fields[19], lineNumber);
          record.payload = unhex(fields[21]);
          if (!indices.emplace(record.id, records.size()).second)
            THROW(, "engine manifest line " << lineNumber << ": duplicate phrase id")
          records.push_back(std::move(record));
        } else if (fields[0] == "relocate") {
          if (fields.size() != 5) THROW(, "engine manifest line " << lineNumber << ": malformed relocation")
          const std::uint64_t owner = integer(fields[1], lineNumber);
          const auto found = indices.find(owner);
          if (found == indices.end())
            THROW(, "engine manifest line " << lineNumber << ": relocation owner is undefined")
          Relocation relocation;
          relocation.offset = integer(fields[3], lineNumber);
          if (fields[2] == "phrase") {
            relocation.kind = RelocationKind::Phrase;
            relocation.phrase = integer(fields[4], lineNumber);
          } else if (fields[2] == "action") {
            relocation.kind = RelocationKind::Action;
            relocation.action = fields[4];
          } else {
            THROW(, "engine manifest line " << lineNumber << ": unknown relocation kind")
          }
          records[found->second].relocations.push_back(std::move(relocation));
        } else if (fields[0] == "routine") {
          THROW(, "engine manifest line " << lineNumber << ": source routines are unsupported")
        } else {
          THROW(, "engine manifest line " << lineNumber << ": expected 'phrase' or 'relocate'")
        }
      }
      return decodeRecords(context, encodeRecords(records));
    }

    void mergeSnapshot(context::Context &context, const Snapshot &snapshot, lexicon::Phrase target) {
      if (target.isNull() || !target.containsSubdictionary())
        THROW(, "cannot merge an engine image into a phrase without a subdictionary")

      const std::vector<Record> &records = snapshot.phrases;
      if (records.empty()) THROW(, "cannot merge an empty engine image")

      std::unordered_map<std::uint64_t, lexicon::Phrase> phrases;
      std::unordered_set<std::uint64_t> created;
      lexicon::Phrase undefined(target.getLexicon());
      phrases.emplace(records.front().id, target);

      for (std::size_t index = 1; index < records.size(); ++index) {
        const Record &record = records[index];
        const auto owner = phrases.find(record.parent);
        if (owner == phrases.end() || !owner->second.containsSubdictionary())
          THROW(, "engine image merge references an unavailable dictionary owner")

        lexicon::Phrase existing = exact(owner->second, record.key, record.keyBits);
        if (!existing.isNull()) {
          if (record.subdictionary && !existing.containsSubdictionary())
            THROW(, "engine image merge found a non-dictionary phrase where a dictionary is required")
          phrases.emplace(record.id, existing);
          continue;
        }

        lexicon::Draft draft =
            owner->second.append(Byte(const_cast<char *>(record.key.data())), 0, record.keyBits).make();
        if (record.subdictionary) draft.enableSubdictionary();
        if (record.prototype) draft.setPrototype(undefined);
        if (record.type) draft.setType(undefined);
        if (record.action) {
          if (record.actionName.empty()) THROW(, "engine image merge contains an unnamed phrase action")
          draft.setAction(context.actions().get(record.actionName));
        }
        if (record.successor) draft.setSuccessor(undefined);

        lexicon::Phrase phrase = draft.save();
        if (!record.payload.empty()) {
          Byte output = phrase.allocate(record.payload.size());
          std::memcpy(output.toPtr(), record.payload.data(), record.payload.size());
        }
        phrases.emplace(record.id, phrase);
        created.insert(record.id);
      }

      const auto resolve = [&](std::uint64_t id) {
        if (id == 0) return undefined;
        const auto found = phrases.find(id);
        if (found == phrases.end()) THROW(, "engine image merge contains an unresolved phrase reference")
        return found->second;
      };

      for (const Record &record : records) {
        if (!created.contains(record.id)) continue;
        lexicon::Phrase phrase = phrases.at(record.id);
        if (record.prototype) phrase.setPrototype(resolve(record.prototypeId));
        if (record.type) phrase.setType(resolve(record.typeId));
        if (record.successor) phrase.setSuccessor(resolve(record.successorId));
        if (record.action) phrase.setActionImplementation(resolve(record.actionImplementationId));
        if (record.rewritable) phrase.setRewritable(true);
        if (record.permanent) phrase.setPermanent(true);
        phrase.save();

        for (const Relocation &relocation : record.relocations) {
          if (relocation.kind == RelocationKind::Phrase) {
            const Size address = resolve(relocation.phrase).getAddress();
            std::memcpy(phrase.content(relocation.offset, sizeof(address)).toPtr(), &address, sizeof(address));
          } else {
            const lexicon::Phrase::Action action =
                relocation.action.empty() ? nullptr : context.actions().get(relocation.action);
            std::memcpy(phrase.content(relocation.offset, sizeof(action)).toPtr(), &action, sizeof(action));
          }
        }
      }
    }

    void mergeDictionary(context::Context &context, lexicon::Phrase source, lexicon::Phrase target) {
      if (source.isNull() || !source.containsSubdictionary()) THROW(, "cannot merge a phrase without a subdictionary")
      if (target.isNull() || !target.containsSubdictionary())
        THROW(, "cannot merge into a phrase without a subdictionary")
      if (source.getLexicon() != target.getLexicon())
        THROW(, "direct dictionary merge requires both phrases to belong to the same lexicon")

      struct Entry {
        lexicon::Phrase source;
        lexicon::Phrase target;
      };
      std::vector<Entry> entries;
      std::unordered_map<Size, lexicon::Phrase> mapped;
      std::unordered_set<Size> created;
      mapped.emplace(source.getAddress(), target);

      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      std::vector<Entry> pending;
      for (lexicon::Dictionary child = source.fore(populated); !child.isNull(); child = child.next(populated))
        pending.push_back({child.getPhrase(), target});

      while (!pending.empty()) {
        Entry entry = pending.back();
        pending.pop_back();
        lexicon::Phrase existing = exact(entry.target, entry.source.getKey(), entry.source.getNode().keyBits());
        lexicon::Phrase destination = existing;
        if (!destination.isNull()) {
          if (entry.source.containsSubdictionary() && !destination.containsSubdictionary())
            THROW(, "dictionary merge found a non-dictionary phrase where a dictionary is required")
        } else {
          lexicon::Draft draft = entry.target.append(entry.source.getKey()).make();
          if (entry.source.containsSubdictionary()) draft.enableSubdictionary();
          if (entry.source.containsPrototype()) draft.setPrototype(lexicon::Phrase(source.getLexicon()));
          if (entry.source.containsType()) draft.setType(lexicon::Phrase(source.getLexicon()));
          if (entry.source.containsAction()) draft.setAction(entry.source.getAction());
          if (entry.source.containsSuccessor()) draft.setSuccessor(lexicon::Phrase(source.getLexicon()));
          destination = draft.save();
          if (entry.source.payloadSize() != 0) {
            Byte output = destination.allocate(entry.source.payloadSize());
            std::memcpy(output.toPtr(), entry.source.content(0, entry.source.payloadSize()).toPtr(),
                        entry.source.payloadSize());
          }
          created.insert(destination.getAddress());
        }
        mapped.emplace(entry.source.getAddress(), destination);
        entries.push_back({entry.source, destination});

        if (entry.source.containsSubdictionary()) {
          for (lexicon::Dictionary child = entry.source.fore(populated); !child.isNull(); child = child.next(populated))
            pending.push_back({child.getPhrase(), destination});
        }
      }

      const auto resolve = [&](lexicon::Phrase phrase) {
        if (phrase.isNull()) return phrase;
        const auto found = mapped.find(phrase.getAddress());
        return found == mapped.end() ? phrase : found->second;
      };

      for (Entry &entry : entries) {
        if (!created.contains(entry.target.getAddress())) continue;
        lexicon::Phrase destination = entry.target;
        if (entry.source.containsPrototype()) destination.setPrototype(resolve(entry.source.getPrototype()));
        if (entry.source.containsType()) destination.setType(resolve(entry.source.getType()));
        if (entry.source.containsSuccessor()) destination.setSuccessor(resolve(entry.source.getSuccessor()));
        if (entry.source.containsAction()) {
          lexicon::Phrase implementation = entry.source.getActionImplementation();
          if (!implementation.isNull()) destination.setActionImplementation(resolve(implementation));
        }
        if (entry.source.isRewritable()) destination.setRewritable(true);
        if (entry.source.isPermanent()) destination.setPermanent(true);
        destination.save();
      }
    }

    void restore(context::Context &context, const Snapshot &snapshot) {
      const std::vector<Record> &records = snapshot.phrases;
      const std::vector<Record> previous = capture(context);
      const std::uint64_t importedRoot = records.front().id;
      const std::uint64_t previousRoot = previous.front().id;
      std::set<std::pair<std::string, std::uint64_t>> importedRoots;
      for (const Record &record : records)
        if (record.parent == importedRoot) importedRoots.emplace(record.key, record.keyBits);

      std::vector<Record> preserved;
      preserved.reserve(previous.size());
      std::unordered_set<std::uint64_t> preservedIds;
      for (const Record &record : previous) {
        const bool retainedRoot =
            record.parent == previousRoot && !importedRoots.contains({record.key, record.keyBits});
        const bool retainedDescendant = record.parent != previousRoot && preservedIds.contains(record.parent);
        if (retainedRoot || retainedDescendant) {
          preserved.push_back(record);
          preservedIds.insert(record.id);
        }
      }

      std::unordered_map<std::string, lexicon::Phrase::Action> actionPointers;
      const auto preserveActions = [&](const std::vector<Record> &source) {
        for (const Record &record : source) {
          if (record.action && !record.actionName.empty())
            actionPointers.try_emplace(record.actionName, context.actions().get(record.actionName));
          for (const Relocation &relocation : record.relocations)
            if (relocation.kind == RelocationKind::Action && !relocation.action.empty())
              actionPointers.try_emplace(relocation.action, context.actions().get(relocation.action));
        }
      };
      preserveActions(records);
      preserveActions(preserved);
      const auto action = [&](const std::string &name) -> lexicon::Phrase::Action {
        if (name.empty()) return nullptr;
        const auto found = actionPointers.find(name);
        if (found == actionPointers.end()) THROW(, "engine restore lost action '" << name << "'")
        return found->second;
      };

      context.lexicon.clear();

      std::unordered_map<std::uint64_t, lexicon::Phrase> phrases;
      lexicon::Phrase undefined(&context.lexicon);
      for (const Record &record : records) {
        lexicon::Draft draft;
        if (record.parent == 0) {
          draft = context.lexicon.make();
        } else {
          const auto parent = phrases.find(record.parent);
          if (parent == phrases.end() || !parent->second.containsSubdictionary())
            THROW(, "engine image phrase is declared before its dictionary owner")
          draft = parent->second.append(Byte(const_cast<char *>(record.key.data())), 0, record.keyBits).make();
        }
        if (record.subdictionary) draft.enableSubdictionary();
        if (record.prototype) draft.setPrototype(undefined);
        if (record.type) draft.setType(undefined);
        if (record.action) draft.setAction(action(record.actionName));
        if (record.successor) draft.setSuccessor(undefined);
        lexicon::Phrase phrase = draft.save();
        if (!record.payload.empty()) {
          Byte output = phrase.allocate(record.payload.size());
          std::memcpy(output.toPtr(), record.payload.data(), record.payload.size());
        }
        phrases.emplace(record.id, phrase);
      }

      const auto resolve = [&](std::uint64_t id) { return id == 0 ? undefined : phrases.at(id); };
      for (const Record &record : records) {
        lexicon::Phrase phrase = phrases.at(record.id);
        if (record.prototype) phrase.setPrototype(resolve(record.prototypeId));
        if (record.type) phrase.setType(resolve(record.typeId));
        if (record.successor) phrase.setSuccessor(resolve(record.successorId));
        if (record.action) phrase.setActionImplementation(resolve(record.actionImplementationId));
        if (record.rewritable) phrase.setRewritable(true);
        if (record.permanent) phrase.setPermanent(true);
        phrase.save();
        for (const Relocation &relocation : record.relocations) {
          if (relocation.kind == RelocationKind::Phrase) {
            const Size address = resolve(relocation.phrase).getAddress();
            std::memcpy(phrase.content(relocation.offset, sizeof(address)).toPtr(), &address, sizeof(address));
          } else {
            const lexicon::Phrase::Action resolvedAction = action(relocation.action);
            std::memcpy(phrase.content(relocation.offset, sizeof(resolvedAction)).toPtr(), &resolvedAction,
                        sizeof(resolvedAction));
          }
        }
      }

      lexicon::Phrase root = records.empty() ? lexicon::Phrase(&context.lexicon) : phrases.at(records.front().id);
      root.load();
      std::unordered_map<std::uint64_t, const Record *> previousById;
      for (const Record &record : previous) previousById.emplace(record.id, &record);
      std::unordered_map<std::uint64_t, lexicon::Phrase> preservedPhrases;
      for (const Record &record : preserved) {
        lexicon::Phrase owner = record.parent == previousRoot ? root : preservedPhrases.at(record.parent);
        if (!owner.containsSubdictionary()) THROW(, "preserved phrase owner has no subdictionary")
        lexicon::Draft draft = owner.append(Byte(const_cast<char *>(record.key.data())), 0, record.keyBits).make();
        if (record.subdictionary) draft.enableSubdictionary();
        if (record.prototype) draft.setPrototype(undefined);
        if (record.type) draft.setType(undefined);
        if (record.action) draft.setAction(action(record.actionName));
        if (record.successor) draft.setSuccessor(undefined);
        lexicon::Phrase phrase = draft.save();
        if (!record.payload.empty()) {
          Byte output = phrase.allocate(record.payload.size());
          std::memcpy(output.toPtr(), record.payload.data(), record.payload.size());
        }
        preservedPhrases.emplace(record.id, phrase);
      }

      const auto resolvePrevious = [&](std::uint64_t id) {
        if (id == 0) return undefined;
        if (const auto retained = preservedPhrases.find(id); retained != preservedPhrases.end())
          return retained->second;
        std::vector<std::pair<std::string, std::uint64_t>> path;
        std::uint64_t cursor = id;
        while (cursor != 0) {
          const auto found = previousById.find(cursor);
          if (found == previousById.end()) THROW(, "preserved phrase references an unknown phrase")
          if (found->second->parent == 0) break;
          path.emplace_back(found->second->key, found->second->keyBits);
          cursor = found->second->parent;
        }
        lexicon::Phrase target = root;
        for (auto key = path.rbegin(); key != path.rend(); ++key) {
          target = exact(target, key->first, key->second);
          if (target.isNull()) THROW(, "preserved phrase dependency is absent from the imported language")
        }
        return target;
      };

      for (const Record &record : preserved) {
        lexicon::Phrase phrase = preservedPhrases.at(record.id);
        if (record.prototype) phrase.setPrototype(resolvePrevious(record.prototypeId));
        if (record.type) phrase.setType(resolvePrevious(record.typeId));
        if (record.successor) phrase.setSuccessor(resolvePrevious(record.successorId));
        if (record.action) phrase.setActionImplementation(resolvePrevious(record.actionImplementationId));
        if (record.rewritable) phrase.setRewritable(true);
        if (record.permanent) phrase.setPermanent(true);
        phrase.save();
        for (const Relocation &relocation : record.relocations) {
          if (relocation.kind == RelocationKind::Phrase) {
            const Size address = resolvePrevious(relocation.phrase).getAddress();
            std::memcpy(phrase.content(relocation.offset, sizeof(address)).toPtr(), &address, sizeof(address));
          } else {
            const lexicon::Phrase::Action resolvedAction = action(relocation.action);
            std::memcpy(phrase.content(relocation.offset, sizeof(resolvedAction)).toPtr(), &resolvedAction,
                        sizeof(resolvedAction));
          }
        }
      }

      root.load();
      context::Values::setup(root);
      compiler::LanguageState::setup(root);
      context.lookup = {};
      context.staging = {};
      context.reference = {};
      context::Lookup::in(context, root);
      context::Staging::push(context, root);
      context::Reference::in(context, root);
    }
  } // namespace

  std::vector<std::uint8_t> EngineImage::encode(context::Context &context) {
    return encodeRecords(capture(context));
  }

  std::vector<std::uint8_t> EngineImage::encode(context::Context &context, Size since) {
    return encodeRecords(capture(context, since));
  }

  void EngineImage::decode(context::Context &context, std::span<const std::uint8_t> bytes) {
    restore(context, decodeRecords(context, bytes));
  }

  void EngineImage::merge(context::Context &context, std::span<const std::uint8_t> bytes, lexicon::Phrase target) {
    mergeSnapshot(context, decodeRecords(context, bytes), target);
  }

  void EngineImage::merge(context::Context &context, lexicon::Phrase source, lexicon::Phrase target) {
    mergeDictionary(context, source, target);
  }

  std::string EngineImage::source(context::Context &context) {
    const std::vector<Record> records = capture(context);
    std::ostringstream output;
    output << "engine define {\n";
    for (const Record &record : records) {
      std::uint8_t flags = record.subdictionary ? 1 : 0;
      flags |= record.prototype ? 2 : 0;
      flags |= record.type ? 4 : 0;
      flags |= record.action ? 8 : 0;
      flags |= record.successor ? 16 : 0;
      flags |= record.permanent ? 32 : 0;
      flags |= record.rewritable ? 64 : 0;
      output << "phrase " << record.id << " parent " << record.parent << " key " << quote(record.key) << " bits "
             << record.keyBits << " flags " << static_cast<unsigned>(flags) << " prototype " << record.prototypeId
             << " type " << record.typeId << " successor " << record.successorId << " action "
             << quote(record.actionName) << " action-target " << record.actionImplementationId << " payload "
             << quote(hexadecimal(record.payload)) << "\n";
      for (const Relocation &relocation : record.relocations) {
        output << "relocate " << record.id << ' ' << (relocation.kind == RelocationKind::Phrase ? "phrase " : "action ")
               << relocation.offset << ' ';
        if (relocation.kind == RelocationKind::Phrase)
          output << relocation.phrase;
        else
          output << quote(relocation.action);
        output << "\n";
      }
    }
    output << "}\n";
    return output.str();
  }

  void EngineImage::define(context::Context &context, std::string_view manifest) {
    restore(context, parseManifest(context, manifest));
  }

  void EngineImage::save(context::Context &context, const std::string &path) {
    if (path.empty()) THROW(, "engine image path cannot be empty")
    const std::vector<std::uint8_t> bytes = encode(context);
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output.is_open()) THROW(, "cannot open engine image for writing: '" << path << "'")
    output.write(reinterpret_cast<const char *>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    output.close();
    if (!output) THROW(, "cannot write engine image: '" << path << "'")
  }

  void EngineImage::load(context::Context &context, const std::string &path) {
    if (path.empty()) THROW(, "engine image path cannot be empty")
    std::ifstream input(path, std::ios::binary);
    if (!input.is_open()) THROW(, "cannot open engine image for reading: '" << path << "'")
    std::vector<std::uint8_t> bytes{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
    if (input.bad()) THROW(, "cannot read engine image: '" << path << "'")
    decode(context, bytes);
  }
} // namespace recurloop
