// Workspace search/replace view. It lives beside Explorer and History and uses
// the same matching policy as Ctrl+F. Directory walking is iterative so a deep
// workspace cannot consume the language/runtime call stack.

extern g_utf8_validate(text:u8*, bytes:i64, end:u8**) -> i32 abi sysv-amd64

record IDE:App:SearchQueueNode {
    path:u8*
    next:IDE:App:SearchQueueNode*
}

record IDE:App:SearchWalk {
    state:IDE:App:State*
    query:u8*
    replacement:u8*
    replace_mode:i64
    replaced:u64
    head:IDE:App:SearchQueueNode*
    tail:IDE:App:SearchQueueNode*
}

let IDE:App:SearchMaxResults = fn () -> u64 { return 10000 }

let IDE:App:search_free_results = fn (state:IDE:App:State*) -> void {
    if !state { return }
    var item = state.search_results
    while item {
        let next = item.next
        if item.path { free(item.path) }
        free(cast(u8*, item))
        item = next
    }
    state.search_results = cast(IDE:App:SearchResult*, 0)
    state.search_result_tail = cast(IDE:App:SearchResult*, 0)
    state.search_result_count = 0
    state.search_next_id = 1
}

let IDE:App:search_clear_results = fn (state:IDE:App:State*) -> void {
    if !state { return }
    IDE:App:search_free_results(state)
    if state.search_tree { Gui:tree_clear(state.search_tree) }
}

let IDE:App:search_result_find = fn (state:IDE:App:State*, id:u64) -> IDE:App:SearchResult* {
    if !state || id == 0 { return cast(IDE:App:SearchResult*, 0) }
    var item = state.search_results
    while item {
        if item.id == id { return item }
        item = item.next
    }
    return cast(IDE:App:SearchResult*, 0)
}

let IDE:App:search_line_number = fn (text:u8*, position:u64) -> u64 {
    if !text { return 1 }
    var line:u64 = 1
    var at:u64 = 0
    while text[at] != 0 && at < position {
        if text[at] == 10 { line += 1 }
        at += 1
    }
    return line
}

let IDE:App:search_result_label = fn (state:IDE:App:State*, path:u8*, text:u8*, start:u64, line:u64) -> u8* {
    if !state || !state.host || !path || !text { return cast(u8*, 0) }
    let label = LanguageKit:Text:new()
    if !label { return cast(u8*, 0) }
    let relative = IDE:relative(state.host.root, path)
    if relative { label.append(relative); free(relative) }
    else { label.append(path) }
    label.append(":")
    IDE:append_u64(label, line)
    label.append("  ")

    var first = start
    while first > 0 && text[first - 1] != 10 && text[first - 1] != 13 { first -= 1 }
    var finish = start
    var width:u64 = 0
    while text[finish] != 0 && text[finish] != 10 && text[finish] != 13 && width < 120 {
        finish += 1
        width += 1
    }
    while first < finish && (text[first] == 32 || text[first] == 9) { first += 1 }
    if finish > first { IDE:append_bytes(label, &text[first], cast(i64, finish - first)) }
    let result = label.take()
    label.destroy()
    return result
}

let IDE:App:search_add_result = fn (state:IDE:App:State*, path:u8*, text:u8*, start:u64, finish:u64) -> void {
    if !state || !state.search_tree || !path || !text { return }
    if state.search_result_count >= IDE:App:SearchMaxResults() { return }
    let item = alloc(IDE:App:SearchResult)
    if !item { return }
    item.id = state.search_next_id
    item.path = IDE:copy(path)
    item.start = start
    item.finish = finish
    item.line = IDE:App:search_line_number(text, start)
    item.next = cast(IDE:App:SearchResult*, 0)
    if !item.path { free(cast(u8*, item)); return }
    state.search_next_id += 1
    if state.search_result_tail { state.search_result_tail.next = item }
    else { state.search_results = item }
    state.search_result_tail = item
    state.search_result_count += 1

    let label = IDE:App:search_result_label(state, path, text, start, item.line)
    let id = IDE:App:history_u64_text(item.id)
    if label && id {
        let row = Gui:tree_append(state.search_tree, cast(u8*, 0), label, id, 0)
        Gui:tree_iter_free(row)
    }
    if label { free(label) }
    if id { free(id) }
}

