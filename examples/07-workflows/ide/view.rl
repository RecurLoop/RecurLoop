// Project-local compact IDE layout. Runtime/window/cache/terminal models live
// in ide.rli; every widget and callback in this file is hot-reloadable source.
let IDE:App:update_status = fn (state:IDE:App:State*) -> void {
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
    if IDE:view_reload_mode(state.host) == IDE:Reload:Hot() { text.append("  |  hot reload") }
    else if IDE:view_reload_mode(state.host) == IDE:Reload:Manual() {
        if state.host.reload_pending { text.append("  |  changes pending") }
        else { text.append("  |  manual reload") }
    } else { text.append("  |  reload off") }
    if state.host.last_reload_ms > 0 {
        text.append("  |  reload ")
        IDE:append_u64(text, cast(u64, state.host.last_reload_ms))
        text.append(" ms")
    }
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

let IDE:App:on_manual_reload = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    IDE:App:set_status(state, "reloading...")
    IDE:manual_reload(state.host)
}

let IDE:App:create_explorer = fn (state:IDE:App:State*) -> u8* {
    if !state || !state.host { return cast(u8*, 0) }
    let explorer = Gui:column(0)
    Gui:class_add(explorer, "explorer-pane")

    let header = Gui:row(0)
    Gui:class_add(header, "explorer-header")
    Gui:align_top(header)
    Gui:expand_x(header, 1)
    let title = Gui:label("EXPLORER")
    Gui:label_align(title, cast(f32, 0.0))
    Gui:class_add(title, "explorer-title")
    Gui:append(header, title, 1, 0)

    let history = Gui:icon_button("view-list-symbolic", "Editor History")
    let search = Gui:icon_button("edit-find-symbolic", "Search Workspace (Ctrl+Shift+F)")
    let new_file = Gui:icon_button("document-new-symbolic", "New File")
    let new_folder = Gui:icon_button("folder-new-symbolic", "New Folder")
    let rename_item = Gui:icon_button("edit-rename-symbolic", "Rename")
    let delete_item = Gui:icon_button("user-trash-symbolic", "Delete")
    let refresh_tree = Gui:icon_button("view-refresh-symbolic", "Refresh Explorer")
    Gui:on_click(history, IDE:App:on_show_history, cast(u8*, state))
    Gui:on_click(search, IDE:App:on_show_search, cast(u8*, state))
    Gui:on_click(new_file, IDE:App:on_explorer_new_file, cast(u8*, state))
    Gui:on_click(new_folder, IDE:App:on_explorer_new_folder, cast(u8*, state))
    Gui:on_click(rename_item, IDE:App:on_explorer_rename, cast(u8*, state))
    Gui:on_click(delete_item, IDE:App:on_explorer_delete, cast(u8*, state))
    Gui:on_click(refresh_tree, IDE:App:on_explorer_refresh, cast(u8*, state))
    Gui:append_end(header, search, 0, 2)
    Gui:append_end(header, history, 0, 0)
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
    Gui:on_tree_select(state.file_box, IDE:App:on_tree_selected, cast(u8*, state))
    Gui:append(explorer, Gui:scroll(state.file_box), 1, 0)
    return explorer
}

