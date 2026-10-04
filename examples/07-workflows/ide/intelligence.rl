// Semantic navigation/refactoring UI. analysis.rl owns the project-local index
// and queries; the host supplies generic source traces and dictionary facts.

record IDE:App:RenameFile {
    path:u8*
    temporary:u8*
    text:u8*
    next:IDE:App:RenameFile*
}

let IDE:App:intelligence_role = fn (role:i64) -> u8* {
    if role == 2 { return "definition" }
    if role == 3 { return "call" }
    if role == 4 { return "type" }
    if role == 5 { return "prototype" }
    return "reference"
}

// Release result model memory independently from its GTK presentation. During
// generation retirement the native subtree has already been destroyed, so the
// unmount path must never call GtkTreeView APIs through stale widget pointers.
let IDE:App:intelligence_release_results = fn (state:IDE:App:State*) -> void {
    if !state { return }
    var item = state.intelligence_results
    while item {
        let next = item.next
        if item.path { free(item.path) }
        if item.label { free(item.label) }
        if item.insert { free(item.insert) }
        free(cast(u8*, item))
        item = next
    }
    state.intelligence_results = cast(IDE:App:IntelligenceResult*, 0)
    state.intelligence_result_tail = cast(IDE:App:IntelligenceResult*, 0)
    state.intelligence_result_count = 0
    state.intelligence_next_id = 1
}

let IDE:App:intelligence_free_results = fn (state:IDE:App:State*) -> void {
    if !state { return }
    IDE:App:intelligence_release_results(state)
    if state.intelligence_tree { Gui:tree_clear(state.intelligence_tree) }
}

let IDE:App:intelligence_result_find = fn (state:IDE:App:State*, id:u64) -> IDE:App:IntelligenceResult* {
    if !state || id == 0 { return cast(IDE:App:IntelligenceResult*, 0) }
    var item = state.intelligence_results
    while item {
        if item.id == id { return item }
        item = item.next
    }
    return cast(IDE:App:IntelligenceResult*, 0)
}

let IDE:App:intelligence_set_status = fn (state:IDE:App:State*, text:u8*) -> void {
    if state && state.intelligence_status { Gui:label_text(state.intelligence_status, text) }
}

let IDE:App:intelligence_result_display = fn (state:IDE:App:State*, path:u8*, line:u64, role:i64, label:u8*) -> u8* {
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    if path {
        var relative = cast(u8*, 0)
        if state && state.host { relative = IDE:relative(state.host.root, path) }
        if relative { out.append(relative); free(relative) }
        else { out.append(path) }
        if line > 0 {
            out.append(":")
            IDE:append_u64(out, line)
        }
        out.append("  ·  ")
        out.append(IDE:App:intelligence_role(role))
        if label && label[0] != 0 { out.append("  ·  "); out.append(label) }
    } else if label { out.append(label) }
    let result = out.take()
    out.destroy()
    return result
}

let IDE:App:intelligence_add_result = fn (state:IDE:App:State*, path:u8*, start:u64, finish:u64, line:u64,
                                           role:i64, label:u8*, insert:u8*, completion:i64) -> void {
    if !state || !state.intelligence_tree { return }
    let item = alloc(IDE:App:IntelligenceResult)
    if !item { return }
    item.id = state.intelligence_next_id
    item.path = cast(u8*, 0)
    if path { item.path = IDE:copy(path) }
    item.start = start
    item.finish = finish
    item.line = line
    item.role = role
    item.label = IDE:copy("")
    if label { if item.label { free(item.label) }; item.label = IDE:copy(label) }
    item.insert = cast(u8*, 0)
    if insert { item.insert = IDE:copy(insert) }
    item.completion = completion
    item.next = cast(IDE:App:IntelligenceResult*, 0)
    if (path && !item.path) || !item.label || (insert && !item.insert) {
        if item.path { free(item.path) }
        if item.label { free(item.label) }
        if item.insert { free(item.insert) }
        free(cast(u8*, item))
        return
    }
    state.intelligence_next_id += 1
    if state.intelligence_result_tail { state.intelligence_result_tail.next = item }
    else { state.intelligence_results = item }
    state.intelligence_result_tail = item
    state.intelligence_result_count += 1

    let display = IDE:App:intelligence_result_display(state, path, line, role, label)
    let id = IDE:App:history_u64_text(item.id)
    if display && id {
        let row = Gui:tree_append(state.intelligence_tree, cast(u8*, 0), display, id, 0)
        Gui:tree_iter_free(row)
    }
    if display { free(display) }
    if id { free(id) }
}

