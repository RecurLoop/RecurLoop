#include <recurloop/Recurloop.hpp>

int main(int argc, char *argv[]) {
  try {
    return recurloop::Recurloop().initialize(argc, argv).execute();
  } catch (const Exception &error) {
    std::cerr << RED_TEXT;
    if (!error.hasSourceLocation()) std::cerr << "<command-line>:1:1: ";
    std::cerr << error.description() << RESET << NEWLINE;
    return error.status();
  } catch (const std::exception &error) {
    std::cerr << RED_TEXT << "<command-line>:1:1: " << error.what() << RESET << NEWLINE;
    return 1;
  }
}
