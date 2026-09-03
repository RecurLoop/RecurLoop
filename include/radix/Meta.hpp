#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace radix {
  class Meta {
  protected:
    Size lastNode = 0;
    Size lastItem = 0;

    Size end = 0;

  public:
    DECLARATION node::Data *getLastNode(Radix *radix);
    DECLARATION void setLastNode(Radix *radix, node::Data *node);

    DECLARATION item::Data *getLastItem(Radix *radix);
    DECLARATION void setLastItem(Radix *radix, item::Data *item);

    DECLARATION Size getEnd();
    DECLARATION void setEnd(Size end);
  };
} // namespace radix