let IDE:App:intelligence_parse = fn (state:IDE:App:State*, response:u8*) -> void {
    IDE:App:intelligence_free_results(state)
    if !state || !response { return }
    var line:i64 = 0
    while response[line] != 0 {
        let line_end = IDE:App:find_byte(response, line, 10)
        if response[line] == 76 && response[line + 1] == 9 { // L\t path start end line role label
            let f1 = IDE:App:find_byte(response, line + 2, 9)
            let f2 = IDE:App:find_byte(response, f1 + 1, 9)
            let f3 = IDE:App:find_byte(response, f2 + 1, 9)
            let f4 = IDE:App:find_byte(response, f3 + 1, 9)
            let f5 = IDE:App:find_byte(response, f4 + 1, 9)
            if f1 < line_end && f2 < line_end && f3 < line_end && f4 < line_end && f5 < line_end {
                let path = IDE:App:decode_hex(response, line + 2, f1)
                let start = IDE:App:parse_decimal(response, f1 + 1, f2)
                let finish = IDE:App:parse_decimal(response, f2 + 1, f3)
                let source_line = IDE:App:parse_decimal(response, f3 + 1, f4)
                let role = IDE:App:parse_decimal(response, f4 + 1, f5)
                let label = IDE:App:decode_hex(response, f5 + 1, line_end)
                if path && start >= 0 && finish >= start && source_line > 0 && role > 0 {
                    IDE:App:intelligence_add_result(state, path, cast(u64, start), cast(u64, finish), cast(u64, source_line), role, label, cast(u8*, 0), 0)
                }
                if path { free(path) }
                if label { free(label) }
            }
        } else if response[line] == 67 && response[line + 1] == 9 { // C\t start end label insert kind docs
            let f1 = IDE:App:find_byte(response, line + 2, 9)
            let f2 = IDE:App:find_byte(response, f1 + 1, 9)
            let f3 = IDE:App:find_byte(response, f2 + 1, 9)
            let f4 = IDE:App:find_byte(response, f3 + 1, 9)
            let f5 = IDE:App:find_byte(response, f4 + 1, 9)
            if f1 < line_end && f2 < line_end && f3 < line_end && f4 < line_end && f5 < line_end {
                let start = IDE:App:parse_decimal(response, line + 2, f1)
                let finish = IDE:App:parse_decimal(response, f1 + 1, f2)
                let label = IDE:App:decode_hex(response, f2 + 1, f3)
                let insert = IDE:App:decode_hex(response, f3 + 1, f4)
                let kind = IDE:App:decode_hex(response, f4 + 1, f5)
                let docs = IDE:App:decode_hex(response, f5 + 1, line_end)
                let display = LanguageKit:Text:new()
                if display {
                    if label { display.append(label) }
                    if kind && kind[0] != 0 { display.append("  ·  "); display.append(kind) }
                    if docs && docs[0] != 0 { display.append("  ·  "); display.append(docs) }
                    let value = display.take()
                    display.destroy()
                    if start >= 0 && finish >= start && value {
                        IDE:App:intelligence_add_result(state, state.host.selected, cast(u64, start), cast(u64, finish), 0, 1, value, insert, 1)
                    }
                    if value { free(value) }
                }
                if label { free(label) }
                if insert { free(insert) }
                if kind { free(kind) }
                if docs { free(docs) }
            }
        } else if response[line] == 71 && response[line + 1] == 9 { // G\t signature docs
            let f1 = IDE:App:find_byte(response, line + 2, 9)
            if f1 < line_end {
                let label = IDE:App:decode_hex(response, line + 2, f1)
                let docs = IDE:App:decode_hex(response, f1 + 1, line_end)
                let display = LanguageKit:Text:new()
                if display {
                    if label { display.append(label) }
                    if docs && docs[0] != 0 { display.append("  ·  "); display.append(docs) }
                    let value = display.take()
                    display.destroy()
                    if value { IDE:App:intelligence_add_result(state, cast(u8*, 0), 0, 0, 0, 1, value, cast(u8*, 0), 0); free(value) }
                }
                if label { free(label) }
                if docs { free(docs) }
            }
        } else if response[line] == 69 && response[line + 1] == 9 { // E\t
            let error = IDE:App:decode_hex(response, line + 2, line_end)
            if error { IDE:App:intelligence_set_status(state, error); free(error) }
        }
        if response[line_end] == 0 { break }
        line = line_end + 1
    }
}

