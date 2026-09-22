// Default compact IDE layout.  These builders are intentionally normal `let`
// phrases: a launcher can replace any one of them before IDE:Config:open().
let IDE_App:update_status = fn (state:IDE_App:State*) -> void {
    if !state || !state.host || !state.host.runner || !state.status { return }
    let status = state.host.runner.last_status
    let generation = state.host.runner.generation
    let revision = state.host.runner.revision
    let error = state.host.runner.last_error

    let text = LanguageKit:Text:new()
    if !text { return }
    if state.host.job && state.host.job.kind == 1 { text.append("starting runtime") }
    else if state.host.job && state.host.job.kind == 2 { text.append("reloading") }
    else if status == 0 && generation == 0 && !state.host.terminals { text.append("starting runtime") }
    else if status == 0 { text.append("ready") }
    else { text.append("build error") }
    text.append("  |  generation ")
    IDE:append_u64(text, generation)
    text.append("  |  rebuild ")
    IDE:append_u64(text, revision)
    if state.host.reload_mode == IDE:Reload:Hot() { text.append("  |  hot reload") }
    else if state.host.reload_mode == IDE:Reload:Manual() {
        if state.host.reload_pending { text.append("  |  changes pending") }
        else { text.append("  |  manual reload") }
    } else { text.append("  |  reload off") }
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

let IDE_App:on_manual_reload = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host { return }
    IDE_App:set_status(state, "reloading...")
    IDE:manual_reload(state.host)
}

let IDE_App:create_explorer = fn (state:IDE_App:State*) -> u8* {
    if !state || !state.host { return cast(u8*, 0) }
    let explorer = Gui:column(0)
    Gui:class_add(explorer, "explorer-pane")

    let header = Gui:row(0)
    Gui:class_add(header, "explorer-header")
    let title = Gui:label("EXPLORER")
    Gui:label_align(title, cast(f32, 0.0))
    Gui:class_add(title, "explorer-title")
    Gui:append(header, title, 1, 0)

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
    Gui:append_end(header, refresh_tree, 0, 0)
    Gui:append_end(header, delete_item, 0, 0)
    Gui:append_end(header, rename_item, 0, 0)
    Gui:append_end(header, new_folder, 0, 0)
    Gui:append_end(header, new_file, 0, 0)
    Gui:append(explorer, header, 0, 0)

    let project_name = IDE:leaf_name(state.host.root)
    var project_text = state.host.root
    if project_name { project_text = project_name }
    let project = Gui:label(project_text)
    Gui:label_align(project, cast(f32, 0.0))
    Gui:class_add(project, "explorer-root")
    Gui:tooltip(project, state.host.root)
    Gui:append(explorer, project, 0, 0)
    if project_name { free(project_name) }

    state.file_box = Gui:tree()
    Gui:on_tree_select(state.file_box, IDE_App:on_tree_selected, cast(u8*, state))
    Gui:append(explorer, Gui:scroll(state.file_box), 1, 0)
    return explorer
}

let IDE_App:create_editor = fn (state:IDE_App:State*) -> u8* {
    if !state || !state.host { return cast(u8*, 0) }
    let box = Gui:column(0)
    Gui:class_add(box, "editor-pane")
    let toolbar = Gui:row(6)
    Gui:class_add(toolbar, "ide-toolbar")
    state.file_label = Gui:label("No file selected")
    Gui:label_align(state.file_label, cast(f32, 0.0))
    Gui:class_add(state.file_label, "path-label")
    Gui:append(toolbar, state.file_label, 1, 6)

    if state.host.reload_mode == IDE:Reload:Manual() {
        let reload = Gui:icon_button("view-refresh-symbolic", "Reload IDE")
        Gui:on_click(reload, IDE_App:on_manual_reload, cast(u8*, state))
        Gui:append_end(toolbar, reload, 0, 2)
    }
    let save = Gui:icon_button("document-save-symbolic", "Save (Ctrl+S)")
    Gui:on_click(save, IDE_App:on_save, cast(u8*, state))
    Gui:shortcut_click(state.host.window, save, Gui:Key:S(), Gui:Modifier:Control())
    Gui:append_end(toolbar, save, 0, 4)

    state.editor = Gui:editor()
    Gui:append(box, toolbar, 0, 0)
    Gui:append(box, Gui:scroll(state.editor), 1, 0)
    return box
}

let IDE_App:create_terminal_panel = fn (state:IDE_App:State*) -> u8* {
    let box = Gui:column(0)
    Gui:class_add(box, "terminal-panel")
    let toolbar = Gui:row(6)
    Gui:class_add(toolbar, "ide-toolbar")
    let label = Gui:label("TERMINAL")
    Gui:label_align(label, cast(f32, 0.0))
    let add_terminal = Gui:icon_button("list-add-symbolic", "New Terminal")
    Gui:on_click(add_terminal, IDE_App:on_add_terminal, cast(u8*, state))
    Gui:append(toolbar, label, 1, 6)
    Gui:append_end(toolbar, add_terminal, 0, 4)
    state.notebook = Gui:tabs()
    Gui:append(box, toolbar, 0, 0)
    Gui:append(box, state.notebook, 1, 0)
    return box
}

let IDE_App:create_status = fn (state:IDE_App:State*) -> u8* {
    state.status = Gui:label("starting")
    Gui:label_align(state.status, cast(f32, 0.0))
    Gui:class_add(state.status, "ide-status")
    return state.status
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
    Gui:add(host.window, state.root_box)

    let main = Gui:split_horizontal()
    let right = Gui:split_vertical()
    let explorer = IDE_App:create_explorer(state)
    let editor = IDE_App:create_editor(state)
    let terminals = IDE_App:create_terminal_panel(state)
    Gui:split_first(main, explorer, 0)
    Gui:split_position(main, 300)
    Gui:split_first(right, editor, 1)
    Gui:split_second(right, terminals, 1)
    Gui:split_position(right, 555)
    Gui:split_second(main, right, 1)
    Gui:append(state.root_box, main, 1, 0)
    Gui:append_end(state.root_box, IDE_App:create_status(state), 0, 0)

    IDE_App:scan_tree(state, host.root)
    if host.selected { IDE_App:open_path(state, host.selected) }
    else if host.entry && IDE:file_exists(host.entry) { IDE_App:open_path(state, host.entry) }
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

let IDE_App:runtime_ready = fn (host:IDE:Host*) -> void {
    let state = IDE_App:state(host)
    if !state { return }
    if !host.terminals {
        let model = IDE:terminal_new(host)
        if model { IDE_App:add_terminal_view(state, model); Gui:show(state.notebook) }
    } else if !state.terminal_views {
        IDE_App:mount_terminals(state)
        Gui:show(state.notebook)
    }
    IDE_App:update_status(state)
}