let IDE:App:create_editor = fn (state:IDE:App:State*) -> u8* {
    if !state || !state.host { return cast(u8*, 0) }
    let box = Gui:column(0)
    Gui:class_add(box, "editor-pane")
    let toolbar = Gui:row(6)
    Gui:class_add(toolbar, "ide-toolbar")
    Gui:align_top(toolbar)
    Gui:expand_x(toolbar, 1)
    state.file_label = Gui:label("No file selected")
    Gui:label_align(state.file_label, cast(f32, 0.0))
    Gui:class_add(state.file_label, "path-label")
    Gui:append(toolbar, state.file_label, 1, 6)

    if IDE:view_reload_mode(state.host) == IDE:Reload:Manual() {
        let reload = Gui:icon_button("view-refresh-symbolic", "Reload IDE")
        Gui:on_click(reload, IDE:App:on_manual_reload, cast(u8*, state))
        Gui:append_end(toolbar, reload, 0, 2)
    }

    let find = Gui:icon_button("edit-find-symbolic", "Find (Ctrl+F)")
    let find_all = Gui:icon_button("edit-find-symbolic", "Search Workspace (Ctrl+Shift+F)")
    let undo = Gui:icon_button("edit-undo-symbolic", "Undo (Ctrl+Z)")
    let redo = Gui:icon_button("edit-redo-symbolic", "Redo (Ctrl+Y / Ctrl+Shift+Z)")
    let save = Gui:icon_button("document-save-symbolic", "Save (Ctrl+S)")
    Gui:on_click(find, IDE:App:on_show_find, cast(u8*, state))
    Gui:on_click(find_all, IDE:App:on_show_search, cast(u8*, state))
    Gui:on_click(undo, IDE:App:on_undo, cast(u8*, state))
    Gui:on_click(redo, IDE:App:on_redo, cast(u8*, state))
    Gui:on_click(save, IDE:App:on_save, cast(u8*, state))
    Gui:shortcut_click(state.host.window, find, 102, Gui:Modifier:Control())
    Gui:shortcut_click(state.host.window, find_all, 102, Gui:Modifier:Control() + 1)
    Gui:shortcut_click(state.host.window, undo, 122, Gui:Modifier:Control())
    Gui:shortcut_click(state.host.window, redo, 121, Gui:Modifier:Control())
    Gui:shortcut_click(state.host.window, redo, 122, Gui:Modifier:Control() + 1)
    Gui:shortcut_click(state.host.window, save, Gui:Key:S(), Gui:Modifier:Control())
    Gui:append_end(toolbar, save, 0, 4)
    Gui:append_end(toolbar, redo, 0, 0)
    Gui:append_end(toolbar, undo, 0, 0)
    Gui:append_end(toolbar, find_all, 0, 0)
    Gui:append_end(toolbar, find, 0, 2)

    state.editor = Gui:editor()
    Gui:on_text_changed(state.editor, IDE:App:on_editor_changed, cast(u8*, state))
    Gui:on_text_tooltip(state.editor, IDE:App:on_editor_tooltip, cast(u8*, state))
    Gui:on_text_popup(state.editor, IDE:App:on_editor_context_menu, cast(u8*, state))
    Gui:on_key_press(state.editor, IDE:App:on_editor_intelligence_key, cast(u8*, state))
    state.semantic_diagnostic = Gui:label("")
    Gui:label_align(state.semantic_diagnostic, cast(f32, 0.0))
    Gui:class_add(state.semantic_diagnostic, "semantic-diagnostic")
    Gui:align_bottom(state.semantic_diagnostic)
    Gui:expand_x(state.semantic_diagnostic, 1)
    Gui:append(box, toolbar, 0, 0)
    Gui:append(box, IDE:App:create_application_toolbar(state), 0, 0)
    Gui:append(box, IDE:App:create_find_bar(state), 0, 0)

    state.editor_scroll = Gui:scroll(state.editor)
    Gui:expand_x(state.editor_scroll, 1)
    Gui:expand_y(state.editor_scroll, 1)
    state.line_gutter = Gui:line_gutter()
    state.line_gutter_breakpoint_style = Gui:text_style(state.line_gutter, "breakpoint", "#a94848")
    state.line_gutter_active_style = Gui:text_style(state.line_gutter, "breakpoint-active", "#ff2d20")
    Gui:on_button_press(state.line_gutter, IDE:App:on_line_gutter_press, cast(u8*, state))
    let editor_adjustment = Gui:scroll_vadjustment(state.editor_scroll)
    state.line_gutter_scroll = Gui:scroll_with_vadjustment(state.line_gutter, editor_adjustment, 2, 2)
    let editor_surface = Gui:row(0)
    Gui:append(editor_surface, state.line_gutter_scroll, 0, 0)
    Gui:append(editor_surface, state.editor_scroll, 1, 0)
    Gui:append(box, editor_surface, 1, 0)
    IDE:App:update_line_gutter(state)
    Gui:append(box, state.semantic_diagnostic, 0, 0)
    return box
}

