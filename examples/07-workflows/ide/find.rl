// Source-defined find bar. It intentionally stays in the project view rather
// than ide.rli so matching policy and controls hot-reload with the IDE itself.

link shared "gtk-3"
link shared "glib-2.0"

extern gtk_widget_hide(widget:u8*) -> void abi sysv-amd64
extern gtk_widget_set_no_show_all(widget:u8*, no_show_all:i32) -> void abi sysv-amd64
extern gtk_text_buffer_select_range(buffer:u8*, insert:u8*, bound:u8*) -> void abi sysv-amd64
extern gtk_text_buffer_get_insert(buffer:u8*) -> u8* abi sysv-amd64
extern gtk_text_buffer_get_selection_bound(buffer:u8*) -> u8* abi sysv-amd64
extern gtk_text_buffer_get_iter_at_mark(buffer:u8*, iterator:u8*, mark:u8*) -> void abi sysv-amd64
extern gtk_button_set_label(button:u8*, label:u8*) -> void abi sysv-amd64
extern g_regex_new(pattern:u8*, compile_options:i32, match_options:i32, error:u8**) -> u8* abi sysv-amd64
extern g_regex_match_full(regex:u8*, text:u8*, text_bytes:i64, start:i32, match_options:i32, info:u8**, error:u8**) -> i32 abi sysv-amd64
extern g_match_info_fetch_pos(info:u8*, match:i32, start:i32*, finish:i32*) -> i32 abi sysv-amd64
extern g_match_info_next(info:u8*, error:u8**) -> i32 abi sysv-amd64
extern g_match_info_free(info:u8*) -> void abi sysv-amd64
extern g_regex_unref(regex:u8*) -> void abi sysv-amd64

let IDE:App:find_ascii_lower = fn (value:u8) -> u8 {
    if value >= 65 && value <= 90 { return value + 32 }
    return value
}

let IDE:App:find_equal_byte = fn (left:u8, right:u8, case_sensitive:i64) -> i64 {
    if case_sensitive != 0 { return left == right }
    return IDE:App:find_ascii_lower(left) == IDE:App:find_ascii_lower(right)
}

let IDE:App:find_is_whitespace = fn (value:u8) -> i64 {
    return value == 32 || value == 9 || value == 10 || value == 13 || value == 11 || value == 12
}

let IDE:App:find_is_delimiter = fn (value:u8) -> i64 {
    if value == 0 || IDE:App:find_is_whitespace(value) { return 1 }
    if value == 40 || value == 41 || value == 91 || value == 93 || value == 123 || value == 125 { return 1 }
    if value == 44 || value == 46 || value == 58 || value == 59 { return 1 }
    if value == 43 || value == 45 || value == 42 || value == 47 || value == 37 { return 1 }
    if value == 61 || value == 60 || value == 62 || value == 33 || value == 38 || value == 124 { return 1 }
    if value == 94 || value == 126 || value == 63 { return 1 }
    return 0
}

let IDE:App:find_boundary_ok = fn (text:u8*, text_bytes:u64, start:u64, finish:u64, mode:i64) -> i64 {
    if mode == 0 { return 1 }
    var left_ok:i64 = start == 0
    var right_ok:i64 = finish >= text_bytes
    if !left_ok {
        if mode == 1 { left_ok = IDE:App:find_is_delimiter(text[start - 1]) }
        else { left_ok = IDE:App:find_is_whitespace(text[start - 1]) }
    }
    if !right_ok {
        if mode == 1 { right_ok = IDE:App:find_is_delimiter(text[finish]) }
        else { right_ok = IDE:App:find_is_whitespace(text[finish]) }
    }
    return left_ok && right_ok
}

