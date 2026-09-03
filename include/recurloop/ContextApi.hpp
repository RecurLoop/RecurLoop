#pragma once

#include <cstdint>

namespace context {
  class Context;
}

namespace recurloop {
  // Typed, host-only operations exposed to compiled fn actions. Phrase
  // addresses are context-local handles; zero means that the operation failed.
  class ContextApi {
  public:
    ContextApi() = delete;

    static void setup(context::Context &context);
  };

  namespace context_phrase {
    enum Find : std::uint64_t { Exact = 0, First = 1, Longest = 2 };
    enum Define : std::uint64_t {
      Dictionary = 1ull << 0,
      Serializable = 1ull << 1,
      Unserializable = 1ull << 2,
      HasType = 1ull << 3,
      HasPrototype = 1ull << 4,
      HasSuccessor = 1ull << 5,
      HasAction = 1ull << 6,
      Permanent = 1ull << 7,
      Rewritable = 1ull << 8
    };
    enum Call : std::uint64_t { Invoke = 0, Elaborate = 1, Action = 2 };
    enum Get : std::uint64_t { Parent = 0, Type = 1, Prototype = 2, Successor = 3, PayloadBytes = 4, Flags = 5 };
    enum Set : std::uint64_t {
      SetType = 1,
      SetPrototype = 2,
      SetSuccessor = 3,
      SetAction = 4,
      SetSerializable = 5,
      SetPermanent = 6,
      SetRewritable = 7
    };
  } // namespace context_phrase

  namespace context_type {
    enum Get : std::uint64_t {
      Kind = 0,
      Size = 1,
      Alignment = 2,
      Signed = 3,
      Element = 4,
      ElementCount = 5,
      PointerDepth = 6,
      Result = 7
    };
  } // namespace context_type
} // namespace recurloop
