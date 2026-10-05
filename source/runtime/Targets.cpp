#include <recurloop/Targets.hpp>

#include <context/Context.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cctype>
#include <functional>
#include <sstream>
#include <unordered_map>

namespace recurloop {
  namespace {
    class TargetCommandException : public SourceException {
    public:
      TargetCommandException(const ProjectTarget &target, int status)
          : SourceException(__FILE__, __LINE__, __PRETTY_FUNCTION__, {target.path, target.line, 1},
                            "project target '" + target.name + "' failed (status " + std::to_string(status) + ")") {
        ret = status;
      }
    };

    std::string trim(std::string value) {
      const auto begin = value.find_first_not_of(" \t\r\n");
      if (begin == std::string::npos) return {};
      return value.substr(begin, value.find_last_not_of(" \t\r\n") - begin + 1);
    }

    std::string field(lexicon::Phrase target, std::string_view name) {
      auto value = LanguageGrammar::find(target, name);
      if (value.isNull() || value.payloadSize() == 0) return {};
      return std::string(reinterpret_cast<const char *>(value.content(0, value.payloadSize()).toPtr()),
                         value.payloadSize());
    }

    std::string pathField(context::Context &context, lexicon::Phrase target, std::string_view name) {
      const auto source = field(target, name);
      if (source.empty()) return {};
      const auto value = Expressions::evaluate(context, source);
      if (!value.isString() || value.asString().empty() || value.asString().find('\0') != std::string::npos)
        THROW(, "project debug entry must be a nonempty path")
      return value.asString();
    }

    std::string json(std::string_view value) {
      constexpr char digits[] = "0123456789abcdef";
      std::string result = "\"";
      for (const unsigned char byte : value) {
        if (byte == '"' || byte == '\\') {
          result += '\\';
          result += byte;
        } else if (byte < 32) {
          result += "\\u00";
          result += digits[byte >> 4];
          result += digits[byte & 15];
        } else
          result += byte;
      }
      return result + '"';
    }
  } // namespace

  std::vector<ProjectTarget> Targets::read(context::Context &context) {
    auto project = LanguageGrammar::find(context.lexicon.phrase(), "Project");
    auto registry = LanguageGrammar::find(project, "Targets");
    if (registry.isNull()) return {};
    auto populated = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
    std::vector<ProjectTarget> targets;
    for (auto cursor = registry.fore(populated); !cursor.isNull(); cursor = cursor.next(populated)) {
      auto phrase = cursor.getPhrase();
      if (phrase.isNull()) continue;
      ProjectTarget target;
      target.name = trim(phrase.getKey());
      if (target.name.empty() || target.name.find_first_of(" \t\r\n,[]{}\"'") != std::string::npos)
        THROW(, "invalid project target name '" << target.name << "'")
      if (std::ranges::any_of(targets, [&](const auto &other) { return other.name == target.name; }))
        THROW(, "duplicate project target '" << target.name << "'")
      target.command = trim(field(phrase, "command"));
      if (target.command.size() < 2 || target.command.front() != '{' || target.command.back() != '}')
        THROW(, "project target '" << phrase.getKeyEscaped() << "' in '" << registry.getKeyEscaped()
                                   << "' requires a source block")
      target.command = target.command.substr(1, target.command.size() - 2);
      std::string dependencies = field(phrase, "dependencies");
      std::replace(dependencies.begin(), dependencies.end(), ',', ' ');
      std::istringstream input(dependencies);
      for (std::string name; input >> name;) target.dependencies.push_back(name);
      target.debugProgram = pathField(context, phrase, "debugProgram");
      target.debugExecutable = pathField(context, phrase, "debugExecutable");
      if (!target.debugProgram.empty() && !target.debugExecutable.empty())
        THROW(, "project target cannot have both source and executable debug entries")
      target.path = field(phrase, "path");
      auto line = LanguageGrammar::find(phrase, "line");
      if (!line.isNull() && line.payloadSize() == sizeof(target.line)) line.fetch(0, target.line);
      targets.push_back(std::move(target));
    }
    std::ranges::sort(targets, {}, &ProjectTarget::name);
    return targets;
  }

  std::string Targets::describe(const std::vector<ProjectTarget> &targets) {
    std::string result = "{\"targets\":[";
    bool first = true;
    for (const auto &target : targets) {
      if (!first) result += ',';
      first = false;
      result += "{\"name\":" + json(target.name) + ",\"command\":" + json(target.command) + ",\"dependencies\":[";
      for (std::size_t index = 0; index < target.dependencies.size(); ++index) {
        if (index) result += ',';
        result += json(target.dependencies[index]);
      }
      result += ']';
      if (!target.debugProgram.empty()) result += ",\"debugProgram\":" + json(target.debugProgram);
      if (!target.debugExecutable.empty()) result += ",\"debugExecutable\":" + json(target.debugExecutable);
      result += '}';
    }
    return result + "]}\n";
  }

  ProjectTarget Targets::run(context::Context &context, std::string_view name, bool dependenciesOnly) {
    const auto targets = read(context);
    std::unordered_map<std::string, std::size_t> names;
    for (std::size_t index = 0; index < targets.size(); ++index) names.emplace(targets[index].name, index);
    const auto requested = names.find(std::string(name));
    if (requested == names.end()) THROW(, "Unknown RecurLoop target: " << name)
    const auto &target = targets[requested->second];
    if (dependenciesOnly && target.debugExecutable.empty() && target.debugProgram.empty())
      THROW(, "project target '" << name << "' has no debug entry")
    std::vector<unsigned char> visited(targets.size());
    std::vector<std::size_t> order;
    std::function<void(std::size_t)> visit = [&](std::size_t index) {
      if (visited[index] == 2) return;
      if (visited[index] == 1) THROW(, "Cyclic target dependency: " << targets[index].name)
      visited[index] = 1;
      for (const auto &dependency : targets[index].dependencies) {
        const auto found = names.find(dependency);
        if (found == names.end()) THROW(, "Unknown RecurLoop target: " << dependency)
        visit(found->second);
      }
      visited[index] = 2;
      order.push_back(index);
    };
    // Validate the entire reachable graph before any command has side effects.
    visit(requested->second);
    for (const auto index : order) {
      if (dependenciesOnly && index == requested->second) continue;
      const auto &step = targets[index];
      executeSource(context, step.command, step.path, step.line, 1);
      if (context.exec.status != 0) throw TargetCommandException(step, context.exec.status);
    }
    return target;
  }
} // namespace recurloop
