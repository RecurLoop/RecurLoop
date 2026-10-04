// Project application controls and source breakpoint gutter. The stable process
// and ptrace-facing state live in ide.rli; this file is only hot-reloadable UI.

let IDE:App:application_root = fn (state:IDE:App:State*) -> u8* {
    if !state || !state.host || !state.host.root { return cast(u8*, 0) }
    return IDE:join(state.host.root, "application")
}

let IDE:App:application_source = fn (state:IDE:App:State*) -> u8* {
    let root = IDE:App:application_root(state)
    if !root { return cast(u8*, 0) }
    let path = IDE:join(root, "main.rl")
    free(root)
    return path
}

let IDE:App:application_debug_output = fn (state:IDE:App:State*) -> u8* {
    if !state || !state.host { return cast(u8*, 0) }
    return IDE:application_artifact(state.host, "example-debug")
}

let IDE:App:application_release_output = fn (state:IDE:App:State*) -> u8* {
    if !state || !state.host { return cast(u8*, 0) }
    return IDE:application_artifact(state.host, "example-release")
}

let IDE:App:application_selected = fn (state:IDE:App:State*) -> i64 {
    if !state || !state.host || !state.host.selected { return 0 }
    let root = IDE:App:application_root(state)
    if !root { return 0 }
    let inside = IDE:path_is_inside(state.host.selected, root)
    free(root)
    return inside
}

let IDE:App:invalidate_application_outputs = fn (state:IDE:App:State*) -> void {
    if !IDE:App:application_selected(state) { return }
    let debug_output = IDE:App:application_debug_output(state)
    let release_output = IDE:App:application_release_output(state)
    if debug_output { unlink(debug_output); free(debug_output) }
    if release_output { unlink(release_output); free(release_output) }
}

let IDE:App:application_editor_ready = fn (state:IDE:App:State*) -> i64 {
    if !IDE:App:application_selected(state) { return 1 }
    if state.history && !IDE:App:history_is_clean(state.history) {
        IDE:App:set_status(state, "save application changes before build/run")
        return 0
    }
    return 1
}

let IDE:App:show_application_console = fn (state:IDE:App:State*) -> void {
    if !state || !state.notebook || state.application_page < 0 { return }
    Gui:tabs_select(state.notebook, cast(i32, state.application_page))
}

let IDE:App:render_application = fn (state:IDE:App:State*) -> void {
    if !state || !state.host || !state.host.application { return }
    let application = state.host.application
    if state.application_output && state.application_render_revision != application.revision {
        Gui:text_set(state.application_output, application.transcript)
        Gui:text_scroll_end(state.application_output)
        state.application_render_revision = application.revision
    }
    if !state.application_status { return }

    if application.pid <= 0 {
        if application.last_status == 0 { Gui:label_text(state.application_status, "APP  idle") }
        else { Gui:label_text(state.application_status, "APP  last process failed") }
        return
    }
    if application.kind == IDE:ApplicationKind:BuildDebug() { Gui:label_text(state.application_status, "APP  building Debug") }
    else if application.kind == IDE:ApplicationKind:BuildRelease() { Gui:label_text(state.application_status, "APP  building Release") }
    else if application.kind == IDE:ApplicationKind:Release() { Gui:label_text(state.application_status, "APP  Release running") }
    else if application.kind == IDE:ApplicationKind:Debug() {
        if application.state == IDE:ApplicationState:Paused() && application.stop_line > 0 {
            let text = LanguageKit:Text:new()
            if text {
                text.append("APP  paused  ")
                if application.stop_function && application.stop_function[0] != 0 { text.append(application.stop_function); text.append("  ·  ") }
                IDE:append_u64(text, application.stop_line)
                Gui:label_text(state.application_status, text.data)
                text.destroy()
            } else { Gui:label_text(state.application_status, "APP  Debug paused") }
        }
        else if application.state == IDE:ApplicationState:Paused() { Gui:label_text(state.application_status, "APP  Debug paused") }
        else if application.state == IDE:ApplicationState:Syncing() { Gui:label_text(state.application_status, "APP  syncing breakpoint") }
        else { Gui:label_text(state.application_status, "APP  Debug running") }
    } else { Gui:label_text(state.application_status, "APP  running") }
}

