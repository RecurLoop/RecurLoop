#pragma once

#include <lexicon/Lexicon.hpp>

#include <string>
#include <string_view>

namespace context {
  // Stable names are the relocation boundary between persisted language
  // images and process-local C++ function addresses.
  class Actions {
  public:
    using Action = lexicon::Phrase::Action;

    explicit Actions(lexicon::Lexicon &lexicon) : lexicon(lexicon) {}

    void define(std::string name, Action action);
    Action get(std::string_view name) const;
    std::string name(Action action) const;
    bool contains(std::string_view name) const;
    void typePhrases();

  private:
    lexicon::Phrase registry(bool create) const;
    lexicon::Lexicon &lexicon;
  };
} // namespace context
