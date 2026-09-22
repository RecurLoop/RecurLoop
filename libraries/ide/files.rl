// Native, lazy file explorer built on Gui:tree. Startup scans only the project
// root. A directory is read when it is selected for the first time, so large
// repositories do not block the initial IDE window while every path is walked.

let IDE_App:add_tree_directory = fn (state:IDE_App:State*, tree:u8*, parent:u8*, path:u8*) -> void {
    if !state || !tree || !path { return }

    // Folders first. Gui:tree_append gives each directory a placeholder child,
    // which makes GTK draw its normal expander without recursively scanning it.
    let directories = opendir(path)
    if directories {
        var entry = readdir(directories)
        while entry {
            let kind = entry[18]
            let name = &entry[19]
            if !IDE:skip_directory(name) {
                let child = IDE:join(path, name)
                if child {
                    let is_dir = kind == 4 || (kind == 0 && IDE:is_directory(child))
                    if is_dir {
                        let iterator = Gui:tree_append(tree, parent, name, child, 1)
                        Gui:tree_iter_free(iterator)
                    }
                    free(child)
                }
            }
            entry = readdir(directories)
        }
        closedir(directories)
    }

    // Files directly in this directory. Nothing below child directories is read
    // until the user opens that directory in the tree.
    let files = opendir(path)
    if !files { return }
    var entry = readdir(files)
    while entry {
        let kind = entry[18]
        let name = &entry[19]
        if !IDE:skip_directory(name) {
            let child = IDE:join(path, name)
            if child {
                let is_dir = kind == 4 || (kind == 0 && IDE:is_directory(child))
                if !is_dir {
                    let iterator = Gui:tree_append(tree, parent, name, child, 0)
                    Gui:tree_iter_free(iterator)
                }
                free(child)
            }
        }
        entry = readdir(files)
    }
    closedir(files)
}

let IDE_App:on_tree_selected = fn (selection:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
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
            IDE_App:add_tree_directory(state, state.file_box, iterator, path)
            Gui:tree_mark_loaded(state.file_box, iterator)
        }
        Gui:tree_expand(state.file_box, iterator)
        return
    }

    IDE_App:open_path(state, path)
}

let IDE_App:scan_tree = fn (state:IDE_App:State*, path:u8*) -> void {
    if !state || !state.file_box || !path { return }
    Gui:tree_clear(state.file_box)
    IDE_App:add_tree_directory(state, state.file_box, cast(u8*, 0), path)
}

// Returns a malloc-owned target directory. If a file is selected, operations
// such as New File/New Folder target its parent; otherwise they target the
// selected directory. With no selection they target the workspace root.
let IDE_App:explorer_target_directory = fn (state:IDE_App:State*) -> u8* {
    if !state || !state.host { return cast(u8*, 0) }
    var directory:i32 = 0
    let selected = Gui:tree_selected_path(state.file_box, &directory)
    if !selected { return IDE:copy(state.host.root) }
    defer Gui:text_free(selected)
    if directory != 0 { return IDE:copy(selected) }
    return IDE:parent_path(selected)
}

let IDE_App:update_open_path_after_rename = fn (state:IDE_App:State*, old_path:u8*, new_path:u8*) -> void {
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

let IDE_App:clear_open_path_if_inside = fn (state:IDE_App:State*, removed:u8*) -> void {
    if !state || !state.host || !state.host.selected || !removed { return }
    if !IDE:path_is_inside(state.host.selected, removed) { return }
    free(state.host.selected)
    state.host.selected = cast(u8*, 0)
    Gui:text_set(state.editor, "")
    Gui:label_text(state.file_label, "No file selected")
}

let IDE_App:on_explorer_refresh = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host { return }
    IDE_App:scan_tree(state, state.host.root)
    IDE_App:set_status(state, "explorer refreshed")
}

let IDE_App:on_explorer_new_file = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host { return }
    let directory = IDE_App:explorer_target_directory(state)
    if !directory { return }
    defer free(directory)

    let name = Gui:prompt(state.host.window, "New File", "File name", "")
    if !name { return }
    defer free(name)
    if !IDE:valid_leaf_name(name) { IDE_App:set_status(state, "invalid file name"); return }

    let path = IDE:join(directory, name)
    if !path { IDE_App:set_status(state, "cannot build file path"); return }
    defer free(path)
    if !IDE:create_empty_file(path) { IDE_App:set_status(state, "cannot create file (already exists?)"); return }

    IDE_App:scan_tree(state, state.host.root)
    IDE_App:open_path(state, path)
    IDE_App:set_status(state, "file created")
}

let IDE_App:on_explorer_new_folder = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host { return }
    let directory = IDE_App:explorer_target_directory(state)
    if !directory { return }
    defer free(directory)

    let name = Gui:prompt(state.host.window, "New Folder", "Folder name", "")
    if !name { return }
    defer free(name)
    if !IDE:valid_leaf_name(name) { IDE_App:set_status(state, "invalid folder name"); return }

    let path = IDE:join(directory, name)
    if !path { IDE_App:set_status(state, "cannot build folder path"); return }
    defer free(path)
    if !IDE:create_directory(path) { IDE_App:set_status(state, "cannot create folder (already exists?)"); return }

    IDE_App:scan_tree(state, state.host.root)
    IDE_App:set_status(state, "folder created")
}

let IDE_App:on_explorer_rename = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host { return }
    var directory:i32 = 0
    let selected = Gui:tree_selected_path(state.file_box, &directory)
    if !selected { IDE_App:set_status(state, "select a file or folder to rename"); return }
    defer Gui:text_free(selected)

    let current = IDE:leaf_name(selected)
    if !current { return }
    defer free(current)
    let name = Gui:prompt(state.host.window, "Rename", "New name", current)
    if !name { return }
    defer free(name)
    if !IDE:valid_leaf_name(name) { IDE_App:set_status(state, "invalid name"); return }
    if strcmp(current, name) == 0 { return }

    let parent = IDE:parent_path(selected)
    if !parent { return }
    defer free(parent)
    let target = IDE:join(parent, name)
    if !target { return }
    defer free(target)

    if !IDE:rename_path(selected, target) { IDE_App:set_status(state, "rename failed (target exists?)"); return }
    IDE_App:update_open_path_after_rename(state, selected, target)
    IDE_App:scan_tree(state, state.host.root)
    IDE_App:set_status(state, "renamed")
}

let IDE_App:on_explorer_delete = fn (widget:u8*, data:u8*) -> void {
    let state = cast(IDE_App:State*, data)
    if !state || !state.host { return }
    var directory:i32 = 0
    let selected = Gui:tree_selected_path(state.file_box, &directory)
    if !selected { IDE_App:set_status(state, "select a file or folder to delete"); return }
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
    if !IDE:remove_path(selected) { IDE_App:set_status(state, "delete failed"); return }

    IDE_App:clear_open_path_if_inside(state, selected)
    IDE_App:scan_tree(state, state.host.root)
    IDE_App:set_status(state, "deleted")
}

// Kept for lifecycle compatibility with older application generations. The
// GtkTreeStore owns explorer rows, so there are no per-file allocations here.
let IDE_App:free_files = fn (state:IDE_App:State*) -> void {
    if !state { return }
    state.files = cast(IDE_App:FileItem*, 0)
}