let IDE:App:search_scan_plain = fn (state:IDE:App:State*, path:u8*, text:u8*, query:u8*) -> void {
    if !state || !path || !text || !query || query[0] == 0 { return }
    let text_bytes = cast(u64, strlen(text))
    let query_bytes = cast(u64, strlen(query))
    if query_bytes == 0 || query_bytes > text_bytes { return }
    var at:u64 = 0
    while at + query_bytes <= text_bytes && state.search_result_count < IDE:App:SearchMaxResults() {
        if IDE:App:find_match_at(text, text_bytes, query, query_bytes, at, state.search_case_sensitive, state.search_boundary) {
            IDE:App:search_add_result(state, path, text, at, at + query_bytes)
            at += query_bytes
        } else { at += 1 }
    }
}

let IDE:App:search_scan_regex = fn (state:IDE:App:State*, path:u8*, text:u8*, query:u8*) -> void {
    if !state || !path || !text || !query || query[0] == 0 { return }
    var flags:i32 = 0
    if state.search_case_sensitive == 0 { flags = 1 }
    let regex = g_regex_new(query, flags, 0, cast(u8**, 0))
    if !regex { return }
    let bytes = cast(i64, strlen(text))
    var info:u8* = cast(u8*, 0)
    let matched = g_regex_match_full(regex, text, bytes, 0, 0, &info, cast(u8**, 0))
    if matched != 0 && info {
        let a = alloc(i32)
        let b = alloc(i32)
        if a && b {
            var keep:i64 = 1
            while keep != 0 && state.search_result_count < IDE:App:SearchMaxResults() {
                if g_match_info_fetch_pos(info, 0, a, b) != 0 && a[0] >= 0 && b[0] >= a[0] {
                    IDE:App:search_add_result(state, path, text, cast(u64, a[0]), cast(u64, b[0]))
                }
                keep = g_match_info_next(info, cast(u8**, 0))
            }
        }
        if a { free(cast(u8*, a)) }
        if b { free(cast(u8*, b)) }
    }
    if info { g_match_info_free(info) }
    g_regex_unref(regex)
}

let IDE:App:search_read_text_file = fn (path:u8*) -> u8* {
    if !path { return cast(u8*, 0) }
    let stream = fopen(path, "rb")
    if !stream { return cast(u8*, 0) }
    if fseek(stream, 0, 2) != 0 { fclose(stream); return cast(u8*, 0) }
    let bytes = ftell(stream)
    fclose(stream)
    if bytes < 0 || bytes > 16777216 { return cast(u8*, 0) }
    let text = IDE:read_file(path)
    if !text { return cast(u8*, 0) }
    if cast(i64, strlen(text)) != bytes || g_utf8_validate(text, bytes, cast(u8**, 0)) == 0 {
        // IDE text editing is UTF-8/C-string based. Never search/replace a
        // binary or invalid-UTF-8 file because writing it back could corrupt it.
        free(text)
        return cast(u8*, 0)
    }
    return text
}

let IDE:App:search_scan_file = fn (walk:IDE:App:SearchWalk*, path:u8*) -> void {
    if !walk || !walk.state || !path || !walk.query { return }
    let state = walk.state
    var text:u8* = cast(u8*, 0)
    var editor_owned:i64 = 0
    if state.host && state.host.selected && strcmp(state.host.selected, path) == 0 {
        text = IDE:App:editor_text(state)
        editor_owned = 1
    } else { text = IDE:App:search_read_text_file(path) }
    if !text { return }
    if state.search_regex != 0 { IDE:App:search_scan_regex(state, path, text, walk.query) }
    else { IDE:App:search_scan_plain(state, path, text, walk.query) }
    if editor_owned != 0 { Gui:text_free(text) } else { free(text) }
}