let IDE:App:find_match_at = fn (text:u8*, text_bytes:u64, needle:u8*, needle_bytes:u64, at:u64, case_sensitive:i64, boundary:i64) -> i64 {
    if at + needle_bytes > text_bytes { return 0 }
    var i:u64 = 0
    while i < needle_bytes {
        if !IDE:App:find_equal_byte(text[at + i], needle[i], case_sensitive) { return 0 }
        i += 1
    }
    return IDE:App:find_boundary_ok(text, text_bytes, at, at + needle_bytes, boundary)
}

let IDE:App:find_plain_next = fn (text:u8*, needle:u8*, from:u64, case_sensitive:i64, boundary:i64, start:u64*, finish:u64*) -> i64 {
    if !text || !needle || !start || !finish || needle[0] == 0 { return 0 }
    let text_bytes = cast(u64, strlen(text))
    let needle_bytes = cast(u64, strlen(needle))
    if needle_bytes == 0 || needle_bytes > text_bytes { return 0 }
    if from > text_bytes { from = text_bytes }
    var at = from
    while at + needle_bytes <= text_bytes {
        if IDE:App:find_match_at(text, text_bytes, needle, needle_bytes, at, case_sensitive, boundary) {
            start[0] = at; finish[0] = at + needle_bytes; return 1
        }
        at += 1
    }
    at = 0
    while at < from && at + needle_bytes <= text_bytes {
        if IDE:App:find_match_at(text, text_bytes, needle, needle_bytes, at, case_sensitive, boundary) {
            start[0] = at; finish[0] = at + needle_bytes; return 1
        }
        at += 1
    }
    return 0
}

let IDE:App:find_plain_previous = fn (text:u8*, needle:u8*, from:u64, case_sensitive:i64, boundary:i64, start:u64*, finish:u64*) -> i64 {
    if !text || !needle || !start || !finish || needle[0] == 0 { return 0 }
    let text_bytes = cast(u64, strlen(text))
    let needle_bytes = cast(u64, strlen(needle))
    if needle_bytes == 0 || needle_bytes > text_bytes { return 0 }
    if from > text_bytes { from = text_bytes }

    var best:u64 = 0
    var found:i64 = 0
    var at:u64 = 0
    while at < from && at + needle_bytes <= text_bytes {
        if IDE:App:find_match_at(text, text_bytes, needle, needle_bytes, at, case_sensitive, boundary) {
            best = at; found = 1
        }
        at += 1
    }
    if !found {
        at = from
        while at + needle_bytes <= text_bytes {
            if IDE:App:find_match_at(text, text_bytes, needle, needle_bytes, at, case_sensitive, boundary) {
                best = at; found = 1
            }
            at += 1
        }
    }
    if found { start[0] = best; finish[0] = best + needle_bytes }
    return found
}

let IDE:App:find_regex_next = fn (text:u8*, pattern:u8*, from:u64, case_sensitive:i64, start:u64*, finish:u64*) -> i64 {
    if !text || !pattern || pattern[0] == 0 { return 0 }
    var flags:i32 = 0
    if case_sensitive == 0 { flags = 1 }
    let regex = g_regex_new(pattern, flags, 0, cast(u8**, 0))
    if !regex { return 0 }
    let text_bytes = cast(u64, strlen(text))
    if from > text_bytes { from = text_bytes }
    var info:u8* = cast(u8*, 0)
    var found = g_regex_match_full(regex, text, cast(i64, text_bytes), cast(i32, from), 0, &info, cast(u8**, 0))
    if found == 0 && from > 0 {
        if info { g_match_info_free(info); info = cast(u8*, 0) }
        found = g_regex_match_full(regex, text, cast(i64, text_bytes), 0, 0, &info, cast(u8**, 0))
    }
    if found != 0 && info {
        let a = alloc(i32)
        let b = alloc(i32)
        if a && b && g_match_info_fetch_pos(info, 0, a, b) != 0 && a[0] >= 0 && b[0] >= a[0] {
            start[0] = cast(u64, a[0]); finish[0] = cast(u64, b[0])
        } else { found = 0 }
        if a { free(cast(u8*, a)) }
        if b { free(cast(u8*, b)) }
    }
    if info { g_match_info_free(info) }
    g_regex_unref(regex)
    return found != 0
}

