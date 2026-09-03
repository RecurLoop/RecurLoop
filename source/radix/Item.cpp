#if !defined(__RADIX_ITEM_CPP)
  #define __RADIX_ITEM_CPP
  #include <radix/Radix.hpp>

namespace radix {
  item::Data *Item::data() {
    return item::Data::get(getRadix(), getAddress());
  }

  Item::Item(Radix *radix, Size address) : radix(radix), address(address) {}

  Radix *Item::getRadix() {
    return radix;
  }

  Item &Item::setAddress(Size address) {
    this->address = address;
    return *this;
  }

  Size Item::getAddress() {
    return address;
  }

  Item Item::prev(item::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Item(radix);

    auto *current = data();

    for (current = current->getPrev(radix); current; current = current->getPrev(radix)) {
      auto candidate = current->cursor(radix);
      if (filter == nullptr || filter(this, &candidate)) return candidate;
    }

    return Item(radix);
  }

  Item Item::next(item::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Item(radix);

    auto *current = data();

    for (current = current->getNext(radix); current; current = current->getNext(radix)) {
      auto candidate = current->cursor(radix);
      if (filter == nullptr || filter(this, &candidate)) return candidate;
    }

    return Item(radix);
  }

  Item Item::earlier(item::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Item(radix);

    auto *current = data();

    for (current = current->getEarlier(radix); current; current = current->getEarlier(radix)) {
      auto candidate = current->cursor(radix);
      if (filter == nullptr || filter(this, &candidate)) return candidate;
    }

    return Item(radix);
  }

  Node Item::getNode() {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    return data()->getNode(radix)->cursor(radix);
  }

  Byte Item::content(Size dataOffset, Size dataSize) {
    auto *radix = getRadix();

    if (isNull()) return (void *)nullptr;

  #if RADIX_REVERSE
    return radix->pointerFromAddress(getAddress() + dataOffset, dataSize); // backward radix
  #else
    return radix->pointerFromAddress(getAddress() + dataOffset + sizeof(item::Data), dataSize); // forward radix
  #endif
  }

  Byte Item::allocate(Size bytes) {
    auto *radix = getRadix();

    if (isNull()) return (void *)nullptr;

    if (radix->lastItem().getAddress() != getAddress()) return (void *)nullptr;

    Byte result = radix->allocate(bytes);
    if (!result.isNull()) data()->addContentBytes(bytes);
    return result;
  }

  Size Item::contentSize() {
    return isNull() ? 0 : data()->getContentBytes();
  }

  bool Item::isNull() {
    return getAddress() == 0;
  }
} // namespace radix

#endif