let IDE:App:intelligence_cursor = fn (state:IDE:App:State*) -> u64 {
    var insert:i64 = 0
    var bound:i64 = 0
    IDE:App:find_selection_chars(state, &insert, &bound)
    if insert < 0 { return 0 }
    return cast(u64, insert)
}

let IDE:App:intelligence_query_current = fn (state:IDE:App:State*, operation:u8*, argument:u8*) -> u8* {
    if !state || !state.host || !state.host.selected || !state.editor || !operation { return cast(u8*, 0) }
    let source = IDE:App:editor_text(state)
    if !source { return cast(u8*, 0) }
    var query_argument:u8* = ""
    if argument { query_argument = argument }
    let response = IDE:Analysis:query(state, operation, state.host.selected, source,
                                          IDE:App:intelligence_cursor(state), query_argument)
    Gui:text_free(source)
    if state.host.intelligence { IDE:App:terminal_refresh_runtime(state, state.host.intelligence) }
    return response
}

let IDE:App:show_intelligence = fn (state:IDE:App:State*) -> void {
    if !state || !state.sidebar_stack || !state.intelligence_pane { return }
    state.history_visible = 0
    state.search_visible = 0
    state.intelligence_visible = 1
    Gui:stack_select(state.sidebar_stack, state.intelligence_pane)
}

let IDE:App:intelligence_run = fn (state:IDE:App:State*, operation:u8*, title:u8*, argument:u8*, show:i64) -> i64 {
    if !state { return 0 }
    if title { IDE:App:intelligence_set_status(state, title) }
    let response = IDE:App:intelligence_query_current(state, operation, argument)
    if !response { IDE:App:intelligence_set_status(state, "semantic query failed"); return 0 }
    IDE:App:intelligence_parse(state, response)
    free(response)
    if state.intelligence_result_count == 0 && title { IDE:App:intelligence_set_status(state, "no results") }
    if show != 0 { IDE:App:show_intelligence(state) }
    return cast(i64, state.intelligence_result_count)
}

let IDE:App:intelligence_navigate = fn (state:IDE:App:State*, result:IDE:App:IntelligenceResult*) -> void {
    if !state || !result || !result.path { return }
    let path = IDE:copy(result.path)
    if !path { return }
    if !state.host || !state.host.selected || strcmp(state.host.selected, path) != 0 { IDE:App:open_path(state, path) }
    free(path)
    let text = IDE:App:editor_text(state)
    if !text { return }
    let start = IDE:App:find_char_to_byte(text, cast(i64, result.start))
    let finish = IDE:App:find_char_to_byte(text, cast(i64, result.finish))
    IDE:App:find_select(state, text, start, finish)
    Gui:text_free(text)
}

let IDE:App:intelligence_replace_chars = fn (text:u8*, start:u64, finish:u64, replacement:u8*) -> u8* {
    if !text || !replacement || finish < start { return cast(u8*, 0) }
    let begin_byte = IDE:App:find_char_to_byte(text, cast(i64, start))
    let end_byte = IDE:App:find_char_to_byte(text, cast(i64, finish))
    let bytes = cast(u64, strlen(text))
    if begin_byte > end_byte || end_byte > bytes { return cast(u8*, 0) }
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    IDE:append_bytes(out, text, cast(i64, begin_byte))
    out.append(replacement)
    if end_byte < bytes { IDE:append_bytes(out, &text[end_byte], cast(i64, bytes - end_byte)) }
    let result = out.take()
    out.destroy()
    return result
}