let IDE:App:find_regex_previous = fn (text:u8*, pattern:u8*, from:u64, case_sensitive:i64, start:u64*, finish:u64*) -> i64 {
    if !text || !pattern || pattern[0] == 0 { return 0 }
    var flags:i32 = 0
    if case_sensitive == 0 { flags = 1 }
    let regex = g_regex_new(pattern, flags, 0, cast(u8**, 0))
    if !regex { return 0 }
    let text_bytes = cast(u64, strlen(text))
    if from > text_bytes { from = text_bytes }
    var info:u8* = cast(u8*, 0)
    var found = g_regex_match_full(regex, text, cast(i64, text_bytes), 0, 0, &info, cast(u8**, 0))
    var have:i64 = 0
    var best_start:u64 = 0
    var best_finish:u64 = 0
    if found != 0 && info {
        let a = alloc(i32)
        let b = alloc(i32)
        if a && b {
            var keep:i64 = 1
            while keep != 0 {
                if g_match_info_fetch_pos(info, 0, a, b) != 0 && a[0] >= 0 && b[0] >= a[0] {
                    let current = cast(u64, a[0])
                    if current < from { best_start = current; best_finish = cast(u64, b[0]); have = 1 }
                }
                keep = g_match_info_next(info, cast(u8**, 0))
            }
        }
        if a { free(cast(u8*, a)) }
        if b { free(cast(u8*, b)) }
    }
    if !have {
        if info { g_match_info_free(info); info = cast(u8*, 0) }
        found = g_regex_match_full(regex, text, cast(i64, text_bytes), 0, 0, &info, cast(u8**, 0))
        if found != 0 && info {
            let a = alloc(i32)
            let b = alloc(i32)
            if a && b {
                var keep:i64 = 1
                while keep != 0 {
                    if g_match_info_fetch_pos(info, 0, a, b) != 0 && a[0] >= 0 && b[0] >= a[0] {
                        best_start = cast(u64, a[0]); best_finish = cast(u64, b[0]); have = 1
                    }
                    keep = g_match_info_next(info, cast(u8**, 0))
                }
            }
            if a { free(cast(u8*, a)) }
            if b { free(cast(u8*, b)) }
        }
    }
    if info { g_match_info_free(info) }
    g_regex_unref(regex)
    if have { start[0] = best_start; finish[0] = best_finish }
    return have
}

let IDE:App:find_byte_to_char = fn (text:u8*, byte_offset:u64) -> i64 {
    if !text { return 0 }
    var at:u64 = 0
    var chars:i64 = 0
    while text[at] != 0 && at < byte_offset {
        if text[at] < 128 || text[at] >= 192 { chars += 1 }
        at += 1
    }
    return chars
}

let IDE:App:find_char_to_byte = fn (text:u8*, char_offset:i64) -> u64 {
    if !text || char_offset <= 0 { return 0 }
    var at:u64 = 0
    var chars:i64 = 0
    while text[at] != 0 && chars < char_offset {
        if text[at] < 128 || text[at] >= 192 { chars += 1 }
        at += 1
    }
    return at
}

let IDE:App:find_advance_byte = fn (text:u8*, position:u64) -> u64 {
    if !text || text[position] == 0 { return position }
    var next = position + 1
    while text[next] != 0 && text[next] >= 128 && text[next] < 192 { next += 1 }
    return next
}

let IDE:App:find_cursor_byte = fn (state:IDE:App:State*, text:u8*) -> u64 {
    if !state || !state.editor || !text { return 0 }
    let buffer = gtk_text_view_get_buffer(state.editor)
    if !buffer { return 0 }
    let mark = gtk_text_buffer_get_insert(buffer)
    if !mark { return 0 }
    let iterator = cast(u8*, malloc(128))
    if !iterator { return 0 }
    gtk_text_buffer_get_iter_at_mark(buffer, iterator, mark)
    let chars = gtk_text_iter_get_offset(iterator)
    free(iterator)
    return IDE:App:find_char_to_byte(text, chars)
}