let IDE:App:search_replace_file = fn (walk:IDE:App:SearchWalk*, path:u8*) -> void {
    if !walk || !walk.state || !path || !walk.query || !walk.replacement { return }
    let state = walk.state
    var text:u8* = cast(u8*, 0)
    var editor_owned:i64 = 0
    let active = state.host && state.host.selected && strcmp(state.host.selected, path) == 0
    if active {
        text = IDE:App:editor_text(state)
        editor_owned = 1
    } else { text = IDE:App:search_read_text_file(path) }
    if !text { return }
    var count:u64 = 0
    let next = IDE:App:find_replace_all_text(text, walk.query, walk.replacement,
                                               state.search_case_sensitive, state.search_boundary,
                                               state.search_regex, &count)
    if next && count > 0 {
        if active { Gui:text_set(state.editor, next); walk.replaced += count }
        else if IDE:write_file(path, next) { walk.replaced += count }
    }
    if next { free(next) }
    if editor_owned != 0 { Gui:text_free(text) } else { free(text) }
}

let IDE:App:search_queue_push = fn (walk:IDE:App:SearchWalk*, path:u8*) -> void {
    if !walk || !path { return }
    let node = alloc(IDE:App:SearchQueueNode)
    if !node { return }
    node.path = IDE:copy(path)
    node.next = cast(IDE:App:SearchQueueNode*, 0)
    if !node.path { free(cast(u8*, node)); return }
    if walk.tail { walk.tail.next = node }
    else { walk.head = node }
    walk.tail = node
}

let IDE:App:search_collect_directory = fn (path:u8*, name:u8*, directory:i64, data:u8*) -> void {
    let walk = cast(IDE:App:SearchWalk*, data)
    if !walk || directory == 0 || !path { return }
    IDE:App:search_queue_push(walk, path)
}

let IDE:App:search_visit_file = fn (path:u8*, name:u8*, directory:i64, data:u8*) -> void {
    let walk = cast(IDE:App:SearchWalk*, data)
    if !walk || directory != 0 || !path { return }
    if walk.replace_mode != 0 { IDE:App:search_replace_file(walk, path) }
    else if walk.state && walk.state.search_result_count < IDE:App:SearchMaxResults() { IDE:App:search_scan_file(walk, path) }
}

let IDE:App:search_walk_workspace = fn (walk:IDE:App:SearchWalk*) -> void {
    if !walk || !walk.state || !walk.state.host || !walk.state.host.root { return }
    IDE:App:search_queue_push(walk, walk.state.host.root)
    while walk.head {
        let current = walk.head
        walk.head = current.next
        if !walk.head { walk.tail = cast(IDE:App:SearchQueueNode*, 0) }
        if current.path {
            IDE:visit_directory(current.path, 1, IDE:App:search_collect_directory, cast(u8*, walk))
            IDE:visit_directory(current.path, 0, IDE:App:search_visit_file, cast(u8*, walk))
            free(current.path)
        }
        free(cast(u8*, current))
        if walk.replace_mode == 0 && walk.state.search_result_count >= IDE:App:SearchMaxResults() {
            while walk.head {
                let rest = walk.head
                walk.head = rest.next
                if rest.path { free(rest.path) }
                free(cast(u8*, rest))
            }
            walk.tail = cast(IDE:App:SearchQueueNode*, 0)
        }
    }
}

let IDE:App:search_set_status = fn (state:IDE:App:State*, prefix:u8*, value:u64) -> void {
    if !state || !state.search_status { return }
    let text = LanguageKit:Text:new()
    if !text { return }
    if prefix { text.append(prefix) }
    IDE:append_u64(text, value)
    if state.search_result_count >= IDE:App:SearchMaxResults() { text.append(" (limit)") }
    Gui:label_text(state.search_status, text.data)
    text.destroy()
}

