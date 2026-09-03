#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace radix {
  class Checkpoint {
  protected:
    Radix *radix = nullptr;
    Size address = 0;

  public:
    DECLARATION Checkpoint(Radix *radix, Size address = 0) : radix(radix), address(address) {}

    DECLARATION Radix *getRadix();
    DECLARATION Size getAddress();

    DECLARATION void restore();
  };
} // namespace radix
