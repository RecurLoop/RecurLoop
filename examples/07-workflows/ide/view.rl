let IDE_App:update_status = fn (state:IDE_App:State*) -> void {
    if !state || !state.host || !state.host.runner || !state.status { return }
    let status = state.host.runner.last_status
    let generation = state.host.runner.generation
    let revision = state.host.runner.revision
    let error = state.host.runner.last_error

    let text = LanguageKit:Text:new()
    if !text { return }
    if status == 0 { text.append("ready") } else { text.append("build error") }
    text.append(" | generation ")
    IDE:append_u64(text, generation)
    text.append(" | rebuild ")
    IDE:append_u64(text, revision)
    if status != 0 && error && error[0] != 0 {
        text.append(" | ")
        var k = 0
        while error[k] != 0 && error[k] != 10 && k < 180 {
            text.append_byte(error[k])
            k += 1
        }
    }
    let ready = text.take()
    text.destroy()
    if ready { Gui:label_text(state.status, ready); free(ready) }
}

let IDE_App:mount = fn (host:IDE:Host*) -> void {
    if !host || !host.window { return }
    let state = cast(IDE_App:State*, malloc(72))
    if !state { return }
    state.host = host
    state.root_box = Gui:column(4)
    state.file_box = cast(u8*, 0)
    state.editor = cast(u8*, 0)
    state.file_label = cast(u8*, 0)
    state.status = cast(u8*, 0)
    state.notebook = cast(u8*, 0)
    state.files = cast(IDE_App:FileItem*, 0)
    state.terminal_views = cast(IDE_App:TerminalView*, 0)
    host.user_data = cast(u8*, state)
    host.content = state.root_box

    Gui:window_title(host.window, "RecurLoop IDE - source hot reload")
    Gui:window_size(host.window, 1280, 820)

    let main_pane = Gui:split_horizontal()
    let right_pane = Gui:split_vertical()
    Gui:add(host.window, state.root_box)
    Gui:append(state.root_box, main_pane, 1, 0)

    // Explorer. Change this code and Save: the whole view is remounted from the
    // newly published generation without restarting the process.
    let explorer = Gui:column(4)
    let explorer_header = Gui:label("FILES - hot reload")
    Gui:append(explorer, explorer_header, 0, 4)
    state.file_box = Gui:column(1)
    let file_scroll = Gui:scroll(state.file_box)
    Gui:append(explorer, file_scroll, 1, 0)
    Gui:split_first(main_pane, explorer, 0)
    Gui:split_position(main_pane, 260)

    // Editor.
    let editor_box = Gui:column(4)
    let editor_toolbar = Gui:row(6)
    state.file_label = Gui:label("No file selected")
    let save = Gui:button("Save")
    Gui:on_click(save, IDE_App:on_save, cast(u8*, state))
    Gui:shortcut_click(host.window, save, Gui:Key:S(), Gui:Modifier:Control())
    Gui:append(editor_toolbar, state.file_label, 1, 4)
    Gui:append_end(editor_toolbar, save, 0, 4)
    state.editor = Gui:editor()
    let editor_scroll = Gui:scroll(state.editor)
    Gui:append(editor_box, editor_toolbar, 0, 0)
    Gui:append(editor_box, editor_scroll, 1, 0)

    // Terminals. Existing runtime sessions retain their original generation;
    // only a newly created terminal connects to the current runner generation.
    let terminal_box = Gui:column(4)
    let terminal_toolbar = Gui:row(6)
    let terminal_label = Gui:label("TERMINALS")
    let add_terminal = Gui:button("New terminal")
    Gui:on_click(add_terminal, IDE_App:on_add_terminal, cast(u8*, state))
    Gui:append(terminal_toolbar, terminal_label, 1, 4)
    Gui:append_end(terminal_toolbar, add_terminal, 0, 4)
    state.notebook = Gui:tabs()
    Gui:append(terminal_box, terminal_toolbar, 0, 0)
    Gui:append(terminal_box, state.notebook, 1, 0)

    Gui:split_first(right_pane, editor_box, 1)
    Gui:split_second(right_pane, terminal_box, 1)
    Gui:split_position(right_pane, 500)
    Gui:split_second(main_pane, right_pane, 1)

    state.status = Gui:label("starting")
    Gui:append_end(state.root_box, state.status, 0, 4)

    IDE_App:scan_tree(state, host.root)
    if host.selected { IDE_App:open_path(state, host.selected) }
    else { IDE_App:open_path(state, host.entry) }
    IDE_App:mount_terminals(state)
    IDE_App:update_status(state)
}

let IDE_App:unmount = fn (host:IDE:Host*) -> void {
    let state = IDE_App:state(host)
    if !state { return }
    IDE_App:free_files(state)
    IDE_App:free_terminal_views(state)
    host.user_data = cast(u8*, 0)
    free(cast(u8*, state))
}

let IDE_App:reload_failed = fn (host:IDE:Host*) -> void {
    let state = IDE_App:state(host)
    if state { IDE_App:update_status(state) }
}
