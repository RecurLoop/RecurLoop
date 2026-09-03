#pragma once

#include "../_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace radix::item {
  class Data {
  protected:
    Size node = 0;

    Size prev = 0;
    Size next = 0;

    Size earlier = 0;

    // Number of bytes allocated after this item header. Keeping the extent on
    // the item makes phrase payloads inspectable and therefore serializable;
    // previously their end could only be inferred from global allocation
    // order.
    Size contentBytes = 0;

  public:
    DECLARATION static Data *get(Radix *radix, Size address);

    DECLARATION Item cursor(Radix *radix);
    DECLARATION Size address(Radix *radix);

    DECLARATION node::Data *getNode(Radix *radix);
    DECLARATION void setNode(Radix *radix, node::Data *data);

    DECLARATION Data *getPrev(Radix *radix);
    DECLARATION void setPrev(Radix *radix, Data *item);
    DECLARATION Data *getNext(Radix *radix);
    DECLARATION void setNext(Radix *radix, Data *item);

    DECLARATION Data *getEarlier(Radix *radix);
    DECLARATION void setEarlier(Radix *radix, Data *item);

    DECLARATION Size getContentBytes();
    DECLARATION void setContentBytes(Size bytes);
    DECLARATION void addContentBytes(Size bytes);
  };
} // namespace radix::item