let IDE:App:on_build_debug = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    if !IDE:App:application_editor_ready(state) { return }
    let source = IDE:App:application_source(state)
    let output = IDE:App:application_debug_output(state)
    if !source || !output {
        if source { free(source) }
        if output { free(output) }
        IDE:App:set_status(state, "cannot resolve Debug application paths")
        return
    }
    let ok = IDE:application_build(state.host, source, "ExampleApplication:main", output, 1)
    free(source); free(output)
    if !ok { IDE:App:set_status(state, "Debug build could not start") }
    else {
        IDE:App:set_status(state, "building Debug application")
        IDE:App:show_application_console(state)
    }
    IDE:App:render_application(state)
}

let IDE:App:on_build_release = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    if !IDE:App:application_editor_ready(state) { return }
    let source = IDE:App:application_source(state)
    let output = IDE:App:application_release_output(state)
    if !source || !output {
        if source { free(source) }
        if output { free(output) }
        IDE:App:set_status(state, "cannot resolve Release application paths")
        return
    }
    let ok = IDE:application_build(state.host, source, "ExampleApplication:main", output, 0)
    free(source); free(output)
    if !ok { IDE:App:set_status(state, "Release build could not start") }
    else {
        IDE:App:set_status(state, "building Release application")
        IDE:App:show_application_console(state)
    }
    IDE:App:render_application(state)
}

let IDE:App:on_run_debug = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    if !IDE:App:application_editor_ready(state) { return }
    let output = IDE:App:application_debug_output(state)
    if !output { IDE:App:set_status(state, "cannot resolve Debug executable"); return }
    if !IDE:file_exists(output) {
        free(output)
        IDE:App:set_status(state, "Debug executable is not built")
        return
    }
    let ok = IDE:application_debug(state.host, output)
    free(output)
    if !ok { IDE:App:set_status(state, "Debug run could not start") }
    else {
        IDE:App:set_status(state, "Debug application started")
        IDE:App:show_application_console(state)
    }
    IDE:App:render_application(state)
}

let IDE:App:on_run_release = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    if !IDE:App:application_editor_ready(state) { return }
    let output = IDE:App:application_release_output(state)
    if !output { IDE:App:set_status(state, "cannot resolve Release executable"); return }
    if !IDE:file_exists(output) {
        free(output)
        IDE:App:set_status(state, "Release executable is not built")
        return
    }
    let ok = IDE:application_run(state.host, output)
    free(output)
    if !ok { IDE:App:set_status(state, "Release run could not start") }
    else {
        IDE:App:set_status(state, "Release application started")
        IDE:App:show_application_console(state)
    }
    IDE:App:render_application(state)
}

let IDE:App:application_mode_debug = fn (state:IDE:App:State*) -> i64 {
    if !state || !state.application_mode { return 1 }
    return Gui:select_get(state.application_mode) != 1
}

let IDE:App:on_application_build = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if IDE:App:application_mode_debug(state) { IDE:App:on_build_debug(widget, data) }
    else { IDE:App:on_build_release(widget, data) }
}

let IDE:App:on_application_run = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if IDE:App:application_mode_debug(state) { IDE:App:on_run_debug(widget, data) }
    else { IDE:App:on_run_release(widget, data) }
}

let IDE:App:on_debug_continue = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    if !IDE:application_debug_command(state.host, "continue") { IDE:App:set_status(state, "Debug target is not paused") }
    IDE:App:render_application(state)
}

let IDE:App:on_debug_step = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    if !IDE:application_debug_command(state.host, "step") { IDE:App:set_status(state, "Debug target is not paused") }
    IDE:App:render_application(state)
}

let IDE:App:on_debug_next = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    if !IDE:application_debug_command(state.host, "next") { IDE:App:set_status(state, "Debug target is not paused") }
    IDE:App:render_application(state)
}

let IDE:App:on_debug_finish = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    if !IDE:application_debug_command(state.host, "finish") { IDE:App:set_status(state, "Debug target is not paused") }
    IDE:App:render_application(state)
}

let IDE:App:on_application_stop = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    if !IDE:application_stop(state.host) { IDE:App:set_status(state, "no application process is running") }
    else { IDE:App:set_status(state, "stopping application") }
}

