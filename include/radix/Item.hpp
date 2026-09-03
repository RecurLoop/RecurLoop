#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace radix {
  class Item {
  protected:
    Radix *radix = nullptr;
    Size address = 0;

    DECLARATION item::Data *data();

  public:
    DECLARATION Item(Radix *radix = nullptr, Size address = 0);

    DECLARATION Radix *getRadix();

    DECLARATION Item &setAddress(Size size);
    DECLARATION Size getAddress();

    DECLARATION Item prev(item::Filter filter = nullptr);
    DECLARATION Item next(item::Filter filter = nullptr);

    DECLARATION Item earlier(item::Filter filter = nullptr);

    DECLARATION Node getNode();

    DECLARATION Byte content(Size dataOffset, Size dataSize);
    DECLARATION Byte allocate(Size bytes);
    DECLARATION Size contentSize();

    DECLARATION bool isNull();
  };
} // namespace radix
