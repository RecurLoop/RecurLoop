// Emit a program with RecurLoop source metadata and debug that executable.
// Run from the repository root:
//   build/Debug/bin/recurloop --file examples/07-workflows/source-debugger/debugger_executable.rl
//
// The prepared command tour demonstrates function breakpoints, step into,
// finish, locals, and phrase-level stepping. The process exits with status 42.

module auto
module clear

fn add_one(value:i64) -> i64 {
var result = value + 1
return result
}

emit executable "/tmp/recurloop-debugger-executable" debugger_program = fn () -> i64 {
var answer = add_one(40)
answer += 1
return answer
}

debug:break function "debugger_program"
debug:executable run "/tmp/recurloop-debugger-executable"
