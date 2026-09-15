#pragma once
#include <context/Context.hpp>

namespace recurloop::bootstrap {
  // Minimal stage-0 language used only to enter `engine define { ... }`.
  // It is deliberately not the standard RecurLoop language and is never
  // embedded in the production executable.
  struct SeedLanguage {
    static void setup(context::Context &context);
  };
}
