// Project-local lazy explorer. The runtime supplies filesystem operations and
// directory enumeration; this file decides only how those resources are shown.

let IDE:App:on_directory_entry = fn (path:u8*, name:u8*, directory:i64, data:u8*) -> void {
    let load = cast(IDE:App:TreeLoad*, data)
    if !load || !load.state || !load.tree || !path || !name { return }
    let iterator = Gui:tree_append(load.tree, load.parent, name, path, directory)
    Gui:tree_iter_free(iterator)
}

let IDE:App:add_tree_directory = fn (state:IDE:App:State*, tree:u8*, parent:u8*, path:u8*) -> void {
    if !state || !tree || !path { return }
    let load = alloc(IDE:App:TreeLoad)
    if !load { return }
    defer free(cast(u8*, load))
    load.state = state
    load.tree = tree
    load.parent = parent

    // Enumeration belongs to ide.rli. The project controls only presentation,
    // so it has no dependency on Linux dirent offsets or a future Windows API.
    IDE:visit_directory(path, 1, IDE:App:on_directory_entry, cast(u8*, load))
    IDE:visit_directory(path, 0, IDE:App:on_directory_entry, cast(u8*, load))
}

let IDE:App:on_tree_selected = fn (selection:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !selection || !state.file_box { return }

    let iterator = Gui:tree_selected_iter(selection)
    if !iterator { return }
    defer Gui:tree_iter_free(iterator)

    var directory:i32 = 0
    var loaded:i32 = 0
    let path = Gui:tree_iter_path(state.file_box, iterator, &directory, &loaded)
    if !path { return }
    defer Gui:text_free(path)
    if path[0] == 0 { return }

    if directory != 0 {
        if loaded == 0 {
            Gui:tree_clear_children(state.file_box, iterator)
            IDE:App:add_tree_directory(state, state.file_box, iterator, path)
            Gui:tree_mark_loaded(state.file_box, iterator)
        }
        Gui:tree_expand(state.file_box, iterator)
        return
    }

    IDE:App:open_path(state, path)
}

let IDE:App:scan_tree = fn (state:IDE:App:State*, path:u8*) -> void {
    if !state || !state.file_box || !path { return }
    Gui:tree_clear(state.file_box)
    IDE:App:add_tree_directory(state, state.file_box, cast(u8*, 0), path)
}

// Returns a malloc-owned target directory. If a file is selected, operations
// such as New File/New Folder target its parent; otherwise they target the
// selected directory. With no selection they target the workspace root.
let IDE:App:explorer_target_directory = fn (state:IDE:App:State*) -> u8* {
    if !state || !state.host { return cast(u8*, 0) }
    var directory:i32 = 0
    let selected = Gui:tree_selected_path(state.file_box, &directory)
    if !selected { return IDE:copy(state.host.root) }
    defer Gui:text_free(selected)
    if directory != 0 { return IDE:copy(selected) }
    return IDE:parent_path(selected)
}

let IDE:App:update_open_path_after_rename = fn (state:IDE:App:State*, old_path:u8*, new_path:u8*) -> void {
    if !state || !state.host || !state.host.selected || !old_path || !new_path { return }
    if !IDE:path_is_inside(state.host.selected, old_path) { return }

    let old_bytes = cast(i64, strlen(old_path))
    let text = LanguageKit:Text:new()
    if !text { return }
    if !text.append(new_path) || !text.append(&state.host.selected[old_bytes]) {
        text.destroy()
        return
    }
    let updated = text.take()
    text.destroy()
    if !updated { return }

    free(state.host.selected)
    state.host.selected = updated
    let relative = IDE:relative(state.host.root, updated)
    if relative {
        Gui:label_text(state.file_label, relative)
        free(relative)
    }
}

let IDE:App:clear_open_path_if_inside = fn (state:IDE:App:State*, removed:u8*) -> void {
    if !state || !state.host || !state.host.selected || !removed { return }
    if !IDE:path_is_inside(state.host.selected, removed) { return }
    free(state.host.selected)
    state.host.selected = cast(u8*, 0)
    Gui:text_set(state.editor, "")
    Gui:label_text(state.file_label, "No file selected")
}

