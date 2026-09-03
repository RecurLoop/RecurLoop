#include <context/Actions.hpp>

#include <utilities/Exception.hpp>

namespace context {
  namespace {
    constexpr std::string_view RegistryName{"\0runtime-actions", 16};

    lexicon::Phrase exact(lexicon::Phrase dictionary, std::string_view key) {
      if (dictionary.isNull() || !dictionary.containsSubdictionary()) return lexicon::Phrase(dictionary.getLexicon());
      lexicon::Match match = dictionary.matchExact(Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length);
      return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
    }
  } // namespace

  lexicon::Phrase Actions::registry(bool create) const {
    lexicon::Phrase root = lexicon.phrase();
    if (root.isNull()) {
      if (create) THROW(, "cannot create the action phrase registry before the lexicon root")
      return lexicon::Phrase(&lexicon);
    }
    lexicon::Phrase found = exact(root, RegistryName);
    if (!found.isNull() || !create) return found;
    lexicon::Draft draft =
        root.append(Byte(const_cast<char *>(RegistryName.data())), 0, RegistryName.size() * Byte::length)
            .make()
            .enableSubdictionary()
            .setType(lexicon::Phrase(&lexicon));
    lexicon::Phrase types = exact(root, "phrase-types");
    lexicon::Phrase data = exact(types, "data");
    if (!data.isNull()) draft.setType(data);
    return draft.save();
  }

  void Actions::define(std::string name, Action action) {
    if (name.empty()) THROW(, "action name cannot be empty")
    if (action == nullptr) THROW(, "cannot register a null action as '" << name << "'")
    lexicon::Phrase actions = registry(true);
    lexicon::Phrase existing = exact(actions, name);
    if (!existing.isNull()) {
      if (!existing.containsAction() || existing.getAction() != action)
        THROW(, "action name is already registered: '" << name << "'")
      return;
    }
    lexicon::Draft draft = actions.append(std::move(name)).make(action);
    lexicon::Phrase callable = exact(exact(lexicon.phrase(), "phrase-types"), "callable");
    draft.setType(callable.isNull() ? lexicon::Phrase(&lexicon) : callable);
    draft.save();
  }

  Actions::Action Actions::get(std::string_view name) const {
    lexicon::Phrase found = exact(registry(false), name);
    if (found.isNull() || !found.containsAction()) THROW(, "unknown engine action: '" << name << "'")
    return found.getAction();
  }

  std::string Actions::name(Action action) const {
    if (action == nullptr) return {};
    lexicon::Phrase actions = registry(false);
    if (!actions.isNull()) {
      auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
      for (lexicon::Dictionary cursor = actions.fore(populated); !cursor.isNull(); cursor = cursor.next(populated)) {
        lexicon::Phrase phrase = cursor.getPhrase();
        if (!phrase.isNull() && phrase.containsAction() && phrase.getAction() == action) return phrase.getKey();
      }
    }
    THROW(, "cannot export an unregistered phrase action")
  }

  bool Actions::contains(std::string_view name) const {
    lexicon::Phrase found = exact(registry(false), name);
    return !found.isNull() && found.containsAction();
  }

  void Actions::typePhrases() {
    lexicon::Phrase root = lexicon.phrase();
    lexicon::Phrase types = exact(root, "phrase-types");
    lexicon::Phrase data = exact(types, "data");
    lexicon::Phrase callable = exact(types, "callable");
    if (data.isNull() || callable.isNull()) THROW(, "cannot type the action registry before phrase types")
    lexicon::Phrase actions = registry(false);
    if (actions.isNull()) return;
    actions.setType(data).save();
    auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
    for (lexicon::Dictionary cursor = actions.fore(populated); !cursor.isNull(); cursor = cursor.next(populated)) {
      lexicon::Phrase phrase = cursor.getPhrase();
      if (!phrase.isNull()) phrase.setType(callable).save();
    }
  }
} // namespace context
