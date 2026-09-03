#pragma once
#include <utilities/Utilities.hpp>

namespace radix {
  class Node;
  class Item;
  namespace node {
    class Data;
    using Filter = bool (*)(Node *node, Node *candidate);
  } // namespace node

  namespace item {
    class Data;
    using Filter = bool (*)(Item *item, Item *candidate);
  } // namespace item

  class Checkpoint;
  class Match;
  class Meta;
  class Radix;

  namespace match {
    using Filter = bool (*)(Node *node, Match *candidate);
  } // namespace match
} // namespace radix
