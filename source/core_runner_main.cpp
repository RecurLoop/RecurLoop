#include <recurloop/Execution.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/HostAbi.hpp>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <span>
#include <string>
#include <vector>

namespace {
  std::vector<std::uint8_t> readBytes(const std::filesystem::path &path) {
    std::ifstream input(path, std::ios::binary);
    if (!input.is_open()) throw std::runtime_error("cannot open image: " + path.string());
    std::vector<std::uint8_t> result{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
    if (input.bad()) throw std::runtime_error("cannot read image: " + path.string());
    return result;
  }

  class CoreBuildRuntime final : public recurloop::Recurloop {
  public:
    void initializeBuildImage(std::span<const std::uint8_t> image) {
      static char program[] = "recurloop-core-runner";
      static char *runtimeArgv[] = {program};
      initializeBase(1, runtimeArgv);
      // Build images may be the minimal seed and therefore intentionally have
      // no compiler registry yet. Register process-local actions, decode the
      // image, and let CoreDefinition materialize/bind the full Host ABI from
      // core.rl. Production initializeEmbedded() remains stricter and binds
      // the already-complete embedded core immediately.
      recurloop::HostAbi::registerActions(context);
      hostActions = context.actions().snapshot();
      recurloop::EngineImage::decodeExact(context, image);
    }
  };
  std::string readText(const std::filesystem::path &path) {
    std::ifstream input(path, std::ios::binary);
    if (!input.is_open()) throw std::runtime_error("cannot open source: " + path.string());
    std::string result{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
    if (input.bad()) throw std::runtime_error("cannot read source: " + path.string());
    return result;
  }
}

int main(int argc, char **argv) {
  if (argc == 3 && std::string_view(argv[1]) == "--dump") {
    try {
      const auto image = readBytes(std::filesystem::absolute(argv[2]).lexically_normal());
      CoreBuildRuntime runtime;
      runtime.initializeBuildImage(image);
      std::cout << recurloop::EngineImage::source(runtime.getContext());
      return 0;
    } catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }
  }
  if (argc != 3) {
    std::cerr << "usage: recurloop-core-runner <input.rli> <core.rl>\n";
    return 2;
  }
  try {
    const std::filesystem::path imagePath = std::filesystem::absolute(argv[1]).lexically_normal();
    const std::filesystem::path sourcePath = std::filesystem::absolute(argv[2]).lexically_normal();
    const auto image = readBytes(imagePath);
    CoreBuildRuntime runtime;
    runtime.initializeBuildImage(image);
    recurloop::executeSource(runtime.getContext(), readText(sourcePath), sourcePath.string(), 1);
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "recurloop-core-runner: " << error.what() << '\n';
    return 1;
  }
}
