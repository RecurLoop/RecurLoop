#pragma once

#if !defined(RADIX_REVERSE)
  #define RADIX_REVERSE false
#endif

#include "_module_classes.hpp"
#include "Item.hpp"
#include "item/Data.hpp"
#include "Node.hpp"
#include "node/Data.hpp"
#include "Checkpoint.hpp"
#include "Match.hpp"
#include "Meta.hpp"
#include <utilities/Declaration.hpp>

namespace radix {
  class Radix {
  protected:
    Byte memory;
    Size size = 0;

  public:
    DECLARATION Radix(Byte memory = (void *)nullptr, Size size = 0) : memory(memory), size(size) {};

    DECLARATION Meta *getMeta();

    DECLARATION Byte getMemory();
    DECLARATION void setMemory(Byte memory);
    DECLARATION Size getSize();
    DECLARATION void setSize(Size size);

    DECLARATION Node node();

    DECLARATION Node lastNode(node::Filter filter = nullptr);
    DECLARATION Item lastItem(item::Filter filter = nullptr);

    DECLARATION Checkpoint checkpoint();

    DECLARATION Byte allocate(Size size);

    DECLARATION bool clear();

    DECLARATION Byte memoryFore();
    DECLARATION Byte memoryRear();

    DECLARATION Size memorySize();
    DECLARATION Size memoryUsed();
    DECLARATION Size memoryUnused();

    DECLARATION Byte pointerFromAddress(Size base = 0, Size address = 0);
    DECLARATION Size pointerToAddress(Byte pointer = (void *)nullptr);
  };
} // namespace radix

#ifdef INLINE
  #include <radix/Item.cpp>
  #include <radix/item/Data.cpp>
  #include <radix/Node.cpp>
  #include <radix/node/Data.cpp>
  #include <radix/Checkpoint.cpp>
  #include <radix/Match.cpp>
  #include <radix/Meta.cpp>
  #include <radix/Radix.cpp>
#endif
