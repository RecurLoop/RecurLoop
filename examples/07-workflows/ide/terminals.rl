let IDE_App:terminal_render = fn (view:IDE_App:TerminalView*) -> void {
    if !view || !view.model || !view.output { return }
    Gui:text_set(view.output, view.model.transcript)
}

let IDE_App:on_terminal_activate = fn (widget:u8*, data:u8*) -> void {
    let view = cast(IDE_App:TerminalView*, data)
    if !view || !view.model || !view.model.runtime { return }
    let source = Gui:input_text(view.entry)
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
    Gui:input_set(view.entry, "")
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
    view.output = Gui:text_view()
    view.entry = Gui:input("RecurLoop command")
    view.next = state.terminal_views
    state.terminal_views = view

    let page_box = Gui:column(4)
    let scroll = Gui:scroll(view.output)
    Gui:expand_y(scroll, 1)
    Gui:on_activate(view.entry, IDE_App:on_terminal_activate, cast(u8*, view))
    Gui:append(page_box, scroll, 1, 0)
    Gui:append_end(page_box, view.entry, 0, 0)

    IDE_App:terminal_render(view)
    let title_text = IDE_App:terminal_title(model)
    let page = Gui:tabs_append(state.notebook, page_box, title_text)
    if title_text { free(title_text) }
    Gui:tabs_select(state.notebook, page)
}

let IDE_App:on_add_terminal = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host { return }
    let model = IDE:terminal_new(state.host)
    if !model { IDE_App:set_status(state, "cannot create terminal session"); return }
    IDE_App:add_terminal_view(state, model)
    Gui:show(state.notebook)
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
