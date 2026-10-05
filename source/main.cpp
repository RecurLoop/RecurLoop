#include <recurloop/Project.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Server.hpp>

#include <string>
#include <string_view>
#include <vector>
#include <filesystem>
#include <fstream>
#include <iterator>

#include <unistd.h>

static void printHelp(const char *program) {
  std::cout << "Recurloop\n\n"
               "Usage:\n"
               "  "
            << program
            << " [options] [file...]\n\n"
               "Options:\n"
               "  -h, --help            Show this help message and exit\n"
               "  -v, --version         Show version information and exit\n"
               "  -f, --file <path>     Read source code from file\n"
               "  -s, --string <code>   Read source code from command line\n"
               "  --reset               Reset language state to the empty host kernel\n"
               "  --import <path>       Import an engine image before source input\n"
               "  --library <name>      Import a library image from the library search path\n"
               "  --library-path <path> Add a library search directory for this process\n"
               "  --serve               Keep the initialized project alive as a multi-client runtime\n"
               "  --unix <path>         Also serve independent sessions on a Unix socket\n"
               "  --connect <path>      Attach an interactive console to a Unix socket\n"
               "  --no-stdio            Do not open a stdio session (requires --unix)\n"
               "  --project-cache <dir> Cache project .rl files as linked .rli modules\n"
               "  --project <path>      Load a project entry (working directory is its parent)\n"
               "  --project-root <dir>  Override the project working directory\n"
               "  --debug-terminal <tty> Route native application IO to a separate terminal\n"
               "  --targets             List project targets as JSON\n"
               "  --target <name>       Execute a target and its dependencies\n"
               "  --debug-target <name> Build dependencies and open the project debugger\n"
               "  --inspect <path>      Query project semantic colors and diagnostics\n"
               "  --trace <path>        Query colors, diagnostics and language facts\n"
               "                       Project actions discover recurloop.project.rl in parent directories\n"
               "  -                     Use standard input (REPL on a terminal, source when piped)\n";
}

static void printVersion() {
  std::cout << "Recurloop v" << PROJECT_VERSION << std::endl;
}

static bool handleMetaArguments(const char *program, const int argc, char **argv) {
  for (int i = 1; i < argc; ++i) {
    std::string_view arg = argv[i];

    if (arg == "--") break;

    if (arg == "-h" || arg == "--help") {
      printHelp(program);
      return true;
    }
  }

  for (int i = 1; i < argc; ++i) {
    std::string_view arg = argv[i];

    if (arg == "--") break;

    if (arg == "-v" || arg == "--version") {
      printVersion();
      return true;
    }
  }

  return false;
}

namespace {
  struct CommandLine {
    bool serve = false;
    std::string connectPath;
    std::string projectCacheDirectory;
    std::string projectEntry;
    std::string projectRoot;
    std::string debugTerminal;
    enum class Action { Targets, Run, Debug, Inspect, Trace };
    std::vector<std::pair<Action, std::string>> projectActions;
    recurloop::ServerOptions options;
    std::vector<std::string> runtimeArguments;
    std::vector<char *> runtimeArgv;
  };

  bool runtimeOptionTakesValue(std::string_view option) {
    return option == "-f" || option == "--file" || option == "-s" || option == "--string" || option == "--import" ||
           option == "--library" || option == "--library-path";
  }

