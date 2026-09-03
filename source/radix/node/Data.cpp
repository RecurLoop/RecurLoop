#if !defined(__RADIX_NODE_DATA_CPP)
  #define __RADIX_NODE_DATA_CPP
  #include <radix/Radix.hpp>

namespace radix::node {
  Data *Data::get(Radix *radix, Size address) {
    return address ? (Data *)radix->pointerFromAddress(address).toPtr() : nullptr;
  }

  Node Data::cursor(Radix *radix) {
    return Node(radix, address(radix));
  }

  Size Data::address(Radix *radix) {
    return radix->pointerToAddress(Byte((void *)this));
  }

  Data *Data::getParent(Radix *radix) {
    return Data::get(radix, parent);
  }

  void Data::setParent(Radix *radix, Data *node) {
    parent = node ? node->address(radix) : 0;
  }

  Data *Data::getChildSmaller(Radix *radix) {
    return Data::get(radix, childSmaller);
  }

  void Data::setChildSmaller(Radix *radix, Data *node) {
    childSmaller = node ? node->address(radix) : 0;
  }

  Data *Data::getChildGreater(Radix *radix) {
    return Data::get(radix, childGreater);
  }

  void Data::setChildGreater(Radix *radix, Data *node) {
    childGreater = node ? node->address(radix) : 0;
  }

  Bit Data::getKeyFore(Radix *radix) {
    return Bit(radix->pointerFromAddress(keyFore), keyForeOffset);
  }

  void Data::setKeyFore(Radix *radix, Bit key) {
    keyFore = radix->pointerToAddress(key.getByte());
    keyForeOffset = key.getOffset();
  }

  Bit Data::getKeyRear(Radix *radix) {
    return Bit(radix->pointerFromAddress(keyRear), keyRearOffset);
  }

  void Data::setKeyRear(Radix *radix, Bit key) {
    keyRear = radix->pointerToAddress(key.getByte());
    keyRearOffset = key.getOffset();
  }

  Data *Data::getEarlier(Radix *radix) {
    return Data::get(radix, earlier);
  }

  void Data::setEarlier(Radix *radix, Data *node) {
    earlier = node ? node->address(radix) : 0;
  }

  item::Data *Data::getItem(Radix *radix) {
    return item::Data::get(radix, item);
  }

  void Data::setItem(Radix *radix, item::Data *itemData) {
    item = itemData ? itemData->address(radix) : 0;
  }
} // namespace radix::node

#endif