let IDE:App:send_debug_text = fn (state:IDE:App:State*, command:u8*) -> i64 {
    if !state || !state.host || !command || command[0] == 0 { return 0 }
    if !IDE:application_debug_command(state.host, command) {
        IDE:App:set_status(state, "debug command requires a paused Debug target")
        return 0
    }
    IDE:App:show_application_console(state)
    IDE:App:render_application(state)
    return 1
}

let IDE:App:on_debug_input = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.application_debug_input { return }
    let command = Gui:input_text(state.application_debug_input)
    if !command || command[0] == 0 { return }
    if IDE:App:send_debug_text(state, command) { Gui:input_set(state.application_debug_input, "") }
}

let IDE:App:on_debug_state = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state { return }
    if !IDE:App:send_debug_text(state, "where") { return }
    IDE:App:send_debug_text(state, "locals")
}

let IDE:App:create_application_toolbar = fn (state:IDE:App:State*) -> u8* {
    if !state { return cast(u8*, 0) }
    let toolbar = Gui:row(4)
    Gui:class_add(toolbar, "application-toolbar")
    Gui:align_top(toolbar)
    Gui:expand_x(toolbar, 1)

    state.application_status = Gui:label("APP  idle")
    Gui:label_align(state.application_status, cast(f32, 0.0))
    Gui:append(toolbar, state.application_status, 1, 4)

    state.application_mode = Gui:select()
    Gui:select_add(state.application_mode, "DEBUG")
    Gui:select_add(state.application_mode, "RELEASE")
    Gui:select_set(state.application_mode, 0)

    let build = Gui:button("Build")
    let run = Gui:button("Run")
    let continue_debug = Gui:button("Continue")
    let step_debug = Gui:button("Step")
    let next_debug = Gui:button("Next")
    let finish_debug = Gui:button("Out")
    let stop = Gui:button("Stop")

    Gui:on_click(build, IDE:App:on_application_build, cast(u8*, state))
    Gui:on_click(run, IDE:App:on_application_run, cast(u8*, state))
    Gui:on_click(continue_debug, IDE:App:on_debug_continue, cast(u8*, state))
    Gui:on_click(step_debug, IDE:App:on_debug_step, cast(u8*, state))
    Gui:on_click(next_debug, IDE:App:on_debug_next, cast(u8*, state))
    Gui:on_click(finish_debug, IDE:App:on_debug_finish, cast(u8*, state))
    Gui:on_click(stop, IDE:App:on_application_stop, cast(u8*, state))

    Gui:append_end(toolbar, stop, 0, 2)
    Gui:append_end(toolbar, finish_debug, 0, 0)
    Gui:append_end(toolbar, next_debug, 0, 0)
    Gui:append_end(toolbar, step_debug, 0, 0)
    Gui:append_end(toolbar, continue_debug, 0, 4)
    Gui:append_end(toolbar, run, 0, 0)
    Gui:append_end(toolbar, build, 0, 0)
    Gui:append_end(toolbar, state.application_mode, 0, 2)
    IDE:App:render_application(state)
    return toolbar
}

let IDE:App:create_application_console = fn (state:IDE:App:State*) -> void {
    if !state || !state.notebook { return }
    let page = Gui:column(0)
    state.application_output = Gui:text_view()
    Gui:class_add(state.application_output, "terminal-output")
    Gui:append(page, Gui:scroll(state.application_output), 1, 0)

    let command = Gui:row(4)
    Gui:class_add(command, "debug-command")
    Gui:align_bottom(command)
    Gui:expand_x(command, 1)
    let prompt = Gui:label("debug>")
    Gui:class_add(prompt, "debug-prompt")
    Gui:align_left(prompt)
    state.application_debug_input = Gui:input("where | locals | eval <name> | registers")
    Gui:input_frame(state.application_debug_input, 0)
    let inspect = Gui:button("State")
    let send = Gui:button("Send")
    Gui:on_activate(state.application_debug_input, IDE:App:on_debug_input, cast(u8*, state))
    Gui:on_click(inspect, IDE:App:on_debug_state, cast(u8*, state))
    Gui:on_click(send, IDE:App:on_debug_input, cast(u8*, state))
    Gui:append(command, prompt, 0, 0)
    Gui:append(command, state.application_debug_input, 1, 0)
    Gui:append_end(command, send, 0, 4)
    Gui:append_end(command, inspect, 0, 0)
    Gui:append(page, command, 0, 0)

    state.application_page = cast(i64, Gui:tabs_append(state.notebook, page, "APPLICATION"))
    IDE:App:render_application(state)
}

