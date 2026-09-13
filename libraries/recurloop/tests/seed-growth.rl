// Second-generation language growth: `word` itself is created with the seed
// and then creates further syntax through Context API, without using kernel
// `form` for those later words.
proc word_action (state:Context*, called:Phrase*) -> void {
    while context:source:peek(state, 0) == 32 || context:source:peek(state, 0) == 9 { context:source:advance(state, 1) }
    var name_bytes = 0
    while 1 {
        let ch = context:source:peek(state, name_bytes)
        if !((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch == 95 || ch == 45) { break }
        name_bytes += 1
    }
    if name_bytes == 0 { context:diagnostic:error(state, "word expects a name"); return }
    let name = cast(u8*, malloc(name_bytes + 1))
    if !name { return }
    defer free(name)
    var i = 0
    while i < name_bytes { name[i] = context:source:peek(state, i); i += 1 }
    name[name_bytes] = 0
    context:source:advance(state, name_bytes)
    while context:source:peek(state, 0) == 32 || context:source:peek(state, 0) == 9 { context:source:advance(state, 1) }
    if context:source:peek(state, 0) != 61 { context:diagnostic:error(state, "word expects '='"); return }
    context:source:advance(state, 1)
    while context:source:peek(state, 0) == 32 || context:source:peek(state, 0) == 9 { context:source:advance(state, 1) }
    var target_bytes = 0
    while 1 {
        let ch = context:source:peek(state, target_bytes)
        if !((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch == 95 || ch == 45) { break }
        target_bytes += 1
    }
    let target = cast(u8*, malloc(target_bytes + 1))
    if !target { return }
    defer free(target)
    i = 0
    while i < target_bytes { target[i] = context:source:peek(state, i); i += 1 }
    target[target_bytes] = 0
    context:source:advance(state, target_bytes)

    let seed = context:phrase:find(state, "RecurLoopSeed")
    let owner = context:phrase:find:exact(state, seed, "Forms")
    let prototype = context:phrase:find:exact(state, owner, target)
    if !prototype { context:diagnostic:error(state, "word target missing"); return }
    let bytes = context:phrase:payload:bytes(state, prototype)
    let symbol = cast(u8*, malloc(bytes + 1))
    if !symbol { return }
    defer free(symbol)
    context:phrase:read(state, prototype, 0, symbol, bytes)
    symbol[bytes] = 0
    let created = context:phrase:define:data(state, owner, name)
    if !created { context:diagnostic:error(state, "word definition failed"); return }
    context:phrase:data(state, created, symbol)
}
form word = word_action

proc bump_action (state:Context*, called:Phrase*) -> void { state.exec.status += 21 }
form bump = bump_action
word another-bump = bump
another-bump
another-bump

proc growth_verify_action (state:Context*, called:Phrase*) -> void {
    if state.exec.status != 42 { context:diagnostic:error(state, "second-generation syntax failed"); return }
    state.exec.status = 0
    printf("growth=42\n")
}
form growth_verify = growth_verify_action
growth_verify
