#include <recurloop/LanguageGrammar.hpp>

#include <lexicon/Dictionary.hpp>
#include <lexicon/Phrase.hpp>

#include <cctype>
#include <unordered_set>

namespace recurloop::LanguageGrammar {
  namespace {

    thread_local context::Context *aliasContext = nullptr;
    thread_local lexicon::Phrase *aliasGrammar = nullptr;
    bool populated(radix::Node *, radix::Node *candidate) {
      return !candidate->isEmpty();
    }

    lexicon::Phrase byPrototype(lexicon::Phrase grammar, lexicon::Phrase prototype) {
      if (grammar.isNull() || !grammar.containsSubdictionary() || prototype.isNull())
        return lexicon::Phrase(grammar.getLexicon());
      for (lexicon::Dictionary cursor = grammar.fore(populated); !cursor.isNull(); cursor = cursor.next(populated)) {
        lexicon::Phrase candidate = cursor.getPhrase();
        if (!candidate.isNull() && candidate.containsPrototype() &&
            candidate.getPrototype().getAddress() == prototype.getAddress())
          return candidate;
      }
      return lexicon::Phrase(grammar.getLexicon());
    }

    bool grammarAlias(radix::Node *, radix::Match *candidate) {
      if (aliasContext == nullptr || aliasGrammar == nullptr) return false;
      lexicon::Phrase phrase = lexicon::Dictionary(*candidate).getPhrase();
      return !phrase.isNull() && !resolve(*aliasContext, *aliasGrammar, phrase.getKey()).isNull();
    }

  } // namespace

  NumberLiteral numberLiteral(std::string_view source) {
    if (source.empty()) return {};
    const unsigned char first = source.front();
    if (!std::isdigit(first) &&
        !(first == '.' && source.size() > 1 && std::isdigit(static_cast<unsigned char>(source[1]))))
      return {};

    std::size_t cursor = 0;
    bool real = first == '.';
    if (source.starts_with("0x") || source.starts_with("0X") || source.starts_with("0b") || source.starts_with("0B") ||
        source.starts_with("0o") || source.starts_with("0O")) {
      cursor = 2;
      while (cursor < source.size() &&
             (std::isalnum(static_cast<unsigned char>(source[cursor])) || source[cursor] == '_'))
        ++cursor;
      return {cursor, false};
    }

    while (cursor < source.size() &&
           (std::isdigit(static_cast<unsigned char>(source[cursor])) || source[cursor] == '_'))
      ++cursor;
    if (cursor < source.size() && source[cursor] == '.') {
      real = true;
      ++cursor;
      while (cursor < source.size() &&
             (std::isdigit(static_cast<unsigned char>(source[cursor])) || source[cursor] == '_'))
        ++cursor;
    }
    if (cursor < source.size() && (source[cursor] == 'e' || source[cursor] == 'E')) {
      real = true;
      ++cursor;
      if (cursor < source.size() && (source[cursor] == '+' || source[cursor] == '-')) ++cursor;
      while (cursor < source.size() && std::isdigit(static_cast<unsigned char>(source[cursor]))) ++cursor;
    }
    return {cursor, real};
  }