let IDE:App:find_select = fn (state:IDE:App:State*, text:u8*, start:u64, finish:u64) -> void {
    if !state || !state.editor || !text { return }
    let buffer = gtk_text_view_get_buffer(state.editor)
    if !buffer { return }
    let first = cast(u8*, malloc(128))
    let last = cast(u8*, malloc(128))
    if !first || !last { if first { free(first) }; if last { free(last) }; return }
    gtk_text_buffer_get_iter_at_offset(buffer, first, cast(i32, IDE:App:find_byte_to_char(text, start)))
    gtk_text_buffer_get_iter_at_offset(buffer, last, cast(i32, IDE:App:find_byte_to_char(text, finish)))
    // The insertion cursor is the first argument; keep it at the match end so
    // repeated Find Next starts after the current selection.
    gtk_text_buffer_select_range(buffer, last, first)
    gtk_text_view_scroll_to_iter(state.editor, first, cast(f64, 0.12), 0, cast(f64, 0.0), cast(f64, 0.0))
    free(first)
    free(last)
}

let IDE:App:find_selection_chars = fn (state:IDE:App:State*, insert_offset:i64*, bound_offset:i64*) -> void {
    if !state || !state.editor || !insert_offset || !bound_offset { return }
    let buffer = gtk_text_view_get_buffer(state.editor)
    if !buffer { return }
    let insert_mark = gtk_text_buffer_get_insert(buffer)
    let bound_mark = gtk_text_buffer_get_selection_bound(buffer)
    if !insert_mark || !bound_mark { return }
    let insert_iter = cast(u8*, malloc(128))
    let bound_iter = cast(u8*, malloc(128))
    if !insert_iter || !bound_iter {
        if insert_iter { free(insert_iter) }
        if bound_iter { free(bound_iter) }
        return
    }
    gtk_text_buffer_get_iter_at_mark(buffer, insert_iter, insert_mark)
    gtk_text_buffer_get_iter_at_mark(buffer, bound_iter, bound_mark)
    insert_offset[0] = cast(i64, gtk_text_iter_get_offset(insert_iter))
    bound_offset[0] = cast(i64, gtk_text_iter_get_offset(bound_iter))
    free(insert_iter)
    free(bound_iter)
}

let IDE:App:find_select_chars = fn (state:IDE:App:State*, insert_offset:i64, bound_offset:i64) -> void {
    if !state || !state.editor { return }
    let buffer = gtk_text_view_get_buffer(state.editor)
    if !buffer { return }
    let insert_iter = cast(u8*, malloc(128))
    let bound_iter = cast(u8*, malloc(128))
    if !insert_iter || !bound_iter {
        if insert_iter { free(insert_iter) }
        if bound_iter { free(bound_iter) }
        return
    }
    gtk_text_buffer_get_iter_at_offset(buffer, insert_iter, cast(i32, insert_offset))
    gtk_text_buffer_get_iter_at_offset(buffer, bound_iter, cast(i32, bound_offset))
    gtk_text_buffer_select_range(buffer, insert_iter, bound_iter)
    free(insert_iter)
    free(bound_iter)
}

let IDE:App:find_update_buttons = fn (state:IDE:App:State*) -> void {
    if !state { return }
    if state.find_case_button { if state.find_case_sensitive != 0 { gtk_button_set_label(state.find_case_button, "Aa*") } else { gtk_button_set_label(state.find_case_button, "Aa") } }
    if state.find_delimiter_button { if state.find_boundary == 1 { gtk_button_set_label(state.find_delimiter_button, "DELIM*") } else { gtk_button_set_label(state.find_delimiter_button, "DELIM") } }
    if state.find_whitespace_button { if state.find_boundary == 2 { gtk_button_set_label(state.find_whitespace_button, "WS*") } else { gtk_button_set_label(state.find_whitespace_button, "WS") } }
    if state.find_regex_button { if state.find_regex != 0 { gtk_button_set_label(state.find_regex_button, ".**") } else { gtk_button_set_label(state.find_regex_button, ".*") } }
}

