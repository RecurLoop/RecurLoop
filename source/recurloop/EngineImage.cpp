#include <recurloop/EngineImage.hpp>
#include <recurloop/Semantic.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/Typed.hpp>

#include "CoreDefinition.hpp"

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <array>
#include <charconv>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iterator>
#include <limits>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

namespace recurloop {
  namespace {
    constexpr std::array<std::uint8_t, 8> Magic = {'R', 'L', 'E', 'N', 'G', 0, 1, 0};
    constexpr std::array<std::uint8_t, 8> LinkedMagic = {'R', 'L', 'L', 'I', 'N', 'K', 0, 1};
    constexpr std::uint32_t LinkedVersion = 1;
    constexpr std::uint64_t ExternalReferenceMask = std::uint64_t{1} << 63;
    constexpr std::string_view ImageLayoutsName{"\0image-layouts", 14};
    constexpr std::string_view ImageDependenciesName{"\0image-dependencies", 19};
    constexpr std::string_view ImageExportBaseName{"\0image-export-base", 18};
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

    struct ImageDependency {
      std::string identity;
      std::string path;
    };

    struct PathElement {
      std::string key;
      std::uint64_t keyBits = 0;
    };

    struct ExternalReference {
      std::vector<PathElement> path;
      std::uint32_t older = 0;
    };

    struct LinkedSnapshot {
      std::vector<ImageDependency> dependencies;
      std::vector<ExternalReference> external;
      std::vector<Record> phrases;
    };

    struct PayloadLayoutField {
      std::size_t offset = 0;
      EngineImage::PayloadFieldKind kind = EngineImage::PayloadFieldKind::PhraseReference;
    };

    using PayloadLayouts = std::unordered_map<Size, std::vector<PayloadLayoutField>>;

    std::vector<std::uint8_t> phrasePayload(lexicon::Phrase phrase) {
      if (phrase.isNull()) return {};
      std::vector<std::uint8_t> bytes(phrase.payloadSize());
      if (!bytes.empty()) std::memcpy(bytes.data(), phrase.content(0, bytes.size()).toPtr(), bytes.size());
      return bytes;
    }

    template <typename Metadata> std::optional<Metadata> schemaMetadata(std::span<const std::uint8_t> payload) {
      if (payload.size() < sizeof(Metadata)) return std::nullopt;
      Metadata metadata;
      std::memcpy(&metadata, payload.data(), sizeof(metadata));
      if (metadata.magic != Metadata::Magic || metadata.version != Metadata::Version || metadata.reserved != 0)
        return std::nullopt;
      return metadata;
    }

    bool compilerTypeMetadata(std::span<const std::uint8_t> payload, std::span<const std::uint8_t> parentPayload) {
      const auto role = schemaMetadata<compiler::RegistryBinding>(parentPayload);
      const auto slot = schemaMetadata<compiler::SlotBinding>(payload);
      return (role && (role->role == compiler::RegistryRole::Types || role->role == compiler::RegistryRole::TypeIds)) ||
             (slot && slot->role == compiler::SlotRole::TypeNextId);
    }

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

    std::string imageIdentity(std::span<const std::uint8_t> bytes) {
      constexpr std::uint64_t offset = 14695981039346656037ull;
      constexpr std::uint64_t prime = 1099511628211ull;
      std::uint64_t hash = offset;
      for (const std::uint8_t byte : bytes) {
        hash ^= byte;
        hash *= prime;
      }
      static constexpr char digits[] = "0123456789abcdef";
      const auto hexadecimal64 = [&](std::uint64_t value) {
        std::string result(16, '0');
        for (std::size_t index = 0; index < result.size(); ++index) {
          result[result.size() - index - 1] = digits[value & 0xf];
          value >>= 4;
        }
        return result;
      };
      return hexadecimal64(hash) + "-" + hexadecimal64(bytes.size());
    }

    std::filesystem::path absolutePath(const std::filesystem::path &path) {
      std::error_code error;
      const std::filesystem::path result = std::filesystem::absolute(path, error).lexically_normal();
      if (error) THROW(, "cannot resolve engine image path '" << path.string() << "': " << error.message())
      return result;
    }

    lexicon::Phrase imageDependencies(context::Context &context, bool create) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase dependencies = exact(root, std::string(ImageDependenciesName));
      if (!dependencies.isNull() || !create) return dependencies;
      return root.append(std::string(ImageDependenciesName))
          .make()
          .enableSubdictionary()
          .setType(lexicon::phrase::type::getData(root))
          .save();
    }

    bool hasImageDependency(context::Context &context, std::string_view identity) {
      lexicon::Phrase dependencies = imageDependencies(context, false);
      if (dependencies.isNull()) return false;
      return !exact(dependencies, std::string(identity)).isNull();
    }

    bool hasImageDependencyPath(context::Context &context, const std::filesystem::path &path) {
      lexicon::Phrase dependencies = imageDependencies(context, false);
      if (dependencies.isNull() || !dependencies.containsSubdictionary()) return false;
      const std::filesystem::path target = absolutePath(path);
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      for (lexicon::Dictionary child = dependencies.fore(populated); !child.isNull(); child = child.next(populated)) {
        lexicon::Phrase entry = child.getPhrase();
        if (entry.payloadSize() == 0) continue;
        const std::string stored(reinterpret_cast<const char *>(entry.content(0, entry.payloadSize()).toPtr()),
                                 entry.payloadSize());
        if (!stored.empty() && stored.find('\0') == std::string::npos && absolutePath(stored) == target) return true;
      }
      return false;
    }

    void rememberImageDependency(context::Context &context, std::string_view identity,
                                 const std::filesystem::path &path) {
      lexicon::Phrase dependencies = imageDependencies(context, true);
      const std::string normalized = absolutePath(path).generic_string();
      lexicon::Phrase current = exact(dependencies, std::string(identity));
      if (!current.isNull() && current.payloadSize() == normalized.size() &&
          (normalized.empty() || std::memcmp(current.content(0, normalized.size()).toPtr(), normalized.data(),
                                             normalized.size()) == 0))
        return;

      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase entry = dependencies.append(std::string(identity))
                                  .make()
                                  .setType(lexicon::phrase::type::getData(root))
                                  .save();
      if (!normalized.empty()) {
        Byte payload = entry.allocate(normalized.size());
        std::memcpy(payload.toPtr(), normalized.data(), normalized.size());
      }
    }

    std::vector<ImageDependency> imageDependencies(const Snapshot &snapshot) {
      if (snapshot.phrases.empty()) return {};
      const std::uint64_t root = snapshot.phrases.front().id;
      std::uint64_t owner = 0;
      for (const Record &record : snapshot.phrases)
        if (record.parent == root && record.key == ImageDependenciesName) {
          owner = record.id;
          break;
        }
      if (owner == 0) return {};

      std::vector<ImageDependency> result;
      for (const Record &record : snapshot.phrases) {
        if (record.parent != owner) continue;
        const std::string path(reinterpret_cast<const char *>(record.payload.data()), record.payload.size());
        if (record.key.empty() || path.empty() || path.find('\0') != std::string::npos)
          THROW(, "engine image contains an invalid dependency descriptor")
        result.push_back({record.key, path});
      }
      std::sort(result.begin(), result.end(), [](const auto &left, const auto &right) {
        if (left.identity != right.identity) return left.identity < right.identity;
        return left.path < right.path;
      });
      result.erase(std::unique(result.begin(), result.end(), [](const auto &left, const auto &right) {
                     return left.identity == right.identity;
                   }),
                   result.end());
      return result;
    }

    std::vector<ImageDependency> imageDependencies(context::Context &context) {
      lexicon::Phrase dependencies = imageDependencies(context, false);
      if (dependencies.isNull() || !dependencies.containsSubdictionary()) return {};

      struct OrderedDependency {
        Size address = 0;
        ImageDependency dependency;
      };
      std::vector<OrderedDependency> ordered;
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      for (lexicon::Dictionary child = dependencies.fore(populated); !child.isNull(); child = child.next(populated)) {
        lexicon::Phrase entry = child.getPhrase();
        if (entry.payloadSize() == 0) continue;
        const std::string path(reinterpret_cast<const char *>(entry.content(0, entry.payloadSize()).toPtr()),
                               entry.payloadSize());
        if (entry.getKey().empty() || path.empty() || path.find('\0') != std::string::npos)
          THROW(, "engine image contains an invalid runtime dependency descriptor")
        ordered.push_back({entry.getAddress(), {entry.getKey(), path}});
      }
      std::sort(ordered.begin(), ordered.end(), [](const auto &left, const auto &right) {
        return left.address < right.address;
      });
      std::vector<ImageDependency> result;
      result.reserve(ordered.size());
      for (OrderedDependency &entry : ordered) result.push_back(std::move(entry.dependency));
      return result;
    }

