let IDE:App:terminal_render = fn (view:IDE:App:TerminalView*) -> void {
    if !view || !view.model || !view.output { return }
    Gui:text_set(view.output, view.model.transcript)
    Gui:text_scroll_end(view.output)
}

let IDE:App:on_terminal_activate = fn (widget:u8*, data:u8*) -> void {
    let view = cast(IDE:App:TerminalView*, data)
    if !view || !view.model || !view.model.runtime { return }
    let source = Gui:input_text(view.entry)
    if !source || source[0] == 0 { return }

    // The transcript is a terminal stream, not a chat history. Input is shown
    // with the same prompt as stdio RecurLoop and output follows immediately.
    view.model.append("> ")
    view.model.append(source)
    view.model.append("\n")
    view.model.runtime.request(source)
    let output = view.model.runtime.last_output
    let error = view.model.runtime.last_error
    if output && output[0] != 0 { view.model.append(output) }
    if error && error[0] != 0 { view.model.append(error); view.model.append("\n") }
    IDE:App:terminal_render(view)
    Gui:input_set(view.entry, "")
    Gui:focus(view.entry)
}

let IDE:App:terminal_title = fn (model:IDE:Terminal*) -> u8* {
    let title = LanguageKit:Text:new()
    if !title { return cast(u8*, 0) }
    defer title.destroy()
    title.append("recurloop ")
    IDE:append_u64(title, cast(u64, model.number))
    return title.take()
}

let IDE:App:add_terminal_view = fn (state:IDE:App:State*, model:IDE:Terminal*) -> void {
    if !state || !model { return }
    let view = alloc(IDE:App:TerminalView)
    if !view { return }
    view.state = cast(u8*, state)
    view.model = model
    view.output = Gui:text_view()
    view.entry = Gui:input("")
    view.next = state.terminal_views
    state.terminal_views = view

    Gui:class_add(view.output, "terminal-output")
    Gui:class_add(view.entry, "terminal-input")
    Gui:input_frame(view.entry, 0)

    let page_box = Gui:column(0)
    view.page = page_box
    Gui:class_add(page_box, "terminal-panel")
    let scroll = Gui:scroll(view.output)
    Gui:expand_y(scroll, 1)

    let command = Gui:row(0)
    Gui:class_add(command, "terminal-command")
    let prompt = Gui:label(">")
    Gui:class_add(prompt, "terminal-prompt")
    Gui:append(command, prompt, 0, 0)
    Gui:append(command, view.entry, 1, 0)

    Gui:on_activate(view.entry, IDE:App:on_terminal_activate, cast(u8*, view))
    Gui:append(page_box, scroll, 1, 0)
    Gui:append_end(page_box, command, 0, 0)

    IDE:App:terminal_render(view)
    let title_text = IDE:App:terminal_title(model)
    let page = Gui:tabs_append(state.notebook, page_box, title_text)
    if title_text { free(title_text) }
    Gui:tabs_select(state.notebook, page)
    Gui:focus(view.entry)
}

let IDE:App:on_add_terminal = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    let model = IDE:terminal_new(state.host)
    if !model { IDE:App:set_status(state, "cannot create terminal session"); return }
    IDE:App:add_terminal_view(state, model)
    Gui:show(state.notebook)
}

let IDE:App:mount_terminals = fn (state:IDE:App:State*) -> void {
    if !state || !state.host { return }
    if !state.host.terminals { IDE:terminal_new(state.host) }
    var model = state.host.terminals
    while model {
        IDE:App:add_terminal_view(state, model)
        model = model.next
    }
}

let IDE:App:free_terminal_views = fn (state:IDE:App:State*) -> void {
    if !state { return }
    var view = state.terminal_views
    while view {
        let next = view.next
        free(cast(u8*, view))
        view = next
    }
    state.terminal_views = cast(IDE:App:TerminalView*, 0)
}
