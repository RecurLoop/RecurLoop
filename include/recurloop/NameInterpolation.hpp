#pragma once

namespace context { class Context; }
namespace lexicon { class Phrase; }

namespace recurloop {
  class NameInterpolation {
  public:
    NameInterpolation() = delete;

    static void append(context::Context &context, lexicon::Phrase &invoked);
  };
} // namespace recurloop
