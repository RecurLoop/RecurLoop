// Project-local IDE application state. None of these records are part of
// ide.rli: changing the view shape is therefore a normal hot-reload operation.
let IDE:App = phrase { dictionary = true permanent = true }

record IDE:App:FileItem {
    state:u8*
    path:u8*
    depth:i64
    directory:i64
    next:IDE:App:FileItem*
}

record IDE:App:TerminalView {
    state:u8*
    model:IDE:Terminal*
    page:u8*
    output:u8*
    entry:u8*
    next:IDE:App:TerminalView*
}

record IDE:App:SemanticSpan {
    start:i64
    finish:i64
    next:IDE:App:SemanticSpan*
}

record IDE:App:SemanticHover {
    start:i64
    finish:i64
    group:i64
    phrase:u8*
    kind:u8*
    docs:u8*
    next:IDE:App:SemanticHover*
}

record IDE:App:SemanticStyle {
    color:u8*
    tag:u8*
    next:IDE:App:SemanticStyle*
}


record IDE:App:SearchResult {
    id:u64
    path:u8*
    start:u64
    finish:u64
    line:u64
    next:IDE:App:SearchResult*
}

record IDE:App:HistoryNode {
    id:u64
    parent_id:u64
    position:u64
    deleted:u8*
    deleted_bytes:u64
    inserted:u8*
    inserted_bytes:u64
    snapshot:u8*
    snapshot_bytes:u64
    parent:IDE:App:HistoryNode*
    first_child:IDE:App:HistoryNode*
    next_sibling:IDE:App:HistoryNode*
    next:IDE:App:HistoryNode*
    branch_depth:u64
}

record IDE:App:History {
    path:u8*
    log_path:u8*
    stream:u8*
    baseline:u8*
    baseline_bytes:u64
    current:u8*
    nodes:IDE:App:HistoryNode*
    tail:IDE:App:HistoryNode*
    index:IDE:App:HistoryNode**
    index_capacity:u64
    head:IDE:App:HistoryNode*
    head_id:u64
    redo_target:IDE:App:HistoryNode*
    saved:IDE:App:HistoryNode*
    saved_id:u64
    saved_valid:i64
    next_id:u64
    record_count:u64
    log_bytes:u64
    disk_hash:u64
    disk_bytes:u64
    enabled:i64
    merge_node:IDE:App:HistoryNode*
}

record IDE:App:ViewSnapshot {
    selected:u8*
    sidebar:i64
    find_visible:i64
    find_query:u8*
    find_replace:u8*
    find_case_sensitive:i64
    find_boundary:i64
    find_regex:i64
    search_query:u8*
    search_replace:u8*
    search_case_sensitive:i64
    search_boundary:i64
    search_regex:i64
    editor_insert:i64
    editor_bound:i64
    editor_scroll_x:f64
    editor_scroll_y:f64
    main_split:i64
    right_split:i64
    terminal_page:i64
}

record IDE:App:State {
    host:IDE:Host*
    root_box:u8*
    file_box:u8*
    main_split:u8*
    right_split:u8*
    editor:u8*
    editor_scroll:u8*
    file_label:u8*
    status:u8*
    semantic_diagnostic:u8*
    notebook:u8*
    files:IDE:App:FileItem*
    terminal_views:IDE:App:TerminalView*
    semantic_spans:IDE:App:SemanticSpan*
    semantic_hovers:IDE:App:SemanticHover*
    semantic_hover_tail:IDE:App:SemanticHover*
    semantic_styles:IDE:App:SemanticStyle*
    semantic_idle_source:u32
    restore_idle_source:u32
    restore_snapshot:IDE:App:ViewSnapshot*

    history:IDE:App:History*
    history_tree:u8*
    history_status:u8*
    history_pane:u8*
    explorer_pane:u8*
    sidebar_stack:u8*
    history_visible:i64
    history_needs_refresh:i64
    history_replaying:i64
    history_refreshing:i64
    history_refresh_idle_source:u32

    find_bar:u8*
    find_input:u8*
    find_replace_input:u8*
    find_status:u8*
    find_case_button:u8*
    find_delimiter_button:u8*
    find_whitespace_button:u8*
    find_regex_button:u8*
    find_query:u8*
    find_case_sensitive:i64
    find_boundary:i64
    find_regex:i64
    find_visible:i64
    find_last_start:i64
    find_last_finish:i64

    search_pane:u8*
    search_tree:u8*
    search_input:u8*
    search_replace_input:u8*
    search_status:u8*
    search_case_button:u8*
    search_delimiter_button:u8*
    search_whitespace_button:u8*
    search_regex_button:u8*
    search_results:IDE:App:SearchResult*
    search_result_tail:IDE:App:SearchResult*
    search_result_count:u64
    search_next_id:u64
    search_case_sensitive:i64
    search_boundary:i64
    search_regex:i64
    search_visible:i64
}

record IDE:App:TreeLoad {
    state:IDE:App:State*
    tree:u8*
    parent:u8*
}

let IDE:App:state = fn (host:IDE:Host*) -> IDE:App:State* {
    if !host { return cast(IDE:App:State*, 0) }
    let data = IDE:view_data(host)
    if !data { return cast(IDE:App:State*, 0) }
    return cast(IDE:App:State*, data)
}

// Shared by find/search/editor modules. Keep this primitive helper in app.rl so
// modules loaded before editor.rl do not depend on a later phrase definition.
let IDE:App:editor_text = fn (state:IDE:App:State*) -> u8* {
    if !state || !state.editor { return cast(u8*, 0) }
    return Gui:text_get(state.editor)
}
