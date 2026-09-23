let IDE:App:set_status = fn (state:IDE:App:State*, text:u8*) -> void {
    if state && state.status { Gui:label_text(state.status, text) }
}

let IDE:App:free_semantic_spans = fn (state:IDE:App:State*) -> void {
    if !state { return }
    var span = state.semantic_spans
    while span {
        let next = span.next
        free(cast(u8*, span))
        span = next
    }
    state.semantic_spans = cast(IDE:App:SemanticSpan*, 0)

    var hover = state.semantic_hovers
    while hover {
        let next = hover.next
        if hover.phrase { free(hover.phrase) }
        if hover.kind { free(hover.kind) }
        if hover.docs { free(hover.docs) }
        free(cast(u8*, hover))
        hover = next
    }
    state.semantic_hovers = cast(IDE:App:SemanticHover*, 0)
    state.semantic_hover_tail = cast(IDE:App:SemanticHover*, 0)
}

let IDE:App:free_semantic_styles = fn (state:IDE:App:State*) -> void {
    if !state { return }
    var style = state.semantic_styles
    while style {
        let next = style.next
        if style.color { free(style.color) }
        free(cast(u8*, style))
        style = next
    }
    state.semantic_styles = cast(IDE:App:SemanticStyle*, 0)
}

let IDE:App:hex_nibble = fn (value:u8) -> i64 {
    if value >= 48 && value <= 57 { return value - 48 }
    if value >= 97 && value <= 102 { return value - 97 + 10 }
    if value >= 65 && value <= 70 { return value - 65 + 10 }
    return -1
}

let IDE:App:decode_hex = fn (text:u8*, begin:i64, finish:i64) -> u8* {
    if !text || begin < 0 || finish < begin || ((finish - begin) % 2) != 0 { return cast(u8*, 0) }
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    var at = begin
    while at < finish {
        let high = IDE:App:hex_nibble(text[at])
        let low = IDE:App:hex_nibble(text[at + 1])
        if high < 0 || low < 0 { out.destroy(); return cast(u8*, 0) }
        if !out.append_byte(cast(u8, high * 16 + low)) { out.destroy(); return cast(u8*, 0) }
        at += 2
    }
    let result = out.take()
    out.destroy()
    return result
}

let IDE:App:parse_decimal = fn (text:u8*, begin:i64, finish:i64) -> i64 {
    if !text || begin >= finish { return -1 }
    var value:i64 = 0
    var at = begin
    while at < finish {
        let digit = text[at]
        if digit < 48 || digit > 57 { return -1 }
        value = value * 10 + digit - 48
        at += 1
    }
    return value
}

let IDE:App:find_byte = fn (text:u8*, begin:i64, value:u8) -> i64 {
    if !text || begin < 0 { return -1 }
    var at = begin
    while text[at] != 0 {
        if text[at] == value { return at }
        at += 1
    }
    return at
}

let IDE:App:semantic_style = fn (state:IDE:App:State*, color:u8*) -> u8* {
    if !state || !state.editor || !color || color[0] == 0 { return cast(u8*, 0) }
    var item = state.semantic_styles
    while item {
        if item.color && strcmp(item.color, color) == 0 { return item.tag }
        item = item.next
    }

    let style = alloc(IDE:App:SemanticStyle)
    if !style { return cast(u8*, 0) }
    style.color = IDE:copy(color)
    if !style.color { free(cast(u8*, style)); return cast(u8*, 0) }
    style.tag = Gui:text_style(state.editor, style.color, style.color)
    if !style.tag { free(style.color); free(cast(u8*, style)); return cast(u8*, 0) }
    style.next = state.semantic_styles
    state.semantic_styles = style
    return style.tag
}

let IDE:App:add_semantic_span = fn (state:IDE:App:State*, start:i64, finish:i64, color:u8*) -> void {
    if !state || start < 0 || finish <= start || !color || color[0] == 0 { return }
    let tag = IDE:App:semantic_style(state, color)
    if !tag { return }
    Gui:text_apply_style(state.editor, tag, start, finish)

    let span = alloc(IDE:App:SemanticSpan)
    if !span { return }
    span.start = start
    span.finish = finish
    span.next = state.semantic_spans
    state.semantic_spans = span
}

