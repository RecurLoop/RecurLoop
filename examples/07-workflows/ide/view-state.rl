// GUI state hand-off across full project-view replacement. GTK widgets never
// cross generations: the visible view stores only plain values and the staged
// view reconstructs fresh widgets, then restores these values after commit.

link shared "gtk-3"

// Only native symbols unique to view-state are declared here. File I/O is
// provided by ide.rli, text selection by find.rl, and history flush by
// history.rl. This avoids duplicate typed-function declarations across modules.
extern gtk_paned_get_position(paned:u8*) -> i32 abi sysv-amd64
extern gtk_scrolled_window_get_hadjustment(window:u8*) -> u8* abi sysv-amd64
extern gtk_adjustment_get_value(adjustment:u8*) -> f64 abi sysv-amd64
extern gtk_adjustment_set_value(adjustment:u8*, value:f64) -> void abi sysv-amd64
extern gtk_notebook_get_current_page(notebook:u8*) -> i32 abi sysv-amd64
let IDE:App:view_state_version = fn () -> u64 { return 1 }

let IDE:App:view_state_utf8_chars = fn (text:u8*) -> i64 {
    if !text { return 0 }
    var bytes:i64 = 0
    var chars:i64 = 0
    while text[bytes] != 0 {
        let value = text[bytes]
        if value < 128 || value >= 192 { chars += 1 }
        bytes += 1
    }
    return chars
}

let IDE:App:view_state_snapshot_free = fn (snapshot:IDE:App:ViewSnapshot*) -> void {
    if !snapshot { return }
    if snapshot.selected { free(snapshot.selected) }
    if snapshot.find_query { free(snapshot.find_query) }
    if snapshot.find_replace { free(snapshot.find_replace) }
    if snapshot.search_query { free(snapshot.search_query) }
    if snapshot.search_replace { free(snapshot.search_replace) }
    free(cast(u8*, snapshot))
}

let IDE:App:view_state_path = fn (state:IDE:App:State*) -> u8* {
    if !state || !state.host || !state.host.runner || !state.host.runner.cache_directory { return cast(u8*, 0) }
    let ide_cache = IDE:join(state.host.runner.cache_directory, "ide")
    if !ide_cache { return cast(u8*, 0) }
    if !IDE:ensure_directory_tree(ide_cache) { free(ide_cache); return cast(u8*, 0) }
    let result = IDE:join(ide_cache, "view-state-v1.bin")
    free(ide_cache)
    return result
}

let IDE:App:view_state_write_f64 = fn (stream:u8*, value:f64) -> i64 {
    if !stream { return 0 }
    return fwrite(cast(u8*, &value), 8, 1, stream) == 1
}

let IDE:App:view_state_read_f64 = fn (stream:u8*, value:f64*) -> i64 {
    if !stream || !value { return 0 }
    return fread(cast(u8*, value), 8, 1, stream) == 1
}

let IDE:App:view_state_write_string = fn (stream:u8*, value:u8*) -> i64 {
    var bytes:u64 = 0
    if value { bytes = cast(u64, strlen(value)) }
    if !IDE:App:history_write_u64(stream, bytes) { return 0 }
    if bytes == 0 { return 1 }
    return IDE:App:history_write_bytes(stream, value, bytes)
}

let IDE:App:view_state_read_string = fn (stream:u8*) -> u8* {
    let bytes = alloc(u64)
    if !bytes { return cast(u8*, 0) }
    if !IDE:App:history_read_u64(stream, bytes) { free(cast(u8*, bytes)); return cast(u8*, 0) }
    let result = IDE:App:history_read_bytes(stream, bytes[0])
    free(cast(u8*, bytes))
    return result
}

let IDE:App:view_state_selection = fn (state:IDE:App:State*, insert_offset:i64*, bound_offset:i64*) -> void {
    IDE:App:find_selection_chars(state, insert_offset, bound_offset)
}

