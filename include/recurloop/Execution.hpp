#pragma once

#include <utilities/Size.hpp>

#include <iosfwd>
#include <string_view>

namespace context {
  class Context;
}

namespace recurloop {
  using SourceCompletedCallback = void (*)(void *user, context::Context &context, std::string_view path);
  using SourceEnterCallback = bool (*)(void *user, context::Context &context, std::string_view path);

  // Request-local observer used by the project runtime to checkpoint completed
  // source files. It is process-local state and never enters engine images.
  class SourceObserverScope {
  public:
    SourceObserverScope(void *user, SourceCompletedCallback callback, SourceEnterCallback enter = nullptr) noexcept;
    SourceObserverScope(const SourceObserverScope &) = delete;
    SourceObserverScope &operator=(const SourceObserverScope &) = delete;
    ~SourceObserverScope();

  private:
    void *previousUser_ = nullptr;
    SourceCompletedCallback previousCallback_ = nullptr;
    SourceEnterCallback previousEnter_ = nullptr;
  };

  // Gives the active project cache a chance to restore a completed nested
  // source fragment before `include` opens and evaluates it.
  bool restoreObservedSource(context::Context &context, std::string_view path);

  void executeSource(context::Context &context, std::string_view source, std::string_view path, Size line,
                     Size position = 1);
  void executeStream(context::Context &context, std::istream &source, std::string_view path, Size line = 1,
                     Size position = 1);
  void executeCurrentBlock(context::Context &context, bool scoped = true);
  int executeInputs(context::Context &context);
} // namespace recurloop
