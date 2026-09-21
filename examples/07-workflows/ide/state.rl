// Stable record layouts live in ide.rli so this application layer can be
// replayed into the same shared project on every hot reload.
//
// Keep source-defined behavior reloadable: `let` intentionally replaces the
// previous phrase generation when application.rl is rebuilt.

IDE_App:hot_reload_probe = 3

let IDE_App:state = fn (host:IDE:Host*) -> IDE_App:State* {
    if !host || !host.user_data { return cast(IDE_App:State*, 0) }
    return cast(IDE_App:State*, host.user_data)
}
