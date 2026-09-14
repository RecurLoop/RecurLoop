#include <recurloop/bootstrap/BootstrapLanguage.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Recurloop.hpp>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

namespace {
  std::string readFile(const std::filesystem::path &path) {
    std::ifstream input(path, std::ios::binary);
    if (!input.is_open()) throw std::runtime_error("cannot open source file: " + path.string());
    std::string result{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
    if (input.bad()) throw std::runtime_error("cannot read source file: " + path.string());
    return result;
  }

  class BootstrapRuntime final : public recurloop::Recurloop {
  public:
    void initializeBootstrap() {
      static char program[] = "recurloop-core-builder";
      static char *argv[] = {program};
      initializeBase(1, argv);
      recurloop::bootstrap::Language::setup(context);
    }
  };
}

int main(int argc, char **argv) {
  if (argc != 3) {
    std::cerr << "usage: recurloop-core-builder <output.rli> <control-flow.rl>\n";
    return 2;
  }
  try {
    const std::filesystem::path controlPath = std::filesystem::absolute(argv[2]).lexically_normal();
    BootstrapRuntime runtime;
    runtime.initializeBootstrap();
    recurloop::executeSource(runtime.getContext(), readFile(controlPath), controlPath.string(), 1);
    recurloop::EngineImage::save(runtime.getContext(), argv[1]);
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "recurloop-core-builder: " << error.what() << '\n';
    return 1;
  }
}
