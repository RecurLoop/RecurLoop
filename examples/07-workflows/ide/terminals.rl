let IDE_App:terminal_render = fn (view:IDE_App:TerminalView*) -> void {
    if !view || !view.model || !view.output { return }
    let buffer = gtk_text_view_get_buffer(view.output)
    if buffer { gtk_text_buffer_set_text(buffer, view.model.transcript, -1) }
}

let IDE_App:on_terminal_activate = fn (widget:u8*, data:u8*) -> void {
    let view = cast(IDE_App:TerminalView*, data)
    if !view || !view.model || !view.model.runtime { return }
    let source = gtk_entry_get_text(view.entry)
    if !source || source[0] == 0 { return }

    view.model.append("> ")
    view.model.append(source)
    view.model.append("\n")
    view.model.runtime.request(source)
    let output = view.model.runtime.last_output
    let error = view.model.runtime.last_error
    if output && output[0] != 0 { view.model.append(output) }
    if error && error[0] != 0 { view.model.append(error); view.model.append("\n") }
    IDE_App:terminal_render(view)
    gtk_entry_set_text(view.entry, "")
}

let IDE_App:terminal_title = fn (model:IDE:Terminal*) -> u8* {
    let title = LanguageKit:Text:new()
    if !title { return cast(u8*, 0) }
    defer title.destroy()
    title.append("Terminal ")
    IDE:append_u64(title, cast(u64, model.number))
    return title.take()
}

let IDE_App:add_terminal_view = fn (state:IDE_App:State*, model:IDE:Terminal*) -> void {
    if !state || !model { return }
    let view = cast(IDE_App:TerminalView*, malloc(40))
    if !view { return }
    view.state = cast(u8*, state)
    view.model = model
    view.output = gtk_text_view_new()
    view.entry = gtk_entry_new()
    view.next = state.terminal_views
    state.terminal_views = view

    let page_box = gtk_box_new(1, 4)
    gtk_text_view_set_monospace(view.output, 1)
    gtk_text_view_set_editable(view.output, 0)
    gtk_text_view_set_cursor_visible(view.output, 0)
    let scroll = gtk_scrolled_window_new(cast(u8*, 0), cast(u8*, 0))
    gtk_scrolled_window_set_policy(scroll, 1, 1)
    gtk_container_add(scroll, view.output)
    gtk_widget_set_vexpand(scroll, 1)
    gtk_entry_set_placeholder_text(view.entry, "RecurLoop command")
    g_signal_connect_data(view.entry, "activate", IDE_App:on_terminal_activate, cast(u8*, view), cast(u8*, 0), 0)
    gtk_box_pack_start(page_box, scroll, 1, 1, 0)
    gtk_box_pack_end(page_box, view.entry, 0, 1, 0)

    IDE_App:terminal_render(view)
    let title_text = IDE_App:terminal_title(model)
    let label = gtk_label_new(title_text)
    if title_text { free(title_text) }
    let page = gtk_notebook_append_page(state.notebook, page_box, label)
    gtk_notebook_set_current_page(state.notebook, page)
}

let IDE_App:on_add_terminal = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host { return }
    let model = IDE:terminal_new(state.host)
    if !model { IDE_App:set_status(state, "cannot create terminal session"); return }
    IDE_App:add_terminal_view(state, model)
    gtk_widget_show_all(state.notebook)
}

let IDE_App:mount_terminals = fn (state:IDE_App:State*) -> void {
    if !state || !state.host { return }
    if !state.host.terminals { IDE:terminal_new(state.host) }
    var model = state.host.terminals
    while model {
        IDE_App:add_terminal_view(state, model)
        model = model.next
    }
}

let IDE_App:free_terminal_views = fn (state:IDE_App:State*) -> void {
    if !state { return }
    var view = state.terminal_views
    while view {
        let next = view.next
        free(cast(u8*, view))
        view = next
    }
    state.terminal_views = cast(IDE_App:TerminalView*, 0)
}