let IDE:App:create_terminal_panel = fn (state:IDE:App:State*) -> u8* {
    let box = Gui:column(0)
    Gui:class_add(box, "terminal-panel")

    let toolbar = Gui:row(6)
    Gui:class_add(toolbar, "ide-toolbar")
    Gui:align_top(toolbar)
    Gui:expand_x(toolbar, 1)

    let label = Gui:label("TERMINAL")
    Gui:label_align(label, cast(f32, 0.0))

    //let remove_terminal = Gui:icon_button("list-remove-symbolic", "Remove Terminal")
    let add_terminal = Gui:icon_button("list-add-symbolic", "New Terminal")

    Gui:on_click(add_terminal, IDE:App:on_add_terminal, cast(u8*, state))

    Gui:append(toolbar, label, 1, 6)
    //Gui:append_end(toolbar, remove_terminal, 0, 0)
    Gui:append_end(toolbar, add_terminal, 0, 4)

    state.notebook = Gui:tabs()
    Gui:expand_x(state.notebook, 1)
    Gui:expand_y(state.notebook, 1)
    IDE:App:create_application_console(state)
    Gui:append(box, toolbar, 0, 0)
    Gui:append(box, state.notebook, 1, 0)

    return box
}

let IDE:App:create_status = fn (state:IDE:App:State*) -> u8* {
    state.status = Gui:label("starting")
    Gui:label_align(state.status, cast(f32, 0.0))
    Gui:class_add(state.status, "ide-status")
    Gui:align_bottom(state.status)
    Gui:expand_x(state.status, 1)
    return state.status
}