let IDE:App:view_state_select = fn (state:IDE:App:State*, insert_offset:i64, bound_offset:i64) -> void {
    IDE:App:find_select_chars(state, insert_offset, bound_offset)
}

let IDE:App:view_state_scroll_x = fn (scroll:u8*) -> f64 {
    if !scroll { return cast(f64, 0.0) }
    let adjustment = gtk_scrolled_window_get_hadjustment(scroll)
    if !adjustment { return cast(f64, 0.0) }
    return gtk_adjustment_get_value(adjustment)
}

let IDE:App:view_state_scroll_y = fn (scroll:u8*) -> f64 {
    if !scroll { return cast(f64, 0.0) }
    let adjustment = gtk_scrolled_window_get_vadjustment(scroll)
    if !adjustment { return cast(f64, 0.0) }
    return gtk_adjustment_get_value(adjustment)
}

let IDE:App:view_state_set_scroll = fn (scroll:u8*, x:f64, y:f64) -> void {
    if !scroll { return }
    let horizontal = gtk_scrolled_window_get_hadjustment(scroll)
    let vertical = gtk_scrolled_window_get_vadjustment(scroll)
    if horizontal { gtk_adjustment_set_value(horizontal, x) }
    if vertical { gtk_adjustment_set_value(vertical, y) }
}

let IDE:App:view_state_capture = fn (state:IDE:App:State*) -> void {
    if !state || !state.host { return }
    // Word-coalescing may have an unflushed TagExtend. Reload is a hard history
    // boundary, so publish the exact current buffer before the new view opens it.
    IDE:App:history_flush(state.history)

    let path = IDE:App:view_state_path(state)
    if !path { return }
    let temp_text = LanguageKit:Text:new()
    if !temp_text { free(path); return }
    temp_text.append(path)
    temp_text.append(".tmp")
    let temporary = temp_text.take()
    temp_text.destroy()
    if !temporary { free(path); return }
    let stream = fopen(temporary, "wb")
    if !stream { free(temporary); free(path); return }

    var sidebar:i64 = 0
    if state.intelligence_visible != 0 { sidebar = 3 }
    else if state.search_visible != 0 { sidebar = 2 }
    else if state.history_visible != 0 { sidebar = 1 }
    var insert_offset:i64 = 0
    var bound_offset:i64 = 0
    IDE:App:view_state_selection(state, &insert_offset, &bound_offset)
    var scroll_x:f64 = cast(f64, 0.0)
    var scroll_y:f64 = cast(f64, 0.0)
    if state.editor_scroll {
        scroll_x = IDE:App:view_state_scroll_x(state.editor_scroll)
        scroll_y = IDE:App:view_state_scroll_y(state.editor_scroll)
    }
    var main_split:i64 = 300
    var right_split:i64 = 555
    if state.main_split { main_split = cast(i64, gtk_paned_get_position(state.main_split)) }
    if state.right_split { right_split = cast(i64, gtk_paned_get_position(state.right_split)) }
    var terminal_page:i64 = 0
    if state.notebook {
        let current_page = gtk_notebook_get_current_page(state.notebook)
        if current_page >= 0 { terminal_page = cast(i64, current_page) }
    }

    var ok:i64 = 1
    if !IDE:App:history_write_u64(stream, IDE:App:view_state_version()) { ok = 0 }
    if ok && !IDE:App:view_state_write_string(stream, state.host.selected) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, sidebar)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, state.find_visible)) { ok = 0 }
    if ok && !IDE:App:view_state_write_string(stream, Gui:input_text(state.find_input)) { ok = 0 }
    if ok && !IDE:App:view_state_write_string(stream, Gui:input_text(state.find_replace_input)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, state.find_case_sensitive)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, state.find_boundary)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, state.find_regex)) { ok = 0 }
    if ok && !IDE:App:view_state_write_string(stream, Gui:input_text(state.search_input)) { ok = 0 }
    if ok && !IDE:App:view_state_write_string(stream, Gui:input_text(state.search_replace_input)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, state.search_case_sensitive)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, state.search_boundary)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, state.search_regex)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, insert_offset)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, bound_offset)) { ok = 0 }
    if ok && !IDE:App:view_state_write_f64(stream, scroll_x) { ok = 0 }
    if ok && !IDE:App:view_state_write_f64(stream, scroll_y) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, main_split)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, right_split)) { ok = 0 }
    if ok && !IDE:App:history_write_u64(stream, cast(u64, terminal_page)) { ok = 0 }
    fclose(stream)
    if ok { IDE:rename_path(temporary, path) } else { IDE:remove_path(temporary) }
    free(temporary)
    free(path)
}