    std::vector<ImageDependency> portableDependencies(context::Context &context,
                                                       const std::filesystem::path &outputPath) {
      std::vector<ImageDependency> result = imageDependencies(context);
      const std::filesystem::path output = absolutePath(outputPath);
      const std::filesystem::path directory = output.parent_path();
      std::erase_if(result, [&](const ImageDependency &dependency) {
        return absolutePath(dependency.path) == output;
      });
      for (ImageDependency &dependency : result) {
        const std::filesystem::path absolute = absolutePath(dependency.path);
        const std::filesystem::path relative = absolute.lexically_relative(directory);
        dependency.path = relative.empty() ? absolute.generic_string() : relative.generic_string();
      }
      return result;
    }

    Size imageExportBase(context::Context &context) {
      lexicon::Phrase marker = exact(context.lexicon.phrase(), std::string(ImageExportBaseName));
      if (marker.isNull() || marker.payloadSize() != sizeof(Size)) return 0;
      Size result = 0;
      std::memcpy(&result, marker.content(0, sizeof(result)).toPtr(), sizeof(result));
      return result <= context.lexicon.checkpoint().getAddress() ? result : 0;
    }

    Size dictionaryRoot(lexicon::Phrase phrase) {
      radix::Node node = phrase.getNode();
      while (true) {
        radix::Node parent = node.predecessor();
        if (parent.isNull()) return node.getAddress();
        node = parent;
      }
    }

