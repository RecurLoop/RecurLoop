// Fast startup shell. It is deliberately small: main.rl can paint this view
// immediately while the persistent Project runtime restores the full IDE from
// <cache>/modules in the background. Once publication is ready, one explicit
// manual reload atomically replaces this shell with IDE:App:lifecycle.
let IDE:Launcher = phrase { dictionary = true permanent = true }

record IDE:Launcher:State {
    host:IDE:Host*
    root:u8*
    tree:u8*
    status:u8*
    loading:i64
}

record IDE:Launcher:TreeLoad {
    tree:u8*
    parent:u8*
}

let IDE:Launcher:on_entry = fn (path:u8*, name:u8*, directory:i64, data:u8*) -> void {
    let load = cast(IDE:Launcher:TreeLoad*, data)
    if !load || !load.tree || !path || !name { return }
    let iterator = Gui:tree_append(load.tree, load.parent, name, path, directory)
    Gui:tree_iter_free(iterator)
}

let IDE:Launcher:add_directory = fn (tree:u8*, parent:u8*, path:u8*) -> void {
    if !tree || !path { return }
    let load = alloc(IDE:Launcher:TreeLoad)
    if !load { return }
    load.tree = tree
    load.parent = parent
    IDE:visit_directory(path, 1, IDE:Launcher:on_entry, cast(u8*, load))
    IDE:visit_directory(path, 0, IDE:Launcher:on_entry, cast(u8*, load))
    free(cast(u8*, load))
}

let IDE:Launcher:on_tree_selected = fn (selection:u8*, data:u8*) -> void {
    let state = cast(IDE:Launcher:State*, data)
    if !state || !selection || !state.tree { return }
    let iterator = Gui:tree_selected_iter(selection)
    if !iterator { return }
    var directory:i32 = 0
    var loaded:i32 = 0
    let path = Gui:tree_iter_path(state.tree, iterator, &directory, &loaded)
    if path && path[0] != 0 && directory != 0 {
        if loaded == 0 {
            Gui:tree_clear_children(state.tree, iterator)
            IDE:Launcher:add_directory(state.tree, iterator, path)
            Gui:tree_mark_loaded(state.tree, iterator)
        }
        Gui:tree_expand(state.tree, iterator)
    }
    if path { Gui:text_free(path) }
    Gui:tree_iter_free(iterator)
}

let IDE:Launcher:mount = fn (host:IDE:Host*) -> void {
    if !host || !host.window || !host.root { return }
    let state = alloc(IDE:Launcher:State)
    if !state { return }
    state.host = host
    state.root = Gui:column(0)
    state.tree = cast(u8*, 0)
    state.status = cast(u8*, 0)
    state.loading = 0
    if !state.root { free(cast(u8*, state)); return }

    // Generation snapshots are process-local hand-off data. A fresh launcher
    // discards a stale file left by an earlier process.
    if host.runner && host.runner.cache_directory {
        let ide_cache = IDE:join(host.runner.cache_directory, "ide")
        if ide_cache {
            let snapshot_path = IDE:join(ide_cache, "view-state-v1.bin")
            if snapshot_path { IDE:remove_path(snapshot_path); free(snapshot_path) }
            free(ide_cache)
        }
    }
    Gui:class_add(state.root, "app-root")

    let main = Gui:split_horizontal()
    let explorer = Gui:column(0)
    Gui:class_add(explorer, "explorer-pane")
    let header = Gui:row(0)
    Gui:class_add(header, "explorer-header")
    let title = Gui:label("EXPLORER")
    Gui:label_align(title, cast(f32, 0.0))
    Gui:class_add(title, "explorer-title")
    Gui:append(header, title, 1, 8)
    Gui:append(explorer, header, 0, 0)

    let project_name = IDE:leaf_name(host.root)
    var project_text = host.root
    if project_name { project_text = project_name }
    let project = Gui:label(project_text)
    Gui:label_align(project, cast(f32, 0.0))
    Gui:class_add(project, "explorer-root")
    Gui:append(explorer, project, 0, 0)
    if project_name { free(project_name) }

    state.tree = Gui:tree()
    Gui:on_tree_select(state.tree, IDE:Launcher:on_tree_selected, cast(u8*, state))
    Gui:append(explorer, Gui:scroll(state.tree), 1, 0)
    IDE:Launcher:add_directory(state.tree, cast(u8*, 0), host.root)

    let loading = Gui:column(0)
    let message = Gui:label("Loading cached IDE modules...")
    Gui:label_align(message, cast(f32, 0.0))
    Gui:class_add(message, "path-label")
    Gui:append(loading, message, 0, 12)

    Gui:split_first(main, explorer, 0)
    Gui:split_position(main, 300)
    Gui:split_second(main, loading, 1)
    Gui:append(state.root, main, 1, 0)
    state.status = Gui:label("starting project runtime")
    Gui:label_align(state.status, cast(f32, 0.0))
    Gui:class_add(state.status, "ide-status")
    Gui:append_end(state.root, state.status, 0, 0)

    if !IDE:view_attach(host, state.root, cast(u8*, state)) {
        Gui:destroy(state.root)
        free(cast(u8*, state))
    }
}

let IDE:Launcher:unmount = fn (host:IDE:Host*) -> void {
    let state = cast(IDE:Launcher:State*, IDE:view_data(host))
    if state { free(cast(u8*, state)) }
}

let IDE:Launcher:runtime_ready = fn (host:IDE:Host*) -> void {
    let state = cast(IDE:Launcher:State*, IDE:view_data(host))
    if !state || state.loading != 0 { return }
    state.loading = 1
    if state.status { Gui:label_text(state.status, "cache ready | loading full IDE") }
    // The launcher intentionally uses manual mode. This one deterministic
    // reload consumes the already-published/cache-warmed ide.rl and the full
    // generation switches itself to hot mode when committed.
    IDE:manual_reload(host)
}

let IDE:Launcher:reload_failed = fn (host:IDE:Host*) -> void {
    let state = cast(IDE:Launcher:State*, IDE:view_data(host))
    if !state { return }
    state.loading = 0
    if state.status {
        if host && host.runner && host.runner.last_error { Gui:label_text(state.status, host.runner.last_error) }
        else { Gui:label_text(state.status, "IDE load failed") }
    }
}

let IDE:Launcher:lifecycle = fn (action:i64, raw:u8*) -> void {
    let host = cast(IDE:Host*, raw)
    if action == 1 { IDE:Launcher:mount(host) }
    else if action == 2 { IDE:Launcher:unmount(host) }
    else if action == 3 { IDE:Launcher:reload_failed(host) }
    else if action == 4 { IDE:Launcher:runtime_ready(host) }
}