let IDE:App:view_state_load = fn (state:IDE:App:State*) -> IDE:App:ViewSnapshot* {
    let path = IDE:App:view_state_path(state)
    if !path { return cast(IDE:App:ViewSnapshot*, 0) }
    let stream = fopen(path, "rb")
    free(path)
    if !stream { return cast(IDE:App:ViewSnapshot*, 0) }
    let value = alloc(u64)
    if !value { fclose(stream); return cast(IDE:App:ViewSnapshot*, 0) }
    if !IDE:App:history_read_u64(stream, value) || value[0] != IDE:App:view_state_version() {
        free(cast(u8*, value)); fclose(stream); return cast(IDE:App:ViewSnapshot*, 0)
    }

    let snapshot = alloc(IDE:App:ViewSnapshot)
    if !snapshot { free(cast(u8*, value)); fclose(stream); return cast(IDE:App:ViewSnapshot*, 0) }
    snapshot.selected = IDE:App:view_state_read_string(stream)
    snapshot.find_query = cast(u8*, 0)
    snapshot.find_replace = cast(u8*, 0)
    snapshot.search_query = cast(u8*, 0)
    snapshot.search_replace = cast(u8*, 0)
    var ok:i64 = snapshot.selected != cast(u8*, 0)
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.sidebar = cast(i64, value[0]) } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.find_visible = cast(i64, value[0]) } }
    if ok { snapshot.find_query = IDE:App:view_state_read_string(stream); if !snapshot.find_query { ok = 0 } }
    if ok { snapshot.find_replace = IDE:App:view_state_read_string(stream); if !snapshot.find_replace { ok = 0 } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.find_case_sensitive = cast(i64, value[0]) } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.find_boundary = cast(i64, value[0]) } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.find_regex = cast(i64, value[0]) } }
    if ok { snapshot.search_query = IDE:App:view_state_read_string(stream); if !snapshot.search_query { ok = 0 } }
    if ok { snapshot.search_replace = IDE:App:view_state_read_string(stream); if !snapshot.search_replace { ok = 0 } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.search_case_sensitive = cast(i64, value[0]) } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.search_boundary = cast(i64, value[0]) } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.search_regex = cast(i64, value[0]) } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.editor_insert = cast(i64, value[0]) } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.editor_bound = cast(i64, value[0]) } }
    if ok && !IDE:App:view_state_read_f64(stream, &snapshot.editor_scroll_x) { ok = 0 }
    if ok && !IDE:App:view_state_read_f64(stream, &snapshot.editor_scroll_y) { ok = 0 }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.main_split = cast(i64, value[0]) } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.right_split = cast(i64, value[0]) } }
    if ok { if !IDE:App:history_read_u64(stream, value) { ok = 0 } else { snapshot.terminal_page = cast(i64, value[0]) } }
    free(cast(u8*, value))
    fclose(stream)
    if !ok { IDE:App:view_state_snapshot_free(snapshot); return cast(IDE:App:ViewSnapshot*, 0) }
    return snapshot
}

