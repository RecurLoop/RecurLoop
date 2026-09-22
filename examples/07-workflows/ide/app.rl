// Project-local IDE application state. None of these records are part of
// ide.rli: changing the view shape is therefore a normal hot-reload operation.
let IDE:App = phrase { dictionary = true permanent = true }

record IDE:App:FileItem {
    state:u8*
    path:u8*
    depth:i64
    directory:i64
    next:IDE:App:FileItem*
}

record IDE:App:TerminalView {
    state:u8*
    model:IDE:Terminal*
    page:u8*
    output:u8*
    entry:u8*
    next:IDE:App:TerminalView*
}

record IDE:App:State {
    host:IDE:Host*
    root_box:u8*
    file_box:u8*
    editor:u8*
    file_label:u8*
    status:u8*
    notebook:u8*
    files:IDE:App:FileItem*
    terminal_views:IDE:App:TerminalView*
}

record IDE:App:TreeLoad {
    state:IDE:App:State*
    tree:u8*
    parent:u8*
}

let IDE:App:state = fn (host:IDE:Host*) -> IDE:App:State* {
    if !host { return cast(IDE:App:State*, 0) }
    let data = IDE:view_data(host)
    if !data { return cast(IDE:App:State*, 0) }
    return cast(IDE:App:State*, data)
}