let IDE:App:find_reset_match = fn (state:IDE:App:State*) -> void {
    if !state { return }
    state.find_last_start = -1
    state.find_last_finish = -1
}

let IDE:App:find_sync_query = fn (state:IDE:App:State*, query:u8*) -> void {
    if !state || !query { return }
    if state.find_query && strcmp(state.find_query, query) == 0 { return }
    if state.find_query { free(state.find_query) }
    state.find_query = IDE:copy(query)
    IDE:App:find_reset_match(state)
}

let IDE:App:find_run = fn (state:IDE:App:State*, direction:i64) -> void {
    if !state || !state.editor || !state.find_input { return }
    let query = Gui:input_text(state.find_input)
    if !query || query[0] == 0 { if state.find_status { Gui:label_text(state.find_status, "") }; return }
    IDE:App:find_sync_query(state, query)

    let text = Gui:text_get(state.editor)
    if !text { return }
    defer Gui:text_free(text)
    var from = IDE:App:find_cursor_byte(state, text)
    if direction > 0 && state.find_last_finish >= 0 {
        from = cast(u64, state.find_last_finish)
        if state.find_last_start == state.find_last_finish { from = IDE:App:find_advance_byte(text, from) }
    }
    if direction < 0 && state.find_last_start >= 0 { from = cast(u64, state.find_last_start) }

    let start = alloc(u64)
    let finish = alloc(u64)
    if !start || !finish { if start { free(cast(u8*, start)) }; if finish { free(cast(u8*, finish)) }; return }
    var found:i64 = 0
    if state.find_regex != 0 {
        if direction > 0 { found = IDE:App:find_regex_next(text, query, from, state.find_case_sensitive, start, finish) }
        else { found = IDE:App:find_regex_previous(text, query, from, state.find_case_sensitive, start, finish) }
    } else {
        if direction > 0 { found = IDE:App:find_plain_next(text, query, from, state.find_case_sensitive, state.find_boundary, start, finish) }
        else { found = IDE:App:find_plain_previous(text, query, from, state.find_case_sensitive, state.find_boundary, start, finish) }
    }

    if found {
        state.find_last_start = cast(i64, start[0])
        state.find_last_finish = cast(i64, finish[0])
        IDE:App:find_select(state, text, start[0], finish[0])
        if state.find_status {
            let label = LanguageKit:Text:new()
            if label {
                label.append("byte ")
                IDE:append_u64(label, start[0])
                Gui:label_text(state.find_status, label.data)
                label.destroy()
            }
        }
    } else {
        IDE:App:find_reset_match(state)
        if state.find_status { Gui:label_text(state.find_status, "no match") }
    }
    free(cast(u8*, start))
    free(cast(u8*, finish))
}