let IDE:App:mount = fn (host:IDE:Host*) -> void {
    if !host || !host.window { return }
    let state = alloc(IDE:App:State)
    if !state { return }
    state.host = host
    state.root_box = Gui:column(0)
    if !state.root_box { free(cast(u8*, state)); return }
    Gui:class_add(state.root_box, "app-root")
    state.file_box = cast(u8*, 0)
    state.main_split = cast(u8*, 0)
    state.right_split = cast(u8*, 0)
    state.editor = cast(u8*, 0)
    state.editor_scroll = cast(u8*, 0)
    state.line_gutter = cast(u8*, 0)
    state.line_gutter_scroll = cast(u8*, 0)
    state.line_gutter_breakpoint_style = cast(u8*, 0)
    state.line_gutter_active_style = cast(u8*, 0)
    state.file_label = cast(u8*, 0)
    state.application_output = cast(u8*, 0)
    state.application_status = cast(u8*, 0)
    state.application_mode = cast(u8*, 0)
    state.application_debug_input = cast(u8*, 0)
    state.application_page = -1
    state.application_render_revision = 0
    state.application_stop_revision_seen = 0
    state.status = cast(u8*, 0)
    state.semantic_diagnostic = cast(u8*, 0)
    state.notebook = cast(u8*, 0)
    state.files = cast(IDE:App:FileItem*, 0)
    state.terminal_views = cast(IDE:App:TerminalView*, 0)
    state.semantic_spans = cast(IDE:App:SemanticSpan*, 0)
    state.semantic_hovers = cast(IDE:App:SemanticHover*, 0)
    state.semantic_hover_tail = cast(IDE:App:SemanticHover*, 0)
    state.semantic_styles = cast(IDE:App:SemanticStyle*, 0)
    state.semantic_idle_source = 0
    state.restore_idle_source = 0
    state.restore_snapshot = IDE:App:view_state_load(state)
    state.history = cast(IDE:App:History*, 0)
    state.history_tree = cast(u8*, 0)
    state.history_status = cast(u8*, 0)
    state.history_pane = cast(u8*, 0)
    state.explorer_pane = cast(u8*, 0)
    state.sidebar_stack = cast(u8*, 0)
    state.history_visible = 0
    state.history_needs_refresh = 1
    state.history_replaying = 0
    state.history_refreshing = 0
    state.history_refresh_idle_source = 0
    state.find_bar = cast(u8*, 0)
    state.find_input = cast(u8*, 0)
    state.find_replace_input = cast(u8*, 0)
    state.find_status = cast(u8*, 0)
    state.find_case_button = cast(u8*, 0)
    state.find_delimiter_button = cast(u8*, 0)
    state.find_whitespace_button = cast(u8*, 0)
    state.find_regex_button = cast(u8*, 0)
    state.find_query = cast(u8*, 0)
    state.find_case_sensitive = 0
    state.find_boundary = 0
    state.find_regex = 0
    state.find_visible = 0
    state.find_last_start = -1
    state.find_last_finish = -1
    state.search_pane = cast(u8*, 0)
    state.search_tree = cast(u8*, 0)
    state.search_input = cast(u8*, 0)
    state.search_replace_input = cast(u8*, 0)
    state.search_status = cast(u8*, 0)
    state.search_case_button = cast(u8*, 0)
    state.search_delimiter_button = cast(u8*, 0)
    state.search_whitespace_button = cast(u8*, 0)
    state.search_regex_button = cast(u8*, 0)
    state.search_results = cast(IDE:App:SearchResult*, 0)
    state.search_result_tail = cast(IDE:App:SearchResult*, 0)
    state.search_result_count = 0
    state.search_next_id = 1
    state.search_case_sensitive = 0
    state.search_boundary = 0
    state.search_regex = 0
    state.search_visible = 0
    state.intelligence_index = cast(u8*, 0)
    state.intelligence_pane = cast(u8*, 0)
    state.intelligence_tree = cast(u8*, 0)
    state.intelligence_input = cast(u8*, 0)
    state.intelligence_status = cast(u8*, 0)
    state.intelligence_results = cast(IDE:App:IntelligenceResult*, 0)
    state.intelligence_result_tail = cast(IDE:App:IntelligenceResult*, 0)
    state.intelligence_result_count = 0
    state.intelligence_next_id = 1
    state.intelligence_visible = 0

    let main = Gui:split_horizontal()
    let right = Gui:split_vertical()
    state.main_split = main
    state.right_split = right
    state.sidebar_stack = Gui:stack()
    state.explorer_pane = IDE:App:create_explorer(state)
    state.history_pane = IDE:App:create_history_view(state)
    state.search_pane = IDE:App:create_search_view(state)
    state.intelligence_pane = IDE:App:create_intelligence_view(state)
    Gui:stack_add(state.sidebar_stack, state.explorer_pane)
    Gui:stack_add(state.sidebar_stack, state.history_pane)
    Gui:stack_add(state.sidebar_stack, state.search_pane)
    Gui:stack_add(state.sidebar_stack, state.intelligence_pane)
    Gui:stack_select(state.sidebar_stack, state.explorer_pane)
    let editor = IDE:App:create_editor(state)
    let terminals = IDE:App:create_terminal_panel(state)
    Gui:split_first(main, state.sidebar_stack, 0)
    var main_position:i32 = 300
    if state.restore_snapshot && state.restore_snapshot.main_split > 0 { main_position = cast(i32, state.restore_snapshot.main_split) }
    Gui:split_position(main, main_position)
    Gui:split_primary(right, editor)
    Gui:split_auxiliary(right, terminals)
    var right_position:i32 = 555
    if state.restore_snapshot && state.restore_snapshot.right_split > 0 { right_position = cast(i32, state.restore_snapshot.right_split) }
    Gui:split_position(right, right_position)
    Gui:split_second(main, right, 1)
    Gui:append(state.root_box, main, 1, 0)
    Gui:append_end(state.root_box, IDE:App:create_status(state), 0, 0)

    IDE:App:scan_tree(state, host.root)
    if host.selected { IDE:App:open_path(state, host.selected) }
    else if state.restore_snapshot && state.restore_snapshot.selected && IDE:file_exists(state.restore_snapshot.selected) { IDE:App:open_path(state, state.restore_snapshot.selected) }
    else if host.entry && IDE:file_exists(host.entry) { IDE:App:open_path(state, host.entry) }
    IDE:App:mount_terminals(state)
    IDE:App:view_state_restore_controls(state)
    IDE:App:update_status(state)

    // This is the commit contract with ide.rli: all widgets are complete before
    // the root enters the hidden stack slot. The runtime decides when this root
    // becomes visible; project code never replaces the native window child.
    if !IDE:view_attach(host, state.root_box, cast(u8*, state)) {
        IDE:App:search_clear_results(state)
        IDE:App:intelligence_free_results(state)
        Gui:destroy(state.root_box)
        IDE:App:free_files(state)
        IDE:App:free_terminal_views(state)
        IDE:App:free_semantic_spans(state)
        IDE:App:free_semantic_styles(state)
        if state.history_refresh_idle_source != 0 { Gui:source_remove(state.history_refresh_idle_source); state.history_refresh_idle_source = 0 }
        IDE:App:history_close(state)
        if state.find_query { free(state.find_query) }
        IDE:App:view_state_snapshot_free(state.restore_snapshot)
        state.restore_snapshot = cast(IDE:App:ViewSnapshot*, 0)
        free(cast(u8*, state))
        return
    }
    if state.restore_snapshot {
        state.restore_idle_source = Gui:idle(IDE:App:view_state_restore_idle, cast(u8*, state))
    }
}

