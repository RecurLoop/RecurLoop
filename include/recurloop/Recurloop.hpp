#pragma once
#include <context/Context.hpp>

#include <cstdint>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace recurloop {
  class Recurloop {
  protected:
    context::Context context;

    void initializeConfig(int argc, char **argv);
    void initializeLexicon();
    void initializeRuntime();
    void initializeWorkspace();
    void initializeBase(int argc, char **argv);
    void initializeRoot();
    void resetToKernel();
    void processStartupOperations();

    void cleanupMemory();

    std::vector<std::pair<std::string, context::Actions::Action>> hostActions;

  public:

    Recurloop();
    ~Recurloop();

    // Initialize the normal runtime from the source-built core embedded in the
    // final runtime layer.  The implementation intentionally lives outside
    // RecurloopLib so stage-0/bootstrap tools do not depend on an embedded core.
    Recurloop& initialize(int argc, char **argv);
    Recurloop& initializeEmbedded(int argc, char **argv, std::span<const std::uint8_t> coreImage);
    int execute();

    context::Context &getContext() {
      return context;
    }
  };
} // namespace recurloop