  lexicon::Phrase find(lexicon::Phrase dictionary, std::string_view key) {
    if (dictionary.isNull() || !dictionary.containsSubdictionary()) return lexicon::Phrase(dictionary.getLexicon());
    lexicon::Match match = dictionary.matchExact(
        Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length,
        [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); });
    return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
  }

  lexicon::Phrase matchLongest(lexicon::Phrase dictionary, std::string_view source) {
    if (dictionary.isNull() || !dictionary.containsSubdictionary()) return lexicon::Phrase(dictionary.getLexicon());
    lexicon::Match match = dictionary.matchLongest(
        Byte(const_cast<char *>(source.data())), 0, source.size() * Byte::length,
        [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); });
    return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
  }

  lexicon::Phrase matchLongest(context::Context &context, std::initializer_list<lexicon::Phrase> grammars,
                               std::string_view source) {
    lexicon::Phrase result(&context.lexicon);
    std::size_t bytes = 0;
    for (lexicon::Phrase grammar : grammars) {
      for (lexicon::Phrase candidate : {matchLongest(grammar, source), matchLongestAlias(context, grammar, source)}) {
        if (!candidate.isNull() && candidate.getKey().size() > bytes) {
          result = candidate;
          bytes = candidate.getKey().size();
        }
      }
    }
    return result;
  }

  lexicon::Phrase matchLongestAlias(context::Context &context, lexicon::Phrase grammar, std::string_view source) {
    lexicon::Phrase root = context.lexicon.phrase();
    context::Context *previousContext = aliasContext;
    lexicon::Phrase *previousGrammar = aliasGrammar;
    aliasContext = &context;
    aliasGrammar = &grammar;
    lexicon::Match match =
        root.matchLongest(Byte(const_cast<char *>(source.data())), 0, source.size() * Byte::length, grammarAlias);
    aliasContext = previousContext;
    aliasGrammar = previousGrammar;
    return match.isNull() ? lexicon::Phrase(&context.lexicon) : match.getPhrase();
  }

  bool inherits(lexicon::Phrase candidate, lexicon::Phrase ancestor) {
    if (candidate.isNull() || ancestor.isNull()) return false;
    std::unordered_set<Size> visited;
    while (!candidate.isNull() && visited.insert(candidate.getAddress()).second) {
      if (candidate.getAddress() == ancestor.getAddress()) return true;
      if (!candidate.containsPrototype()) break;
      candidate = candidate.getPrototype();
    }
    return false;
  }

  bool matches(context::Context &context, std::string_view spelling, std::string_view canonical) {
    if (spelling == canonical) return true;
    lexicon::Phrase root = context.lexicon.phrase();
    return inherits(find(root, spelling), find(root, canonical));
  }

  lexicon::Phrase resolve(context::Context &context, lexicon::Phrase grammar, std::string_view name) {
    lexicon::Phrase direct = matchLongest(grammar, name);
    if (!direct.isNull() && direct.getKey().size() != name.size()) direct = lexicon::Phrase(grammar.getLexicon());
    if (!direct.isNull()) return direct;

    lexicon::Phrase root = find(context.lexicon.phrase(), name);
    if (root.isNull()) return lexicon::Phrase(grammar.getLexicon());

    std::unordered_set<Size> visited;
    while (!root.isNull() && visited.insert(root.getAddress()).second) {
      lexicon::Phrase result = byPrototype(grammar, root);
      if (!result.isNull()) return result;
      if (!root.containsPrototype()) break;
      root = root.getPrototype();
    }
    return lexicon::Phrase(grammar.getLexicon());
  }

  lexicon::Phrase metadata(lexicon::Phrase phrase, std::size_t bytes) {
    std::unordered_set<Size> visited;
    while (!phrase.isNull() && visited.insert(phrase.getAddress()).second) {
      if (phrase.payloadSize() >= bytes) return phrase;
      if (!phrase.containsPrototype()) break;
      phrase = phrase.getPrototype();
    }
    return lexicon::Phrase(phrase.getLexicon());
  }

  lexicon::Phrase behavior(lexicon::Phrase phrase, std::string_view key) {
    std::unordered_set<Size> visited;
    while (!phrase.isNull() && visited.insert(phrase.getAddress()).second) {
      lexicon::Phrase result = find(phrase, key);
      if (!result.isNull()) return result;
      if (!phrase.containsPrototype()) break;
      phrase = phrase.getPrototype();
    }
    return lexicon::Phrase(phrase.getLexicon());
  }

  lexicon::Phrase ensureMarker(context::Context &context, std::string_view name, lexicon::Phrase prototype) {
    return ensureMarker(context.lexicon.phrase(), name, prototype);
  }

  lexicon::Phrase ensureMarker(lexicon::Phrase root, std::string_view name, lexicon::Phrase prototype) {
    lexicon::Phrase marker = find(root, name);
    if (!marker.isNull()) return marker;
    lexicon::Draft draft = root.append(std::string(name)).make().setType(lexicon::phrase::type::getData(root));
    if (!prototype.isNull()) draft.setPrototype(prototype);
    return draft.save();
  }

} // namespace recurloop::LanguageGrammar
