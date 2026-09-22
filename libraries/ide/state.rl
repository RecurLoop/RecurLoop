// Stable record layouts live in ide.rli so this application layer can be
// replayed into the same shared project on every hot reload.
//
// Keep source-defined behavior reloadable: launcher definitions may replace
// these phrases in the next project generation.

let IDE:App:state = fn (host:IDE:Host*) -> IDE:App:State* {
    if !host || !host.user_data { return cast(IDE:App:State*, 0) }
    return cast(IDE:App:State*, host.user_data)
}
