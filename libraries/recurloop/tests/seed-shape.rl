shape SeedNode {
    value:i64
    next:SeedNode*
    lanes:u8[8]
}

proc verify_shape_action (state:Context*, called:Phrase*) -> void {
    let node = context:type:find(state, "SeedNode")
    if !node { context:diagnostic:error(state, "SeedNode missing"); return }
    if context:type:size(state, node) != 24 { context:diagnostic:error(state, "SeedNode size mismatch"); return }
    if context:type:alignment(state, node) != 8 { context:diagnostic:error(state, "SeedNode alignment mismatch"); return }
    printf("shape=24\n")
}

form verify_shape = verify_shape_action
verify_shape
