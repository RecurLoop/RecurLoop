#include <context/Actions.hpp>

#include <utilities/Exception.hpp>

namespace context {
  void Actions::define(std::string name, Action action) {
    if (name.empty()) THROW(, "action name cannot be empty")
    if (action == nullptr) THROW(, "cannot register a null action as '" << name << "'")
    for (const auto &[existingName, existingAction] : registry.entries) {
      if (existingName != name) continue;
      if (existingAction != action) THROW(, "action name is already registered: '" << name << "'")
      return;
    }
    registry.entries.emplace_back(std::move(name), action);
  }

  Actions::Action Actions::get(std::string_view name) const {
    for (const auto &[existingName, action] : registry.entries)
      if (existingName == name) return action;
    THROW(, "unknown engine action: '" << name << "'")
  }

  std::string Actions::name(Action action) const {
    if (action == nullptr) return {};
    for (const auto &[name, existingAction] : registry.entries)
      if (existingAction == action) return name;
    THROW(, "cannot export an unregistered phrase action")
  }

  bool Actions::contains(std::string_view name) const {
    for (const auto &[existingName, action] : registry.entries)
      if (existingName == name && action != nullptr) return true;
    return false;
  }

  std::vector<std::pair<std::string, Actions::Action>> Actions::snapshot() const {
    return registry.entries;
  }

  void Actions::restore(const std::vector<std::pair<std::string, Action>> &entries) {
    for (const auto &[name, action] : entries) define(name, action);
  }

  void Actions::replace(const std::vector<std::pair<std::string, Action>> &entries) {
    registry.entries.clear();
    restore(entries);
  }
} // namespace context
