proc seed_add (a:i64, b:i64) -> i64 {
    return a + b
}

proc seed_mix (value:i64) -> i64 {
    return seed_add(value, 2) * 2
}

proc verify_proc_action (state:Context*, called:Phrase*) -> void {
    let address = context:function:address(state, "seed_mix")
    if !address { context:diagnostic:error(state, "seed_mix missing"); return }
    let target = cast(RecurLoopSeed:I64Call1, address)
    if target(19) != 42 { context:diagnostic:error(state, "proc result mismatch"); return }
    printf("proc=42\n")
}

form verify_proc = verify_proc_action
verify_proc
