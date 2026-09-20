// Generation-owned view state.  The stable IDE:Host and terminal runtimes live
// in ide.rli; these pointers are thrown away and rebuilt after every publish.

let IDE_App = phrase { dictionary = true permanent = true }
const IDE_App:hot_reload_probe = 1

record IDE_App:FileItem {
    state:u8*
    path:u8*
    next:IDE_App:FileItem*
}

record IDE_App:TerminalView {
    state:u8*
    model:IDE:Terminal*
    output:u8*
    entry:u8*
    next:IDE_App:TerminalView*
}

record IDE_App:State {
    host:IDE:Host*
    root_box:u8*
    file_box:u8*
    editor:u8*
    file_label:u8*
    status:u8*
    notebook:u8*
    files:IDE_App:FileItem*
    terminal_views:IDE_App:TerminalView*
}

let IDE_App:state = fn (host:IDE:Host*) -> IDE_App:State* {
    if !host || !host.user_data { return cast(IDE_App:State*, 0) }
    return cast(IDE_App:State*, host.user_data)
}
