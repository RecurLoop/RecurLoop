let IDE_App:set_status = fn (state:IDE_App:State*, text:u8*) -> void {
    if state && state.status { gtk_label_set_text(state.status, text) }
}

let IDE_App:editor_text = fn (state:IDE_App:State*) -> u8* {
    if !state || !state.editor { return cast(u8*, 0) }
    let buffer = gtk_text_view_get_buffer(state.editor)
    if !buffer { return cast(u8*, 0) }
    let first = malloc(128)
    let last = malloc(128)
    if !first || !last {
        if first { free(first) }
        if last { free(last) }
        return cast(u8*, 0)
    }
    defer free(first)
    defer free(last)
    gtk_text_buffer_get_start_iter(buffer, first)
    gtk_text_buffer_get_end_iter(buffer, last)
    return gtk_text_buffer_get_text(buffer, first, last, 1)
}

let IDE_App:open_path = fn (state:IDE_App:State*, path:u8*) -> void {
    if !state || !state.host || !path { return }
    let selected = IDE:copy(path)
    if !selected { IDE_App:set_status(state, "cannot copy file path"); return }
    let data = IDE:read_file(selected)
    if !data { free(selected); IDE_App:set_status(state, "cannot read file"); return }
    defer free(data)

    if state.host.selected { free(state.host.selected) }
    state.host.selected = selected
    let buffer = gtk_text_view_get_buffer(state.editor)
    gtk_text_buffer_set_text(buffer, data, -1)
    let relative = IDE:relative(state.host.root, selected)
    if relative { gtk_label_set_text(state.file_label, relative); free(relative) }
}

let IDE_App:on_save = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host || !state.host.selected { return }
    let text = IDE_App:editor_text(state)
    if !text { IDE_App:set_status(state, "cannot read editor buffer"); return }
    let ok = IDE:write_file(state.host.selected, text)
    g_free(text)
    if ok { IDE_App:set_status(state, "saved | hot reload pending") }
    else { IDE_App:set_status(state, "save failed") }
}
