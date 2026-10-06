#pragma once

#include <context/IOStreams.hpp>

namespace recurloop {
  // Native stdio imports use the calling session's streams. No process-wide
  // descriptor redirection: concurrent sessions keep independent output.
  class NativeIO {
  public:
    static void install();
    static const context::IOStreams *current();

    class Scope {
    public:
      explicit Scope(context::IOStreams streams);
      ~Scope();
      Scope(const Scope &) = delete;
      Scope &operator=(const Scope &) = delete;

    private:
      friend class NativeIO;
      context::IOStreams streams_;
      int process_;
      Scope *previous_;
    };

  private:
    static thread_local Scope *active_;
  };
} // namespace recurloop
