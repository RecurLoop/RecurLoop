let IDE_App:set_status = fn (state:IDE_App:State*, text:u8*) -> void {
    if state && state.status { Gui:label_text(state.status, text) }
}

let IDE_App:editor_text = fn (state:IDE_App:State*) -> u8* {
    if !state || !state.editor { return cast(u8*, 0) }
    return Gui:text_get(state.editor)
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
    Gui:text_set(state.editor, data)
    let relative = IDE:relative(state.host.root, selected)
    if relative { Gui:label_text(state.file_label, relative); free(relative) }
}

let IDE_App:on_save = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host || !state.host.selected { return }
    let text = IDE_App:editor_text(state)
    if !text { IDE_App:set_status(state, "cannot read editor buffer"); return }
    let ok = IDE:write_file(state.host.selected, text)
    Gui:text_free(text)
    if ok {
        if state.host.reload_mode == IDE:Reload:Hot() { IDE_App:set_status(state, "saved | hot reload pending") }
        else if state.host.reload_mode == IDE:Reload:Manual() { IDE_App:set_status(state, "saved | reload available") }
        else { IDE_App:set_status(state, "saved") }
    } else { IDE_App:set_status(state, "save failed") }
}
