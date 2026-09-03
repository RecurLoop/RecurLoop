#pragma once

namespace context { class Context; }
namespace lexicon { class Phrase; }

namespace recurloop {
  class ControlFlow {
  public:
    ControlFlow() = delete;

    static void setup(context::Context &context);
    static void conditional(context::Context &context, lexicon::Phrase &invoked);
    static void loop(context::Context &context, lexicon::Phrase &invoked);
  };
} // namespace recurloop
