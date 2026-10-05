#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace context {
  class Context;
}

namespace recurloop {
  struct ProjectTarget {
    std::string name;
    std::string command;
    std::vector<std::string> dependencies;
    std::string debugProgram;
    std::string debugExecutable;
    std::string path;
    std::uint64_t line = 1;
  };

  class Targets {
  public:
    static std::vector<ProjectTarget> read(context::Context &context);
    static std::string describe(const std::vector<ProjectTarget> &targets);
    static ProjectTarget run(context::Context &context, std::string_view name, bool dependenciesOnly = false);
  };
} // namespace recurloop
