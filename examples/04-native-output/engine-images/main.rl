// =============================================================================
// Exporting and importing RecurLoop state
//
// Run: make example EXAMPLE=04-native-output/engine-images
//
// This example creates two binary images in /tmp. `engine import` restores
// serializable lexicon state, including values, phrases, types, and
// relocations. Process-local JIT entries are rebuilt from stored modules.
// =============================================================================


// -----------------------------------------------------------------------------
// 1. A persistent value.
// -----------------------------------------------------------------------------

var answer = 40
answer += 2

engine export "/tmp/recurloop-simple-state.rli"

// Change the active state after export.
answer = 0
assert answer == 0

// Import restores the serialized state.
engine import "/tmp/recurloop-simple-state.rli"

assert answer == 42
print "[simple] restored answer=" + str(answer)


// -----------------------------------------------------------------------------
// 2. Related values and a stored native module.
// -----------------------------------------------------------------------------

const project = "RecurLoop"
var completed = 4
var pending = 3

var progress = project + ": " + str(completed) + "/" + str(completed + pending)

// The module is persistent. The first call creates a process-local JIT entry,
// which is excluded from the image and rebuilt after import.
let persisted_compiler_entry = asm { ret }
persisted_compiler_entry

engine export "/tmp/recurloop-complex-state.rli"

// Corrupt the active state so the restore is visible.
completed = 0
pending = 100
progress = project + ": " + str(completed) + "/" + str(completed + pending)

assert progress == "RecurLoop: 0/100"

engine import "/tmp/recurloop-complex-state.rli"

assert completed == 4
assert pending == 3
assert progress == "RecurLoop: 4/7"
print "[complex] restored progress=" + progress

// The imported module resolves a new JIT entry.
persisted_compiler_entry

// Expected output:
//   [simple] restored answer=42
//   [complex] restored progress=RecurLoop: 4/7
