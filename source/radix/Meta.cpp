#if !defined(__RADIX_META_CPP)
  #define __RADIX_META_CPP
  #include <radix/Radix.hpp>

namespace radix {
  node::Data *Meta::getLastNode(Radix *radix) {
    return node::Data::get(radix, lastNode);
  }

  void Meta::setLastNode(Radix *radix, node::Data *node) {
    lastNode = radix->pointerToAddress(Byte((void *)node));
  }

  item::Data *Meta::getLastItem(Radix *radix) {
    return item::Data::get(radix, lastItem);
  }

  void Meta::setLastItem(Radix *radix, item::Data *item) {
    lastItem = radix->pointerToAddress(Byte((void *)item));
  }

  Size Meta::getEnd() {
    return end;
  }

  void Meta::setEnd(Size address) {
    end = address;
  }
} // namespace radix

#endif
