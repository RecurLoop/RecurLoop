proc tick_action (state:Context*, called:Phrase*) -> void {
    state.exec.status += 1
}
form tick = tick_action

proc repeat_action (state:Context*, called:Phrase*) -> void {
    let block = context:source:block:capture(state)
    if !block { context:diagnostic:error(state, "repeat expects a block"); return }
    defer context:source:block:release(block)
    let header = context:source:block:header(block)
    var i = 0
    while header[i] == 32 || header[i] == 9 || header[i] == 10 || header[i] == 13 { i += 1 }
    var count = 0
    while header[i] >= 48 && header[i] <= 57 { count = count * 10 + header[i] - 48; i += 1 }
    while header[i] == 32 || header[i] == 9 || header[i] == 10 || header[i] == 13 { i += 1 }
    if count <= 0 || header[i] != 0 { context:diagnostic:error(state, "repeat expects one positive integer"); return }
    while count > 0 { context:source:block:execute:current(state, block); count -= 1 }
}
form repeat = repeat_action

proc verify_status_action (state:Context*, called:Phrase*) -> void {
    if state.exec.status != 3 { context:diagnostic:error(state, "form dispatch mismatch"); return }
    state.exec.status = 0
    printf("form=3\n")
}
form verify_status = verify_status_action

repeat 3 {
    tick
}
verify_status