let IDE:App:find_replace_all_text = fn (text:u8*, query:u8*, replacement:u8*, case_sensitive:i64, boundary:i64, regex_mode:i64, count:u64*) -> u8* {
    if count { count[0] = 0 }
    if !text || !query || query[0] == 0 || !replacement { return IDE:copy(text) }
    let output = LanguageKit:Text:new()
    if !output { return cast(u8*, 0) }
    let text_bytes = cast(u64, strlen(text))
    var copied:u64 = 0

    if regex_mode != 0 {
        var flags:i32 = 0
        if case_sensitive == 0 { flags = 1 }
        let regex = g_regex_new(query, flags, 0, cast(u8**, 0))
        if !regex { output.destroy(); return cast(u8*, 0) }
        var info:u8* = cast(u8*, 0)
        let matched = g_regex_match_full(regex, text, cast(i64, text_bytes), 0, 0, &info, cast(u8**, 0))
        if matched != 0 && info {
            let a = alloc(i32)
            let b = alloc(i32)
            if a && b {
                var keep:i64 = 1
                while keep != 0 {
                    if g_match_info_fetch_pos(info, 0, a, b) != 0 && a[0] >= 0 && b[0] >= a[0] {
                        let start = cast(u64, a[0])
                        let finish = cast(u64, b[0])
                        if start >= copied {
                            IDE:append_bytes(output, &text[copied], cast(i64, start - copied))
                            output.append(replacement)
                            copied = finish
                            if count { count[0] += 1 }
                        }
                    }
                    keep = g_match_info_next(info, cast(u8**, 0))
                }
            }
            if a { free(cast(u8*, a)) }
            if b { free(cast(u8*, b)) }
        }
        if info { g_match_info_free(info) }
        g_regex_unref(regex)
    } else {
        let needle_bytes = cast(u64, strlen(query))
        var at:u64 = 0
        while needle_bytes > 0 && at + needle_bytes <= text_bytes {
            if IDE:App:find_match_at(text, text_bytes, query, needle_bytes, at, case_sensitive, boundary) {
                IDE:append_bytes(output, &text[copied], cast(i64, at - copied))
                output.append(replacement)
                at += needle_bytes
                copied = at
                if count { count[0] += 1 }
            } else { at += 1 }
        }
    }
    if copied < text_bytes { IDE:append_bytes(output, &text[copied], cast(i64, text_bytes - copied)) }
    let result = output.take()
    output.destroy()
    return result
}

let IDE:App:find_replace_current = fn (state:IDE:App:State*) -> void {
    if !state || !state.editor || !state.find_input || !state.find_replace_input { return }
    let query = Gui:input_text(state.find_input)
    if !query || query[0] == 0 { return }
    IDE:App:find_sync_query(state, query)
    if state.find_last_start < 0 || state.find_last_finish < state.find_last_start {
        IDE:App:find_run(state, 1)
    }
    if state.find_last_start < 0 || state.find_last_finish < state.find_last_start { return }
    var replacement = Gui:input_text(state.find_replace_input)
    if !replacement { replacement = "" }
    let text = IDE:App:editor_text(state)
    if !text { return }
    let start = cast(u64, state.find_last_start)
    let finish = cast(u64, state.find_last_finish)
    let bytes = cast(u64, strlen(text))
    if finish > bytes || start > finish { Gui:text_free(text); IDE:App:find_reset_match(state); return }
    let next = IDE:App:history_splice(text, start, finish - start, replacement, cast(u64, strlen(replacement)))
    Gui:text_free(text)
    if !next { return }
    Gui:text_set(state.editor, next)
    let replacement_bytes = cast(u64, strlen(replacement))
    state.find_last_start = cast(i64, start)
    state.find_last_finish = cast(i64, start + replacement_bytes)
    IDE:App:find_select(state, next, start, start + replacement_bytes)
    free(next)
    if state.find_status { Gui:label_text(state.find_status, "replaced") }
}

let IDE:App:find_replace_all = fn (state:IDE:App:State*) -> void {
    if !state || !state.editor || !state.find_input || !state.find_replace_input { return }
    let query = Gui:input_text(state.find_input)
    if !query || query[0] == 0 { return }
    var replacement = Gui:input_text(state.find_replace_input)
    if !replacement { replacement = "" }
    let text = IDE:App:editor_text(state)
    if !text { return }
    let count = alloc(u64)
    if !count { Gui:text_free(text); return }
    let next = IDE:App:find_replace_all_text(text, query, replacement, state.find_case_sensitive, state.find_boundary, state.find_regex, count)
    Gui:text_free(text)
    if next {
        if count[0] > 0 { Gui:text_set(state.editor, next) }
        IDE:App:find_reset_match(state)
        if state.find_status {
            let label = LanguageKit:Text:new()
            if label {
                IDE:append_u64(label, count[0])
                label.append(" replaced")
                Gui:label_text(state.find_status, label.data)
                label.destroy()
            }
        }
        free(next)
    } else if state.find_status { Gui:label_text(state.find_status, "invalid regex") }
    free(cast(u8*, count))
}

