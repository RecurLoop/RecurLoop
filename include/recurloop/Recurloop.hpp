#pragma once
#include "Language.hpp"

namespace recurloop {
  class Recurloop {
  protected:
    context::Context context;

    void initializeConfig(int argc, char **argv);
    void initializeLexicon();
    void initializeRuntime();
    void initializeWorkspace();

    void cleanupMemory();

  public:

    Recurloop();
    ~Recurloop();

    Recurloop& initialize(int argc, char **argv);
    int execute();

    context::Context &getContext() {
      return context;
    }
  };
} // namespace recurloop
