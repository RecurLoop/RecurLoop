#pragma once

#include <vector>

namespace context {
  class Context;
}
namespace lexicon {
  class Phrase;
}

namespace recurloop {
  enum class SessionCommand {
    Generations,
    Publish,
    Refresh,
    Baseline,
    Cache,
    CacheStatus,
    Help,
    Quit,
  };

  struct SessionRequestState {
    std::vector<SessionCommand> commands;
  };

  // Request-local bridge between source-defined session phrases and the
  // Session wrapper that owns project publication and context attachment.
  // Commands are recorded while source executes and applied only after the
  // request transaction commits.
  class SessionRequestScope {
  public:
    explicit SessionRequestScope(SessionRequestState &state) noexcept;
    SessionRequestScope(const SessionRequestScope &) = delete;
    SessionRequestScope &operator=(const SessionRequestScope &) = delete;
    ~SessionRequestScope();

    static void registerActions(context::Context &context);

  private:
    SessionRequestState *previous_ = nullptr;
  };
} // namespace recurloop
