let IDE:App:set_status = fn (state:IDE:App:State*, text:u8*) -> void {
    if state && state.status { Gui:label_text(state.status, text) }
}

let IDE:App:editor_text = fn (state:IDE:App:State*) -> u8* {
    if !state || !state.editor { return cast(u8*, 0) }
    return Gui:text_get(state.editor)
}

let IDE:App:open_path = fn (state:IDE:App:State*, path:u8*) -> void {
    if !state || !state.host || !path { return }
    let selected = IDE:copy(path)
    if !selected { IDE:App:set_status(state, "cannot copy file path"); return }
    let data = IDE:read_file(selected)
    if !data { free(selected); IDE:App:set_status(state, "cannot read file"); return }
    defer free(data)

    if state.host.selected { free(state.host.selected) }
    state.host.selected = selected
    Gui:text_set(state.editor, data)
    let relative = IDE:relative(state.host.root, selected)
    if relative { Gui:label_text(state.file_label, relative); free(relative) }
}

let IDE:App:on_save = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host || !state.host.selected { return }
    let text = IDE:App:editor_text(state)
    if !text { IDE:App:set_status(state, "cannot read editor buffer"); return }
    let ok = IDE:write_file(state.host.selected, text)
    Gui:text_free(text)
    if ok {
        if state.host.reload_mode == IDE:Reload:Hot() { IDE:App:set_status(state, "saved | hot reload pending") }
        else if state.host.reload_mode == IDE:Reload:Manual() { IDE:App:set_status(state, "saved | reload available") }
        else { IDE:App:set_status(state, "saved") }
    } else { IDE:App:set_status(state, "save failed") }
}