let IDE:App:add_semantic_hover = fn (state:IDE:App:State*, start:i64, finish:i64, group:i64, phrase:u8*, kind:u8*, docs:u8*) -> void {
    if !state || start < 0 || finish <= start || !docs || docs[0] == 0 { return }

    // Consecutive lexicon phrases that keep the same docs owner form one hover
    // region. Gaps are intentional: whitespace between those phrases belongs
    // to the same construct, so the tooltip does not flicker while crossing it.
    let previous = state.semantic_hover_tail
    if previous && previous.group == group && previous.phrase && phrase && previous.kind && kind && previous.docs &&
       strcmp(previous.phrase, phrase) == 0 && strcmp(previous.kind, kind) == 0 && strcmp(previous.docs, docs) == 0 &&
       start >= previous.finish {
        previous.finish = finish
        return
    }

    let hover = alloc(IDE:App:SemanticHover)
    if !hover { return }
    hover.start = start
    hover.finish = finish
    hover.group = group
    hover.phrase = IDE:copy(phrase)
    hover.kind = IDE:copy(kind)
    hover.docs = IDE:copy(docs)
    hover.next = cast(IDE:App:SemanticHover*, 0)
    if !hover.phrase || !hover.kind || !hover.docs {
        if hover.phrase { free(hover.phrase) }
        if hover.kind { free(hover.kind) }
        if hover.docs { free(hover.docs) }
        free(cast(u8*, hover))
        return
    }
    if state.semantic_hover_tail { state.semantic_hover_tail.next = hover }
    else { state.semantic_hovers = hover }
    state.semantic_hover_tail = hover
}

let IDE:App:semantic_parse = fn (state:IDE:App:State*, response:u8*) -> void {
    if !state || !response { return }
    if state.semantic_diagnostic { Gui:label_text(state.semantic_diagnostic, "") }
    var line:i64 = 0
    while response[line] != 0 {
        let line_end = IDE:App:find_byte(response, line, 10)
        if response[line] == 83 && response[line + 1] == 9 { // S\t
            let f1 = IDE:App:find_byte(response, line + 2, 9)
            let f2 = IDE:App:find_byte(response, f1 + 1, 9)
            let f3 = IDE:App:find_byte(response, f2 + 1, 9)
            let f4 = IDE:App:find_byte(response, f3 + 1, 9)
            let f5 = IDE:App:find_byte(response, f4 + 1, 9)
            let f6 = IDE:App:find_byte(response, f5 + 1, 9)
            if f1 < line_end && f2 < line_end && f3 < line_end && f4 < line_end && f5 < line_end && f6 < line_end {
                let start = IDE:App:parse_decimal(response, line + 2, f1)
                let finish = IDE:App:parse_decimal(response, f1 + 1, f2)
                let group = IDE:App:parse_decimal(response, f2 + 1, f3)
                let color = IDE:App:decode_hex(response, f3 + 1, f4)
                let kind = IDE:App:decode_hex(response, f4 + 1, f5)
                let docs = IDE:App:decode_hex(response, f5 + 1, f6)
                let phrase = IDE:App:decode_hex(response, f6 + 1, line_end)
                if start >= 0 && finish > start {
                    if color { IDE:App:add_semantic_span(state, start, finish, color) }
                    if docs { IDE:App:add_semantic_hover(state, start, finish, group, phrase, kind, docs) }
                }
                if color { free(color) }
                if kind { free(kind) }
                if docs { free(docs) }
                if phrase { free(phrase) }
            }
        } else if response[line] == 69 && response[line + 1] == 9 { // E\t
            let diagnostic = IDE:App:decode_hex(response, line + 2, line_end)
            if diagnostic {
                if state.semantic_diagnostic { Gui:label_text(state.semantic_diagnostic, diagnostic) }
                free(diagnostic)
            }
        }
        if response[line_end] == 0 { return }
        line = line_end + 1
    }
}

