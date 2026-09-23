#include <recurloop/Project.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Server.hpp>

#include <string>
#include <string_view>
#include <vector>

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
    recurloop::ServerOptions options;
    std::vector<std::string> runtimeArguments;
    std::vector<char *> runtimeArgv;
  };

  bool runtimeOptionTakesValue(std::string_view option) {
    return option == "-f" || option == "--file" || option == "-s" || option == "--string" ||
           option == "--import" || option == "--library" || option == "--library-path";
  }

  CommandLine commandLine(int argc, char **argv) {
    CommandLine result;
    result.runtimeArguments.reserve(argc);
    result.runtimeArguments.emplace_back(argc > 0 ? argv[0] : "Recurloop");

    bool runtimeOnly = false;
    for (int i = 1; i < argc; ++i) {
      const std::string_view argument(argv[i]);
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
    if (!result.connectPath.empty() && (result.serve || result.runtimeArguments.size() != 1))
      THROW(, "--connect cannot be combined with runtime/server arguments")

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

    if (command.serve) {
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
