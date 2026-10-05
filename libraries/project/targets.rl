// Source-owned project grammar. Every client consumes the same phrase registry.
link shared "c"
extern strlen(text:u8*) -> u64 abi sysv-amd64
extern strcmp(left:u8*, right:u8*) -> i32 abi sysv-amd64
extern getenv(name:u8*) -> u8* abi sysv-amd64

let Project:Targets = phrase { dictionary = true }

let Project:field = fn (state:Context*, target:u64, name:u8*, text:u8*) -> void {
    if !text { return }
    let field = context:phrase:define:data(state, target, name)
    context:phrase:data(state, field, text, 0, strlen(text))
}

syntax target <name:raw> [depends "[" <dependencies:raw> "]"] [debug (executable <executable:string> | source <program:string>)] <body:block> action fn (state:Context*, called:Phrase*) -> void {
    let name = context:syntax:capture(state, "name")
    if !name || !name[0] {
        context:diagnostic:error(state, "project target requires a name")
        return
    }
    let project = context:phrase:find(state, "Project")
    let owner = context:phrase:find:exact(state, project, "Targets")
    if !owner {
        context:diagnostic:error(state, "project target registry is unavailable")
        return
    }
    if context:phrase:find:exact(state, owner, name) {
        context:diagnostic:error(state, "duplicate project target")
        return
    }
    let target = context:phrase:define:dictionary(state, owner, name)
    let body = context:syntax:capture(state, "body")
    Project:field(state, target, "command", body)
    Project:field(state, target, "dependencies", context:syntax:capture(state, "dependencies"))
    Project:field(state, target, "debugExecutable", context:syntax:capture(state, "executable"))
    Project:field(state, target, "debugProgram", context:syntax:capture(state, "program"))
    Project:field(state, target, "path", context:syntax:path(state))
    var line = state.source.line
    var at:u64 = 0
    while body[at] {
        if body[at] == 10 { line -= 1 }
        at += 1
    }
    let location = context:phrase:define:data(state, target, "line")
    context:phrase:data(state, location, cast(u8*, &line), 0, 8)
}
set target.kind = "keyword"
set target.color = "#C586C0"
set target.docs = "Declares a deferred project target, dependencies and optional native or source debug entry."
