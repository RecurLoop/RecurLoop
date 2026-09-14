// RecurLoop standard language, defined as source rather than as an image dump.
// The existing core is used only to read this declaration. engine define captures
// the whole block first, replaces the lexicon, and rebuilds the stage-0 language
// from these symbolic declarations.
engine define {
  include "core/phrases.rl"
  include "core/types.rl"
  include "core/expressions.rl"
  include "core/functions.rl"
  include "core/assembler.rl"
  include "core/runtime.rl"
  include "core/compiler.rl"
}

// Control flow is already source-defined and is applied after the fresh stage-0
// lexicon exists, so it is parsed by the language that was just constructed.
include "core/control-flow.rl"

engine export "core.rli"
