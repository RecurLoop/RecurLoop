#pragma once

#include <utilities/Size.hpp>

#include <cstdint>
#include <string>

namespace context {
  class Context;
}

namespace lexicon {
  class Phrase;
}

namespace recurloop {
  struct DebugLocation {
    std::string path;
    Size line = 1;
    Size position = 1;
  };

  class DebuggerState {
  public:
    enum class Mode : std::uint8_t { Continue, Step, Next, Finish };
    enum class Target : std::uint8_t { None, Source, Executable };

    struct Event {
      DebugLocation location;
      std::string phrase;
      Size depth = 0;
      std::uint64_t sequence = 0;
      bool breakpoint = false;
    } current;

    bool active = false;
    bool controller = false;
    bool paused = false;
    bool trace = false;
    Mode mode = Mode::Continue;
    Target target = Target::None;
    Size sourceDepth = 0;
    Size resumeDepth = 0;
    std::uint64_t sequence = 0;
    std::uint64_t nextBreakpoint = 1;
  };

  class Debugger {
  public:
    Debugger() = delete;

    static void initialize(context::Context &context);
    static void release(context::Context &context);
    static void registerActions(context::Context &context);
    static void setup(context::Context &context, lexicon::Phrase debug);

    static void sourceEnter(context::Context &context);
    static void sourceLeave(context::Context &context);
    static void beforeElaborate(context::Context &context, lexicon::Phrase &phrase, const DebugLocation &location);

    static void breakPhrase(context::Context &context, lexicon::Phrase &invoked);
    static void breakLine(context::Context &context, lexicon::Phrase &invoked);
    static void breakFunction(context::Context &context, lexicon::Phrase &invoked);
    static void deleteBreakpoint(context::Context &context, lexicon::Phrase &invoked);
    static void listBreakpoints(context::Context &context, lexicon::Phrase &invoked);
    static void trace(context::Context &context, lexicon::Phrase &invoked);
    static void run(context::Context &context, lexicon::Phrase &invoked);
    static void resume(context::Context &context, lexicon::Phrase &invoked);
    static void step(context::Context &context, lexicon::Phrase &invoked);
    static void next(context::Context &context, lexicon::Phrase &invoked);
    static void finish(context::Context &context, lexicon::Phrase &invoked);
    static void where(context::Context &context, lexicon::Phrase &invoked);
    static void evaluate(context::Context &context, lexicon::Phrase &invoked);
    static void runExecutable(context::Context &context, lexicon::Phrase &invoked);
    static void locals(context::Context &context, lexicon::Phrase &invoked);
    static void registers(context::Context &context, lexicon::Phrase &invoked);

  private:
    static DebuggerState &state(context::Context &context);
  };
} // namespace recurloop
