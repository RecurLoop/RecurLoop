#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

#define constAppend(name) append((char *)name, 0, (sizeof(name) - 1) * Byte::length)

namespace radix {
  class Node {
  protected:
    Radix *radix = nullptr;
    Size address = 0;

    DECLARATION node::Data *data();

  public:
    DECLARATION Node(Radix *radix = nullptr, Size address = 0);

    DECLARATION Radix *getRadix();

    DECLARATION Node &setAddress(Size size);
    DECLARATION Size getAddress();

    DECLARATION Node append(Byte key, Size keyOffset, Size keyBits);
    DECLARATION Item push();

    DECLARATION Match matchFirst(Byte key, Size keyOffset, Size keyBits, match::Filter filter = nullptr);
    DECLARATION Match matchLongest(Byte key, Size keyOffset, Size keyBits, match::Filter filter = nullptr);
    DECLARATION Match matchExact(Byte key, Size keyOffset, Size keyBits, match::Filter filter = nullptr);

    DECLARATION Node predecessor(node::Filter filter = nullptr);

    DECLARATION Node fore(node::Filter filter = nullptr);
    DECLARATION Node rear(node::Filter filter = nullptr);
    DECLARATION Node prev(node::Filter filter = nullptr);
    DECLARATION Node next(node::Filter filter = nullptr);

    DECLARATION Node foreInverse(node::Filter filter = nullptr);
    DECLARATION Node rearInverse(node::Filter filter = nullptr);
    DECLARATION Node prevInverse(node::Filter filter = nullptr);
    DECLARATION Node nextInverse(node::Filter filter = nullptr);

    DECLARATION Node earlier(node::Filter filter = nullptr);

    DECLARATION Item item(item::Filter filter = nullptr);

    DECLARATION Byte content(Size dataOffset, Size dataSize);
    DECLARATION Byte allocate(Size bytes);

    DECLARATION Size keyBits(node::Filter filter = nullptr);
    DECLARATION bool keyCopy(Bit keyOut, Size keyBits);

    DECLARATION bool isNull();
    DECLARATION bool isEmpty(item::Filter filter = nullptr);

  public:
    template <Size N> Node append(const char (&str)[N]) {
      return append(str, 0, N - 1);
    }
  };
} // namespace radix
