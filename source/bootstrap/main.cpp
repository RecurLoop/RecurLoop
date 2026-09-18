#include <recurloop/bootstrap/SeedLanguage.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Recurloop.hpp>

#include <iostream>

namespace {
  class SeedRuntime final : public recurloop::Recurloop {
  public:
    void initializeSeed() {
      static char program[] = "recurloop-seed-builder";
      static char *argv[] = {program};
      initializeBase(1, argv);
      recurloop::bootstrap::SeedLanguage::setup(context);
    }
  };
}

int main(int argc, char **argv) {
  if (argc != 2) {
    std::cerr << "usage: recurloop-seed-builder <output.rli>\n";
    return 2;
  }
  try {
    SeedRuntime runtime;
    runtime.initializeSeed();
    recurloop::EngineImage::save(runtime.getContext(), argv[1]);
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "recurloop-seed-builder: " << error.what() << '\n';
    return 1;
  }
}
