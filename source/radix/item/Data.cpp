#if !defined(__RADIX_ITEM_DATA_CPP)
  #define __RADIX_ITEM_DATA_CPP
  #include <radix/Radix.hpp>

namespace radix::item {
  Data *Data::get(Radix *radix, Size address) {
    return address ? (Data *)radix->pointerFromAddress(address).toPtr() : nullptr;
  }

  Item Data::cursor(Radix *radix) {
    return Item(radix, address(radix));
  }

  Size Data::address(Radix *radix) {
    return radix->pointerToAddress(Byte((void *)this));
  }

  node::Data *Data::getNode(Radix *radix) {
    return node::Data::get(radix, node);
  }

  void Data::setNode(Radix *radix, node::Data *nodeData) {
    node = nodeData ? radix->pointerToAddress(Byte((void *)nodeData)) : 0;
  }

  Data *Data::getPrev(Radix *radix) {
    return Data::get(radix, prev);
  }

  Data *Data::getNext(Radix *radix) {
    return Data::get(radix, next);
  }

  void Data::setPrev(Radix *radix, Data *item) {
    prev = item ? item->address(radix) : 0;
  }

  void Data::setNext(Radix *radix, Data *item) {
    next = item ? item->address(radix) : 0;
  }

  Data *Data::getEarlier(Radix *radix) {
    return Data::get(radix, earlier);
  }

  void Data::setEarlier(Radix *radix, Data *item) {
    earlier = item ? item->address(radix) : 0;
  }

  Size Data::getContentBytes() {
    return contentBytes;
  }

  void Data::setContentBytes(Size bytes) {
    contentBytes = bytes;
  }

  void Data::addContentBytes(Size bytes) {
    contentBytes += bytes;
  }
} // namespace radix::item

#endif