let IDE:App:intelligence_rename_spelling = fn (old:u8*, next:u8*) -> u8* {
    if !next { return cast(u8*, 0) }
    var new_has_colon:i64 = 0
    var i:u64 = 0
    while next[i] != 0 { if next[i] == 58 { new_has_colon = 1 }; i += 1 }
    if new_has_colon != 0 || !old { return IDE:copy(next) }
    var last:i64 = -1
    i = 0
    while old[i] != 0 { if old[i] == 58 { last = cast(i64, i) }; i += 1 }
    if last < 0 { return IDE:copy(next) }
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    IDE:append_bytes(out, old, last + 1)
    out.append(next)
    let result = out.take()
    out.destroy()
    return result
}

let IDE:App:intelligence_temp_path = fn (path:u8*) -> u8* {
    if !path { return cast(u8*, 0) }
    var suffix:u64 = 0
    while suffix < 1024 {
        let out = LanguageKit:Text:new()
        if !out { return cast(u8*, 0) }
        out.append(path)
        out.append(".recurloop-rename.tmp")
        if suffix != 0 { out.append("."); IDE:append_u64(out, suffix) }
        let result = out.take()
        out.destroy()
        if result && !IDE:path_exists(result) { return result }
        if result { free(result) }
        suffix += 1
    }
    return cast(u8*, 0)
}

let IDE:App:intelligence_free_rename_files = fn (files:IDE:App:RenameFile*, remove_temporary:i64) -> void {
    var file = files
    while file {
        let next = file.next
        if remove_temporary != 0 && file.temporary { IDE:remove_path(file.temporary) }
        if file.path { free(file.path) }
        if file.temporary { free(file.temporary) }
        if file.text { free(file.text) }
        free(cast(u8*, file))
        file = next
    }
}

let IDE:App:intelligence_prepare_rename = fn (state:IDE:App:State*, name:u8*) -> IDE:App:RenameFile* {
    if !state || !name || name[0] == 0 { return cast(IDE:App:RenameFile*, 0) }
    var head = cast(IDE:App:RenameFile*, 0)
    var tail = cast(IDE:App:RenameFile*, 0)
    var item = state.intelligence_results
    while item {
        if !item.path { item = item.next; continue }
        let path = item.path
        var source:u8* = cast(u8*, 0)
        if state.host && state.host.selected && strcmp(state.host.selected, path) == 0 {
            let editor = IDE:App:editor_text(state)
            if editor { source = IDE:copy(editor); Gui:text_free(editor) }
        } else { source = IDE:read_file(path) }
        if !source { IDE:App:intelligence_free_rename_files(head, 1); return cast(IDE:App:RenameFile*, 0) }

        // Backend returns locations descending within each path. Apply every
        // edit for this file before moving to the next one, so earlier offsets
        // remain valid regardless of replacement length.
        var cursor = item
        while cursor && cursor.path && strcmp(cursor.path, path) == 0 {
            let spelling = IDE:App:intelligence_rename_spelling(cursor.label, name)
            var changed:u8* = cast(u8*, 0)
            if spelling { changed = IDE:App:intelligence_replace_chars(source, cursor.start, cursor.finish, spelling) }
            if spelling { free(spelling) }
            if !changed { free(source); IDE:App:intelligence_free_rename_files(head, 1); return cast(IDE:App:RenameFile*, 0) }
            free(source)
            source = changed
            cursor = cursor.next
        }

        let pending = alloc(IDE:App:RenameFile)
        if !pending { free(source); IDE:App:intelligence_free_rename_files(head, 1); return cast(IDE:App:RenameFile*, 0) }
        pending.path = IDE:copy(path)
        pending.temporary = IDE:App:intelligence_temp_path(path)
        pending.text = source
        pending.next = cast(IDE:App:RenameFile*, 0)
        if !pending.path || !pending.temporary {
            if pending.path { free(pending.path) }
            if pending.temporary { free(pending.temporary) }
            free(source); free(cast(u8*, pending)); IDE:App:intelligence_free_rename_files(head, 1)
            return cast(IDE:App:RenameFile*, 0)
        }
        if tail { tail.next = pending } else { head = pending }
        tail = pending
        item = cursor
    }
    return head
}