  CommandLine commandLine(int argc, char **argv) {
    CommandLine result;
    result.runtimeArguments.reserve(argc);
    result.runtimeArguments.emplace_back(argc > 0 ? argv[0] : "Recurloop");

    bool runtimeOnly = false;
    for (int i = 1; i < argc; ++i) {
      const std::string_view argument(argv[i]);
      if (!runtimeOnly && (argument == "--project-root" || argument == "--debug-terminal")) {
        if (++i >= argc) THROW(, argument << " requires a value")
        (argument == "--project-root" ? result.projectRoot : result.debugTerminal) = argv[i];
        continue;
      }
      if (!runtimeOnly && argument == "--project") {
        if (++i >= argc) THROW(, "--project requires a path")
        if (!result.projectEntry.empty()) THROW(, "--project may only be specified once")
        result.projectEntry = argv[i];
        continue;
      }
      if (!runtimeOnly && argument == "--targets") {
        result.projectActions.emplace_back(CommandLine::Action::Targets, "");
        continue;
      }
      if (!runtimeOnly && (argument == "--target" || argument == "--debug-target" || argument == "--inspect" ||
                           argument == "--trace")) {
        if (++i >= argc) THROW(, argument << " requires a value")
        const auto action = argument == "--target"         ? CommandLine::Action::Run
                            : argument == "--debug-target" ? CommandLine::Action::Debug
                            : argument == "--inspect"      ? CommandLine::Action::Inspect
                                                           : CommandLine::Action::Trace;
        result.projectActions.emplace_back(action, argv[i]);
        continue;
      }
      if (!runtimeOnly && argument == "--serve") {
        result.serve = true;
        continue;
      }
      if (!runtimeOnly && argument == "--unix") {
        result.serve = true;
        if (++i >= argc) THROW(, "--unix requires a path")
        result.options.unixPath = argv[i];
        continue;
      }
      if (!runtimeOnly && argument == "--connect") {
        if (++i >= argc) THROW(, "--connect requires a path")
        result.connectPath = argv[i];
        continue;
      }
      if (!runtimeOnly && argument == "--no-stdio") {
        result.serve = true;
        result.options.stdio = false;
        continue;
      }
      if (!runtimeOnly && argument == "--project-cache") {
        if (++i >= argc) THROW(, "--project-cache requires a directory")
        result.projectCacheDirectory = argv[i];
        continue;
      }

      result.runtimeArguments.emplace_back(argv[i]);
      if (argument == "--") {
        runtimeOnly = true;
        continue;
      }
      if (!runtimeOnly && runtimeOptionTakesValue(argument) && i + 1 < argc)
        result.runtimeArguments.emplace_back(argv[++i]);
    }

    if (result.serve && !result.options.stdio && result.options.unixPath.empty())
      THROW(, "--no-stdio requires --unix <path>")
    if (!result.connectPath.empty() &&
        (result.serve || result.runtimeArguments.size() != 1 || !result.projectEntry.empty() ||
         !result.projectActions.empty() || !result.projectRoot.empty() || !result.debugTerminal.empty()))
      THROW(, "--connect cannot be combined with runtime/server arguments")

    if (!result.projectEntry.empty() || !result.projectActions.empty() || !result.projectRoot.empty() ||
        !result.debugTerminal.empty()) {
      namespace fs = std::filesystem;
      if (result.projectEntry.empty()) {
        for (auto directory = fs::current_path();;) {
          const auto candidate = directory / "recurloop.project.rl";
          if (fs::is_regular_file(candidate)) {
            result.projectEntry = candidate.string();
            break;
          }
          if (directory == directory.parent_path()) THROW(, "cannot find recurloop.project.rl in parent directories")
          directory = directory.parent_path();
        }
      }
      result.projectEntry = fs::absolute(result.projectEntry).lexically_normal().string();
      if (!fs::is_regular_file(result.projectEntry)) THROW(, "project entry does not exist: " << result.projectEntry)
      // File operands for inspection are relative to the caller, not the entry.
      for (auto &[action, operand] : result.projectActions)
        if (action == CommandLine::Action::Inspect || action == CommandLine::Action::Trace)
          operand = fs::absolute(operand).lexically_normal().string();
      const auto root = result.projectRoot.empty() ? fs::path(result.projectEntry).parent_path()
                                                   : fs::absolute(result.projectRoot).lexically_normal();
      result.projectRoot = root.string();
      if (!result.debugTerminal.empty())
        result.debugTerminal = fs::absolute(result.debugTerminal).lexically_normal().string();
      fs::current_path(root);
      if (setenv("RECURLOOP_PROJECT_ROOT", root.c_str(), 1) != 0) THROW(, "cannot set project root")
      if (result.projectCacheDirectory.empty()) result.projectCacheDirectory = (root / ".cache/recurloop").string();
      std::size_t start = 1;
      bool customLibraries = false;
      while (start < result.runtimeArguments.size()) {
        const auto &option = result.runtimeArguments[start];
        if (option == "--reset") {
          ++start;
          continue;
        }
        if (option != "--import" && option != "--library" && option != "--library-path") break;
        if (start + 1 >= result.runtimeArguments.size()) THROW(, option << " requires a value")
        if (option == "--library") customLibraries = true;
        start += 2;
      }
      std::vector<std::string> startup{"--library", "project"};
      if (!customLibraries) startup.insert(startup.end(), {"--library", "shell", "--library", "inferred"});
      result.runtimeArguments.insert(result.runtimeArguments.begin() + start, startup.begin(), startup.end());
    }

    result.runtimeArgv.reserve(result.runtimeArguments.size());
    for (std::string &argument : result.runtimeArguments) result.runtimeArgv.push_back(argument.data());
    return result;
  }

  bool interactiveStdinOnly(const CommandLine &command, int inputIndex) {
    if (command.serve && !command.options.stdio) return false;
    return inputIndex >= 0 && static_cast<std::size_t>(inputIndex + 1) == command.runtimeArguments.size() &&
           command.runtimeArguments[static_cast<std::size_t>(inputIndex)] == "-" && isatty(STDIN_FILENO);
  }

