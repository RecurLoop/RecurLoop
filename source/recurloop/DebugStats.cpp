#include "LanguageInternal.hpp"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <sys/resource.h>
#include <unistd.h>

namespace recurloop::internal {
  namespace {
    using Fields = std::map<std::string, std::string>;

    Fields readFields(const char *path) {
      std::ifstream input(path);
      Fields fields;
      for (std::string line; std::getline(input, line);) {
        const auto colon = line.find(':');
        if (colon == std::string::npos) continue;
        const auto first = line.find_first_not_of(" \t", colon + 1);
        if (first != std::string::npos) fields.emplace(line.substr(0, colon), line.substr(first));
      }
      return fields;
    }

    std::string number(double value, int precision = 2) {
      std::ostringstream out;
      out << std::fixed << std::setprecision(precision) << value;
      return out.str();
    }

    std::string bytes(double value) {
      const char *units[] = {"B", "KiB", "MiB", "GiB", "TiB"};
      unsigned unit = 0;
      while (value >= 1024 && unit < 4) {
        value /= 1024;
        ++unit;
      }
      return number(value, unit == 0 ? 0 : 2) + " " + units[unit];
    }

    std::string field(const Fields &fields, const char *key) {
      const auto it = fields.find(key);
      return it == fields.end() ? "n/a" : it->second;
    }

    std::string memory(const Fields &fields, const char *key, double multiplier = 1024) {
      std::istringstream input(field(fields, key));
      double value;
      return input >> value ? bytes(value * multiplier) : "n/a";
    }

    // /proc/self/stat's command name can contain spaces and parentheses.
    double processAge() {
      std::ifstream stat("/proc/self/stat");
      std::string line;
      std::getline(stat, line);
      const auto close = line.rfind(')');
      if (close == std::string::npos) return -1;
      std::istringstream fields(line.substr(close + 1));
      std::string ignored;
      for (int index = 3; index < 22; ++index)
        if (!(fields >> ignored)) return -1;
      double started, uptime;
      std::ifstream boot("/proc/uptime");
      const long ticks = sysconf(_SC_CLK_TCK);
      if (!(fields >> started) || !(boot >> uptime) || ticks <= 0) return -1;
      return std::max(0.0, uptime - started / ticks);
    }
  } // namespace

  void action_debug_stats(context::Context &context, lexicon::Phrase &) {
    DEBUG_PROFILE_SCOPE(Stats);
    const Fields status = readFields("/proc/self/status");
    const Fields io = readFields("/proc/self/io");
    const double age = processAge();
    rusage usage{};
    const bool hasUsage = getrusage(RUSAGE_SELF, &usage) == 0;
    const auto seconds = [](timeval time) { return time.tv_sec + time.tv_usec / 1000000.0; };
    const double user = seconds(usage.ru_utime), system = seconds(usage.ru_stime);
    const auto sampledAt = std::chrono::steady_clock::now();
    auto &previous = context.processStatsSample;
    const bool firstSample = !previous.valid;
    const double interval = firstSample ? age : std::chrono::duration<double>(sampledAt - previous.time).count();
    const double cpuDelta = user + system - (firstSample ? 0 : previous.cpuSeconds);
    const bool hasInterval = hasUsage && interval > 0 && cpuDelta >= 0;
    const std::string cpuLoad = hasInterval ? number(100 * cpuDelta / interval, 1) + "%  (100% = one core)" : "n/a";
    previous = {sampledAt, user + system, hasUsage};
    const char *term = std::getenv("TERM");
    const bool color = context.io.out == &std::cout && isatty(STDOUT_FILENO) && !std::getenv("NO_COLOR") && term &&
                       std::string_view(term) != "dumb";

    // Render into a private stream: diagnostics must not change program formatting.
    std::ostringstream out;
    constexpr int width = 76;
    const auto row = [&](std::string text, bool heading = false) {
      out << "│ ";
      if (color && heading) out << "\033[1;36m";
      out << text;
      if (color && heading) out << "\033[0m";
      out << std::string(text.size() < width ? width - text.size() : 0, ' ') << " │\n";
    };
    const auto rule = [&](const char *left, const char *right) {
      out << left;
      for (int i = 0; i < width + 2; ++i) out << "─";
      out << right << '\n';
    };
    const auto metric = [&](const std::string &label, const std::string &value) {
      row("  " + label + std::string(label.size() < 22 ? 22 - label.size() : 1, ' ') + value);
    };

    out << '\n';
    rule("╭", "╮");
    row("RECURLOOP  /  PROCESS SNAPSHOT", true);
    metric("PID / parent", std::to_string(getpid()) + " / " + std::to_string(getppid()));
    metric("Process age", age >= 0 ? number(age, 3) + " s" : "n/a");
    metric("Threads", field(status, "Threads"));
    rule("├", "┤");
    row("CPU  /  all threads", true);
    metric(firstSample ? "CPU since start" : "CPU since last stats", cpuLoad);
    metric("Sample interval", hasInterval ? number(interval, 6) + " s" : "n/a");
    row("  Counters below: process lifetime.");
    metric("User / system", hasUsage ? number(user, 3) + " s / " + number(system, 3) + " s" : "n/a");
    metric("Context switches", hasUsage ? std::to_string(usage.ru_nvcsw) + " voluntary / " +
                                              std::to_string(usage.ru_nivcsw) + " involuntary"
                                        : "n/a");
    metric("Page faults",
           hasUsage ? std::to_string(usage.ru_minflt) + " minor / " + std::to_string(usage.ru_majflt) + " major"
                    : "n/a");
    rule("├", "┤");
    row("MEMORY  /  process", true);
    metric("Resident / peak", memory(status, "VmRSS") + " / " + memory(status, "VmHWM"));
    metric("Virtual / swap", memory(status, "VmSize") + " / " + memory(status, "VmSwap"));
    rule("├", "┤");
    row("ENGINE  /  current context", true);
    const Size used = context.lexicon.memoryUsed(), total = context.lexicon.memorySize();
    const double ratio = total ? std::clamp(static_cast<double>(used) / total, 0.0, 1.0) : 0;
    const int filled = static_cast<int>(ratio * 24);
    metric("Lexicon arena",
           "[" + std::string(filled, '#') + std::string(24 - filled, '.') + "] " + number(ratio * 100, 1) + "%");
    metric("Used / capacity", bytes(used) + " / " + bytes(total));
    metric("Program JIT used", bytes(context.runtime.memoryUsed()));
    metric("Action JIT used", bytes(context.actionRuntime.memoryUsed()));
    const auto &timing = context.exec.timing;
    metric("Elaborate time:",
           number(timing.elaborate.count() / 1e9, 6) + " s / " + std::to_string(timing.elaborateCount) + " calls");
    metric("Invoke time:",
           number(timing.invoke.count() / 1e9, 6) + " s / " + std::to_string(timing.invokeCount) + " calls");
    row("  Timings: accumulated completed scopes; may overlap.");
    rule("├", "┤");
    row("I/O  /  process lifetime", true);
    metric("Storage read / write", memory(io, "read_bytes", 1) + " / " + memory(io, "write_bytes", 1));
    metric("Read / write calls", field(io, "syscr") + " / " + field(io, "syscw"));
    rule("╰", "╯");
    *context.io.out << out.str();
  }
} // namespace recurloop::internal
