// A compact tour of the Bash-like shell after importing library.rl.
//
//   Recurloop --file examples/07-workflows/shell-language/library.rl
//   Recurloop --import /tmp/recurloop-shell-library.rli \
//       --file examples/07-workflows/shell-language/bash_like.rl
//
// Unknown top-level lines are commands. `run` stores an exit code, `capture`
// stores owned stdout, and `spawn` starts an Invocation whose result getters
// wait lazily. Native RecurLoop functions can also be pipeline stages.

var direct_status = run true
let direct_output = capture printf "assigned"
print direct_status
print direct_output
set direct_status = run false
assert direct_status == 1

let ShellDemo = []

let ShellDemo:uppercase = fn (input:u8*) -> u8* {
    let output = Shell:copy_text(input)
    if !output { return cast(u8*, 0) }
    var index = 0
    while output[index] != 0 {
        if output[index] >= 97 && output[index] <= 122 {
            output[index] -= 32
        }
        index += 1
    }
    return output
}

let shell_demo_main = fn (argc:i64, argv:u8**) -> i64 {
    // Both processes are running before either accessor synchronizes.
    let first = spawn sh -c "sleep 0.05; printf first"
    let second = spawn sh -c "sleep 0.05; printf second"
    if !first || !second { return 10 }
    defer first.destroy()
    defer second.destroy()
    printf("async: %s + %s\n", first.stdout(), second.stdout())

    let pipeline = Shell:Pipeline:new()
    if !pipeline { return 11 }
    defer Shell:Pipeline:destroy(pipeline)
    if !pipeline.add_command("printf", "mixed case\n") { return 12 }
    if !pipeline.add_function(ShellDemo:uppercase) { return 13 }

    let transformed = Shell:Invocation:start(pipeline, 1)
    if !transformed { return 14 }
    defer transformed.destroy()
    printf("function stage: %s", transformed.stdout())
    if transformed.exit_code() != 0 { return 15 }

    let failed = spawn sh -c "printf partial; exit 7"
    if !failed { return 16 }
    defer failed.destroy()
    printf("result object: stdout=%s, exit=%ld\n", failed.stdout(), failed.exit_code())
    return 0
}

emit executable "/tmp/recurloop-bash-like" shell_demo_entry = fn (argc:i64, argv:u8**) -> i64 {
    return shell_demo_main(argc, argv)
}

run true