let IDE:App:on_find_replace = fn (widget:u8*, data:u8*) -> void { IDE:App:find_replace_current(cast(IDE:App:State*, data)) }
let IDE:App:on_find_replace_all = fn (widget:u8*, data:u8*) -> void { IDE:App:find_replace_all(cast(IDE:App:State*, data)) }

let IDE:App:on_find_next = fn (widget:u8*, data:u8*) -> void { IDE:App:find_run(cast(IDE:App:State*, data), 1) }
let IDE:App:on_find_previous = fn (widget:u8*, data:u8*) -> void { IDE:App:find_run(cast(IDE:App:State*, data), -1) }
let IDE:App:on_find_activate = fn (widget:u8*, data:u8*) -> void { IDE:App:find_run(cast(IDE:App:State*, data), 1) }

let IDE:App:on_find_case = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    state.find_case_sensitive = state.find_case_sensitive == 0
    IDE:App:find_reset_match(state)
    IDE:App:find_update_buttons(state)
}

let IDE:App:on_find_delimiter = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    if state.find_boundary == 1 { state.find_boundary = 0 } else { state.find_boundary = 1 }
    state.find_regex = 0
    IDE:App:find_reset_match(state)
    IDE:App:find_update_buttons(state)
}

let IDE:App:on_find_whitespace = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    if state.find_boundary == 2 { state.find_boundary = 0 } else { state.find_boundary = 2 }
    state.find_regex = 0
    IDE:App:find_reset_match(state)
    IDE:App:find_update_buttons(state)
}

let IDE:App:on_find_regex = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    state.find_regex = state.find_regex == 0
    if state.find_regex != 0 { state.find_boundary = 0 }
    IDE:App:find_reset_match(state)
    IDE:App:find_update_buttons(state)
}

let IDE:App:show_find = fn (state:IDE:App:State*) -> void {
    if !state || !state.find_bar { return }
    state.find_visible = 1
    gtk_widget_set_no_show_all(state.find_bar, 0)
    Gui:show(state.find_bar)
    if state.find_input { Gui:focus(state.find_input) }
}

let IDE:App:hide_find = fn (state:IDE:App:State*) -> void {
    if !state || !state.find_bar { return }
    state.find_visible = 0
    gtk_widget_set_no_show_all(state.find_bar, 1)
    gtk_widget_hide(state.find_bar)
    IDE:App:find_reset_match(state)
    if state.editor { Gui:focus(state.editor) }
}

let IDE:App:on_show_find = fn (widget:u8*, data:u8*) -> void { IDE:App:show_find(cast(IDE:App:State*, data)) }
let IDE:App:on_hide_find = fn (widget:u8*, data:u8*) -> void { IDE:App:hide_find(cast(IDE:App:State*, data)) }

