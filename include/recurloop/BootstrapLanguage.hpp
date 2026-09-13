#pragma once

#include <context/Context.hpp>

namespace recurloop {
  // Fixed implementation language used only while constructing/restoring a
  // source-defined language image. It is intentionally separate from the
  // compatibility Language surface so legacy grammar can later be removed
  // without changing the bootstrap contract.
  class BootstrapLanguage {
  public:
    BootstrapLanguage() = delete;

    static void setup(context::Context &context);
  };
} // namespace recurloop
