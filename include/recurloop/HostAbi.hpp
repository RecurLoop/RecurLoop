#pragma once

#include <context/Context.hpp>

namespace recurloop {
  // Process-local implementation registry required by persisted language
  // images. Host ABI registration installs no user-visible language phrases;
  // it only makes stable action names resolvable when an .rli is restored.
  class HostAbi {
  public:
    HostAbi() = delete;

    static void registerActions(context::Context &context);
  };
} // namespace recurloop
