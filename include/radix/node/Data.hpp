#pragma once

#include "../_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace radix::node {
  class Data {
  protected:
    Size parent = 0;

    Size childSmaller = 0;
    Size childGreater = 0;

    Size keyFore = 0;
    Size keyRear = 0;
    struct {
      Byte::Offset keyForeOffset : Byte::offsetBits = 0;
      Byte::Offset keyRearOffset : Byte::offsetBits = 0;
    };

    Size earlier = 0;

    Size item = 0;

  public:
    DECLARATION static Data *get(Radix *radix, Size address);

    DECLARATION Node cursor(Radix *radix);
    DECLARATION Size address(Radix *radix);

    DECLARATION Data *getParent(Radix *radix);
    DECLARATION void setParent(Radix *radix, Data *node);

    DECLARATION Data *getChildSmaller(Radix *radix);
    DECLARATION void setChildSmaller(Radix *radix, Data *node);
    DECLARATION Data *getChildGreater(Radix *radix);
    DECLARATION void setChildGreater(Radix *radix, Data *node);

    DECLARATION Bit getKeyFore(Radix *radix);
    DECLARATION void setKeyFore(Radix *radix, Bit key);
    DECLARATION Bit getKeyRear(Radix *radix);
    DECLARATION void setKeyRear(Radix *radix, Bit key);

    DECLARATION Data *getEarlier(Radix *radix);
    DECLARATION void setEarlier(Radix *radix, Data *node);

    DECLARATION item::Data *getItem(Radix *radix);
    DECLARATION void setItem(Radix *radix, item::Data *item);
  };
} // namespace radix::node
