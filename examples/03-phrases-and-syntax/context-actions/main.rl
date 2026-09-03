// A parser implemented as a compiled phrase action. It reads comma-separated
// names and installs each name in the active lexicon through the typed Context
// API.

extern printf(format:u8*, ...) -> i64 abi sysv-amd64

fn count_invocation(state:Context*, called:Phrase*) -> void {
    // During an action, Context.exec.invoked points to the same phrase passed
    // as the second argument.
    if state.exec.invoked == called {
        state.exec.status += 1
    }

    printf("executed command #%lld\n", state.exec.status)
    return
}

fn install_commands(state:Context*, called:Phrase*) -> void {
    var source:u8* = "alpha,beta,gamma"
    var prototype = context:phrase:find(state, "count_invocation", 0, 16)
    var start = 0
    var index = 0

    while source[index] != 0 {
        if source[index] == 44 {
            context:phrase:define(state, source, start, index - start, prototype)
            start = index + 1
        }
        index += 1
    }

    context:phrase:define(state, source, start, index - start, prototype)
    return
}

// This example uses the process status as a counter and resets it before exit.
fn reset_status(state:Context*, called:Phrase*) -> void {
    state.exec.status = 0
    return
}

// alpha, beta, and gamma do not exist until this action installs them from the
// count_invocation prototype.
install_commands

alpha
beta alpha
gamma beta alpha

reset_status

debug:stats
