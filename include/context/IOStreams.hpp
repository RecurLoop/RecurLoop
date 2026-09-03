#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace context {
  class IOStreams {
  public:
    std::istream *in = nullptr;
    std::ostream *out = nullptr;
    std::ostream *err = nullptr;
  };
} // namespace context
