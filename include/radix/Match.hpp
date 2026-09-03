#pragma once

#include "_module_classes.hpp"
#include "Node.hpp"
#include <utilities/Declaration.hpp>

namespace radix {
  class Match : public Node {
  protected:
    Size bits = 0;
    bool more = false;

  public:
    DECLARATION Match(Radix *radix = nullptr, Size address = 0, Size bits = 0, bool wantsMore = false)
        : Node(radix, address), bits(bits), more(wantsMore) {}

    DECLARATION Node node();

    DECLARATION Match *setBits(Size bits);
    DECLARATION Size getBits();

    DECLARATION Match *wantsMore(bool more);
    DECLARATION bool wantsMore();

    friend Node;
  };
} // namespace radix