let IDE:App:on_explorer_refresh = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    IDE:App:scan_tree(state, state.host.root)
    IDE:App:set_status(state, "explorer refreshed")
}

let IDE:App:on_explorer_new_file = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    let directory = IDE:App:explorer_target_directory(state)
    if !directory { return }
    defer free(directory)

    let name = Gui:prompt(state.host.window, "New File", "File name", "")
    if !name { return }
    defer free(name)
    if !IDE:valid_leaf_name(name) { IDE:App:set_status(state, "invalid file name"); return }

    let path = IDE:join(directory, name)
    if !path { IDE:App:set_status(state, "cannot build file path"); return }
    defer free(path)
    if !IDE:create_empty_file(path) { IDE:App:set_status(state, "cannot create file (already exists?)"); return }

    IDE:App:scan_tree(state, state.host.root)
    IDE:App:open_path(state, path)
    IDE:App:set_status(state, "file created")
}

let IDE:App:on_explorer_new_folder = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    let directory = IDE:App:explorer_target_directory(state)
    if !directory { return }
    defer free(directory)

    let name = Gui:prompt(state.host.window, "New Folder", "Folder name", "")
    if !name { return }
    defer free(name)
    if !IDE:valid_leaf_name(name) { IDE:App:set_status(state, "invalid folder name"); return }

    let path = IDE:join(directory, name)
    if !path { IDE:App:set_status(state, "cannot build folder path"); return }
    defer free(path)
    if !IDE:create_directory(path) { IDE:App:set_status(state, "cannot create folder (already exists?)"); return }

    IDE:App:scan_tree(state, state.host.root)
    IDE:App:set_status(state, "folder created")
}

let IDE:App:on_explorer_rename = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    var directory:i32 = 0
    let selected = Gui:tree_selected_path(state.file_box, &directory)
    if !selected { IDE:App:set_status(state, "select a file or folder to rename"); return }
    defer Gui:text_free(selected)

    let current = IDE:leaf_name(selected)
    if !current { return }
    defer free(current)
    let name = Gui:prompt(state.host.window, "Rename", "New name", current)
    if !name { return }
    defer free(name)
    if !IDE:valid_leaf_name(name) { IDE:App:set_status(state, "invalid name"); return }
    if strcmp(current, name) == 0 { return }

    let parent = IDE:parent_path(selected)
    if !parent { return }
    defer free(parent)
    let target = IDE:join(parent, name)
    if !target { return }
    defer free(target)

    if !IDE:rename_path(selected, target) { IDE:App:set_status(state, "rename failed (target exists?)"); return }
    IDE:App:update_open_path_after_rename(state, selected, target)
    IDE:App:scan_tree(state, state.host.root)
    IDE:App:set_status(state, "renamed")
}

let IDE:App:on_explorer_delete = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !state.host { return }
    var directory:i32 = 0
    let selected = Gui:tree_selected_path(state.file_box, &directory)
    if !selected { IDE:App:set_status(state, "select a file or folder to delete"); return }
    defer Gui:text_free(selected)

    let relative = IDE:relative(state.host.root, selected)
    if !relative { return }
    let prompt = LanguageKit:Text:new()
    if !prompt { free(relative); return }
    prompt.append("Delete ")
    prompt.append(relative)
    if directory != 0 { prompt.append(" and all of its contents?") }
    else { prompt.append("?") }
    free(relative)
    let message = prompt.take()
    prompt.destroy()
    if !message { return }
    defer free(message)

    if !Gui:confirm(state.host.window, "Delete", message, "Delete") { return }
    if !IDE:remove_path(selected) { IDE:App:set_status(state, "delete failed"); return }

    IDE:App:clear_open_path_if_inside(state, selected)
    IDE:App:scan_tree(state, state.host.root)
    IDE:App:set_status(state, "deleted")
}

// Kept for lifecycle compatibility with older application generations. The
// GtkTreeStore owns explorer rows, so there are no per-file allocations here.
let IDE:App:free_files = fn (state:IDE:App:State*) -> void {
    if !state { return }
    state.files = cast(IDE:App:FileItem*, 0)
}