let IDE:App:semantic_analyze = fn (state:IDE:App:State*) -> void {
    if !state || !state.host || !state.editor || !state.host.selected { return }
    let source = IDE:App:editor_text(state)
    if !source { return }
    let response = IDE:intelligence_analyze(state.host, state.host.selected, source)
    Gui:text_free(source)
    if !response { return }

    IDE:App:free_semantic_spans(state)
    state.semantic_hover_tail = cast(IDE:App:SemanticHover*, 0)
    Gui:text_clear_styles(state.editor)
    IDE:App:semantic_parse(state, response)
    free(response)
}

let IDE:App:semantic_idle = fn (data:u8*) -> i32 {
    let state = cast(IDE:App:State*, data)
    if !state { return 0 }
    state.semantic_idle_source = 0
    IDE:App:semantic_analyze(state)
    return 0
}

let IDE:App:schedule_semantics = fn (state:IDE:App:State*) -> void {
    if !state || !state.editor || !state.host || !state.host.selected { return }
    // One deterministic main-loop turn coalesces GTK's burst of buffer change
    // signals. No time delay/debounce participates in semantic correctness.
    if state.semantic_idle_source == 0 {
        state.semantic_idle_source = Gui:idle(IDE:App:semantic_idle, cast(u8*, state))
    }
}

let IDE:App:on_editor_changed = fn (buffer:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    if state.history_replaying == 0 && state.history && state.host && state.host.selected {
        let text = IDE:App:editor_text(state)
        if text {
            IDE:App:history_capture(state, text)
            Gui:text_free(text)
        }
    }
    IDE:App:schedule_semantics(state)
}

let IDE:App:on_editor_tooltip = fn (widget:u8*, x:i32, y:i32, keyboard:i32, tooltip:u8*, data:u8*) -> i32 {
    let state = cast(IDE:App:State*, data)
    if !state || keyboard != 0 { return 0 }
    let offset = Gui:text_position_at(widget, x, y)
    if offset < 0 { return 0 }

    var best = cast(IDE:App:SemanticHover*, 0)
    var best_width:i64 = 0
    var hover = state.semantic_hovers
    while hover {
        if offset >= hover.start && offset < hover.finish {
            let width = hover.finish - hover.start
            if !best || width < best_width { best = hover; best_width = width }
        }
        hover = hover.next
    }
    if !best { return 0 }

    let text = LanguageKit:Text:new()
    if !text { return 0 }
    if best.phrase && best.phrase[0] != 0 { text.append(best.phrase) }
    if best.kind && best.kind[0] != 0 {
        if text.length > 0 { text.append("  ·  ") }
        text.append(best.kind)
    }
    if best.docs && best.docs[0] != 0 {
        if text.length > 0 { text.append("\n\n") }
        text.append(best.docs)
    }
    Gui:tooltip_text(tooltip, text.data)
    text.destroy()
    return 1
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

    let restored = IDE:App:history_open(state, selected, data)
    state.history_replaying = 1
    if restored { Gui:text_set(state.editor, restored) }
    else { Gui:text_set(state.editor, data) }
    state.history_replaying = 0
    if restored { free(restored) }
    state.history_needs_refresh = 1
    if state.history_visible != 0 { IDE:App:history_refresh(state) }
    IDE:App:find_reset_match(state)

    let relative = IDE:relative(state.host.root, selected)
    if relative { Gui:label_text(state.file_label, relative); free(relative) }
    IDE:App:schedule_semantics(state)
}

let IDE:App:on_save = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host || !state.host.selected { return }
    let text = IDE:App:editor_text(state)
    if !text { IDE:App:set_status(state, "cannot read editor buffer"); return }
    let ok = IDE:write_file(state.host.selected, text)
    if ok { IDE:App:history_mark_saved(state, text) }
    Gui:text_free(text)
    if ok {
        if IDE:view_reload_mode(state.host) == IDE:Reload:Hot() { IDE:App:set_status(state, "saved | hot reload pending") }
        else if IDE:view_reload_mode(state.host) == IDE:Reload:Manual() { IDE:App:set_status(state, "saved | reload available") }
        else { IDE:App:set_status(state, "saved") }
    } else { IDE:App:set_status(state, "save failed") }
}