let IDE:App:intelligence_commit_rename = fn (state:IDE:App:State*, files:IDE:App:RenameFile*) -> i64 {
    if !state || !files { return 0 }
    var file = files
    while file {
        if !IDE:write_file(file.temporary, file.text) {
            IDE:App:intelligence_free_rename_files(files, 1)
            return 0
        }
        file = file.next
    }
    file = files
    while file {
        if !IDE:replace_path(file.temporary, file.path) {
            IDE:App:intelligence_free_rename_files(files, 1)
            return 0
        }
        file = file.next
    }
    file = files
    while file {
        if state.host && state.host.selected && strcmp(state.host.selected, file.path) == 0 {
            state.history_replaying = 1
            Gui:text_set(state.editor, file.text)
            state.history_replaying = 0
            IDE:App:history_mark_saved(state, file.text)
            IDE:App:schedule_semantics(state)
        }
        file = file.next
    }
    IDE:App:intelligence_free_rename_files(files, 0)
    return 1
}

let IDE:App:intelligence_selected = fn (state:IDE:App:State*) -> IDE:App:IntelligenceResult* {
    if !state || !state.intelligence_tree { return cast(IDE:App:IntelligenceResult*, 0) }
    let selection = Gui:tree_selection(state.intelligence_tree)
    let iterator = Gui:tree_selected_iter(selection)
    if !iterator { return cast(IDE:App:IntelligenceResult*, 0) }
    var directory:i32 = 0
    var loaded:i32 = 0
    let id_text = Gui:tree_iter_path(state.intelligence_tree, iterator, &directory, &loaded)
    Gui:tree_iter_free(iterator)
    if !id_text { return cast(IDE:App:IntelligenceResult*, 0) }
    let id = IDE:App:history_parse_u64(id_text)
    Gui:text_free(id_text)
    return IDE:App:intelligence_result_find(state, id)
}

let IDE:App:on_intelligence_selected = fn (selection:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    let result = IDE:App:intelligence_selected(state)
    if !state || !result { return }
    if result.completion != 0 && result.insert {
        let text = IDE:App:editor_text(state)
        if !text { return }
        let changed = IDE:App:intelligence_replace_chars(text, result.start, result.finish, result.insert)
        Gui:text_free(text)
        if changed {
            Gui:text_set(state.editor, changed)
            let added = IDE:App:find_byte_to_char(result.insert, cast(u64, strlen(result.insert)))
            IDE:App:find_select_chars(state, cast(i64, result.start) + added, cast(i64, result.start) + added)
            free(changed)
        }
        return
    }
    IDE:App:intelligence_navigate(state, result)
}

let IDE:App:on_go_definition = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if IDE:App:intelligence_run(state, "definition", "Go to Definition", "", 0) > 0 {
        IDE:App:intelligence_navigate(state, state.intelligence_results)
    } else { IDE:App:show_intelligence(state) }
}

let IDE:App:on_find_references = fn (widget:u8*, data:u8*) -> void {
    IDE:App:intelligence_run(cast(IDE:App:State*, data), "references", "References", "", 1)
}

let IDE:App:on_type_definition = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if IDE:App:intelligence_run(state, "type-definition", "Type Definition", "", 0) > 0 {
        IDE:App:intelligence_navigate(state, state.intelligence_results)
    } else { IDE:App:show_intelligence(state) }
}