let IDE:App:line_digits = fn (value:u64) -> i64 {
    var digits:i64 = 1
    var current = value
    while current >= 10 { current = current / 10; digits += 1 }
    return digits
}

let IDE:App:update_line_gutter = fn (state:IDE:App:State*) -> void {
    if !state || !state.line_gutter { return }
    if !state.editor {
        Gui:text_set(state.line_gutter, "")
        return
    }
    let source = IDE:App:editor_text(state)
    if !source { Gui:text_set(state.line_gutter, ""); return }

    var lines:u64 = 1
    var at:i64 = 0
    while source[at] != 0 {
        if source[at] == 10 { lines += 1 }
        at += 1
    }

    let text = LanguageKit:Text:new()
    if text {
        var line:u64 = 1
        while line <= lines {
            var active:i64 = 0
            if state.host && state.host.application && state.host.selected &&
               state.host.application.state == IDE:ApplicationState:Paused() && state.host.application.stop_path &&
               state.host.application.stop_line == line && strcmp(state.host.application.stop_path, state.host.selected) == 0 { active = 1 }
            if active != 0 || (state.host && state.host.selected && IDE:breakpoint_has(state.host, state.host.selected, line)) { text.append("● ") }
            else { text.append("  ") }
            let digits = IDE:App:line_digits(line)
            var spaces = 5 - digits
            while spaces > 0 { text.append(" "); spaces -= 1 }
            IDE:append_u64(text, line)
            if line < lines { text.append("\n") }
            line += 1
        }
        Gui:text_set(state.line_gutter, text.data)
        Gui:text_clear_styles(state.line_gutter)
        if state.line_gutter_breakpoint_style && state.host && state.host.selected {
            line = 1
            var offset:i64 = 0
            while line <= lines {
                let application = state.host.application
                var active:i64 = 0
                if application && application.state == IDE:ApplicationState:Paused() && application.stop_path &&
                   application.stop_line == line && strcmp(application.stop_path, state.host.selected) == 0 { active = 1 }
                if active != 0 || IDE:breakpoint_has(state.host, state.host.selected, line) {
                    // GTK offsets are character based, so the Unicode dot is one
                    // character even though it occupies multiple UTF-8 bytes.
                    var style = state.line_gutter_breakpoint_style
                    if active != 0 && state.line_gutter_active_style { style = state.line_gutter_active_style }
                    Gui:text_apply_style(state.line_gutter, style, offset, offset + 1)
                }
                let digits = IDE:App:line_digits(line)
                var number_width = digits
                if number_width < 5 { number_width = 5 }
                offset += 2 + number_width
                if line < lines { offset += 1 }
                line += 1
            }
        }
        text.destroy()
    }
    Gui:text_free(source)
}

let IDE:App:on_line_gutter_press = fn (widget:u8*, event:u8*, data:u8*) -> i32 {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host || !state.host.selected || Gui:event_button(event) != 1 { return 0 }
    let line = Gui:text_event_line(widget, event)
    if line <= 0 { return 1 }

    let application_root = IDE:App:application_root(state)
    if !application_root { return 1 }
    let allowed = IDE:path_is_inside(state.host.selected, application_root)
    free(application_root)
    if !allowed {
        IDE:App:set_status(state, "breakpoints are enabled only for application sources")
        return 1
    }
    if state.host.application && state.host.application.state == IDE:ApplicationState:Syncing() {
        IDE:App:set_status(state, "breakpoint update is already in progress")
        return 1
    }

    if !IDE:breakpoint_toggle(state.host, state.host.selected, cast(u64, line)) {
        IDE:App:set_status(state, "could not update breakpoint")
        return 1
    }
    IDE:App:update_line_gutter(state)
    return 1
}

let IDE:App:debug_line_start = fn (text:u8*, line:u64) -> u64 {
    if !text || line <= 1 { return 0 }
    var current:u64 = 1
    var at:u64 = 0
    while text[at] != 0 && current < line {
        if text[at] == 10 { current += 1 }
        at += 1
    }
    return at
}

