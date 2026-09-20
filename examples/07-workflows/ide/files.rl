let IDE_App:has_file = fn (state:IDE_App:State*, path:u8*) -> i64 {
    if !state || !path { return 0 }
    var item = state.files
    while item {
        if item.path && strcmp(item.path, path) == 0 { return 1 }
        item = item.next
    }
    return 0
}

let IDE_App:on_file_clicked = fn (widget:u8*, data:u8*) -> void {
    let item = cast(IDE_App:FileItem*, data)
    if !item { return }
    IDE_App:open_path(cast(IDE_App:State*, item.state), item.path)
}

let IDE_App:add_file = fn (state:IDE_App:State*, full:u8*) -> void {
    if !state || !full || IDE_App:has_file(state, full) { return }
    let relative = IDE:relative(state.host.root, full)
    if !relative { return }
    let button = gtk_button_new_with_label(relative)
    free(relative)
    if !button { return }

    let item = cast(IDE_App:FileItem*, malloc(24))
    if !item { return }
    item.state = cast(u8*, state)
    item.path = IDE:copy(full)
    item.next = state.files
    if !item.path { free(cast(u8*, item)); return }
    state.files = item

    g_signal_connect_data(button, "clicked", IDE_App:on_file_clicked, cast(u8*, item), cast(u8*, 0), 0)
    gtk_box_pack_start(state.file_box, button, 0, 0, 1)
}

let IDE_App:scan_tree = fn (state:IDE_App:State*, path:u8*) -> void {
    let directory = opendir(path)
    if !directory { return }
    defer closedir(directory)
    while 1 {
        let entry = readdir(directory)
        if !entry { return }
        let kind = entry[18]
        let name = &entry[19]
        if IDE:skip_directory(name) { continue }
        let child = IDE:join(path, name)
        if !child { continue }
        if kind == 4 { IDE_App:scan_tree(state, child) }
        else if kind == 0 && IDE:is_directory(child) { IDE_App:scan_tree(state, child) }
        else { IDE_App:add_file(state, child) }
        free(child)
    }
}

let IDE_App:free_files = fn (state:IDE_App:State*) -> void {
    if !state { return }
    var item = state.files
    while item {
        let next = item.next
        if item.path { free(item.path) }
        free(cast(u8*, item))
        item = next
    }
    state.files = cast(IDE_App:FileItem*, 0)
}