let IDE:App:search_update_buttons = fn (state:IDE:App:State*) -> void {
    if !state { return }
    if state.search_case_button { if state.search_case_sensitive != 0 { gtk_button_set_label(state.search_case_button, "Aa*") } else { gtk_button_set_label(state.search_case_button, "Aa") } }
    if state.search_delimiter_button { if state.search_boundary == 1 { gtk_button_set_label(state.search_delimiter_button, "DELIM*") } else { gtk_button_set_label(state.search_delimiter_button, "DELIM") } }
    if state.search_whitespace_button { if state.search_boundary == 2 { gtk_button_set_label(state.search_whitespace_button, "WS*") } else { gtk_button_set_label(state.search_whitespace_button, "WS") } }
    if state.search_regex_button { if state.search_regex != 0 { gtk_button_set_label(state.search_regex_button, ".**") } else { gtk_button_set_label(state.search_regex_button, ".*") } }
}

let IDE:App:search_run = fn (state:IDE:App:State*) -> void {
    if !state || !state.search_input { return }
    let query = Gui:input_text(state.search_input)
    IDE:App:search_clear_results(state)
    if !query || query[0] == 0 { if state.search_status { Gui:label_text(state.search_status, "") }; return }
    if state.search_regex != 0 {
        var flags:i32 = 0
        if state.search_case_sensitive == 0 { flags = 1 }
        let probe = g_regex_new(query, flags, 0, cast(u8**, 0))
        if !probe { if state.search_status { Gui:label_text(state.search_status, "invalid regex") }; return }
        g_regex_unref(probe)
    }
    let walk = alloc(IDE:App:SearchWalk)
    if !walk { return }
    walk.state = state
    walk.query = query
    walk.replacement = cast(u8*, 0)
    walk.replace_mode = 0
    walk.replaced = 0
    walk.head = cast(IDE:App:SearchQueueNode*, 0)
    walk.tail = cast(IDE:App:SearchQueueNode*, 0)
    IDE:App:search_walk_workspace(walk)
    free(cast(u8*, walk))
    IDE:App:search_set_status(state, "matches ", state.search_result_count)
}

let IDE:App:search_selected_result = fn (state:IDE:App:State*) -> IDE:App:SearchResult* {
    if !state || !state.search_tree { return cast(IDE:App:SearchResult*, 0) }
    let selection = Gui:tree_selection(state.search_tree)
    let iterator = Gui:tree_selected_iter(selection)
    if !iterator { return cast(IDE:App:SearchResult*, 0) }
    var directory:i32 = 0
    var loaded:i32 = 0
    let id_text = Gui:tree_iter_path(state.search_tree, iterator, &directory, &loaded)
    Gui:tree_iter_free(iterator)
    if !id_text { return cast(IDE:App:SearchResult*, 0) }
    let id = IDE:App:history_parse_u64(id_text)
    Gui:text_free(id_text)
    return IDE:App:search_result_find(state, id)
}

let IDE:App:on_search_selected = fn (selection:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !selection { return }
    let result = IDE:App:search_selected_result(state)
    if !result || !result.path { return }
    let path = IDE:copy(result.path)
    let start = result.start
    let finish = result.finish
    if !path { return }
    if !state.host || !state.host.selected || strcmp(state.host.selected, path) != 0 {
        IDE:App:open_path(state, path)
    }
    free(path)
    let text = IDE:App:editor_text(state)
    if text {
        let bytes = cast(u64, strlen(text))
        if start <= finish && finish <= bytes { IDE:App:find_select(state, text, start, finish) }
        Gui:text_free(text)
    }
}

