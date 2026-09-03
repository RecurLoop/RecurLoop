#include <recurloop/Recurloop.hpp>

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
               "  --import <path>       Import an engine image before sources\n"
               "  --engine-image <path> Compatibility alias for --import\n"
               "  -                     Read source code from standard input\n"
               "                        (interactive line editing on a terminal)\n";
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

static bool handleEmptyArguments(const char *&program, int &argc, char **&argv) {
  if (argc > 1) return false;

  static const char *argvInteractive[] = {nullptr, "-"};
  argvInteractive[0] = program;

  argv = (char **)argvInteractive;
  argc = countof(argvInteractive);

  return false;
}

int main(int argc, char *argv[]) {
  const char *program = argc > 0 ? argv[0] : "Recurloop";

  if (handleMetaArguments(program, argc, argv)) return 0;
  if (handleEmptyArguments(program, argc, argv)) return 0;

  DEBUG_LOG_INIT(".debug/log.csv")
  DEBUG_PROFILER_INIT(".debug/profile.speedscope")

  int result = 0;

  try {
    result = recurloop::Recurloop().initialize(argc, argv).execute();
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