let IDE:App:on_rename_symbol = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    let name = Gui:prompt(state.host.window, "Rename Symbol", "New symbol name", "")
    if !name || name[0] == 0 { if name { free(name) }; return }
    if IDE:App:intelligence_run(state, "rename", "Rename Symbol", name, 0) <= 0 { free(name); IDE:App:show_intelligence(state); return }
    let files = IDE:App:intelligence_prepare_rename(state, name)
    free(name)
    if !files { IDE:App:intelligence_set_status(state, "rename validation failed"); IDE:App:show_intelligence(state); return }
    let count = state.intelligence_result_count
    if IDE:App:intelligence_commit_rename(state, files) {
        let status = LanguageKit:Text:new()
        if status { status.append("renamed "); IDE:append_u64(status, count); status.append(" occurrences"); IDE:App:intelligence_set_status(state, status.data); status.destroy() }
    } else { IDE:App:intelligence_set_status(state, "rename write failed") }
    IDE:App:show_intelligence(state)
}

let IDE:App:on_document_symbols = fn (widget:u8*, data:u8*) -> void {
    IDE:App:intelligence_run(cast(IDE:App:State*, data), "document-symbols", "Document Symbols", "", 1)
}

let IDE:App:on_workspace_symbols = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    var query:u8* = ""
    if state && state.intelligence_input { query = Gui:input_text(state.intelligence_input) }
    IDE:App:intelligence_run(state, "workspace-symbols", "Workspace Symbols", query, 1)
}

let IDE:App:on_workspace_symbols_command = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    IDE:App:show_intelligence(state)
    IDE:App:intelligence_set_status(state, "workspace symbols")
    if state.intelligence_input { Gui:focus(state.intelligence_input) }
}

let IDE:App:on_incoming_calls = fn (widget:u8*, data:u8*) -> void {
    IDE:App:intelligence_run(cast(IDE:App:State*, data), "incoming-calls", "Incoming Calls", "", 1)
}

let IDE:App:on_outgoing_calls = fn (widget:u8*, data:u8*) -> void {
    IDE:App:intelligence_run(cast(IDE:App:State*, data), "outgoing-calls", "Outgoing Calls", "", 1)
}

let IDE:App:on_implementations = fn (widget:u8*, data:u8*) -> void {
    IDE:App:intelligence_run(cast(IDE:App:State*, data), "implementations", "Implementations", "", 1)
}

let IDE:App:on_prototype_hierarchy = fn (widget:u8*, data:u8*) -> void {
    IDE:App:intelligence_run(cast(IDE:App:State*, data), "prototype-hierarchy", "Prototype Hierarchy", "", 1)
}

let IDE:App:on_completion = fn (widget:u8*, data:u8*) -> void {
    IDE:App:intelligence_run(cast(IDE:App:State*, data), "completion", "Completion", "", 1)
}

let IDE:App:on_signature_help = fn (widget:u8*, data:u8*) -> void {
    IDE:App:intelligence_run(cast(IDE:App:State*, data), "signature", "Signature Help", "", 1)
}

// Editor language actions live in the native text-view context menu, matching
// the interaction model of a normal IDE instead of occupying permanent toolbar
// space. GtkTextView keeps its own Cut/Copy/Paste entries; these are appended as
// a separate language-navigation section.
let IDE:App:on_editor_context_menu = fn (widget:u8*, menu:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !menu { return }

    // GtkTextView creates the standard edit actions itself. Styling the menu
    // root lets the GUI backend theme both those native entries and the
    // RecurLoop language actions as one coherent VS Code-like popup.
    Gui:class_add(menu, "ide-context-menu")

    Gui:menu_separator(menu)
    Gui:menu_action(menu, "Go to Definition  (F12)", IDE:App:on_go_definition, data)
    Gui:menu_action(menu, "Go to Type Definition", IDE:App:on_type_definition, data)
    Gui:menu_action(menu, "Go to Implementations", IDE:App:on_implementations, data)
    Gui:menu_action(menu, "Find All References  (Shift+F12)", IDE:App:on_find_references, data)

    Gui:menu_separator(menu)
    Gui:menu_action(menu, "Rename Symbol…  (F2)", IDE:App:on_rename_symbol, data)

    Gui:menu_separator(menu)
    Gui:menu_action(menu, "Show Incoming Calls", IDE:App:on_incoming_calls, data)
    Gui:menu_action(menu, "Show Outgoing Calls", IDE:App:on_outgoing_calls, data)
    Gui:menu_action(menu, "Show Prototype Hierarchy", IDE:App:on_prototype_hierarchy, data)

    Gui:menu_separator(menu)
    Gui:menu_action(menu, "Trigger Completion  (Ctrl+Space)", IDE:App:on_completion, data)
    Gui:menu_action(menu, "Signature Help", IDE:App:on_signature_help, data)

    Gui:menu_separator(menu)
    Gui:menu_action(menu, "Document Symbols  (Ctrl+Shift+O)", IDE:App:on_document_symbols, data)
    Gui:menu_action(menu, "Workspace Symbols  (Ctrl+T)", IDE:App:on_workspace_symbols_command, data)
    Gui:show(menu)
}

