#if !defined(__RADIX_RADIX_CPP)
  #define __RADIX_RADIX_CPP
  #include <radix/Radix.hpp>

namespace radix {
  Meta *Radix::getMeta() {
    return (Meta *)pointerFromAddress(0, sizeof(Meta)).toPtr();
  }

  Byte Radix::getMemory() {
    return memory;
  }

  void Radix::setMemory(Byte byte) {
    memory = byte;
  }

  Size Radix::getSize() {
    return size;
  }

  void Radix::setSize(Size givenSize) {
    size = givenSize;
  }

  Node Radix::node() {
    return Node(this, pointerToAddress(pointerFromAddress(sizeof(Meta), sizeof(node::Data))));
  }

  Node Radix::lastNode(node::Filter filter) {
    auto *meta = getMeta();

    Node nullNode = Node(this);

    for (auto *current = meta->getLastNode(this); current; current = current->getEarlier(this)) {
      auto candidate = current->cursor(this);
      if (filter == nullptr || filter(&nullNode, &candidate)) return candidate;
    }

    return Node(this);
  }

  Item Radix::lastItem(item::Filter filter) {
    auto *meta = getMeta();

    Item nullItem = Item(this);

    for (auto *current = meta->getLastItem(this); current; current = current->getEarlier(this)) {
      auto candidate = current->cursor(this);
      if (filter == nullptr || filter(&nullItem, &candidate)) return candidate;
    }

    return Item(this);
  }

  Checkpoint Radix::checkpoint() {
    return Checkpoint(this, memoryUsed());
  }

  Byte Radix::allocate(Size size) {
    if (size > memoryUnused()) return (void *)nullptr;

    Meta *meta = getMeta();

    Size end = meta->getEnd();

    meta->setEnd(end + size);

    return pointerFromAddress(end, size);
  }

  bool Radix::clear() {
    if (memorySize() < sizeof(Meta) + sizeof(node::Data)) return false;

    // Reset
    Meta *meta = getMeta();
    meta->setEnd(0);

    // Prepare
    meta = (Meta *)allocate(sizeof(Meta)).toPtr();
    node::Data *head = (node::Data *)allocate(sizeof(node::Data)).toPtr();
    *head = {};

    meta->setLastNode(this, head);
    meta->setLastItem(this, nullptr);

    return true;
  }

  Byte Radix::memoryFore() {
    return memory;
  }

  Byte Radix::memoryRear() {
    return memoryFore() + memorySize();
  }

  Size Radix::memorySize() {
    return size;
  }

  Size Radix::memoryUsed() {
    return getMeta()->getEnd();
  }

  Size Radix::memoryUnused() {
    return memorySize() - memoryUsed();
  }

  Byte Radix::pointerFromAddress(Size base, Size address) {
    Size size = memorySize();

    if (size < base || size < address || size < base + address) return (void *)nullptr;

    #if RADIX_REVERSE
      return memoryRear() - base - address;
    #else
      return memoryFore() + base;
    #endif
  }

  Size Radix::pointerToAddress(Byte pointer) {
    auto ptr = pointer.toPtr();
    auto fore = memoryFore().toPtr();
    auto rear = memoryRear().toPtr();

    if (ptr < fore || rear < ptr) return 0;

    #if RADIX_REVERSE
      return rear - ptr;
    #else
      return ptr - fore;
    #endif
  }
} // namespace radix

#endif