let IDE:App:search_replace_selected = fn (state:IDE:App:State*) -> void {
    if !state || !state.search_replace_input { return }
    let result = IDE:App:search_selected_result(state)
    if !result || !result.path { if state.search_status { Gui:label_text(state.search_status, "select a match") }; return }
    var replacement = Gui:input_text(state.search_replace_input)
    if !replacement { replacement = "" }
    let active = state.host && state.host.selected && strcmp(state.host.selected, result.path) == 0
    var text:u8* = cast(u8*, 0)
    var editor_owned:i64 = 0
    if active { text = IDE:App:editor_text(state); editor_owned = 1 }
    else { text = IDE:App:search_read_text_file(result.path) }
    if !text { return }
    let bytes = cast(u64, strlen(text))
    if result.start > result.finish || result.finish > bytes {
        if editor_owned != 0 { Gui:text_free(text) } else { free(text) }
        IDE:App:search_run(state)
        return
    }
    let next = IDE:App:history_splice(text, result.start, result.finish - result.start,
                                       replacement, cast(u64, strlen(replacement)))
    if next {
        if active { Gui:text_set(state.editor, next) }
        else { IDE:write_file(result.path, next) }
        free(next)
    }
    if editor_owned != 0 { Gui:text_free(text) } else { free(text) }
    IDE:App:search_run(state)
}

let IDE:App:search_replace_all = fn (state:IDE:App:State*) -> void {
    if !state || !state.search_input || !state.search_replace_input { return }
    let query = Gui:input_text(state.search_input)
    let replacement = Gui:input_text(state.search_replace_input)
    if !query || query[0] == 0 || !replacement { return }
    if state.search_regex != 0 {
        var flags:i32 = 0
        if state.search_case_sensitive == 0 { flags = 1 }
        let probe = g_regex_new(query, flags, 0, cast(u8**, 0))
        if !probe { if state.search_status { Gui:label_text(state.search_status, "invalid regex") }; return }
        g_regex_unref(probe)
    }
    let walk = alloc(IDE:App:SearchWalk)
    if !walk { return }
    walk.state = state
    walk.query = query
    walk.replacement = replacement
    walk.replace_mode = 1
    walk.replaced = 0
    walk.head = cast(IDE:App:SearchQueueNode*, 0)
    walk.tail = cast(IDE:App:SearchQueueNode*, 0)
    IDE:App:search_walk_workspace(walk)
    let replaced = walk.replaced
    free(cast(u8*, walk))
    IDE:App:search_run(state)
    IDE:App:search_set_status(state, "replaced ", replaced)
}

let IDE:App:on_search_run = fn (widget:u8*, data:u8*) -> void { IDE:App:search_run(cast(IDE:App:State*, data)) }
let IDE:App:on_search_replace = fn (widget:u8*, data:u8*) -> void { IDE:App:search_replace_selected(cast(IDE:App:State*, data)) }
let IDE:App:on_search_replace_all = fn (widget:u8*, data:u8*) -> void { IDE:App:search_replace_all(cast(IDE:App:State*, data)) }

let IDE:App:on_search_case = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    state.search_case_sensitive = state.search_case_sensitive == 0
    IDE:App:search_update_buttons(state)
}

let IDE:App:on_search_delimiter = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    if state.search_boundary == 1 { state.search_boundary = 0 } else { state.search_boundary = 1 }
    state.search_regex = 0
    IDE:App:search_update_buttons(state)
}

let IDE:App:on_search_whitespace = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    if state.search_boundary == 2 { state.search_boundary = 0 } else { state.search_boundary = 2 }
    state.search_regex = 0
    IDE:App:search_update_buttons(state)
}

let IDE:App:on_search_regex = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    state.search_regex = state.search_regex == 0
    if state.search_regex != 0 { state.search_boundary = 0 }
    IDE:App:search_update_buttons(state)
}

let IDE:App:show_search = fn (state:IDE:App:State*) -> void {
    if !state || !state.sidebar_stack || !state.search_pane { return }
    state.history_visible = 0
    state.search_visible = 1
    Gui:stack_select(state.sidebar_stack, state.search_pane)
    if state.search_input { Gui:focus(state.search_input) }
}

let IDE:App:on_show_search = fn (widget:u8*, data:u8*) -> void { IDE:App:show_search(cast(IDE:App:State*, data)) }

