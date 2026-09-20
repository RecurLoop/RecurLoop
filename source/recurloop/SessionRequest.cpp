#include <recurloop/SessionRequest.hpp>

#include <context/Context.hpp>
#include <utilities/Exception.hpp>

namespace recurloop {
  namespace {
    thread_local SessionRequestState *activeRequest = nullptr;

    void request(SessionCommand command) {
      if (activeRequest == nullptr) THROW(, "session command requires a managed Session")
      activeRequest->commands.push_back(command);
    }

    void generations(context::Context &, lexicon::Phrase &) {
      request(SessionCommand::Generations);
    }

    void publish(context::Context &, lexicon::Phrase &) {
      request(SessionCommand::Publish);
    }

    void refresh(context::Context &, lexicon::Phrase &) {
      request(SessionCommand::Refresh);
    }

    void help(context::Context &, lexicon::Phrase &) {
      request(SessionCommand::Help);
    }

    void quit(context::Context &, lexicon::Phrase &) {
      request(SessionCommand::Quit);
    }
  } // namespace

  SessionRequestScope::SessionRequestScope(SessionRequestState &state) noexcept : previous_(activeRequest) {
    activeRequest = &state;
  }

  SessionRequestScope::~SessionRequestScope() {
    activeRequest = previous_;
  }

  void SessionRequestScope::registerActions(context::Context &context) {
    context.actions().define("session.generations", generations);
    context.actions().define("session.publish", publish);
    context.actions().define("session.refresh", refresh);
    context.actions().define("session.help", help);
    context.actions().define("session.quit", quit);
  }
} // namespace recurloop
