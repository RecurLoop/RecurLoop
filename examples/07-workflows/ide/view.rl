let IDE_App:update_status = fn (state:IDE_App:State*) -> void {
    if !state || !state.host || !state.host.runner || !state.status { return }
    let status = state.host.runner.last_status
    let generation = state.host.runner.generation
    let revision = state.host.runner.revision
    let error = state.host.runner.last_error

    let text = LanguageKit:Text:new()
    if !text {
        return
    }
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
    if ready { gtk_label_set_text(state.status, ready); free(ready) }
}

let IDE_App:mount = fn (host:IDE:Host*) -> void {
    if !host || !host.window { return }
    let state = cast(IDE_App:State*, malloc(72))
    if !state { return }
    state.host = host
    state.root_box = gtk_box_new(1, 4)
    state.file_box = cast(u8*, 0)
    state.editor = cast(u8*, 0)
    state.file_label = cast(u8*, 0)
    state.status = cast(u8*, 0)
    state.notebook = cast(u8*, 0)
    state.files = cast(IDE_App:FileItem*, 0)
    state.terminal_views = cast(IDE_App:TerminalView*, 0)
    host.user_data = cast(u8*, state)
    host.content = state.root_box

    gtk_window_set_title(host.window, "RecurLoop IDE - source hot reload")
    gtk_window_set_default_size(host.window, 1280, 820)

    let main_pane = gtk_paned_new(0)
    let right_pane = gtk_paned_new(1)
    gtk_container_add(host.window, state.root_box)
    gtk_box_pack_start(state.root_box, main_pane, 1, 1, 0)

    // Explorer. Change this code and Save: the whole view is remounted from the
    // newly published generation without restarting the process.
    let explorer = gtk_box_new(1, 4)
    let explorer_header = gtk_label_new("FILES - hot reload")
    gtk_box_pack_start(explorer, explorer_header, 0, 1, 4)
    state.file_box = gtk_box_new(1, 1)
    let file_scroll = gtk_scrolled_window_new(cast(u8*, 0), cast(u8*, 0))
    gtk_scrolled_window_set_policy(file_scroll, 1, 1)
    gtk_container_add(file_scroll, state.file_box)
    gtk_box_pack_start(explorer, file_scroll, 1, 1, 0)
    gtk_paned_pack1(main_pane, explorer, 0, 0)
    gtk_paned_set_position(main_pane, 260)

    // Editor.
    let editor_box = gtk_box_new(1, 4)
    let editor_toolbar = gtk_box_new(0, 6)
    state.file_label = gtk_label_new("No file selected")
    let save = gtk_button_new_with_label("Save")
    g_signal_connect_data(save, "clicked", IDE_App:on_save, cast(u8*, state), cast(u8*, 0), 0)
    let accelerators = gtk_accel_group_new()
    if accelerators {
        gtk_window_add_accel_group(host.window, accelerators)
        gtk_widget_add_accelerator(save, "clicked", accelerators, 115, 4, 1)
    }
    gtk_box_pack_start(editor_toolbar, state.file_label, 1, 1, 4)
    gtk_box_pack_end(editor_toolbar, save, 0, 0, 4)
    state.editor = gtk_text_view_new()
    gtk_text_view_set_monospace(state.editor, 1)
    let editor_scroll = gtk_scrolled_window_new(cast(u8*, 0), cast(u8*, 0))
    gtk_scrolled_window_set_policy(editor_scroll, 1, 1)
    gtk_container_add(editor_scroll, state.editor)
    gtk_box_pack_start(editor_box, editor_toolbar, 0, 1, 0)
    gtk_box_pack_start(editor_box, editor_scroll, 1, 1, 0)

    // Terminals. Existing runtime sessions retain their original generation;
    // only a newly created terminal connects to the current runner generation.
    let terminal_box = gtk_box_new(1, 4)
    let terminal_toolbar = gtk_box_new(0, 6)
    let terminal_label = gtk_label_new("TERMINALS")
    let add_terminal = gtk_button_new_with_label("New terminal")
    g_signal_connect_data(add_terminal, "clicked", IDE_App:on_add_terminal, cast(u8*, state), cast(u8*, 0), 0)
    gtk_box_pack_start(terminal_toolbar, terminal_label, 1, 1, 4)
    gtk_box_pack_end(terminal_toolbar, add_terminal, 0, 0, 4)
    state.notebook = gtk_notebook_new()
    gtk_notebook_set_scrollable(state.notebook, 1)
    gtk_box_pack_start(terminal_box, terminal_toolbar, 0, 1, 0)
    gtk_box_pack_start(terminal_box, state.notebook, 1, 1, 0)

    gtk_paned_pack1(right_pane, editor_box, 1, 0)
    gtk_paned_pack2(right_pane, terminal_box, 1, 0)
    gtk_paned_set_position(right_pane, 500)
    gtk_paned_pack2(main_pane, right_pane, 1, 0)

    state.status = gtk_label_new("starting")
    gtk_box_pack_end(state.root_box, state.status, 0, 1, 4)

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