let IDE:App:create_search_view = fn (state:IDE:App:State*) -> u8* {
    let pane = Gui:column(0)
    Gui:class_add(pane, "explorer-pane")
    let header = Gui:row(0)
    Gui:class_add(header, "explorer-header")
    let title = Gui:label("SEARCH")
    Gui:label_align(title, cast(f32, 0.0))
    Gui:class_add(title, "explorer-title")
    Gui:append(header, title, 1, 0)
    let history = Gui:icon_button("view-list-symbolic", "Editor History")
    let explorer = Gui:icon_button("folder-symbolic", "Back to Explorer")
    Gui:on_click(history, IDE:App:on_show_history, cast(u8*, state))
    Gui:on_click(explorer, IDE:App:on_show_explorer, cast(u8*, state))
    Gui:append_end(header, history, 0, 0)
    Gui:append_end(header, explorer, 0, 2)
    Gui:append(pane, header, 0, 0)

    let query_row = Gui:row(4)
    state.search_input = Gui:input("Search workspace")
    Gui:on_activate(state.search_input, IDE:App:on_search_run, cast(u8*, state))
    Gui:append(query_row, state.search_input, 1, 4)
    let run = Gui:icon_button("edit-find-symbolic", "Search")
    Gui:on_click(run, IDE:App:on_search_run, cast(u8*, state))
    Gui:append_end(query_row, run, 0, 2)
    Gui:append(pane, query_row, 0, 2)

    let options = Gui:row(2)
    state.search_case_button = Gui:button("Aa")
    state.search_delimiter_button = Gui:button("DELIM")
    state.search_whitespace_button = Gui:button("WS")
    state.search_regex_button = Gui:button(".*")
    Gui:class_add(state.search_case_button, "tool-button")
    Gui:class_add(state.search_delimiter_button, "tool-button")
    Gui:class_add(state.search_whitespace_button, "tool-button")
    Gui:class_add(state.search_regex_button, "tool-button")
    Gui:tooltip(state.search_case_button, "Case sensitive")
    Gui:tooltip(state.search_delimiter_button, "Require delimiter boundaries")
    Gui:tooltip(state.search_whitespace_button, "Require whitespace boundaries")
    Gui:tooltip(state.search_regex_button, "Regular expression")
    Gui:on_click(state.search_case_button, IDE:App:on_search_case, cast(u8*, state))
    Gui:on_click(state.search_delimiter_button, IDE:App:on_search_delimiter, cast(u8*, state))
    Gui:on_click(state.search_whitespace_button, IDE:App:on_search_whitespace, cast(u8*, state))
    Gui:on_click(state.search_regex_button, IDE:App:on_search_regex, cast(u8*, state))
    Gui:append(options, state.search_case_button, 0, 4)
    Gui:append(options, state.search_delimiter_button, 0, 0)
    Gui:append(options, state.search_whitespace_button, 0, 0)
    Gui:append(options, state.search_regex_button, 0, 0)
    Gui:append(pane, options, 0, 2)

    let replace_row = Gui:row(4)
    state.search_replace_input = Gui:input("Replace")
    Gui:on_activate(state.search_replace_input, IDE:App:on_search_replace, cast(u8*, state))
    Gui:append(replace_row, state.search_replace_input, 1, 4)
    let replace = Gui:button("Replace")
    let replace_all = Gui:button("All")
    Gui:tooltip(replace, "Replace selected match")
    Gui:tooltip(replace_all, "Replace all workspace matches")
    Gui:on_click(replace, IDE:App:on_search_replace, cast(u8*, state))
    Gui:on_click(replace_all, IDE:App:on_search_replace_all, cast(u8*, state))
    Gui:append_end(replace_row, replace_all, 0, 2)
    Gui:append_end(replace_row, replace, 0, 0)
    Gui:append(pane, replace_row, 0, 2)

    state.search_status = Gui:label("")
    Gui:label_align(state.search_status, cast(f32, 0.0))
    Gui:class_add(state.search_status, "explorer-root")
    Gui:append(pane, state.search_status, 0, 0)

    state.search_tree = Gui:tree()
    Gui:on_tree_select(state.search_tree, IDE:App:on_search_selected, cast(u8*, state))
    Gui:append(pane, Gui:scroll(state.search_tree), 1, 0)
    state.search_pane = pane
    return pane
}

set g_utf8_validate.serializable = false
