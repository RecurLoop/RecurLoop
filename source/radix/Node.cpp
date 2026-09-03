#if !defined(__RADIX_NODE_CPP)
  #define __RADIX_NODE_CPP
  #include <radix/Radix.hpp>

namespace radix {
  node::Data *Node::data() {
    return node::Data::get(getRadix(), getAddress());
  }

  Node::Node(Radix *radix, Size address) : radix(radix), address(address) {}

  Radix *Node::getRadix() {
    return radix;
  }

  Node &Node::setAddress(Size address) {
    this->address = address;
    return *this;
  }

  Size Node::getAddress() {
    return address;
  }

  Node Node::append(Byte key, Size keyOffset, Size keyBits) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    auto *meta = radix->getMeta();
    auto *current = data();

    // Iterate
    for (Size keyProgress = keyOffset; keyProgress - keyOffset < keyBits;) {
      node::Data *child = nullptr;

      if (Bit(key, keyProgress).get())
        child = current->getChildGreater(radix);
      else
        child = current->getChildSmaller(radix);

      // If child doesnt exists, create it and break
      if (!child) {
        node::Data *lastNode = meta->getLastNode(radix);

        Size keyMemoryBits = keyBits - (keyProgress - keyOffset);

        Size keyMemoryBytes = Bit::bytes(keyMemoryBits);

        if (keyMemoryBytes + sizeof(node::Data) > radix->memoryUnused()) return Node(radix);

        node::Data *newNode = (node::Data *)radix->allocate(sizeof(node::Data)).toPtr();
        Byte newKey = radix->allocate(keyMemoryBytes);

        newNode->setParent(radix, current);
        newNode->setChildSmaller(radix, nullptr);
        newNode->setChildGreater(radix, nullptr);
        newNode->setItem(radix, nullptr);
        newNode->setEarlier(radix, lastNode);
        newNode->setKeyFore(radix, Bit(newKey));
        newNode->setKeyRear(radix, Bit(newKey, keyMemoryBits));

        Bit::copy(Bit(key, keyProgress), Bit(newKey), keyMemoryBits);

        if ((Bit(key, keyProgress)).get())
          current->setChildGreater(radix, newNode);
        else
          current->setChildSmaller(radix, newNode);

        meta->setLastNode(radix, newNode);

        current = newNode;

        break;
      }

      Size matchedBits =
          Bit::compare(Bit(key, keyProgress), Bit(key, keyBits), child->getKeyFore(radix), child->getKeyRear(radix));

      // If key is not fully correct, split child
      if (matchedBits < child->getKeyRear(radix) - child->getKeyFore(radix)) {
        node::Data *newNode = (node::Data *)radix->allocate(sizeof(node::Data)).toPtr();
        if (!newNode) return Node(radix);

        bool splitDirection = (child->getKeyFore(radix) + matchedBits).get();

        newNode->setParent(radix, child->getParent(radix));
        newNode->setChildSmaller(radix, splitDirection ? nullptr : child);
        newNode->setChildGreater(radix, splitDirection ? child : nullptr);
        newNode->setItem(radix, nullptr);
        newNode->setEarlier(radix, meta->getLastNode(radix));
        newNode->setKeyFore(radix, child->getKeyFore(radix));
        newNode->setKeyRear(radix, child->getKeyFore(radix) + matchedBits);

        child->setParent(radix, newNode);
        child->setKeyFore(radix, newNode->getKeyRear(radix));

        if (Bit(key, keyProgress).get())
          current->setChildGreater(radix, newNode);
        else
          current->setChildSmaller(radix, newNode);

        meta->setLastNode(radix, newNode);

        // New node is fully correct, new node is child node now, continue
        child = newNode;
      }

      // child node key is fully correct, childNode is current now, repeat iteration
      current = child;
      keyProgress += matchedBits;
    }

