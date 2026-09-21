let IDE_App:update_status = fn (state:IDE_App:State*) -> void {
    if !state || !state.host || !state.host.runner || !state.status { return }
    let status = state.host.runner.last_status
    let generation = state.host.runner.generation
    let revision = state.host.runner.revision
    let error = state.host.runner.last_error

    let text = LanguageKit:Text:new()
    if !text { return }
    if status == 0 { text.append("ready") } else { text.append("build error") }
    text.append("  |  generation ")
    IDE:append_u64(text, generation)
    text.append("  |  rebuild ")
    IDE:append_u64(text, revision)
    if status != 0 && error && error[0] != 0 {
        text.append("  |  ")
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
    state.root_box = Gui:column(0)
    Gui:class_add(state.root_box, "app-root")
    state.file_box = cast(u8*, 0)
    state.editor = cast(u8*, 0)
    state.file_label = cast(u8*, 0)
    state.status = cast(u8*, 0)
    state.notebook = cast(u8*, 0)
    state.files = cast(IDE_App:FileItem*, 0)
    state.terminal_views = cast(IDE_App:TerminalView*, 0)
    host.user_data = cast(u8*, state)
    host.content = state.root_box

    Gui:window_title(host.window, "RecurLoop IDE")
    Gui:window_size(host.window, 1360, 860)

    let main_pane = Gui:split_horizontal()
    let right_pane = Gui:split_vertical()
    Gui:add(host.window, state.root_box)
    Gui:append(state.root_box, main_pane, 1, 0)

    // Explorer uses the toolkit's native tree model/view. GTK handles row
    // virtualization and folder expansion; RecurLoop only supplies filesystem
    // data and reacts when a file row is selected.
    let explorer = Gui:column(0)
    Gui:class_add(explorer, "explorer-pane")

    let explorer_header = Gui:row(0)
    Gui:class_add(explorer_header, "explorer-header")
    let explorer_title = Gui:label("EXPLORER")
    Gui:label_align(explorer_title, cast(f32, 0.0))
    Gui:class_add(explorer_title, "explorer-title")
    Gui:append(explorer_header, explorer_title, 1, 0)

    let new_file = Gui:icon_button("document-new-symbolic", "New File")
    let new_folder = Gui:icon_button("folder-new-symbolic", "New Folder")
    let rename_item = Gui:icon_button("edit-rename-symbolic", "Rename")
    let delete_item = Gui:icon_button("user-trash-symbolic", "Delete")
    let refresh_tree = Gui:icon_button("view-refresh-symbolic", "Refresh Explorer")
    Gui:on_click(new_file, IDE_App:on_explorer_new_file, cast(u8*, state))
    Gui:on_click(new_folder, IDE_App:on_explorer_new_folder, cast(u8*, state))
    Gui:on_click(rename_item, IDE_App:on_explorer_rename, cast(u8*, state))
    Gui:on_click(delete_item, IDE_App:on_explorer_delete, cast(u8*, state))
    Gui:on_click(refresh_tree, IDE_App:on_explorer_refresh, cast(u8*, state))
    Gui:append_end(explorer_header, refresh_tree, 0, 0)
    Gui:append_end(explorer_header, delete_item, 0, 0)
    Gui:append_end(explorer_header, rename_item, 0, 0)
    Gui:append_end(explorer_header, new_folder, 0, 0)
    Gui:append_end(explorer_header, new_file, 0, 0)
    Gui:append(explorer, explorer_header, 0, 0)

    let project_name = IDE:leaf_name(host.root)
    var project_text = host.root
    if project_name { project_text = project_name }
    let project = Gui:label(project_text)
    Gui:label_align(project, cast(f32, 0.0))
    Gui:class_add(project, "explorer-root")
    Gui:tooltip(project, host.root)
    Gui:append(explorer, project, 0, 0)
    if project_name { free(project_name) }

    state.file_box = Gui:tree()
    Gui:on_tree_select(state.file_box, IDE_App:on_tree_selected, cast(u8*, state))
    let file_scroll = Gui:scroll(state.file_box)
    Gui:append(explorer, file_scroll, 1, 0)
    Gui:split_first(main_pane, explorer, 0)
    Gui:split_position(main_pane, 300)

    // Editor.
    let editor_box = Gui:column(0)
    Gui:class_add(editor_box, "editor-pane")
    let editor_toolbar = Gui:row(6)
    Gui:class_add(editor_toolbar, "ide-toolbar")
    state.file_label = Gui:label("No file selected")
    Gui:label_align(state.file_label, cast(f32, 0.0))
    Gui:class_add(state.file_label, "path-label")
    let save = Gui:icon_button("document-save-symbolic", "Save (Ctrl+S)")
    Gui:on_click(save, IDE_App:on_save, cast(u8*, state))
    Gui:shortcut_click(host.window, save, Gui:Key:S(), Gui:Modifier:Control())
    Gui:append(editor_toolbar, state.file_label, 1, 6)
    Gui:append_end(editor_toolbar, save, 0, 4)
    state.editor = Gui:editor()
    let editor_scroll = Gui:scroll(state.editor)
    Gui:append(editor_box, editor_toolbar, 0, 0)
    Gui:append(editor_box, editor_scroll, 1, 0)

    // Terminal panel follows the VS Code shape: compact panel header/tabs, a
    // single continuous monospace transcript and an inline `>` command row.
    let terminal_box = Gui:column(0)
    Gui:class_add(terminal_box, "terminal-panel")
    let terminal_toolbar = Gui:row(6)
    Gui:class_add(terminal_toolbar, "ide-toolbar")
    let terminal_label = Gui:label("TERMINAL")
    Gui:label_align(terminal_label, cast(f32, 0.0))
    let add_terminal = Gui:icon_button("list-add-symbolic", "New Terminal")
    Gui:on_click(add_terminal, IDE_App:on_add_terminal, cast(u8*, state))
    Gui:append(terminal_toolbar, terminal_label, 1, 6)
    Gui:append_end(terminal_toolbar, add_terminal, 0, 4)
    state.notebook = Gui:tabs()
    Gui:append(terminal_box, terminal_toolbar, 0, 0)
    Gui:append(terminal_box, state.notebook, 1, 0)

    Gui:split_first(right_pane, editor_box, 1)
    Gui:split_second(right_pane, terminal_box, 1)
    Gui:split_position(right_pane, 555)
    Gui:split_second(main_pane, right_pane, 1)

    state.status = Gui:label("starting")
    Gui:label_align(state.status, cast(f32, 0.0))
    Gui:class_add(state.status, "ide-status")
    Gui:append_end(state.root_box, state.status, 0, 0)

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
