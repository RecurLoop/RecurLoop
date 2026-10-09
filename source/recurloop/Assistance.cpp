#include <recurloop/Assistance.hpp>

#include <context/Context.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/Semantic.hpp>
#include <recurloop/SyntaxPattern.hpp>
#include <utilities/Exception.hpp>

#include <cstddef>
#include <unordered_set>

namespace recurloop {
  namespace {
    constexpr std::string_view Registry{"\0phrase-help", 12};
    constexpr std::string_view Schema{"\0phrase-help-schema", 19};
    struct Attachment {
      Size target = 0;
      Size descriptor = 0;
    };

    lexicon::Phrase dictionary(context::Context &context, std::string_view key, bool create) {
      auto root = context.lexicon.phrase();
      auto result = LanguageGrammar::find(root, key);
      if (result.isNull() && create)
        result = root.append(std::string(key)).make().enableSubdictionary()
                     .setType(lexicon::phrase::type::getData(root)).save();
      return result;
    }
  } // namespace

  Assistance::Assistance(context::Context &context) : context(context) {
    auto registry = dictionary(context, Registry, false);
    auto schema = dictionary(context, Schema, false);
    if (registry.isNull() || schema.isNull()) return;
    auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
    for (auto item = registry.fore(populated); !item.isNull(); item = item.next(populated)) {
      auto phrase = item.getPhrase();
      if (phrase.isNull() || phrase.payloadSize() != sizeof(Attachment) || !phrase.containsPrototype() ||
          phrase.getPrototype().getAddress() != schema.getAddress()) continue;
      Attachment attachment;
      phrase.fetch(0, attachment);
      if (attachment.target) contracts[attachment.target] = attachment.descriptor;
    }
  }

  void Assistance::attach(context::Context &context, lexicon::Phrase target, lexicon::Phrase descriptor) {
    if (target.isNull()) THROW(, "help requires an owning phrase")
    if (!descriptor.isNull()) {
      auto owner = descriptor;
      std::unordered_set<Size> seen;
      while (!owner.isNull() && !owner.containsSubdictionary() && seen.insert(owner.getAddress()).second)
        owner = owner.containsPrototype() ? owner.getPrototype() : lexicon::Phrase(&context.lexicon);
      if (owner.isNull() || !owner.containsSubdictionary()) THROW(, "help expects a dictionary reference or none")
      auto pattern = child(descriptor, "pattern");
      if (!pattern.isNull()) SyntaxPattern::validate(text(descriptor, "pattern"));
    }
    auto schema = dictionary(context, Schema, true);
    EngineImage::declarePayloadField(context, schema, offsetof(Attachment, target),
                                    EngineImage::PayloadFieldKind::PhraseReference);
    EngineImage::declarePayloadField(context, schema, offsetof(Attachment, descriptor),
                                    EngineImage::PayloadFieldKind::PhraseReference);
    auto registry = dictionary(context, Registry, true);
    const Size address = target.getAddress();
    // Dictionary keys are not relocated during import. Locate an existing
    // attachment by its relocated payload before creating a new record.
    auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
    Size ordinal = 0;
    for (auto item = registry.fore(populated); !item.isNull(); item = item.next(populated)) {
      ++ordinal;
      auto entry = item.getPhrase();
      if (entry.isNull() || entry.payloadSize() != sizeof(Attachment) || !entry.containsPrototype() ||
          entry.getPrototype().getAddress() != schema.getAddress()) continue;
      Attachment attachment;
      entry.fetch(0, attachment);
      if (attachment.target != address) continue;
      entry.update(0, Attachment{address, descriptor.getAddress()}).save();
      Semantic::markInspectionMetadataDirty(context);
      return;
    }
    auto root = context.lexicon.phrase();
    auto key = std::to_string(ordinal);
    while (!LanguageGrammar::find(registry, key).isNull()) key = std::to_string(++ordinal);
    auto entry = registry.append(key)
                         .make().setPrototype(schema).setType(lexicon::phrase::type::getData(root)).save();
    entry.store(Attachment{address, descriptor.getAddress()}).save();
    Semantic::markInspectionMetadataDirty(context);
  }

  lexicon::Phrase Assistance::descriptor(lexicon::Phrase target) const {
    std::unordered_set<Size> visited;
    while (!target.isNull() && visited.insert(target.getAddress()).second) {
      if (auto found = contracts.find(target.getAddress()); found != contracts.end())
        return lexicon::Phrase(&context.lexicon, found->second).load();
      if (!target.containsPrototype()) break;
      target = target.getPrototype();
    }
    return lexicon::Phrase(&context.lexicon);
  }

  lexicon::Phrase Assistance::child(lexicon::Phrase owner, std::string_view key) {
    std::unordered_set<Size> visited;
    while (!owner.isNull() && visited.insert(owner.getAddress()).second) {
      auto result = LanguageGrammar::find(owner, key);
      if (!result.isNull()) return result;
      if (!owner.containsPrototype()) break;
      owner = owner.getPrototype();
    }
    return lexicon::Phrase(owner.getLexicon());
  }

  std::vector<lexicon::Phrase> Assistance::children(lexicon::Phrase owner) {
    std::vector<lexicon::Phrase> result;
    std::unordered_set<Size> visited;
    std::unordered_set<std::string> keys;
    auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
    while (!owner.isNull() && visited.insert(owner.getAddress()).second) {
      if (owner.containsSubdictionary()) {
        for (auto item = owner.fore(populated); !item.isNull(); item = item.next(populated)) {
          auto phrase = item.getPhrase();
          if (phrase.isNull()) continue;
          auto key = phrase.getKey();
          if (key.empty() || static_cast<unsigned char>(key.front()) < 32 || !keys.insert(key).second) continue;
          result.push_back(phrase);
        }
      }
      if (!owner.containsPrototype()) break;
      owner = owner.getPrototype();
    }
    return result;
  }

  std::string Assistance::text(lexicon::Phrase owner, std::string_view key) {
    auto value = child(owner, key);
    std::unordered_set<Size> seen;
    while (!value.isNull() && seen.insert(value.getAddress()).second) {
      if (value.payloadSize() != 0)
        return std::string(reinterpret_cast<const char *>(value.content(0, value.payloadSize()).toPtr()), value.payloadSize());
      if (!value.containsPrototype()) break;
      value = value.getPrototype();
    }
    return {};
  }
} // namespace recurloop