let IDE:App:create_find_bar = fn (state:IDE:App:State*) -> u8* {
    let bar = Gui:column(0)
    Gui:class_add(bar, "ide-toolbar")
    state.find_bar = bar

    let query_row = Gui:row(4)
    state.find_input = Gui:input("Find")
    Gui:size(state.find_input, 220, -1)
    Gui:on_activate(state.find_input, IDE:App:on_find_activate, cast(u8*, state))
    Gui:append(query_row, state.find_input, 1, 6)

    state.find_case_button = Gui:button("Aa")
    state.find_delimiter_button = Gui:button("DELIM")
    state.find_whitespace_button = Gui:button("WS")
    state.find_regex_button = Gui:button(".*")
    Gui:class_add(state.find_case_button, "tool-button")
    Gui:class_add(state.find_delimiter_button, "tool-button")
    Gui:class_add(state.find_whitespace_button, "tool-button")
    Gui:class_add(state.find_regex_button, "tool-button")
    Gui:tooltip(state.find_case_button, "Case sensitive")
    Gui:tooltip(state.find_delimiter_button, "Require delimiter boundaries")
    Gui:tooltip(state.find_whitespace_button, "Require whitespace boundaries")
    Gui:tooltip(state.find_regex_button, "Regular expression")
    Gui:on_click(state.find_case_button, IDE:App:on_find_case, cast(u8*, state))
    Gui:on_click(state.find_delimiter_button, IDE:App:on_find_delimiter, cast(u8*, state))
    Gui:on_click(state.find_whitespace_button, IDE:App:on_find_whitespace, cast(u8*, state))
    Gui:on_click(state.find_regex_button, IDE:App:on_find_regex, cast(u8*, state))
    Gui:append_end(query_row, state.find_regex_button, 0, 0)
    Gui:append_end(query_row, state.find_whitespace_button, 0, 0)
    Gui:append_end(query_row, state.find_delimiter_button, 0, 0)
    Gui:append_end(query_row, state.find_case_button, 0, 0)

    let previous = Gui:icon_button("go-up-symbolic", "Previous match")
    let next = Gui:icon_button("go-down-symbolic", "Next match")
    let close = Gui:icon_button("window-close-symbolic", "Close Find")
    Gui:on_click(previous, IDE:App:on_find_previous, cast(u8*, state))
    Gui:on_click(next, IDE:App:on_find_next, cast(u8*, state))
    Gui:on_click(close, IDE:App:on_hide_find, cast(u8*, state))
    Gui:append_end(query_row, close, 0, 4)
    Gui:append_end(query_row, next, 0, 0)
    Gui:append_end(query_row, previous, 0, 0)
    Gui:append(bar, query_row, 0, 0)

    let replace_row = Gui:row(4)
    state.find_replace_input = Gui:input("Replace")
    Gui:size(state.find_replace_input, 260, -1)
    Gui:on_activate(state.find_replace_input, IDE:App:on_find_replace, cast(u8*, state))
    Gui:append(replace_row, state.find_replace_input, 1, 6)
    let replace = Gui:button("Replace")
    let replace_all = Gui:button("All")
    Gui:tooltip(replace, "Replace current match")
    Gui:tooltip(replace_all, "Replace all matches in current file")
    Gui:on_click(replace, IDE:App:on_find_replace, cast(u8*, state))
    Gui:on_click(replace_all, IDE:App:on_find_replace_all, cast(u8*, state))
    Gui:append_end(replace_row, replace_all, 0, 0)
    Gui:append_end(replace_row, replace, 0, 0)
    state.find_status = Gui:label("")
    Gui:label_align(state.find_status, cast(f32, 1.0))
    Gui:append_end(replace_row, state.find_status, 0, 4)
    Gui:append(bar, replace_row, 0, 0)

    gtk_widget_set_no_show_all(bar, 1)
    gtk_widget_hide(bar)
    return bar
}

// Project modules are cached as .rli images. Keep native symbols symbolic so
// a hot-reloaded module never persists process-local GTK/GLib addresses.
set gtk_widget_hide.serializable = false
set gtk_widget_set_no_show_all.serializable = false
set gtk_text_buffer_select_range.serializable = false
set gtk_text_buffer_get_insert.serializable = false
set gtk_text_buffer_get_selection_bound.serializable = false
set gtk_text_buffer_get_iter_at_mark.serializable = false
set gtk_button_set_label.serializable = false
set g_regex_new.serializable = false
set g_regex_match_full.serializable = false
set g_match_info_fetch_pos.serializable = false
set g_match_info_next.serializable = false
set g_match_info_free.serializable = false
set g_regex_unref.serializable = false
