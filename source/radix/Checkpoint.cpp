#if !defined(__RADIX_CHECKPOINT_CPP)
  #define __RADIX_CHECKPOINT_CPP
  #include <radix/Radix.hpp>

namespace radix {
  Radix *Checkpoint::getRadix() {
    return radix;
  }

  Size Checkpoint::getAddress() {
    return address;
  }

  void Checkpoint::restore() {
    auto *radix = getRadix();
    auto *meta = radix->getMeta();
    auto addr = getAddress();

    // Restore items
    for (item::Data *drop = meta->getLastItem(radix); drop->address(radix) >= addr;) {
      node::Data *node = drop->getNode(radix);
      item::Data *prev = drop->getPrev(radix);

      node->setItem(radix, prev);

      if (prev) prev->setNext(radix, nullptr);

      drop = drop->getEarlier(radix);

      meta->setLastItem(radix, drop);
    }

    // Restore nodes
    for (node::Data *drop = meta->getLastNode(radix); drop->address(radix) >= addr;) {
      bool direction = drop->getKeyFore(radix).get();

      // If node has child it means that node is spliting node (child is splitted)
      // otherwise there was no split (parent had null child)
      if (drop->getChildSmaller(radix) || drop->getChildGreater(radix)) {
        node::Data *splittedNode =
            drop->getChildSmaller(radix) ? drop->getChildSmaller(radix) : drop->getChildGreater(radix);

        if (!splittedNode) splittedNode = drop->getChildGreater(radix);

        // Restore splitted node context
        splittedNode->setParent(radix, drop->getParent(radix));
        splittedNode->setKeyFore(radix, drop->getKeyFore(radix));

        // Restore parent node context
        node::Data *dropParent = drop->getParent(radix);
        if (direction)
          drop->getParent(radix)->setChildGreater(radix, splittedNode);
        else
          drop->getParent(radix)->setChildSmaller(radix, splittedNode);
      } else {
        // We may have reached the head node
        node::Data *dropParent = drop->getParent(radix);

        if (dropParent) {
          if (direction)
            dropParent->setChildGreater(radix, nullptr);
          else
            dropParent->setChildSmaller(radix, nullptr);
        }
      }

      // Restore meta information
      drop = drop->getEarlier(radix);

      meta->setLastNode(radix, drop);
    }

    meta->setEnd(addr);
  }
} // namespace radix

#endif