// Semantic shortcuts are handled directly by the editor so the corresponding
// actions do not need fake/hidden toolbar buttons merely to own accelerators.
let IDE:App:on_editor_intelligence_key = fn (widget:u8*, event:u8*, data:u8*) -> i32 {
    let key = Gui:event_key(event)
    let modifiers = Gui:event_modifiers(event)
    let shift = modifiers % 2 != 0
    let control = (modifiers / 4) % 2 != 0

    if key == 65481 { // F12
        if shift { IDE:App:on_find_references(widget, data) }
        else { IDE:App:on_go_definition(widget, data) }
        return 1
    }
    if key == Gui:Key:F2() {
        IDE:App:on_rename_symbol(widget, data)
        return 1
    }
    if control && key == 32 {
        IDE:App:on_completion(widget, data)
        return 1
    }
    if control && shift && (key == 111 || key == 79) { // Ctrl+Shift+O
        IDE:App:on_document_symbols(widget, data)
        return 1
    }
    if control && (key == 116 || key == 84) { // Ctrl+T
        IDE:App:on_workspace_symbols_command(widget, data)
        return 1
    }
    return 0
}

let IDE:App:create_intelligence_view = fn (state:IDE:App:State*) -> u8* {
    let pane = Gui:column(0)
    Gui:class_add(pane, "explorer-pane")
    let header = Gui:row(0)
    Gui:class_add(header, "explorer-header")
    Gui:align_top(header)
    Gui:expand_x(header, 1)
    let title = Gui:label("INTELLIGENCE")
    Gui:label_align(title, cast(f32, 0.0))
    Gui:class_add(title, "explorer-title")
    Gui:append(header, title, 1, 0)
    let document = Gui:icon_button("view-list-symbolic", "Document Symbols (Ctrl+Shift+O)")
    let explorer = Gui:icon_button("folder-symbolic", "Back to Explorer")
    Gui:on_click(document, IDE:App:on_document_symbols, cast(u8*, state))
    Gui:on_click(explorer, IDE:App:on_show_explorer, cast(u8*, state))
    Gui:append_end(header, explorer, 0, 2)
    Gui:append_end(header, document, 0, 0)
    Gui:append(pane, header, 0, 0)

    let query_row = Gui:row(4)
    state.intelligence_input = Gui:input("Search workspace symbols")
    Gui:on_activate(state.intelligence_input, IDE:App:on_workspace_symbols, cast(u8*, state))
    Gui:append(query_row, state.intelligence_input, 1, 4)
    let workspace = Gui:icon_button("edit-find-symbolic", "Search Workspace Symbols (Ctrl+T)")
    Gui:on_click(workspace, IDE:App:on_workspace_symbols, cast(u8*, state))
    Gui:append_end(query_row, workspace, 0, 2)
    Gui:append(pane, query_row, 0, 2)

    state.intelligence_status = Gui:label("No results")
    Gui:label_align(state.intelligence_status, cast(f32, 0.0))
    Gui:class_add(state.intelligence_status, "explorer-root")
    Gui:append(pane, state.intelligence_status, 0, 0)

    state.intelligence_tree = Gui:tree()
    Gui:on_tree_select(state.intelligence_tree, IDE:App:on_intelligence_selected, cast(u8*, state))
    Gui:append(pane, Gui:scroll(state.intelligence_tree), 1, 0)
    state.intelligence_pane = pane
    return pane
}
