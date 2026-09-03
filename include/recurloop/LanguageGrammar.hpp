#pragma once

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>

#include <cstddef>
#include <initializer_list>
#include <cstdint>
#include <string_view>

namespace recurloop::LanguageGrammar {

  struct NumberLiteral {
    std::size_t bytes = 0;
    bool real = false;
  };

  // Numbers carry arbitrary source data, so they remain a native lexical
  // primitive. All parsers use this one scanner; their operators and syntax
  // continue to come from lexicon phrases.
  NumberLiteral numberLiteral(std::string_view source);

  // Find a phrase in a dictionary without exposing radix matching details to
  // each parser. The returned phrase is null when the dictionary has no such
  // entry.
  lexicon::Phrase find(lexicon::Phrase dictionary, std::string_view key);

  // Match the longest phrase at the beginning of source. Unlike find(), the
  // input may contain bytes after the matched phrase.
  lexicon::Phrase matchLongest(lexicon::Phrase dictionary, std::string_view source);
  lexicon::Phrase matchLongest(context::Context &context, std::initializer_list<lexicon::Phrase> grammars,
                               std::string_view source);
  lexicon::Phrase matchLongestAlias(context::Context &context, lexicon::Phrase grammar, std::string_view source);

  // Resolve a grammar entry by the public phrase name or by any of its
  // prototypes. Grammar dictionaries store their canonical entries with a
  // prototype pointing at the public mechanism they parse.
  lexicon::Phrase resolve(context::Context &context, lexicon::Phrase grammar, std::string_view name);

  // Grammar metadata and compiler behaviors live on phrases too. Follow the
  // prototype chain so a syntax alias does not have to copy private payload or
  // hidden implementation phrases.
  lexicon::Phrase metadata(lexicon::Phrase phrase, std::size_t bytes);
  lexicon::Phrase behavior(lexicon::Phrase phrase, std::string_view key);

  // Whether candidate is the ancestor itself or inherits it through prototypes.
  bool inherits(lexicon::Phrase candidate, lexicon::Phrase ancestor);

  // Compare source spelling by phrase identity. This keeps parsers independent
  // from the concrete spelling of structural tokens such as `(`, `{`, or `->`.
  bool matches(context::Context &context, std::string_view spelling, std::string_view canonical);

  // Some grammar mechanisms (return, break, else, ...) are parser-only and do
  // not have an executable root phrase. A data-only marker gives them a stable
  // phrase identity that users can alias without making the marker executable.
  lexicon::Phrase ensureMarker(context::Context &context, std::string_view name, lexicon::Phrase prototype = {});
  lexicon::Phrase ensureMarker(lexicon::Phrase root, std::string_view name, lexicon::Phrase prototype = {});

} // namespace recurloop::LanguageGrammar
