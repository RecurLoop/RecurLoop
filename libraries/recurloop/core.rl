engine define {
  // RecurLoop standard language is defined semantically from these sources.
  // The seed only enters this block; CoreDefinition replaces the seed lexicon.
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

// Compiler working collections are implemented in RecurLoop and persisted as
// compiled functions in the core image. Live collection instances remain
// process-local scratch memory.
include "core/collections.rl"

// Standard actions that can be expressed in RecurLoop are compiled into the
// image after the fresh source-defined language exists.
include "core/actions.rl"

engine export "core.rli"