let IDE:App:unmount = fn (host:IDE:Host*) -> void {
    let state = IDE:App:state(host)
    if !state { return }
    if state.semantic_idle_source != 0 { Gui:source_remove(state.semantic_idle_source); state.semantic_idle_source = 0 }
    if state.restore_idle_source != 0 { Gui:source_remove(state.restore_idle_source); state.restore_idle_source = 0 }
    IDE:App:free_files(state)
    IDE:App:free_terminal_views(state)
    IDE:App:free_semantic_spans(state)
    IDE:App:free_semantic_styles(state)
    if state.history_refresh_idle_source != 0 { Gui:source_remove(state.history_refresh_idle_source); state.history_refresh_idle_source = 0 }
    IDE:App:history_close(state)
    IDE:App:search_free_results(state)
    LanguageKit:Analysis:destroy(cast(LanguageKit:Analysis:Index*, state.intelligence_index))
    state.intelligence_index = cast(u8*, 0)
    IDE:App:intelligence_release_results(state)
    if state.find_query { free(state.find_query) }
    IDE:App:view_state_snapshot_free(state.restore_snapshot)
    state.restore_snapshot = cast(IDE:App:ViewSnapshot*, 0)
    free(cast(u8*, state))
}

let IDE:App:reload_failed = fn (host:IDE:Host*) -> void {
    let state = IDE:App:state(host)
    if state { IDE:App:update_status(state) }
}

let IDE:App:navigate_debug_stop = fn (state:IDE:App:State*) -> void {
    if !state || !state.host || !state.host.application { return }
    let application = state.host.application
    if application.state != IDE:ApplicationState:Paused() || application.stop_revision == 0 ||
       application.stop_revision == state.application_stop_revision_seen || !application.stop_path || application.stop_line == 0 { return }
    state.application_stop_revision_seen = application.stop_revision

    let root = IDE:App:application_root(state)
    if !root { return }
    let allowed = IDE:path_is_inside(application.stop_path, root)
    free(root)
    if !allowed || !IDE:file_exists(application.stop_path) { return }

    if !state.host.selected || strcmp(state.host.selected, application.stop_path) != 0 {
        IDE:App:open_path(state, application.stop_path)
    }
    let text = IDE:App:editor_text(state)
    if text {
        let start = IDE:App:debug_line_start(text, application.stop_line)
        IDE:App:find_select(state, text, start, start)
        Gui:text_free(text)
    }
    IDE:App:show_application_console(state)
}

let IDE:App:application_event = fn (host:IDE:Host*) -> void {
    let state = IDE:App:state(host)
    if !state { return }
    IDE:App:render_application(state)
    IDE:App:navigate_debug_stop(state)
    IDE:App:update_line_gutter(state)
}

let IDE:App:runtime_ready = fn (host:IDE:Host*) -> void {
    let state = IDE:App:state(host)
    if !state { return }
    // start_reload() calls runtime_ready on the still-visible generation after
    // installing the reload worker. Capture exactly at that generation boundary.
    if host.job && host.job.kind == 2 { IDE:App:view_state_capture(state) }
    // User terminals and internal IDE worker sessions are persistent models.
    // Mount only models not already represented by this view generation.
    IDE:App:mount_terminals(state)
    if state.terminal_views { Gui:show(state.notebook) }
    IDE:App:schedule_semantics(state)
    IDE:App:update_status(state)
}

// One lifecycle object is the only contract between ide.rli and this project
// view. It deliberately contains no singleton state: IDE:view_data(host)
// resolves the object owned by the active/staged/retiring generation.
let IDE:App:lifecycle = fn (action:i64, raw:u8*) -> void {
    let host = cast(IDE:Host*, raw)
    if action == 1 { IDE:App:mount(host) }
    else if action == 2 { IDE:App:unmount(host) }
    else if action == 3 { IDE:App:reload_failed(host) }
    else if action == 4 { IDE:App:runtime_ready(host) }
    else if action == 6 { IDE:App:application_event(host) }
}