    return current->cursor(radix);
  }

  Item Node::push() {
    auto *radix = getRadix();

    if (isNull()) return Item(radix);

    auto *meta = radix->getMeta();

    node::Data *current = data();
    item::Data *prevItem = current->getItem(radix);

    if (sizeof(item::Data) > radix->memoryUnused()) return Item(radix);

    item::Data *newItem = (item::Data *)radix->allocate(sizeof(item::Data)).toPtr();

    newItem->setNode(radix, current);
    newItem->setPrev(radix, prevItem);
    newItem->setNext(radix, nullptr);
    newItem->setEarlier(radix, meta->getLastItem(radix));
    newItem->setContentBytes(0);

    if (prevItem) prevItem->setNext(radix, newItem);

    current->setItem(radix, newItem);

    meta->setLastItem(radix, newItem);

    return newItem->cursor(radix);
  }

  Match Node::matchFirst(Byte key, Size keyOffset, Size keyBits, match::Filter filter) {
    auto *radix = getRadix();

    auto result = Match(radix, 0, 0, false);

    if (isNull()) return result;

    node::Data *current = data();

    for (Size keyProgress = keyOffset;;) {
      Match candidate(radix, current->address(radix), keyProgress - keyOffset, false);
      if (filter == nullptr || filter(this, &candidate)) return candidate;

      if (keyBits <= keyProgress - keyOffset) {
        result.more = (bool)current->getChildGreater(radix) || (bool)current->getChildSmaller(radix);
        break;
      }

      node::Data *child = nullptr;

      if (Bit(key, keyProgress).get())
        child = current->getChildGreater(radix);
      else
        child = current->getChildSmaller(radix);

      if (!child) {
        result.more = false;
        break;
      }

      Bit keyFore = Bit(key, keyProgress);
      Bit keyRear = Bit(key, keyProgress + keyBits + keyOffset);
      Bit childFore = child->getKeyFore(radix);
      Bit childRear = child->getKeyRear(radix);

      Size matchedBits = Bit::compare(keyFore, keyRear, childFore, childRear);

      if (matchedBits < childRear - childFore) {
        result.more = bool(keyRear - keyFore <= matchedBits);
        break;
      }

      current = child;
      keyProgress += matchedBits;
    }

    return result;
  }

  Match Node::matchLongest(Byte key, Size keyOffset, Size keyBits, match::Filter filter) {
    auto *radix = getRadix();

    auto result = Match(radix, 0, 0, false);

    if (isNull()) return result;

    node::Data *current = data();

    for (Size keyProgress = keyOffset;;) {
      Match candidate(radix, current->address(radix), keyProgress - keyOffset, true);
      if (filter == nullptr || filter(this, &candidate)) result = candidate;

      if (keyBits <= keyProgress - keyOffset) {
        result.more = (bool)current->getChildGreater(radix) || (bool)current->getChildSmaller(radix);
        break;
      }

      node::Data *child = nullptr;

      if (Bit(key, keyProgress).get())
        child = current->getChildGreater(radix);
      else
        child = current->getChildSmaller(radix);

      if (!child) {
        result.more = false;
        break;
      }

      Bit keyFore = Bit(key, keyProgress);
      Bit keyRear = Bit(key, keyBits + keyOffset);
      Bit childFore = child->getKeyFore(radix);
      Bit childRear = child->getKeyRear(radix);

      Size matchedBits = Bit::compare(keyFore, keyRear, childFore, childRear);

      if (matchedBits < childRear - childFore) {
        result.more = bool(keyRear - keyFore <= matchedBits);
        break;
      }

      current = child;
      keyProgress += matchedBits;
    }

    return result;
  }

  Match Node::matchExact(Byte key, Size keyOffset, Size keyBits, match::Filter filter) {
    auto *radix = getRadix();

    auto result = Match(radix, 0, 0, false);

    if (isNull()) return result;

    node::Data *current = data();

    for (Size keyProgress = keyOffset;;) {
      if (keyBits <= keyProgress - keyOffset) {
        Match candidate(radix, current->address(radix), keyProgress - keyOffset, false);
        if (filter == nullptr || filter(this, &candidate)) return candidate;
      }

      node::Data *child = nullptr;

      if (Bit(key, keyProgress).get())
        child = current->getChildGreater(radix);
      else
        child = current->getChildSmaller(radix);

      if (!child) {
        result.more = false;
        break;
      }

      Bit keyFore = Bit(key, keyProgress);
      Bit keyRear = Bit(key, keyProgress + keyBits + keyOffset);
      Bit childFore = child->getKeyFore(radix);
      Bit childRear = child->getKeyRear(radix);

      Size matchedBits = Bit::compare(keyFore, keyRear, childFore, childRear);

      if (matchedBits < childRear - childFore) {
        result.more = bool(keyRear - keyFore <= matchedBits);
        break;
      }

      current = child;
      keyProgress += matchedBits;
    }

    return result;
  }

  Node Node::predecessor(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    Node candidate;
    node::Data *current = data();

    for (current = current->getParent(radix); current; current = current->getParent(radix)) {
      candidate = current->cursor(radix);
      if (filter == nullptr || filter(this, &candidate)) return candidate;
    }

    return Node(radix);
  }

  Node Node::fore(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    return filter == nullptr || filter(this, this) ? *this : next(filter);
  }

  Node Node::rear(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    node::Data *current = data();
    while (node::Data *rear = current->getChildGreater(radix) ?: current->getChildSmaller(radix)) current = rear;

    Node candidate = current->cursor(radix);
    if (filter == nullptr || filter(this, &candidate)) return candidate;

    return candidate.prev(filter);
  }

  Node Node::prev(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    node::Data *current = data();
    while (true) {
      node::Data *parent = current->getParent(radix);
      if (!parent) return Node(radix);

      node::Data *prev = parent->getChildSmaller(radix);
      if (prev && prev != current) {
        current = prev;

        while (node::Data *prev = current->getChildGreater(radix) ?: current->getChildSmaller(radix)) current = prev;
      } else {
        current = parent;
      }

      Node candidate = current->cursor(radix);
      if (filter == nullptr || filter(this, &candidate)) return candidate;
    }
  }

  Node Node::next(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    node::Data *current = data();
    while (true) {
      node::Data *child = current->getChildSmaller(radix);
      child = child ? child : current->getChildGreater(radix);

      if (child) {
        current = child;
        Node candidate = current->cursor(radix);
        if (filter == nullptr || filter(this, &candidate)) return candidate;
        continue;
      }

      while (true) {
        node::Data *parent = current->getParent(radix);
        if (!parent) return Node(radix);

        node::Data *childGreater = parent->getChildGreater(radix);
        if (childGreater && childGreater != current) {
          current = childGreater;
          break;
        }

        current = parent;
      }

      Node candidate = current->cursor(radix);
      if (filter == nullptr || filter(this, &candidate)) return candidate;
    }
  }

  Node Node::foreInverse(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    node::Data *current = data();
    while (node::Data *foreInverse = current->getChildSmaller(radix) ?: current->getChildGreater(radix))
      current = foreInverse;

    Node candicate = current->cursor(radix);
    if (filter == nullptr || filter(this, &candicate)) return candicate;

    return candicate.nextInverse(filter);
  }

  Node Node::rearInverse(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    return filter == nullptr || filter(this, this) ? *this : prevInverse(filter);
  }

  Node Node::prevInverse(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    node::Data *current = data();
    while (true) {
      node::Data *prevInverse = current->getChildGreater(radix);
      prevInverse = prevInverse ? prevInverse : current->getChildSmaller(radix);

      if (prevInverse) {
        current = prevInverse;
        Node candidate = current->cursor(radix);
        if (filter == nullptr || filter(this, &candidate)) return candidate;
        continue;
      }

      while (true) {
        node::Data *parent = current->getParent(radix);
        if (!parent) return Node(radix);

        node::Data *childSmaller = parent->getChildSmaller(radix);
        if (childSmaller && childSmaller != current) {
          current = childSmaller;
          break;
        }

        current = parent;
      }

      Node candidate = current->cursor(radix);
      if (filter == nullptr || filter(this, &candidate)) return candidate;
    }
  }

  Node Node::nextInverse(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    node::Data *current = data();
    while (true) {
      node::Data *parent = current->getParent(radix);
      if (!parent) return Node(radix);

      node::Data *nextInverse = parent->getChildGreater(radix);
      if (nextInverse && nextInverse != current) {
        current = nextInverse;

        while (node::Data *nextInverse = current->getChildSmaller(radix) ?: current->getChildGreater(radix))
          current = nextInverse;
      } else {
        current = parent;
      }

      Node candidate = current->cursor(radix);
      if (filter == nullptr || filter(this, &candidate)) return candidate;
    }
  }

  Node Node::earlier(node::Filter filter) {
    auto *radix = getRadix();

    if (isNull()) return Node(radix);

    node::Data *current = data();
    for (current = current->getEarlier(radix); current; current = current->getEarlier(radix)) {
      Node candidate = current->cursor(radix);
      if (filter == nullptr || filter(this, &candidate)) return candidate;
    }

    return Node(radix);
  }

  Item Node::item(item::Filter filter) {
    auto *radix = getRadix();

    Item nullItem = Item(radix);

    if (isNull()) return nullItem;

    item::Data *current = data()->getItem(radix);

    while (current) {
      Item candidate = current->cursor(radix);
      if (filter == nullptr || filter(&nullItem, &candidate)) return candidate;

      current = current->getPrev(radix);
    }

    return Item(radix);
  }

  Byte Node::content(Size dataOffset, Size dataSize) {
    auto *radix = getRadix();

    if (isNull()) return (void *)nullptr;

  #if RADIX_REVERSE
    return data()->getKeyFore(radix).getByte() - dataOffset - dataSize; // backward radix
  #else
    return data()->getKeyRear(radix).getByte() + dataOffset; // forward radix
  #endif
  }

  Byte Node::allocate(Size bytes) {
    auto *radix = getRadix();

    if (isNull()) return (void *)nullptr;

    if (radix->lastNode().getAddress() != getAddress()) return (void *)nullptr;

    return radix->allocate(bytes);
  }

  Size Node::keyBits(node::Filter filter) {
    auto *radix = getRadix();

    Size keyBits = 0;
    node::Data *current = data();
    for (; current; current = current->getParent(radix)) {
      Size addr = current->address(radix);
      Node candidate = current->cursor(radix);
      if (filter != nullptr && !filter(this, &candidate)) break;

      keyBits += current->getKeyRear(radix) - current->getKeyFore(radix);
    }

    return keyBits;
  }

  bool Node::keyCopy(Bit keyOut, Size keyBits) {
    auto *radix = getRadix();

    node::Data *current = data();

    while (current) {
      Size nodeKeyBits = current->getKeyRear(radix) - current->getKeyFore(radix);

      if (keyBits < nodeKeyBits) {
        Size nodeKeySuffixOffset = current->getKeyFore(radix).getOffset() + nodeKeyBits - keyBits;

        Bit::copy(current->getKeyFore(radix) + nodeKeySuffixOffset, keyOut, keyBits);

        return false;
      }

      keyBits -= nodeKeyBits;

      Bit::copy(current->getKeyFore(radix), keyOut + keyBits + keyOut.getOffset(), nodeKeyBits);

      current = current->getParent(radix);
    }

    return true;
  }

  bool Node::isNull() {
    return address == 0;
  }

  bool Node::isEmpty(item::Filter filter) {
    return item(filter).isNull();
  }
} // namespace radix

#endif
