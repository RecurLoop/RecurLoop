#pragma once

#include <lexicon/Phrase.hpp>

#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace context {
  using Action = lexicon::Phrase::Action;

  struct ActionRegistry {
    std::vector<std::pair<std::string, Action>> entries;
  };

  // Process-local registry that binds stable persisted action names to C++
  // function pointers. It is kernel state, not part of the language lexicon.
  class Actions {
  public:
    using Action = context::Action;

    explicit Actions(ActionRegistry &registry) : registry(registry) {}

    void define(std::string name, Action action);
    Action get(std::string_view name) const;
    std::string name(Action action) const;
    bool contains(std::string_view name) const;
    std::vector<std::pair<std::string, Action>> snapshot() const;
    void restore(const std::vector<std::pair<std::string, Action>> &entries);
    void replace(const std::vector<std::pair<std::string, Action>> &entries);


  private:
    ActionRegistry &registry;
  };
} // namespace context