let IDE:App:view_state_restore_controls = fn (state:IDE:App:State*) -> void {
    if !state || !state.restore_snapshot { return }
    let snapshot = state.restore_snapshot
    if state.find_input && snapshot.find_query { Gui:input_set(state.find_input, snapshot.find_query) }
    if state.find_replace_input && snapshot.find_replace { Gui:input_set(state.find_replace_input, snapshot.find_replace) }
    state.find_case_sensitive = snapshot.find_case_sensitive
    state.find_boundary = snapshot.find_boundary
    state.find_regex = snapshot.find_regex
    IDE:App:find_update_buttons(state)
    if state.search_input && snapshot.search_query { Gui:input_set(state.search_input, snapshot.search_query) }
    if state.search_replace_input && snapshot.search_replace { Gui:input_set(state.search_replace_input, snapshot.search_replace) }
    state.search_case_sensitive = snapshot.search_case_sensitive
    state.search_boundary = snapshot.search_boundary
    state.search_regex = snapshot.search_regex
    IDE:App:search_update_buttons(state)
    if snapshot.sidebar == 3 { IDE:App:show_intelligence(state) }
    else if snapshot.sidebar == 2 {
        IDE:App:show_search(state)
        if state.search_input {
            let query = Gui:input_text(state.search_input)
            if query && query[0] != 0 { IDE:App:search_run(state) }
        }
    } else if snapshot.sidebar == 1 { IDE:App:show_history(state) }
    else { IDE:App:show_explorer(state) }
    if snapshot.find_visible != 0 { IDE:App:show_find(state) } else { state.find_visible = 0 }
    if state.notebook { Gui:tabs_select(state.notebook, cast(i32, snapshot.terminal_page)) }
}

let IDE:App:view_state_restore_idle = fn (data:u8*) -> i32 {
    let state = cast(IDE:App:State*, data)
    if !state { return 0 }
    state.restore_idle_source = 0
    let snapshot = state.restore_snapshot
    if !snapshot { return 0 }

    // Cursor/selection can scroll GtkTextView by itself, so restore it first and
    // the exact scroll adjustments second. This runs on the next main-loop turn,
    // after the staged widget tree has been realized; there is no timeout/debounce.
    if state.editor {
        let text = IDE:App:editor_text(state)
        if text {
            let chars = IDE:App:view_state_utf8_chars(text)
            var insert_offset = snapshot.editor_insert
            var bound_offset = snapshot.editor_bound
            if insert_offset < 0 { insert_offset = 0 }
            if bound_offset < 0 { bound_offset = 0 }
            if insert_offset > chars { insert_offset = chars }
            if bound_offset > chars { bound_offset = chars }
            IDE:App:view_state_select(state, insert_offset, bound_offset)
            Gui:text_free(text)
        }
    }
    if state.main_split && snapshot.main_split > 0 {
        var position = snapshot.main_split
        let available = cast(i64, Gui:allocated_width(state.main_split))
        if available > 1 && position >= available { position = available - 1 }
        if position < 0 { position = 0 }
        Gui:split_position(state.main_split, cast(i32, position))
    }
    if state.right_split && snapshot.right_split > 0 {
        var position = snapshot.right_split
        let available = cast(i64, Gui:allocated_height(state.right_split))
        if available > 1 && position >= available { position = available - 1 }
        if position < 0 { position = 0 }
        Gui:split_position(state.right_split, cast(i32, position))
    }
    if state.editor_scroll { IDE:App:view_state_set_scroll(state.editor_scroll, snapshot.editor_scroll_x, snapshot.editor_scroll_y) }
    if state.notebook { Gui:tabs_select(state.notebook, cast(i32, snapshot.terminal_page)) }

    IDE:App:view_state_snapshot_free(snapshot)
    state.restore_snapshot = cast(IDE:App:ViewSnapshot*, 0)
    return 0
}

set gtk_paned_get_position.serializable = false
set gtk_scrolled_window_get_hadjustment.serializable = false
set gtk_adjustment_get_value.serializable = false
set gtk_adjustment_set_value.serializable = false
set gtk_notebook_get_current_page.serializable = false