    lexicon::Phrase imageLayouts(context::Context &context, bool create) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase layouts = exact(root, std::string(ImageLayoutsName));
      if (!layouts.isNull() || !create) return layouts;
      return root.append(std::string(ImageLayoutsName))
          .make()
          .enableSubdictionary()
          .setType(lexicon::phrase::type::getData(root))
          .save();
    }

    std::string binaryKey(std::uint64_t value) {
      return std::string(reinterpret_cast<const char *>(&value), sizeof(value));
    }

    PayloadLayouts loadPayloadLayouts(context::Context &context) {
      PayloadLayouts result;
      lexicon::Phrase layouts = imageLayouts(context, false);
      if (layouts.isNull() || !layouts.containsSubdictionary()) return result;
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      for (lexicon::Dictionary entry = layouts.fore(populated); !entry.isNull(); entry = entry.next(populated)) {
        lexicon::Phrase layout = entry.getPhrase();
        if (!layout.containsSuccessor() || !layout.containsSubdictionary()) continue;
        lexicon::Phrase schema = layout.getSuccessor();
        if (schema.isNull()) continue;
        std::vector<PayloadLayoutField> fields;
        for (lexicon::Dictionary child = layout.fore(populated); !child.isNull(); child = child.next(populated)) {
          lexicon::Phrase descriptor = child.getPhrase();
          if (descriptor.getNode().keyBits() != sizeof(std::uint64_t) * Byte::length ||
              descriptor.getKey().size() != sizeof(std::uint64_t) || descriptor.payloadSize() != sizeof(std::uint8_t))
            THROW(, "invalid engine image payload-layout descriptor")
          std::uint64_t offset = 0;
          const std::string key = descriptor.getKey();
          std::memcpy(&offset, key.data(), sizeof(offset));
          std::uint8_t kind = 0;
          descriptor.fetch(0, kind);
          if (kind != static_cast<std::uint8_t>(EngineImage::PayloadFieldKind::PhraseReference) &&
              kind != static_cast<std::uint8_t>(EngineImage::PayloadFieldKind::NativePointer))
            THROW(, "invalid engine image payload-layout field kind")
          fields.push_back({static_cast<std::size_t>(offset), static_cast<EngineImage::PayloadFieldKind>(kind)});
        }
        std::sort(fields.begin(), fields.end(), [](const auto &left, const auto &right) {
          return left.offset < right.offset;
        });
        result[schema.getAddress()] = std::move(fields);
      }
      return result;
    }

    const std::vector<PayloadLayoutField> *payloadLayout(const PayloadLayouts &layouts, lexicon::Phrase phrase) {
      if (!phrase.containsPrototype()) return nullptr;
      lexicon::Phrase schema = phrase.getPrototype();
      if (schema.isNull()) return nullptr;
      const auto found = layouts.find(schema.getAddress());
      return found == layouts.end() ? nullptr : &found->second;
    }

    void validatePayloadField(const std::vector<std::uint8_t> &bytes, const PayloadLayoutField &field) {
      const std::size_t width = field.kind == EngineImage::PayloadFieldKind::PhraseReference ? sizeof(Size)
                                                                                           : sizeof(std::uintptr_t);
      if (field.offset > bytes.size() || width > bytes.size() - field.offset)
        THROW(, "engine image payload-layout field points outside phrase payload")
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
      lexicon::Phrase dependencyMetadata = imageDependencies(context, false);
      const std::unordered_set<Size> behaviorTypes =
          types.isNull()
              ? std::unordered_set<Size>{}
              : std::unordered_set<Size>{exact(types, "elaborate").getAddress(), exact(types, "callable").getAddress(),
                                         exact(types, "scoped-callable").getAddress()};
      const PayloadLayouts layouts = loadPayloadLayouts(context);

      const auto dependencyPayload = [&](lexicon::Phrase phrase) {
        if (dependencyMetadata.isNull()) return false;
        const auto owner = dictionaryOwners.find(dictionaryRoot(phrase));
        return owner != dictionaryOwners.end() && owner->second == dependencyMetadata.getAddress();
      };

      const auto payloadTargets = [&](lexicon::Phrase phrase) {
        const std::vector<std::uint8_t> bytes = phrasePayload(phrase);
        std::vector<Size> result;
        if (!dependencyPayload(phrase) && bytes.size() >= sizeof(compiler::LanguageBinding)) {
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
        if (const auto *fields = payloadLayout(layouts, phrase); fields != nullptr) {
          for (const PayloadLayoutField &field : *fields) {
            validatePayloadField(bytes, field);
            if (field.kind == EngineImage::PayloadFieldKind::PhraseReference) {
              Size address = 0;
              std::memcpy(&address, bytes.data() + field.offset, sizeof(address));
              if (address != 0) result.push_back(address);
            } else {
              std::uintptr_t pointer = 0;
              std::memcpy(&pointer, bytes.data() + field.offset, sizeof(pointer));
              if (pointer != 0)
                THROW(, "engine image cannot serialize a non-zero native pointer declared by payload layout")
            }
          }
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
      if (since != 0) {
        // A checkpoint delta can add children below dictionaries that existed
        // before the checkpoint. Walk the active dictionary graph to discover
        // those descendants, then `ensure` adds only the ownership path needed
        // to materialize them. This avoids copying unrelated old siblings.
        std::vector<lexicon::Phrase> dictionaries{root};
        for (std::size_t cursor = 0; cursor < dictionaries.size(); ++cursor) {
          lexicon::Phrase owner = dictionaries[cursor];
          if (!owner.containsSubdictionary()) continue;
          auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
          for (lexicon::Dictionary child = owner.fore(populated); !child.isNull(); child = child.next(populated)) {
            lexicon::Phrase candidate = child.getPhrase();
            if (!candidate.isSerializable()) continue;
            if (candidate.getAddress() >= since || compilerTypeMetadata(phrasePayload(candidate), phrasePayload(owner)))
              ensure(candidate.getAddress(), ensure);
            if (candidate.containsSubdictionary()) dictionaries.push_back(candidate);
          }
        }
      }
      for (std::size_t cursor = 0; cursor < pending.size(); ++cursor) {
        lexicon::Phrase phrase = pending[cursor].phrase;
        if (!phrase.isSerializable()) THROW(, "engine image cannot serialize phrase '" << phrase.getKeyEscaped() << "'")
        if (phrase.containsSubdictionary()) {
          auto filter = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
          for (lexicon::Dictionary child = phrase.fore(filter); !child.isNull(); child = child.next(filter)) {
            lexicon::Phrase candidate = child.getPhrase();
            if (!candidate.isSerializable()) continue;
            const bool dependencyTree = !dependencyMetadata.isNull() &&
                                        (phrase.getAddress() == dependencyMetadata.getAddress() ||
                                         candidate.getAddress() == dependencyMetadata.getAddress());
            if (since == 0 || candidate.getAddress() >= since || dependencyTree)
              add(candidate, phrase.getAddress());
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
        record.payload = phrasePayload(phrase);
        record.sourceAddress = pending[index].address;
        record.parentAddress = pending[index].parent;
        record.depth = pending[index].depth;
        records.push_back(std::move(record));
      }

      for (Record &record : records) {
        lexicon::Phrase sourcePhrase(&context.lexicon, record.sourceAddress);
        sourcePhrase.load();
        if (!dependencyPayload(sourcePhrase) && record.payload.size() >= sizeof(compiler::LanguageBinding)) {
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

        if (const auto *fields = payloadLayout(layouts, sourcePhrase); fields != nullptr) {
          for (const PayloadLayoutField &field : *fields) {
            validatePayloadField(record.payload, field);
            const std::size_t width = field.kind == EngineImage::PayloadFieldKind::PhraseReference ? sizeof(Size)
                                                                                                  : sizeof(std::uintptr_t);
            for (const Relocation &existing : record.relocations)
              if (existing.offset < field.offset + width && field.offset < existing.offset +
                      (existing.kind == RelocationKind::Phrase ? sizeof(Size) : sizeof(lexicon::Phrase::Action)))
                THROW(, "engine image payload-layout field overlaps an existing relocation")
            if (field.kind == EngineImage::PayloadFieldKind::PhraseReference) {
              Size address = 0;
              std::memcpy(&address, record.payload.data() + field.offset, sizeof(address));
              const auto target = address == 0 ? ids.end() : ids.find(address);
              if (address != 0 && target == ids.end())
                THROW(, "engine image payload-layout phrase reference points outside the engine image")
              record.relocations.push_back(
                  {RelocationKind::Phrase, field.offset, address == 0 ? 0 : target->second, {}});
              std::memset(record.payload.data() + field.offset, 0, sizeof(Size));
            } else {
              std::uintptr_t pointer = 0;
              std::memcpy(&pointer, record.payload.data() + field.offset, sizeof(pointer));
              if (pointer != 0)
                THROW(, "engine image cannot serialize a non-zero native pointer declared by payload layout")
            }
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
      // Kept as a zero count for compatibility with the existing record
      // layout. Source routines are deliberately unsupported now that every
      // function is compiled.
      writer.number(0, 4);
      return writer.bytes;
    }

    bool linkedMagic(std::span<const std::uint8_t> bytes) {
      return bytes.size() >= LinkedMagic.size() &&
             std::equal(LinkedMagic.begin(), LinkedMagic.end(), bytes.begin());
    }

    std::string externalReferenceKey(const ExternalReference &reference) {
      Writer writer;
      writer.number(reference.path.size(), 4);
      for (const PathElement &element : reference.path) {
        writer.number(element.keyBits, 8);
        writer.data(std::span<const std::uint8_t>(reinterpret_cast<const std::uint8_t *>(element.key.data()),
                                                  element.key.size()));
      }
      writer.number(reference.older, 4);
      return {reinterpret_cast<const char *>(writer.bytes.data()), writer.bytes.size()};
    }

    lexicon::Phrase resolveExternal(context::Context &context, const ExternalReference &reference) {
      lexicon::Phrase phrase = context.lexicon.phrase();
      for (const PathElement &element : reference.path) {
        if (phrase.isNull() || !phrase.containsSubdictionary())
          THROW(, "linked engine image external path crosses a non-dictionary phrase")
        phrase = exact(phrase, element.key, element.keyBits);
        if (phrase.isNull()) THROW(, "linked engine image external phrase is unavailable")
      }
      for (std::uint32_t index = 0; index < reference.older; ++index) {
        phrase = phrase.older();
        if (phrase.isNull()) THROW(, "linked engine image external phrase history is unavailable")
      }
      return phrase;
    }

    ExternalReference describeExternal(context::Context &context, const Record &record,
                                       const std::unordered_map<std::uint64_t, const Record *> &byId) {
      ExternalReference result;
      const Record *cursor = &record;
      while (cursor->parent != 0) {
        result.path.push_back({cursor->key, cursor->keyBits});
        const auto parent = byId.find(cursor->parent);
        if (parent == byId.end()) THROW(, "linked engine image cannot resolve an external phrase owner")
        cursor = parent->second;
      }
      std::reverse(result.path.begin(), result.path.end());

      lexicon::Phrase visible = context.lexicon.phrase();
      for (const PathElement &element : result.path) {
        if (!visible.containsSubdictionary())
          THROW(, "linked engine image external phrase owner is not a dictionary")
        visible = exact(visible, element.key, element.keyBits);
        if (visible.isNull()) THROW(, "linked engine image cannot locate an external phrase")
      }
      while (visible.getAddress() != record.sourceAddress) {
        visible = visible.older();
        if (visible.isNull()) THROW(, "linked engine image cannot identify an external phrase generation")
        if (result.older == std::numeric_limits<std::uint32_t>::max())
          THROW(, "linked engine image external phrase history is too deep")
        ++result.older;
      }
      return result;
    }

    // Type IDs belong to one compiler registry, not to an image or process.
    // Rebase incoming metadata before comparing paths or writing any phrases.
    void rebaseTypes(context::Context &context, std::vector<Record> &records,
                     const std::function<lexicon::Phrase(std::uint64_t)> &external = {}) {
      std::unordered_map<std::uint64_t, Record *> byId;
      for (Record &record : records) byId.emplace(record.id, &record);
      lexicon::Phrase undefined(&context.lexicon);
      std::unordered_map<Size, lexicon::Phrase> dictionaryOwners;
      if (external) {
        for (radix::Item item = context.lexicon.lastItem(); !item.isNull(); item = item.earlier()) {
          lexicon::Phrase phrase(item);
          phrase.load();
          if (phrase.containsSubdictionary())
            dictionaryOwners.try_emplace(phrase.getSubdictionary().getAddress(), phrase);
        }
      }
      const auto lexicalParent = [&](lexicon::Phrase phrase) {
        if (phrase.isNull() || phrase.getAddress() == context.lexicon.phrase().getAddress()) return undefined;
        const auto found = dictionaryOwners.find(dictionaryRoot(phrase));
        if (found == dictionaryOwners.end()) THROW(, "engine image compiler registry has no dictionary owner")
        return found->second;
      };
      const auto recordPayload = [&](std::uint64_t id) {
        if (id == 0) return std::vector<std::uint8_t>{};
        if (const auto found = byId.find(id); found != byId.end()) return found->second->payload;
        return external ? phrasePayload(external(id)) : std::vector<std::uint8_t>{};
      };
      const auto parentId = [&](std::uint64_t id) {
        const auto found = byId.find(id);
        return found == byId.end() ? std::uint64_t{0} : found->second->parent;
      };
      const auto registry = [&](std::uint64_t id) {
        return schemaMetadata<compiler::RegistryBinding>(recordPayload(id));
      };
      const auto actionName = [&](std::uint64_t id) -> std::string {
        if (const auto found = byId.find(id); found != byId.end()) return found->second->actionName;
        if (!external || id == 0) return {};
        lexicon::Phrase phrase = external(id);
        return phrase.containsAction() ? context.actions().name(phrase.getAction()) : std::string{};
      };
      std::unordered_map<std::uint64_t, lexicon::Phrase> existing;
      std::function<lexicon::Phrase(std::uint64_t)> existingPhrase = [&](std::uint64_t id) {
        if (const auto found = existing.find(id); found != existing.end()) return found->second;
        const auto found = byId.find(id);
        if (found == byId.end()) return external ? external(id) : undefined;
        const Record &record = *found->second;
        lexicon::Phrase phrase = record.parent == 0 ? context.lexicon.phrase() : existingPhrase(record.parent);
        if (record.parent != 0 && !phrase.isNull()) phrase = exact(phrase, record.key, record.keyBits);
        existing.emplace(id, phrase);
        return phrase;
      };
      struct Plan {
        compiler::TypeIdRemapping mapping;
        std::unordered_map<std::string, compiler::TypeDescriptor> previous;
        std::uint64_t next = 1;
        lexicon::Phrase language;
      };
      std::unordered_map<std::uint64_t, Plan> plans;
      std::unordered_map<std::uint64_t, std::uint64_t> registryLanguages;
      std::unordered_map<Size, std::uint64_t> languagePlans;
      for (Record &record : records) {
        const auto role = registry(record.parent);
        if (!role || role->role != compiler::RegistryRole::Types) continue;
        const auto language = byId.contains(record.parent)
                                  ? parentId(record.parent)
                                  : (ExternalReferenceMask | lexicalParent(external(record.parent)).getAddress());
        auto [entry, inserted] = plans.try_emplace(language);
        Plan &plan = entry->second;
        if (inserted) {
          plan.language =
              byId.contains(record.parent) ? existingPhrase(language) : lexicalParent(external(record.parent));
          if (!plan.language.isNull()) {
            if (!schemaMetadata<compiler::Language>(phrasePayload(plan.language)))
              THROW(, "engine image compiler language conflicts with an existing phrase")
            const compiler::TypeRegistry types(plan.language);
            for (const auto &type : types.types()) {
              plan.previous.emplace(type.name, type);
              plan.next = std::max(plan.next, std::uint64_t{type.id} + 1);
            }
            plan.next =
                std::max(plan.next, compiler::RegistrySchema::unsignedSlot(context.lexicon, plan.language.getAddress(),
                                                                           compiler::SlotRole::TypeNextId));
            languagePlans.emplace(plan.language.getAddress(), language);
          }
        }
        registryLanguages.emplace(record.parent, language);
        const auto type = compiler::TypeRegistry::deserialize(record.payload);
        compiler::TypeId id = type.id;
        if (!plan.language.isNull()) {
          const auto previous = plan.previous.find(type.name);
          if (previous != plan.previous.end())
            id = previous->second.id;
          else {
            if (plan.next >= std::numeric_limits<compiler::TypeId>::max()) THROW(, "type registry is full")
            id = static_cast<compiler::TypeId>(plan.next++);
          }
        } else
          plan.next = std::max(plan.next, std::uint64_t{type.id} + 1);
        if (!plan.mapping.emplace(type.id, id).second) THROW(, "engine image contains duplicate compiler type IDs")
      }
      if (plans.empty()) return;
      const auto planForRegistry = [&](std::uint64_t id) -> Plan * {
        if (id == 0) return nullptr;
        if (const auto found = registryLanguages.find(id); found != registryLanguages.end())
          return &plans.at(found->second);
        if (byId.contains(id)) {
          const auto found = plans.find(parentId(id));
          return found == plans.end() ? nullptr : &found->second;
        }
        const auto found = languagePlans.find(lexicalParent(external(id)).getAddress());
        return found == languagePlans.end() ? nullptr : &plans.at(found->second);
      };
      Plan *defaultPlan = nullptr;
      for (auto &[id, plan] : plans) {
        if ((external && !plan.language.isNull() &&
             lexicalParent(plan.language).getAddress() == context.lexicon.phrase().getAddress()) ||
            (byId.contains(id) && byId.contains(parentId(id)) && parentId(parentId(id)) == 0))
          defaultPlan = &plan;
      }
      for (Record &record : records) {
        const auto owner = registry(record.parent);
        if (owner && (owner->role == compiler::RegistryRole::Types || owner->role == compiler::RegistryRole::TypeIds)) {
          Plan *plan = planForRegistry(record.parent);
          if (!plan) continue;
          auto type = compiler::TypeRegistry::deserialize(record.payload);
          compiler::TypeRegistry::remap(type, plan->mapping);
          record.payload = compiler::TypeRegistry::serialize(type);
          const auto previous = plan->previous.find(type.name);
          if (previous != plan->previous.end() && record.payload != compiler::TypeRegistry::serialize(previous->second))
            THROW(, "engine image contains an incompatible definition of type '" << type.name << "'")
          if (owner->role == compiler::RegistryRole::TypeIds) {
            record.key.assign(reinterpret_cast<const char *>(&type.id), sizeof(type.id));
            record.keyBits = sizeof(type.id) * Byte::length;
          }
          continue;
        }
        const auto overloads =
            byId.contains(record.parent)
                ? registry(parentId(record.parent))
                : (external && record.parent != 0 ? schemaMetadata<compiler::RegistryBinding>(
                                                        phrasePayload(lexicalParent(external(record.parent))))
                                                  : std::nullopt);
        if (overloads && overloads->role == compiler::RegistryRole::Functions) {
          Plan *plan = nullptr;
          if (byId.contains(record.parent))
            plan = planForRegistry(parentId(record.parent));
          else {
            const auto found = languagePlans.find(lexicalParent(lexicalParent(external(record.parent))).getAddress());
            if (found != languagePlans.end()) plan = &plans.at(found->second);
          }
          if (plan) compiler::LanguageState::remapFunctionPayload(record.payload, plan->mapping);
          continue;
        }
        const auto slot = schemaMetadata<compiler::SlotBinding>(record.payload);
        if (slot && slot->role == compiler::SlotRole::TypeNextId) {
          if (Plan *plan = planForRegistry(record.parent)) {
            if (record.payload.size() != sizeof(*slot) + sizeof(plan->next)) THROW(, "invalid compiler type counter")
            std::memcpy(record.payload.data() + sizeof(*slot), &plan->next, sizeof(plan->next));
          }
          continue;
        }
        if (defaultPlan) {
          const bool field =
              actionName(record.parent) == "typed.instantiate" && !record.subdictionary && !record.action;
          const bool instance = actionName(record.prototypeId) == "typed.instantiate";
          if (record.actionName == "typed.instantiate" || field || instance)
            Typed::remapTypePayload(record.payload, defaultPlan->mapping, field);
          Functions::remapSignaturePayload(record.payload, defaultPlan->mapping);
        }
      }
    }

    LinkedSnapshot captureLinked(context::Context &context, Size since, const std::filesystem::path &outputPath) {
      if (since == 0 || since > context.lexicon.memoryUsed())
        THROW(, "linked engine image checkpoint is outside the lexicon")

      std::vector<Record> captured = capture(context, since);
      if (captured.empty()) THROW(, "cannot export an empty linked engine image context")

      std::unordered_map<std::uint64_t, const Record *> byId;
      byId.reserve(captured.size());
      for (const Record &record : captured) byId.emplace(record.id, &record);

      // Runtime dependency descriptors belong to the image header, not to the
      // module's semantic delta. Excluding this hidden subtree is what keeps a
      // linked module independent of how many dependencies were already loaded.
      std::unordered_set<std::uint64_t> dependencyRecords;
      const std::uint64_t rootId = captured.front().id;
      for (const Record &record : captured)
        if (record.parent == rootId && record.key == ImageDependenciesName) {
          dependencyRecords.insert(record.id);
          break;
        }
      if (!dependencyRecords.empty()) {
        bool changed = true;
        while (changed) {
          changed = false;
          for (const Record &record : captured)
            if (!dependencyRecords.contains(record.id) && dependencyRecords.contains(record.parent)) {
              dependencyRecords.insert(record.id);
              changed = true;
            }
        }
      }

      std::vector<const Record *> local;
      local.reserve(captured.size());
      std::unordered_map<std::uint64_t, std::uint64_t> localIds;
      for (const Record &record : captured) {
        const auto parent = byId.find(record.parent);
        // Keep symbolic type metadata for IDs inherited from a base image.
        const bool typeMetadata = compilerTypeMetadata(
            record.payload, parent == byId.end() ? std::vector<std::uint8_t>{} : parent->second->payload);
        if ((record.sourceAddress < since && !typeMetadata) || dependencyRecords.contains(record.id)) continue;
        const std::uint64_t id = local.size() + 1;
        if ((id & ExternalReferenceMask) != 0) THROW(, "linked engine image has too many local phrases")
        localIds.emplace(record.id, id);
        local.push_back(&record);
      }

      std::unordered_set<std::uint64_t> externalIds;
      const auto collect = [&](std::uint64_t id) {
        if (id != 0 && !localIds.contains(id)) externalIds.insert(id);
      };
      for (const Record *record : local) {
        collect(record->parent);
        collect(record->prototypeId);
        collect(record->typeId);
        collect(record->successorId);
        collect(record->actionImplementationId);
        for (const Relocation &relocation : record->relocations)
          if (relocation.kind == RelocationKind::Phrase) collect(relocation.phrase);
      }

      struct ExternalEntry {
        std::uint64_t originalId = 0;
        ExternalReference reference;
        std::string key;
      };
      std::vector<ExternalEntry> externalEntries;
      externalEntries.reserve(externalIds.size());
      for (const std::uint64_t id : externalIds) {
        const auto found = byId.find(id);
        if (found == byId.end()) THROW(, "linked engine image contains an unknown external phrase")
        ExternalReference reference = describeExternal(context, *found->second, byId);
        externalEntries.push_back({id, reference, externalReferenceKey(reference)});
      }
      std::sort(externalEntries.begin(), externalEntries.end(), [](const auto &left, const auto &right) {
        return left.key < right.key;
      });

      LinkedSnapshot result;
      result.dependencies = portableDependencies(context, outputPath);
      result.external.reserve(externalEntries.size());
      std::unordered_map<std::uint64_t, std::uint64_t> externalReferences;
      for (std::size_t index = 0; index < externalEntries.size(); ++index) {
        if (index + 1 >= ExternalReferenceMask) THROW(, "linked engine image has too many external phrases")
        result.external.push_back(std::move(externalEntries[index].reference));
        externalReferences.emplace(externalEntries[index].originalId,
                                   ExternalReferenceMask | static_cast<std::uint64_t>(index + 1));
      }

      const auto remap = [&](std::uint64_t id) -> std::uint64_t {
        if (id == 0) return 0;
        if (const auto found = localIds.find(id); found != localIds.end()) return found->second;
        const auto external = externalReferences.find(id);
        if (external == externalReferences.end()) THROW(, "linked engine image lost an external phrase reference")
        return external->second;
      };

      result.phrases.reserve(local.size());
      for (const Record *source : local) {
        Record record = *source;
        record.id = localIds.at(source->id);
        record.parent = remap(source->parent);
        record.prototypeId = remap(source->prototypeId);
        record.typeId = remap(source->typeId);
        record.successorId = remap(source->successorId);
        record.actionImplementationId = remap(source->actionImplementationId);
        for (Relocation &relocation : record.relocations)
          if (relocation.kind == RelocationKind::Phrase) relocation.phrase = remap(relocation.phrase);
        record.sourceAddress = 0;
        record.parentAddress = 0;
        record.depth = 0;
        result.phrases.push_back(std::move(record));
      }
      return result;
    }

    void writeRecord(Writer &writer, const Record &record) {
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

    Record readRecord(context::Context &context, Reader &reader) {
      Record record;
      record.id = reader.number(8);
      record.parent = reader.number(8);
      record.key = reader.text();
      record.keyBits = reader.number(8);
      if (record.keyBits > record.key.size() * Byte::length || record.key.size() != Bit::bytes(record.keyBits))
        THROW(, "engine image phrase key size does not match its bit length")
      if (record.keyBits % Byte::length != 0 && !record.key.empty() &&
          (static_cast<std::uint8_t>(record.key.back()) &
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
      if (record.action && !record.actionName.empty()) (void)context.actions().get(record.actionName);
      return record;
    }

    std::vector<std::uint8_t> encodeLinked(const LinkedSnapshot &snapshot) {
      Writer writer;
      writer.bytes.insert(writer.bytes.end(), LinkedMagic.begin(), LinkedMagic.end());
      writer.number(LinkedVersion, 4);
      writer.number(sizeof(Size), 1);
      writer.number(sizeof(void *), 1);
      writer.number(snapshot.dependencies.size(), 4);
      for (const ImageDependency &dependency : snapshot.dependencies) {
        writer.text(dependency.identity);
        writer.text(dependency.path);
      }
      writer.number(snapshot.external.size(), 4);
      for (const ExternalReference &reference : snapshot.external) {
        writer.number(reference.path.size(), 4);
        for (const PathElement &element : reference.path) {
          writer.text(element.key);
          writer.number(element.keyBits, 8);
        }
        writer.number(reference.older, 4);
      }
      writer.number(snapshot.phrases.size(), 8);
      for (const Record &record : snapshot.phrases) writeRecord(writer, record);
      return writer.bytes;
    }

    LinkedSnapshot decodeLinked(context::Context &context, std::span<const std::uint8_t> bytes) {
      Reader reader(bytes);
      for (std::uint8_t expected : LinkedMagic)
        if (reader.number(1) != expected) THROW(, "invalid linked engine image magic")
      if (reader.number(4) != LinkedVersion) THROW(, "unsupported linked engine image version")
      if (reader.number(1) != sizeof(Size) || reader.number(1) != sizeof(void *))
        THROW(, "linked engine image ABI does not match this runtime")

      LinkedSnapshot result;
      const std::size_t dependencyCount = reader.number(4);
      result.dependencies.reserve(dependencyCount);
      std::unordered_set<std::string> dependencyIdentities;
      for (std::size_t index = 0; index < dependencyCount; ++index) {
        ImageDependency dependency{reader.text(), reader.text()};
        if (dependency.identity.empty() || dependency.path.empty() || dependency.path.find('\0') != std::string::npos ||
            !dependencyIdentities.insert(dependency.identity).second)
          THROW(, "linked engine image contains an invalid dependency descriptor")
        result.dependencies.push_back(std::move(dependency));
      }

      const std::size_t externalCount = reader.number(4);
      result.external.reserve(externalCount);
      for (std::size_t index = 0; index < externalCount; ++index) {
        ExternalReference reference;
        const std::size_t pathCount = reader.number(4);
        reference.path.reserve(pathCount);
        for (std::size_t pathIndex = 0; pathIndex < pathCount; ++pathIndex) {
          PathElement element{reader.text(), reader.number(8)};
          if (element.keyBits > element.key.size() * Byte::length || element.key.size() != Bit::bytes(element.keyBits))
            THROW(, "linked engine image external path has an invalid key size")
          if (element.keyBits % Byte::length != 0 && !element.key.empty() &&
              (static_cast<std::uint8_t>(element.key.back()) &
               ((1u << (Byte::length - element.keyBits % Byte::length)) - 1)) != 0)
            THROW(, "linked engine image external path has non-zero padding bits")
          reference.path.push_back(std::move(element));
        }
        reference.older = static_cast<std::uint32_t>(reader.number(4));
        result.external.push_back(std::move(reference));
      }

      const std::size_t count = reader.number(8);
      result.phrases.reserve(count);
      std::unordered_set<std::uint64_t> ids;
      std::unordered_map<std::uint64_t, bool> dictionaries;
      for (std::size_t index = 0; index < count; ++index) {
        Record record = readRecord(context, reader);
        if (record.id == 0 || (record.id & ExternalReferenceMask) != 0 || !ids.insert(record.id).second)
          THROW(, "linked engine image contains an invalid local phrase id")
        dictionaries.emplace(record.id, record.subdictionary);
        result.phrases.push_back(std::move(record));
      }
      if (!reader.done()) THROW(, "linked engine image contains trailing bytes")

      const auto validReference = [&](std::uint64_t id) {
        if (id == 0) return true;
        if ((id & ExternalReferenceMask) != 0) {
          const std::uint64_t external = id & ~ExternalReferenceMask;
          return external != 0 && external <= result.external.size();
        }
        return ids.contains(id);
      };
      std::unordered_set<std::uint64_t> available;
      for (const Record &record : result.phrases) {
        if (!validReference(record.parent) || !validReference(record.prototypeId) || !validReference(record.typeId) ||
            !validReference(record.successorId) || !validReference(record.actionImplementationId))
          THROW(, "linked engine image contains an unresolved phrase reference")
        if (record.parent == 0) THROW(, "linked engine image local phrase has no owner")
        if ((record.parent & ExternalReferenceMask) == 0) {
          if (!available.contains(record.parent))
            THROW(, "linked engine image phrase is declared before its dictionary owner")
          if (!dictionaries.at(record.parent)) THROW(, "linked engine image phrase owner has no subdictionary")
        }
        if ((!record.prototype && record.prototypeId != 0) || (!record.type && record.typeId != 0) ||
            (!record.successor && record.successorId != 0))
          THROW(, "linked engine image assigns a reference to a phrase without the corresponding slot")
        if (!record.action && (!record.actionName.empty() || record.actionImplementationId != 0))
          THROW(, "linked engine image assigns an action to a phrase without an action slot")
        for (const Relocation &relocation : record.relocations)
          if (relocation.kind == RelocationKind::Phrase) {
            if (!relocation.action.empty() || !validReference(relocation.phrase))
              THROW(, "linked engine image contains an invalid payload phrase relocation")
          } else if (relocation.phrase != 0) {
            THROW(, "linked engine image action relocation contains a phrase id")
          }
        available.insert(record.id);
      }
      return result;
    }

    void applyLinked(context::Context &context, LinkedSnapshot snapshot) {
      std::vector<lexicon::Phrase> external;
      external.reserve(snapshot.external.size());
      for (const ExternalReference &reference : snapshot.external) external.push_back(resolveExternal(context, reference));
      rebaseTypes(context, snapshot.phrases, [&](std::uint64_t id) {
        const auto index = id & ~ExternalReferenceMask;
        if (!(id & ExternalReferenceMask) || index == 0 || index > external.size())
          THROW(, "linked engine image compiler reference is unavailable")
        return external[index - 1];
      });

      std::unordered_map<std::uint64_t, lexicon::Phrase> phrases;
      phrases.reserve(snapshot.phrases.size());
      lexicon::Phrase undefined(&context.lexicon);
      const auto resolve = [&](std::uint64_t id) -> lexicon::Phrase {
        if (id == 0) return undefined;
        if ((id & ExternalReferenceMask) != 0) {
          const std::uint64_t index = id & ~ExternalReferenceMask;
          if (index == 0 || index > external.size()) THROW(, "linked engine image external reference is out of range")
          return external[index - 1];
        }
        const auto found = phrases.find(id);
        if (found == phrases.end()) THROW(, "linked engine image local phrase reference is unavailable")
        return found->second;
      };

      for (const Record &record : snapshot.phrases) {
        lexicon::Phrase owner = resolve(record.parent);
        if (owner.isNull() || !owner.containsSubdictionary())
          THROW(, "linked engine image phrase owner is not a dictionary")
        lexicon::Draft draft = owner.append(Byte(const_cast<char *>(record.key.data())), 0, record.keyBits).make();
        if (record.subdictionary) draft.enableSubdictionary();
        if (record.prototype) draft.setPrototype(undefined);
        if (record.type) draft.setType(undefined);
        if (record.action)
          draft.setAction(record.actionName.empty() ? nullptr : context.actions().get(record.actionName));
        if (record.successor) draft.setSuccessor(undefined);
        lexicon::Phrase phrase = draft.save();
        if (!record.payload.empty()) {
          Byte output = phrase.allocate(record.payload.size());
          std::memcpy(output.toPtr(), record.payload.data(), record.payload.size());
        }
        phrases.emplace(record.id, phrase);
      }

      for (const Record &record : snapshot.phrases) {
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

    void prepareDependencyPaths(std::vector<Record> &records, const std::filesystem::path &outputPath) {
      if (records.empty()) return;
      const std::uint64_t root = records.front().id;
      std::uint64_t owner = 0;
      for (const Record &record : records)
        if (record.parent == root && record.key == ImageDependenciesName) {
          owner = record.id;
          break;
        }
      if (owner == 0) return;

      const std::filesystem::path output = absolutePath(outputPath);
      const std::filesystem::path directory = output.parent_path();
      for (Record &record : records) {
        if (record.parent != owner) continue;
        const std::string stored(reinterpret_cast<const char *>(record.payload.data()), record.payload.size());
        if (stored.empty() || stored.find('\0') != std::string::npos)
          THROW(, "engine image contains an invalid dependency path")
        const std::filesystem::path dependency = absolutePath(stored);
        std::filesystem::path relative = dependency.lexically_relative(directory);
        const std::string portable = relative.empty() ? dependency.generic_string() : relative.generic_string();
        record.payload.assign(portable.begin(), portable.end());
      }
    }

    void removeDependencyMetadata(std::vector<Record> &records) {
      if (records.empty()) return;
      const std::uint64_t root = records.front().id;
      std::uint64_t owner = 0;
      for (const Record &record : records)
        if (record.parent == root && record.key == ImageDependenciesName) {
          owner = record.id;
          break;
        }
      if (owner == 0) return;
      std::erase_if(records, [&](const Record &record) { return record.id == owner || record.parent == owner; });
    }

    void removeSelfDependency(std::vector<Record> &records, const std::filesystem::path &outputPath) {
      if (records.empty()) return;
      const std::uint64_t root = records.front().id;
      std::uint64_t owner = 0;
      for (const Record &record : records)
        if (record.parent == root && record.key == ImageDependenciesName) {
          owner = record.id;
          break;
        }
      if (owner == 0) return;

      const std::filesystem::path output = absolutePath(outputPath);
      std::erase_if(records, [&](const Record &record) {
        if (record.parent != owner) return false;
        const std::string stored(reinterpret_cast<const char *>(record.payload.data()), record.payload.size());
        if (stored.empty() || stored.find('\0') != std::string::npos) return false;
        return absolutePath(stored) == output;
      });
    }

    Snapshot decodeRecords(context::Context &context, std::span<const std::uint8_t> bytes) {
      Reader reader(bytes);
      for (std::uint8_t expected : Magic)
        if (reader.number(1) != expected) THROW(, "invalid engine image magic")
      const std::uint64_t version = reader.number(4);
      if (version != 7 && version != EngineImage::Version) THROW(, "unsupported engine image version")
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

    std::unordered_set<Size> promotionSelection(std::span<const lexicon::Phrase> roots, Size checkpoint,
                                                       lexicon::Lexicon &lexicon) {
      std::unordered_set<Size> selected;
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      std::vector<lexicon::Phrase> pending;
      for (lexicon::Phrase root : roots) {
        if (root.isNull() || root.getLexicon() != &lexicon) THROW(, "promotion root does not belong to this lexicon")
        root.load();
        if (root.getAddress() < checkpoint) THROW(, "promotion root predates the transaction checkpoint")
        pending.push_back(root);
      }
      while (!pending.empty()) {
        lexicon::Phrase phrase = pending.back();
        pending.pop_back();
        if (!selected.insert(phrase.getAddress()).second) continue;
        if (!phrase.isSerializable()) THROW(, "promotion cannot preserve an unserializable phrase")
        if (!phrase.containsSubdictionary()) continue;
        for (lexicon::Dictionary child = phrase.fore(populated); !child.isNull(); child = child.next(populated)) {
          lexicon::Phrase nested = child.getPhrase();
          if (nested.isSerializable()) pending.push_back(nested);
        }
      }
      return selected;
    }

    void replayPromotion(context::Context &context, Size checkpoint, const std::vector<Record> &records,
                         const std::unordered_map<std::uint64_t, Size> &addresses,
                         const std::unordered_set<Size> &selected) {
      std::unordered_map<Size, lexicon::Phrase> replayed;
      lexicon::Phrase undefined(&context.lexicon);

      const auto resolveAddress = [&](Size address) -> lexicon::Phrase {
        if (address == 0) return undefined;
        if (const auto found = replayed.find(address); found != replayed.end()) return found->second;
        if (address >= checkpoint) THROW(, "promoted state depends on discarded post-checkpoint state")
        lexicon::Phrase phrase(&context.lexicon, address);
        phrase.load();
        if (phrase.isNull()) THROW(, "promotion dependency is unavailable after rollback")
        return phrase;
      };
      const auto resolveId = [&](std::uint64_t id) -> lexicon::Phrase {
        if (id == 0) return undefined;
        const auto found = addresses.find(id);
        if (found == addresses.end()) THROW(, "promotion contains an unknown phrase reference")
        return resolveAddress(found->second);
      };

      for (const Record &record : records) {
        if (!selected.contains(record.sourceAddress)) continue;
        lexicon::Phrase owner = resolveAddress(record.parentAddress);
        if (owner.isNull() || !owner.containsSubdictionary()) THROW(, "promotion owner is unavailable after rollback")
        lexicon::Draft draft = owner.append(Byte(const_cast<char *>(record.key.data())), 0, record.keyBits).make();
        if (record.subdictionary) draft.enableSubdictionary();
        if (record.prototype) draft.setPrototype(undefined);
        if (record.type) draft.setType(undefined);
        if (record.action) {
          if (record.actionName.empty()) THROW(, "promotion contains an unnamed phrase action")
          draft.setAction(context.actions().get(record.actionName));
        }
        if (record.successor) draft.setSuccessor(undefined);
        lexicon::Phrase phrase = draft.save();
        if (!record.payload.empty()) {
          Byte output = phrase.allocate(record.payload.size());
          std::memcpy(output.toPtr(), record.payload.data(), record.payload.size());
        }
        replayed.emplace(record.sourceAddress, phrase);
      }

      for (const Record &record : records) {
        if (!selected.contains(record.sourceAddress)) continue;
        lexicon::Phrase phrase = replayed.at(record.sourceAddress);
        if (record.prototype) phrase.setPrototype(resolveId(record.prototypeId));
        if (record.type) phrase.setType(resolveId(record.typeId));
        if (record.successor) phrase.setSuccessor(resolveId(record.successorId));
        if (record.action) phrase.setActionImplementation(resolveId(record.actionImplementationId));
        if (record.rewritable) phrase.setRewritable(true);
        if (record.permanent) phrase.setPermanent(true);
        phrase.save();
        for (const Relocation &relocation : record.relocations) {
          if (relocation.kind == RelocationKind::Phrase) {
            lexicon::Phrase target = resolveId(relocation.phrase);
            const Size address = target.getAddress();
            std::memcpy(phrase.content(relocation.offset, sizeof(address)).toPtr(), &address, sizeof(address));
          } else {
            const lexicon::Phrase::Action action =
                relocation.action.empty() ? nullptr : context.actions().get(relocation.action);
            std::memcpy(phrase.content(relocation.offset, sizeof(action)).toPtr(), &action, sizeof(action));
          }
        }
      }
    }

    void restore(context::Context &context, Snapshot snapshot, bool initializeSemanticDefaults, bool preserveExisting) {
      if (preserveExisting) rebaseTypes(context, snapshot.phrases);
      const std::vector<Record> &records = snapshot.phrases;
      // Normal image imports are composable overlays and therefore need a
      // complete capture of the current graph before replacement. A project
      // cache checkpoint is already a self-contained full graph; when the
      // caller guarantees a baseline-reset cache walk, skipping this capture
      // avoids an otherwise redundant full graph traversal and path index.
      const std::vector<Record> previous = preserveExisting ? capture(context) : std::vector<Record>{};
      const std::uint64_t previousRoot = previous.empty() ? 0 : previous.front().id;

      std::vector<Record> preserved;
      if (preserveExisting) {
        // Composable imports preserve every phrase whose exact binary path is
        // absent from the incoming image. Full project checkpoints skip this
        // entire path-indexing pass because they intentionally replace the
        // graph produced by a baseline-reset build session.
        const auto indexPaths = [](const std::vector<Record> &source) {
          std::unordered_map<std::uint64_t, std::string> paths;
          paths.reserve(source.size());
          for (const Record &record : source) {
            if (record.parent == 0) {
              paths.emplace(record.id, std::string{});
              continue;
            }
            const auto parent = paths.find(record.parent);
            if (parent == paths.end()) THROW(, "engine image phrase is declared before its path parent")
            std::string path = parent->second;
            const std::uint64_t bytes = record.key.size();
            path.append(reinterpret_cast<const char *>(&record.keyBits), sizeof(record.keyBits));
            path.append(reinterpret_cast<const char *>(&bytes), sizeof(bytes));
            path.append(record.key);
            paths.emplace(record.id, std::move(path));
          }
          return paths;
        };
        const auto importedPathsById = indexPaths(records);
        const auto previousPathsById = indexPaths(previous);
        std::unordered_set<std::string> importedPaths;
        importedPaths.reserve(records.size());
        for (const Record &record : records) importedPaths.insert(importedPathsById.at(record.id));

        preserved.reserve(previous.size());
        for (const Record &record : previous) {
          if (record.parent == 0) continue;
          if (!importedPaths.contains(previousPathsById.at(record.id))) preserved.push_back(record);
        }
      }

      const auto registeredActions = context.actions().snapshot();
      std::unordered_map<std::string, lexicon::Phrase::Action> actionPointers;
      for (const auto &[name, pointer] : registeredActions) actionPointers.emplace(name, pointer);
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

      Semantic::InspectionRelocation inspection(context);
      context.lexicon.clear();
      context.exec.valueScopes.clear();

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
      const auto resolvePreviousPath = [&](std::uint64_t id) {
        if (id == previousRoot) return root;
        std::vector<std::pair<std::string, std::uint64_t>> path;
        std::uint64_t cursor = id;
        while (cursor != previousRoot) {
          const auto found = previousById.find(cursor);
          if (found == previousById.end()) THROW(, "preserved phrase owner references an unknown phrase")
          path.emplace_back(found->second->key, found->second->keyBits);
          cursor = found->second->parent;
        }
        lexicon::Phrase target = root;
        for (auto key = path.rbegin(); key != path.rend(); ++key) {
          target = exact(target, key->first, key->second);
          if (target.isNull()) THROW(, "preserved phrase owner is absent from the imported language")
        }
        return target;
      };
      for (const Record &record : preserved) {
        lexicon::Phrase owner;
        if (record.parent == previousRoot) owner = root;
        else if (const auto retained = preservedPhrases.find(record.parent); retained != preservedPhrases.end())
          owner = retained->second;
        else
          owner = resolvePreviousPath(record.parent);
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

      // Only retained records keep their identity. Imported replacements and
      // versions dropped by serialization keep the facts captured before clear.
      std::unordered_map<Size, Size> relocated;
      if (Semantic::active(context))
        for (const Record &record : preserved)
          relocated.emplace(record.sourceAddress, preservedPhrases.at(record.id).getAddress());
      inspection.relocate([&](std::uint64_t address) {
        const auto found = relocated.find(address);
        return found == relocated.end() ? 0 : found->second;
      });

      root.load();
      // The action registry is process-local kernel state and is intentionally
      // excluded from .rli images. Recreate the names used by the restored
      // image after the lexicon replacement.
      context.actions().restore(registeredActions);
      if (initializeSemanticDefaults) {
        context::Values::setup(root);
        // Compiler registry topology is part of the serialized/source-defined
        // language image. Loading an image validates it; production C++ no
        // longer synthesizes hidden registry names or defaults.
        (void)compiler::LanguageState::locate(context.lexicon);
      }
      context.lookup = {};
      context.staging = {};
      context.reference = {};
      context::Lookup::in(context, root);
      context::Staging::push(context, root);
      context::Reference::in(context, root);
    }

    void loadImage(context::Context &context, const std::filesystem::path &path,
                   std::unordered_set<std::string> &loading, const std::string *expectedIdentity = nullptr) {
      if (expectedIdentity != nullptr && hasImageDependency(context, *expectedIdentity)) return;

      const std::filesystem::path resolved = absolutePath(path);
      const std::vector<std::uint8_t> bytes = EngineImage::read(resolved.string());
      const std::string identity = imageIdentity(bytes);
      if (expectedIdentity != nullptr && identity != *expectedIdentity)
        THROW(, "engine image dependency identity mismatch for '" << resolved.string() << "'")
      if (hasImageDependency(context, identity)) return;
      if (!loading.insert(identity).second)
        THROW(, "engine image dependency cycle contains '" << resolved.string() << "'")

      try {
        const bool linked = linkedMagic(bytes);
        LinkedSnapshot linkedSnapshot;
        Snapshot snapshot;
        std::vector<ImageDependency> dependencies;
        if (linked) {
          linkedSnapshot = decodeLinked(context, bytes);
          dependencies = linkedSnapshot.dependencies;
        } else {
          snapshot = decodeRecords(context, bytes);
          dependencies = imageDependencies(snapshot);
        }

        std::vector<std::pair<ImageDependency, std::filesystem::path>> resolvedDependencies;
        resolvedDependencies.reserve(dependencies.size());
        for (const ImageDependency &dependency : dependencies) {
          std::filesystem::path dependencyPath(dependency.path);
          if (dependencyPath.is_relative()) dependencyPath = resolved.parent_path() / dependencyPath;
          dependencyPath = absolutePath(dependencyPath);
          resolvedDependencies.emplace_back(dependency, dependencyPath);
          loadImage(context, dependencyPath, loading, &resolvedDependencies.back().first.identity);
        }

        if (linked) applyLinked(context, linkedSnapshot);
        else restore(context, snapshot, true, true);
        for (const auto &[dependency, dependencyPath] : resolvedDependencies)
          rememberImageDependency(context, dependency.identity, dependencyPath);
        rememberImageDependency(context, identity, resolved);
      } catch (...) {
        loading.erase(identity);
        throw;
      }
      loading.erase(identity);
    }
  } // namespace

  std::vector<std::uint8_t> EngineImage::encode(context::Context &context) {
    return encodeRecords(capture(context));
  }

  std::vector<std::uint8_t> EngineImage::encode(context::Context &context, Size since) {
    return encodeRecords(capture(context, since));
  }

  void EngineImage::decode(context::Context &context, std::span<const std::uint8_t> bytes) {
    restore(context, decodeRecords(context, bytes), true, true);
  }

  void EngineImage::decodeExact(context::Context &context, std::span<const std::uint8_t> bytes) {
    restore(context, decodeRecords(context, bytes), false, true);
  }

  void EngineImage::merge(context::Context &context, std::span<const std::uint8_t> bytes, lexicon::Phrase target) {
    mergeSnapshot(context, decodeRecords(context, bytes), target);
  }

  void EngineImage::merge(context::Context &context, lexicon::Phrase source, lexicon::Phrase target) {
    mergeDictionary(context, source, target);
  }

  void EngineImage::declarePayloadField(context::Context &context, lexicon::Phrase schema, std::size_t offset,
                                        PayloadFieldKind kind) {
    if (schema.isNull() || schema.getLexicon() != &context.lexicon)
      THROW(, "engine image payload layout schema does not belong to this lexicon")
    if (kind != PayloadFieldKind::PhraseReference && kind != PayloadFieldKind::NativePointer)
      THROW(, "unsupported engine image payload layout field kind")

    lexicon::Phrase layouts = imageLayouts(context, true);
    lexicon::Phrase lexiconRoot = context.lexicon.phrase();
    lexicon::Phrase dataType = lexicon::phrase::type::getData(lexiconRoot);
    lexicon::Phrase layout(&context.lexicon);
    auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
    for (lexicon::Dictionary entry = layouts.fore(populated); !entry.isNull(); entry = entry.next(populated)) {
      lexicon::Phrase candidate = entry.getPhrase();
      if (candidate.containsSuccessor() && candidate.getSuccessor().getAddress() == schema.getAddress()) {
        layout = candidate;
        break;
      }
    }
    if (layout.isNull()) {
      layout = layouts.append(binaryKey(schema.getAddress()))
                   .make()
                   .enableSubdictionary()
                   .setType(dataType)
                   .setSuccessor(schema)
                   .save();
    }

    const std::string key = binaryKey(static_cast<std::uint64_t>(offset));
    layout.append(key)
        .make()
        .setType(dataType)
        .save()
        .store(static_cast<std::uint8_t>(kind))
        .save();
  }

  void EngineImage::promote(context::Context &context, Size checkpoint, std::span<const lexicon::Phrase> roots) {
    if (roots.empty()) {
      radix::Checkpoint(&context.lexicon, checkpoint).restore();
      return;
    }
    const std::unordered_set<Size> selected = promotionSelection(roots, checkpoint, context.lexicon);
    const std::vector<Record> captured = capture(context, checkpoint);
    std::unordered_map<std::uint64_t, Size> addresses;
    addresses.reserve(captured.size());
    std::unordered_set<Size> available;
    for (const Record &record : captured) {
      addresses.emplace(record.id, record.sourceAddress);
      available.insert(record.sourceAddress);
    }
    for (Size address : selected)
      if (!available.contains(address))
        THROW(, "promotion selected a phrase that is not serializable from the transaction delta")

    const auto requireReference = [&](std::uint64_t id) {
      if (id == 0) return;
      const auto found = addresses.find(id);
      if (found == addresses.end()) THROW(, "promotion contains an unresolved phrase reference")
      if (found->second >= checkpoint && !selected.contains(found->second))
        THROW(, "promoted state depends on unselected post-checkpoint state")
    };
    for (const Record &record : captured) {
      if (!selected.contains(record.sourceAddress)) continue;
      if (record.parentAddress >= checkpoint && !selected.contains(record.parentAddress))
        THROW(, "promoted phrase is owned by unselected post-checkpoint state")
      if (record.prototype) requireReference(record.prototypeId);
      if (record.type) requireReference(record.typeId);
      if (record.successor) requireReference(record.successorId);
      if (record.action) requireReference(record.actionImplementationId);
      for (const Relocation &relocation : record.relocations)
        if (relocation.kind == RelocationKind::Phrase) requireReference(relocation.phrase);
    }

    radix::Checkpoint(&context.lexicon, checkpoint).restore();
    const Size replayCheckpoint = context.lexicon.checkpoint().getAddress();
    try {
      replayPromotion(context, checkpoint, captured, addresses, selected);
    } catch (...) {
      radix::Checkpoint(&context.lexicon, replayCheckpoint).restore();
      throw;
    }
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

  void EngineImage::define(context::Context &context, std::string_view source, std::string_view sourcePath) {
    // `engine define` has two source forms:
    //
    //  * EngineImage::source() emits the historical numeric manifest used for
    //    lossless source-image round trips ("phrase <id> parent ...").
    //  * libraries/recurloop/core.rl uses the semantic source-core format
    //    ("phrase <label> = <key> in <parent> {").
    //
    // Keep the old manifest reader for generated/source images while routing
    // the human-authored core definition through the semantic bootstrap
    // parser.  The third token is an unambiguous discriminator between both
    // grammars and preserves compatibility with source images produced before
    // the source-defined-core migration.
    std::istringstream input{std::string(source)};
    std::string line;
    for (std::size_t lineNumber = 1; std::getline(input, line); ++lineNumber) {
      const std::vector<std::string> fields = tokens(line, lineNumber);
      if (fields.empty()) continue;
      if ((fields[0] == "phrase" && fields.size() >= 3 && fields[2] == "parent") || fields[0] == "relocate") {
        restore(context, parseManifest(context, source), true, true);
        return;
      }
      break;
    }
    internal::CoreDefinition::apply(context, source, sourcePath);
  }

  std::vector<std::uint8_t> EngineImage::read(const std::string &path) {
    if (path.empty()) THROW(, "engine image path cannot be empty")
    std::ifstream input(path, std::ios::binary);
    if (!input.is_open()) THROW(, "cannot open engine image for reading: '" << path << "'")
    std::vector<std::uint8_t> bytes{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
    if (input.bad()) THROW(, "cannot read engine image: '" << path << "'")
    return bytes;
  }

  void EngineImage::write(std::span<const std::uint8_t> bytes, const std::string &path) {
    if (path.empty()) THROW(, "engine image path cannot be empty")
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output.is_open()) THROW(, "cannot open engine image for writing: '" << path << "'")
    output.write(reinterpret_cast<const char *>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    output.close();
    if (!output) THROW(, "cannot write engine image: '" << path << "'")
  }

  void EngineImage::save(context::Context &context, const std::string &path) {
    Size base = imageExportBase(context);
    if (hasImageDependencyPath(context, path)) base = 0;
    std::vector<Record> records = capture(context, base);
    if (base == 0) {
      // A full snapshot is self-contained. Loaded-image metadata is useful to
      // this process for duplicate suppression, but must not make a standalone
      // export depend on files it already contains.
      removeDependencyMetadata(records);
    } else {
      removeSelfDependency(records, path);
      prepareDependencyPaths(records, path);
    }
    const std::vector<std::uint8_t> bytes = encodeRecords(records);
    write(bytes, path);
  }

  void EngineImage::saveLinked(context::Context &context, Size since, const std::string &path) {
    const LinkedSnapshot snapshot = captureLinked(context, since, path);
    write(encodeLinked(snapshot), path);
  }

  void EngineImage::saveFull(context::Context &context, const std::string &path) {
    std::vector<Record> records = capture(context);
    // A project checkpoint must be self-contained. In particular it must carry
    // in-place updates to phrases that came from the baseline image; an
    // incremental export can only describe newly appended phrases.
    removeDependencyMetadata(records);
    write(encodeRecords(records), path);
  }

  void EngineImage::load(context::Context &context, const std::string &path) {
    std::unordered_set<std::string> loading;
    loadImage(context, path, loading);
  }

  void EngineImage::loadFull(context::Context &context, const std::string &path) {
    const Snapshot snapshot = decodeRecords(context, read(path));
    if (!imageDependencies(snapshot).empty())
      THROW(, "full engine snapshot unexpectedly contains image dependencies")
    restore(context, snapshot, true, false);
  }

  void EngineImage::rememberDependency(context::Context &context, const std::string &path) {
    const std::filesystem::path resolved = absolutePath(path);
    const std::vector<std::uint8_t> bytes = read(resolved.string());
    rememberImageDependency(context, imageIdentity(bytes), resolved);
  }

  std::vector<std::string> EngineImage::dependencyPaths(context::Context &context) {
    std::vector<std::string> result;
    for (const ImageDependency &dependency : imageDependencies(context))
      result.push_back(absolutePath(dependency.path).string());
    return result;
  }


  void EngineImage::releaseNativeState(context::Context &context) noexcept {
    try {
      if (context.lexicon.getMemory().isNull()) return;
      const PayloadLayouts layouts = loadPayloadLayouts(context);
      if (layouts.empty()) return;

      std::unordered_set<Size> visited;
      std::vector<lexicon::Phrase> pending{context.lexicon.phrase()};
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      while (!pending.empty()) {
        lexicon::Phrase phrase = pending.back();
        pending.pop_back();
        if (phrase.isNull() || !visited.insert(phrase.getAddress()).second) continue;

        const auto *fields = payloadLayout(layouts, phrase);
        bool liveNative = false;
        if (fields != nullptr) {
          for (const PayloadLayoutField &field : *fields) {
            if (field.kind != PayloadFieldKind::NativePointer ||
                field.offset > phrase.payloadSize() ||
                sizeof(std::uintptr_t) > phrase.payloadSize() - field.offset)
              continue;
            std::uintptr_t pointer = 0;
            std::memcpy(&pointer, phrase.content(field.offset, sizeof(pointer)).toPtr(), sizeof(pointer));
            if (pointer != 0) {
              liveNative = true;
              break;
            }
          }
        }

        if (liveNative && phrase.containsAction() && phrase.getAction() != nullptr) {
          try {
            phrase.getAction()(context, phrase);
          } catch (...) {
            // Teardown is best effort. The engine must still release its own
            // arenas and executable mappings even if a library finalizer fails.
          }
        }

        if (!phrase.containsSubdictionary()) continue;
        for (lexicon::Dictionary child = phrase.fore(populated); !child.isNull(); child = child.next(populated))
          pending.push_back(child.getPhrase());
      }
    } catch (...) {
      // Destructors call this path; never let cleanup escape.
    }
  }

  void EngineImage::markExportBase(context::Context &context) {
    if (imageDependencies(context, false).isNull()) return;
    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase marker = root.append(std::string(ImageExportBaseName))
                                 .make()
                                 .setType(lexicon::phrase::type::getData(root))
                                 .save();
    marker.setSerializable(false).save();
    marker.store(Size{0});
    const Size checkpoint = context.lexicon.checkpoint().getAddress();
    marker.update(0, checkpoint);
  }
} // namespace recurloop