  void writeResponse(const recurloop::SessionResponse &response) {
    if (!response.output.empty()) std::cout << response.output << std::flush;
    if (!response.error.empty()) {
      std::cerr << response.error;
      if (response.error.back() != '\n') std::cerr << '\n';
      std::cerr << std::flush;
    }
  }
  std::string sourceString(std::string_view text) {
    std::string result = "\"";
    for (const auto ch : text) {
      if (ch == '\\' || ch == '"') result += '\\';
      if (ch == '\n')
        result += "\\n";
      else if (ch == '\r')
        result += "\\r";
      else if (ch == '\t')
        result += "\\t";
      else
        result += ch;
    }
    return result + '"';
  }
} // namespace

int main(int argc, char *argv[]) {
  const char *program = argc > 0 ? argv[0] : "Recurloop";

  if (handleMetaArguments(program, argc, argv)) return 0;

  DEBUG_LOG_INIT(".debug/log.csv")
  DEBUG_PROFILER_INIT(".debug/profile.speedscope")

  int result = 0;

  try {
    CommandLine command = commandLine(argc, argv);
    if (!command.connectPath.empty()) {
      result = recurloop::Server::connectUnix(command.connectPath);
      DEBUG_PROFILER_END();
      DEBUG_LOG_END();
      return result;
    }

    recurloop::Recurloop base;
    base.initialize(static_cast<int>(command.runtimeArgv.size()), command.runtimeArgv.data());
    const int inputIndex = base.getContext().exec.args.index;
    const bool hasInputs = inputIndex < static_cast<int>(command.runtimeArgv.size());
    const bool interactiveInput = interactiveStdinOnly(command, inputIndex);

    auto project = recurloop::Project::create(base.getContext(), command.runtimeArguments);
    if (!command.projectCacheDirectory.empty()) project->configureCache(command.projectCacheDirectory);

    if (!command.projectEntry.empty()) {
      auto session = project->openSession();
      auto response = session->executeFile(command.projectEntry, &std::cout, &std::cerr);
      writeResponse(response);
      result = response.status;
      if (result == 0 && hasInputs && !interactiveInput) {
        response = session->executeArguments(inputIndex, &std::cout, &std::cerr);
        writeResponse(response);
        result = response.status;
      }
      if (result == 0) session->publish();
      for (const auto &[action, operand] : command.projectActions) {
        if (result != 0) break;
        switch (action) {
        case CommandLine::Action::Targets: response = session->projectTargets(); break;
        case CommandLine::Action::Run: response = session->runTarget(operand, false, &std::cout, &std::cerr); break;
        case CommandLine::Action::Debug:
          if (!command.debugTerminal.empty()) {
            response = session->evaluate("debug:terminal " + sourceString(command.debugTerminal) + '\n', {}, &std::cout,
                                         &std::cerr);
            if (response.status != 0) break;
          }
          response = session->debugTarget(operand, &std::cout, &std::cerr);
          break;
        case CommandLine::Action::Inspect:
        case CommandLine::Action::Trace: {
          std::ifstream input(operand, std::ios::binary);
          if (!input) THROW(, "cannot read source file: " << operand)
          const std::string source{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
          if (input.bad()) THROW(, "cannot read source file: " << operand)
          response = session->inspect(source, operand, action == CommandLine::Action::Trace);
          break;
        }
        }
        writeResponse(response);
        result = response.status;
      }
      if (result == 0 && command.serve) {
        session->publish();
        result = recurloop::Server(std::move(project), std::move(command.options)).run();
      }
    } else if (command.serve) {
      // Files/strings supplied together with --serve initialize the published
      // project through the same Session/Request path used by every client.
      if (hasInputs && !interactiveInput) {
        auto bootstrap = project->openSession();
        recurloop::SessionResponse response = bootstrap->executeArguments(inputIndex, &std::cout, &std::cerr);
        writeResponse(response);
        if (response.status != 0) {
          result = response.status;
        } else {
          bootstrap->publish();
        }
      }
      if (result == 0) result = recurloop::Server(std::move(project), std::move(command.options)).run();
    } else if (!hasInputs || interactiveInput) {
      // The normal REPL is now just the stdio transport of the project runtime.
      // No source path in main bypasses Session/RequestGeneration anymore.
      result = recurloop::Server(std::move(project), recurloop::ServerOptions{}).run();
    } else {
      auto session = project->openSession();
      recurloop::SessionResponse response = session->executeArguments(inputIndex, &std::cout, &std::cerr);
      writeResponse(response);
      result = response.status;
    }
  } catch (const Exception &error) {
    result = error.status();
    std::cerr << RED_TEXT;
    if (!error.hasSourceLocation()) std::cerr << "<command-line>:1:1: ";
    std::cerr << error.description() << RESET << NEWLINE;
  } catch (const std::exception &error) {
    result = 1;
    std::cerr << RED_TEXT << "<command-line>:1:1: " << error.what() << RESET << NEWLINE;
  } catch (...) {
    result = 1;
    std::cerr << RED_TEXT << "<command-line>:1:1: unknown internal error" << RESET << NEWLINE;
  }

  DEBUG_PROFILER_END();
  DEBUG_LOG_END();

  return result;
}
