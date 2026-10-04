// Persistent, project-local editor history. The source-defined IDE owns undo /
// redo policy; ide.rli only supplies the stable window/runtime/filesystem.
//
// Storage is an append-only delta log in <cache>/ide/history. Each edit stores
// one minimal splice (common prefix/suffix removed), not a full file snapshot.
// Consecutive word-character insertions extend one logical graph node; deletes
// deliberately remain one node per edit. A full checkpoint is embedded every
// 128 logical records so arbitrary graph checkout
// is bounded. Logs are compacted deterministically when either the record or
// byte limit is reached; compaction never writes the source file.

extern fflush(stream:u8*) -> i32 abi sysv-amd64

let IDE:App:History:Version = fn () -> u64 { return 2 }
let IDE:App:History:TagHeader = fn () -> u64 { return 1 }
let IDE:App:History:TagNode = fn () -> u64 { return 2 }
let IDE:App:History:TagHead = fn () -> u64 { return 3 }
let IDE:App:History:TagSave = fn () -> u64 { return 4 }
let IDE:App:History:TagExtend = fn () -> u64 { return 5 }
let IDE:App:History:CheckpointEvery = fn () -> u64 { return 128 }
let IDE:App:History:MaxRecords = fn () -> u64 { return 20000 }
let IDE:App:History:MaxBytes = fn () -> u64 { return 134217728 }
let IDE:App:History:GlobalMaxBytes = fn () -> u64 { return 536870912 }

record IDE:App:HistorySweep {
    keep:u8*
    total:u64
}

let IDE:App:history_sweep_size = fn (path:u8*, name:u8*, directory:i64, data:u8*) -> void {
    let sweep = cast(IDE:App:HistorySweep*, data)
    if !sweep || directory != 0 || !path { return }
    let stream = fopen(path, "rb")
    if !stream { return }
    if fseek(stream, 0, 2) == 0 {
        let bytes = ftell(stream)
        if bytes > 0 { sweep.total += cast(u64, bytes) }
    }
    fclose(stream)
}

let IDE:App:history_sweep_remove = fn (path:u8*, name:u8*, directory:i64, data:u8*) -> void {
    let sweep = cast(IDE:App:HistorySweep*, data)
    if !sweep || directory != 0 || !path { return }
    if sweep.keep && strcmp(path, sweep.keep) == 0 { return }
    unlink(path)
}

let IDE:App:history_enforce_global = fn (state:IDE:App:State*, keep:u8*) -> void {
    if !state || !state.host || !state.host.runner || !state.host.runner.cache_directory { return }
    let ide_cache = IDE:join(state.host.runner.cache_directory, "ide")
    if !ide_cache { return }
    let directory = IDE:join(ide_cache, "history")
    free(ide_cache)
    if !directory { return }
    if !IDE:ensure_directory_tree(directory) { free(directory); return }
    let sweep = alloc(IDE:App:HistorySweep)
    if !sweep { free(directory); return }
    sweep.keep = keep
    sweep.total = 0
    IDE:visit_directory(directory, 0, IDE:App:history_sweep_size, cast(u8*, sweep))
    if sweep.total > IDE:App:History:GlobalMaxBytes() {
        // Deterministic emergency pruning: keep the active file's log and drop
        // every inactive history log. This avoids timestamp/LRU heuristics.
        IDE:visit_directory(directory, 0, IDE:App:history_sweep_remove, cast(u8*, sweep))
    }
    free(cast(u8*, sweep))
    free(directory)
}

let IDE:App:history_copy_bytes = fn (source:u8*, offset:u64, bytes:u64) -> u8* {
    if !source { return cast(u8*, 0) }
    let result = cast(u8*, malloc(bytes + 1))
    if !result { return cast(u8*, 0) }
    if bytes > 0 { memcpy(result, &source[offset], bytes) }
    result[bytes] = 0
    return result
}

let IDE:App:history_hash = fn (text:u8*) -> u64 {
    if !text { return 0 }
    var hash:u64 = 1469598103934665603
    var at:u64 = 0
    while text[at] != 0 {
        hash = hash * 131 + cast(u64, text[at]) + 1
        at += 1
    }
    return hash
}

let IDE:App:history_hex = fn (value:u64) -> u8* {
    let digits = "0123456789abcdef"
    let result = cast(u8*, malloc(17))
    if !result { return cast(u8*, 0) }
    var at:i64 = 15
    var current = value
    while at >= 0 {
        result[at] = digits[current % 16]
        current = current / 16
        at -= 1
    }
    result[16] = 0
    return result
}

let IDE:App:history_u64_text = fn (value:u64) -> u8* {
    let text = LanguageKit:Text:new()
    if !text { return cast(u8*, 0) }
    IDE:append_u64(text, value)
    let result = text.take()
    text.destroy()
    return result
}

let IDE:App:history_parse_u64 = fn (text:u8*) -> u64 {
    if !text { return 0 }
    var value:u64 = 0
    var at:u64 = 0
    while text[at] >= 48 && text[at] <= 57 {
        value = value * 10 + cast(u64, text[at] - 48)
        at += 1
    }
    return value
}

let IDE:App:history_write_u64 = fn (stream:u8*, value:u64) -> i64 {
    if !stream { return 0 }
    return fwrite(cast(u8*, &value), 8, 1, stream) == 1
}

let IDE:App:history_read_u64 = fn (stream:u8*, value:u64*) -> i64 {
    if !stream || !value { return 0 }
    return fread(cast(u8*, value), 8, 1, stream) == 1
}

let IDE:App:history_write_bytes = fn (stream:u8*, data:u8*, bytes:u64) -> i64 {
    if bytes == 0 { return 1 }
    if !stream || !data { return 0 }
    return fwrite(data, 1, bytes, stream) == bytes
}

let IDE:App:history_read_bytes = fn (stream:u8*, bytes:u64) -> u8* {
    let data = cast(u8*, malloc(bytes + 1))
    if !data { return cast(u8*, 0) }
    if bytes > 0 && fread(data, 1, bytes, stream) != bytes { free(data); return cast(u8*, 0) }
    data[bytes] = 0
    return data
}

let IDE:App:history_ensure_index = fn (history:IDE:App:History*, id:u64) -> i64 {
    if !history { return 0 }
    if id < history.index_capacity { return 1 }
    var capacity:u64 = history.index_capacity
    if capacity < 256 { capacity = 256 }
    while capacity <= id { capacity *= 2 }
    let previous = history.index_capacity
    let replacement = cast(IDE:App:HistoryNode**, realloc(cast(u8*, history.index), capacity * sizeof(IDE:App:HistoryNode*)))
    if !replacement { return 0 }
    history.index = replacement
    var at = previous
    while at < capacity { history.index[at] = cast(IDE:App:HistoryNode*, 0); at += 1 }
    history.index_capacity = capacity
    return 1
}

let IDE:App:history_node_free = fn (node:IDE:App:HistoryNode*) -> void {
    if !node { return }
    if node.deleted { free(node.deleted) }
    if node.inserted { free(node.inserted) }
    if node.snapshot { free(node.snapshot) }
    free(cast(u8*, node))
}

let IDE:App:history_clear_nodes = fn (history:IDE:App:History*) -> void {
    if !history { return }
    var node = history.nodes
    while node {
        let next = node.next
        IDE:App:history_node_free(node)
        node = next
    }
    history.nodes = cast(IDE:App:HistoryNode*, 0)
    history.tail = cast(IDE:App:HistoryNode*, 0)
    history.head = cast(IDE:App:HistoryNode*, 0)
    history.redo_target = cast(IDE:App:HistoryNode*, 0)
    history.saved = cast(IDE:App:HistoryNode*, 0)
    history.head_id = 0
    history.saved_id = 0
    history.saved_valid = 0
    history.merge_node = cast(IDE:App:HistoryNode*, 0)
    history.next_id = 1
    history.record_count = 0
    if history.index {
        free(cast(u8*, history.index))
        history.index = cast(IDE:App:HistoryNode**, 0)
    }
    history.index_capacity = 0
}

let IDE:App:history_link_node = fn (history:IDE:App:History*, node:IDE:App:HistoryNode*) -> i64 {
    if !history || !node || node.id == 0 { return 0 }
    if !IDE:App:history_ensure_index(history, node.id) { return 0 }
    if history.index[node.id] { return 0 }

    if node.parent_id != 0 {
        if node.parent_id >= history.index_capacity || !history.index[node.parent_id] { return 0 }
        node.parent = history.index[node.parent_id]
        node.branch_depth = node.parent.branch_depth
        if node.parent.first_child { node.branch_depth += 1 }
        node.next_sibling = node.parent.first_child
        node.parent.first_child = node
    } else {
        node.parent = cast(IDE:App:HistoryNode*, 0)
        node.branch_depth = 0
        node.next_sibling = cast(IDE:App:HistoryNode*, 0)
    }

    node.first_child = cast(IDE:App:HistoryNode*, 0)
    node.next = cast(IDE:App:HistoryNode*, 0)
    if history.tail { history.tail.next = node }
    else { history.nodes = node }
    history.tail = node
    history.index[node.id] = node
    history.record_count += 1
    if node.id >= history.next_id { history.next_id = node.id + 1 }
    return 1
}

let IDE:App:history_find = fn (history:IDE:App:History*, id:u64) -> IDE:App:HistoryNode* {
    if !history || id == 0 || id >= history.index_capacity { return cast(IDE:App:HistoryNode*, 0) }
    return history.index[id]
}

let IDE:App:history_splice = fn (source:u8*, position:u64, removed:u64, inserted:u8*, inserted_bytes:u64) -> u8* {
    if !source { return cast(u8*, 0) }
    let source_bytes = cast(u64, strlen(source))
    if position > source_bytes || removed > source_bytes - position { return cast(u8*, 0) }
    let result_bytes = source_bytes - removed + inserted_bytes
    let result = cast(u8*, malloc(result_bytes + 1))
    if !result { return cast(u8*, 0) }
    if position > 0 { memcpy(result, source, position) }
    if inserted_bytes > 0 && inserted { memcpy(&result[position], inserted, inserted_bytes) }
    let suffix = source_bytes - position - removed
    if suffix > 0 { memcpy(&result[position + inserted_bytes], &source[position + removed], suffix) }
    result[result_bytes] = 0
    return result
}

let IDE:App:history_apply_forward = fn (source:u8*, node:IDE:App:HistoryNode*) -> u8* {
    if !node { return IDE:copy(source) }
    return IDE:App:history_splice(source, node.position, node.deleted_bytes, node.inserted, node.inserted_bytes)
}

let IDE:App:history_apply_inverse = fn (source:u8*, node:IDE:App:HistoryNode*) -> u8* {
    if !node { return IDE:copy(source) }
    return IDE:App:history_splice(source, node.position, node.inserted_bytes, node.deleted, node.deleted_bytes)
}

let IDE:App:history_reconstruct = fn (history:IDE:App:History*, target:IDE:App:HistoryNode*) -> u8* {
    if !history || !history.baseline { return cast(u8*, 0) }
    if !target { return IDE:copy(history.baseline) }

    var anchor = target
    var count:u64 = 0
    while anchor && !anchor.snapshot { count += 1; anchor = anchor.parent }

    var text:u8* = cast(u8*, 0)
    if anchor && anchor.snapshot { text = IDE:copy(anchor.snapshot) }
    else { text = IDE:copy(history.baseline) }
    if !text { return cast(u8*, 0) }
    if count == 0 { return text }

    let stack = cast(IDE:App:HistoryNode**, malloc(count * sizeof(IDE:App:HistoryNode*)))
    if !stack { free(text); return cast(u8*, 0) }
    var node = target
    var at:u64 = 0
    while node && node != anchor && at < count {
        stack[at] = node
        at += 1
        node = node.parent
    }
    while at > 0 {
        at -= 1
        let next = IDE:App:history_apply_forward(text, stack[at])
        free(text)
        if !next { free(cast(u8*, stack)); return cast(u8*, 0) }
        text = next
    }
    free(cast(u8*, stack))
    return text
}

let IDE:App:history_header_bytes = fn (history:IDE:App:History*) -> u64 {
    if !history || !history.path || !history.baseline { return 0 }
    return 56 + cast(u64, strlen(history.path)) + history.baseline_bytes
}

let IDE:App:history_write_header = fn (history:IDE:App:History*, stream:u8*, baseline_saved:i64) -> i64 {
    if !history || !stream || !history.path || !history.baseline { return 0 }
    let path_bytes = cast(u64, strlen(history.path))
    return IDE:App:history_write_u64(stream, IDE:App:History:TagHeader()) &&
           IDE:App:history_write_u64(stream, IDE:App:History:Version()) &&
           IDE:App:history_write_u64(stream, path_bytes) &&
           IDE:App:history_write_u64(stream, history.baseline_bytes) &&
           IDE:App:history_write_u64(stream, cast(u64, baseline_saved != 0)) &&
           IDE:App:history_write_u64(stream, history.disk_hash) &&
           IDE:App:history_write_u64(stream, history.disk_bytes) &&
           IDE:App:history_write_bytes(stream, history.path, path_bytes) &&
           IDE:App:history_write_bytes(stream, history.baseline, history.baseline_bytes)
}

let IDE:App:history_open_append = fn (history:IDE:App:History*) -> i64 {
    if !history || !history.log_path || !history.enabled { return 0 }
    if history.stream { fclose(history.stream); history.stream = cast(u8*, 0) }
    history.stream = fopen(history.log_path, "ab")
    return history.stream != cast(u8*, 0)
}

let IDE:App:history_rewrite = fn (history:IDE:App:History*, baseline:u8*, baseline_saved:i64) -> i64 {
    if !history || !history.log_path || !baseline { return 0 }
    if history.stream { fclose(history.stream); history.stream = cast(u8*, 0) }

    IDE:App:history_clear_nodes(history)
    if history.baseline { free(history.baseline) }
    history.baseline = IDE:copy(baseline)
    if !history.baseline { return 0 }
    history.baseline_bytes = cast(u64, strlen(history.baseline))
    if history.current { free(history.current) }
    // Copy from the retained baseline, not from the caller pointer: callers may
    // pass history.current itself, which was just released above.
    history.current = IDE:copy(history.baseline)
    if !history.current { return 0 }
    history.head_id = 0
    history.head = cast(IDE:App:HistoryNode*, 0)
    history.redo_target = cast(IDE:App:HistoryNode*, 0)
    history.saved_valid = baseline_saved != 0
    history.saved_id = 0
    history.saved = cast(IDE:App:HistoryNode*, 0)
    history.next_id = 1

    let stream = fopen(history.log_path, "wb")
    if !stream { history.enabled = 0; return 0 }
    let ok = IDE:App:history_write_header(history, stream, baseline_saved)
    fflush(stream)
    fclose(stream)
    if !ok { history.enabled = 0; return 0 }
    history.log_bytes = IDE:App:history_header_bytes(history)
    return IDE:App:history_open_append(history)
}

let IDE:App:history_cache_path = fn (state:IDE:App:State*, source_path:u8*) -> u8* {
    if !state || !state.host || !state.host.runner || !source_path { return cast(u8*, 0) }
    var cache = state.host.runner.cache_directory
    if !cache { return cast(u8*, 0) }
    let ide_cache = IDE:join(cache, "ide")
    if !ide_cache { return cast(u8*, 0) }
    let directory = IDE:join(ide_cache, "history")
    free(ide_cache)
    if !directory { return cast(u8*, 0) }
    if !IDE:ensure_directory_tree(directory) { free(directory); return cast(u8*, 0) }

    let hash_text = IDE:App:history_hex(IDE:App:history_hash(source_path))
    if !hash_text { free(directory); return cast(u8*, 0) }
    let name = LanguageKit:Text:new()
    if !name { free(hash_text); free(directory); return cast(u8*, 0) }
    name.append(hash_text)
    name.append(".bin")
    free(hash_text)
    let leaf = name.take()
    name.destroy()
    if !leaf { free(directory); return cast(u8*, 0) }
    let result = IDE:join(directory, leaf)
    free(leaf)
    free(directory)
    return result
}

let IDE:App:history_load = fn (history:IDE:App:History*) -> i64 {
    if !history || !history.log_path || !history.path { return 0 }
    let stream = fopen(history.log_path, "rb")
    if !stream { return 0 }

    var tag:u64 = 0
    var version:u64 = 0
    var path_bytes:u64 = 0
    var baseline_bytes:u64 = 0
    var baseline_saved:u64 = 0
    var disk_hash:u64 = 0
    var disk_bytes:u64 = 0
    var ok:i64 = 1

    if !IDE:App:history_read_u64(stream, &tag) || tag != IDE:App:History:TagHeader() ||
       !IDE:App:history_read_u64(stream, &version) || version != IDE:App:History:Version() ||
       !IDE:App:history_read_u64(stream, &path_bytes) || path_bytes == 0 || path_bytes > 1048576 ||
       !IDE:App:history_read_u64(stream, &baseline_bytes) || baseline_bytes > IDE:App:History:MaxBytes() ||
       !IDE:App:history_read_u64(stream, &baseline_saved) ||
       !IDE:App:history_read_u64(stream, &disk_hash) ||
       !IDE:App:history_read_u64(stream, &disk_bytes) {
        fclose(stream)
        return 0
    }

    let stored_path = IDE:App:history_read_bytes(stream, path_bytes)
    let baseline = IDE:App:history_read_bytes(stream, baseline_bytes)
    if !stored_path || !baseline || strcmp(stored_path, history.path) != 0 {
        if stored_path { free(stored_path) }
        if baseline { free(baseline) }
        fclose(stream)
        return 0
    }
    free(stored_path)

    history.baseline = baseline
    history.baseline_bytes = baseline_bytes
    history.disk_hash = disk_hash
    history.disk_bytes = disk_bytes
    history.saved_valid = baseline_saved != 0
    history.saved_id = 0
    history.log_bytes = 56 + path_bytes + baseline_bytes
    history.next_id = 1

    while ok {
        var record_tag:u64 = 0
        if !IDE:App:history_read_u64(stream, &record_tag) { break }
        history.log_bytes += 8

        if record_tag == IDE:App:History:TagNode() {
            let node = alloc(IDE:App:HistoryNode)
            if !node { ok = 0; break }
            node.deleted = cast(u8*, 0)
            node.inserted = cast(u8*, 0)
            node.snapshot = cast(u8*, 0)
            var snapshot_bytes:u64 = 0
            if !IDE:App:history_read_u64(stream, &node.id) ||
               !IDE:App:history_read_u64(stream, &node.parent_id) ||
               !IDE:App:history_read_u64(stream, &node.position) ||
               !IDE:App:history_read_u64(stream, &node.deleted_bytes) ||
               !IDE:App:history_read_u64(stream, &node.inserted_bytes) ||
               !IDE:App:history_read_u64(stream, &snapshot_bytes) ||
               node.id == 0 || node.id > IDE:App:History:MaxRecords() + 1 ||
               node.parent_id > IDE:App:History:MaxRecords() ||
               node.deleted_bytes + node.inserted_bytes + snapshot_bytes > IDE:App:History:MaxBytes() {
                IDE:App:history_node_free(node); ok = 0; break
            }
            history.log_bytes += 48
            node.deleted = IDE:App:history_read_bytes(stream, node.deleted_bytes)
            node.inserted = IDE:App:history_read_bytes(stream, node.inserted_bytes)
            if snapshot_bytes > 0 { node.snapshot = IDE:App:history_read_bytes(stream, snapshot_bytes) }
            node.snapshot_bytes = snapshot_bytes
            if !node.deleted || !node.inserted || (snapshot_bytes > 0 && !node.snapshot) || !IDE:App:history_link_node(history, node) {
                IDE:App:history_node_free(node); ok = 0; break
            }
            history.log_bytes += node.deleted_bytes + node.inserted_bytes + snapshot_bytes
            history.head = node
            history.head_id = node.id
        } else if record_tag == IDE:App:History:TagExtend() {
            var id:u64 = 0
            var bytes:u64 = 0
            if !IDE:App:history_read_u64(stream, &id) ||
               !IDE:App:history_read_u64(stream, &bytes) || bytes == 0 || bytes > IDE:App:History:MaxBytes() {
                ok = 0; break
            }
            let node = IDE:App:history_find(history, id)
            if !node || history.head != node || node.deleted_bytes != 0 || node.snapshot_bytes != 0 ||
               node.inserted_bytes + bytes > IDE:App:History:MaxBytes() {
                ok = 0; break
            }
            let extra = IDE:App:history_read_bytes(stream, bytes)
            if !extra { ok = 0; break }
            let merged = cast(u8*, malloc(node.inserted_bytes + bytes + 1))
            if !merged { free(extra); ok = 0; break }
            if node.inserted_bytes > 0 { memcpy(merged, node.inserted, node.inserted_bytes) }
            memcpy(&merged[node.inserted_bytes], extra, bytes)
            merged[node.inserted_bytes + bytes] = 0
            free(extra)
            if node.inserted { free(node.inserted) }
            node.inserted = merged
            node.inserted_bytes += bytes
            history.log_bytes += 16 + bytes
        } else if record_tag == IDE:App:History:TagHead() {
            var id:u64 = 0
            if !IDE:App:history_read_u64(stream, &id) { ok = 0; break }
            history.log_bytes += 8
            if id == 0 { history.head = cast(IDE:App:HistoryNode*, 0); history.head_id = 0 }
            else {
                let node = IDE:App:history_find(history, id)
                if !node { ok = 0; break }
                history.head = node
                history.head_id = id
            }
        } else if record_tag == IDE:App:History:TagSave() {
            var id:u64 = 0
            var hash:u64 = 0
            var bytes:u64 = 0
            if !IDE:App:history_read_u64(stream, &id) || !IDE:App:history_read_u64(stream, &hash) || !IDE:App:history_read_u64(stream, &bytes) {
                ok = 0; break
            }
            history.log_bytes += 24
            if id != 0 {
                let node = IDE:App:history_find(history, id)
                if !node { ok = 0; break }
                history.saved = node
            } else { history.saved = cast(IDE:App:HistoryNode*, 0) }
            history.saved_id = id
            history.saved_valid = 1
            history.disk_hash = hash
            history.disk_bytes = bytes
        } else {
            ok = 0
            break
        }
        if history.record_count > IDE:App:History:MaxRecords() || history.log_bytes > IDE:App:History:MaxBytes() * 2 { ok = 0; break }
    }
    fclose(stream)
    if !ok { return 0 }

    history.current = IDE:App:history_reconstruct(history, history.head)
    return history.current != cast(u8*, 0)
}

let IDE:App:history_destroy = fn (history:IDE:App:History*) -> void {
    if !history { return }
    if history.stream { fflush(history.stream); fclose(history.stream) }
    IDE:App:history_clear_nodes(history)
    if history.path { free(history.path) }
    if history.log_path { free(history.log_path) }
    if history.baseline { free(history.baseline) }
    if history.current { free(history.current) }
    free(cast(u8*, history))
}

let IDE:App:history_close = fn (state:IDE:App:State*) -> void {
    if !state || !state.history { return }
    IDE:App:history_destroy(state.history)
    state.history = cast(IDE:App:History*, 0)
}

let IDE:App:history_open = fn (state:IDE:App:State*, path:u8*, disk:u8*) -> u8* {
    if !state || !path || !disk { return cast(u8*, 0) }
    IDE:App:history_close(state)

    let history = alloc(IDE:App:History)
    if !history { return IDE:copy(disk) }
    history.path = IDE:copy(path)
    history.log_path = IDE:App:history_cache_path(state, path)
    history.stream = cast(u8*, 0)
    history.baseline = cast(u8*, 0)
    history.current = cast(u8*, 0)
    history.nodes = cast(IDE:App:HistoryNode*, 0)
    history.tail = cast(IDE:App:HistoryNode*, 0)
    history.index = cast(IDE:App:HistoryNode**, 0)
    history.index_capacity = 0
    history.head = cast(IDE:App:HistoryNode*, 0)
    history.head_id = 0
    history.redo_target = cast(IDE:App:HistoryNode*, 0)
    history.saved = cast(IDE:App:HistoryNode*, 0)
    history.saved_id = 0
    history.saved_valid = 0
    history.merge_node = cast(IDE:App:HistoryNode*, 0)
    history.next_id = 1
    history.record_count = 0
    history.log_bytes = 0
    history.disk_hash = IDE:App:history_hash(disk)
    history.disk_bytes = cast(u64, strlen(disk))
    history.enabled = history.path && history.log_path && history.disk_bytes < IDE:App:History:MaxBytes()
    history.merge_node = cast(IDE:App:HistoryNode*, 0)
    state.history = history
    if history.log_path { IDE:App:history_enforce_global(state, history.log_path) }

    if !history.enabled {
        history.current = IDE:copy(disk)
        return IDE:copy(disk)
    }

    let expected_hash = history.disk_hash
    let expected_bytes = history.disk_bytes
    if IDE:App:history_load(history) {
        if history.disk_hash == expected_hash && history.disk_bytes == expected_bytes {
            IDE:App:history_open_append(history)
            return IDE:copy(history.current)
        }
        IDE:App:history_clear_nodes(history)
        if history.baseline { free(history.baseline); history.baseline = cast(u8*, 0) }
        if history.current { free(history.current); history.current = cast(u8*, 0) }
    }

    history.disk_hash = expected_hash
    history.disk_bytes = expected_bytes
    if !IDE:App:history_rewrite(history, disk, 1) {
        history.current = IDE:copy(disk)
    }
    return IDE:copy(history.current)
}

let IDE:App:history_is_clean = fn (history:IDE:App:History*) -> i64 {
    if !history || !history.saved_valid { return 0 }
    return history.saved_id == history.head_id
}

let IDE:App:history_compact = fn (history:IDE:App:History*) -> void {
    if !history || !history.enabled || !history.current { return }
    let clean = IDE:App:history_is_clean(history)
    IDE:App:history_rewrite(history, history.current, clean)
}

let IDE:App:history_append_head = fn (history:IDE:App:History*) -> void {
    if !history { return }
    history.merge_node = cast(IDE:App:HistoryNode*, 0)
    if !history.enabled || !history.stream { return }
    if history.log_bytes + 16 >= IDE:App:History:MaxBytes() { IDE:App:history_compact(history); return }
    if IDE:App:history_write_u64(history.stream, IDE:App:History:TagHead()) &&
       IDE:App:history_write_u64(history.stream, history.head_id) {
        history.log_bytes += 16
        fflush(history.stream)
    }
}

let IDE:App:history_append_node = fn (history:IDE:App:History*, node:IDE:App:HistoryNode*) -> i64 {
    if !history || !node || !history.enabled || !history.stream { return 0 }
    let snapshot_bytes = node.snapshot_bytes
    if !IDE:App:history_write_u64(history.stream, IDE:App:History:TagNode()) ||
       !IDE:App:history_write_u64(history.stream, node.id) ||
       !IDE:App:history_write_u64(history.stream, node.parent_id) ||
       !IDE:App:history_write_u64(history.stream, node.position) ||
       !IDE:App:history_write_u64(history.stream, node.deleted_bytes) ||
       !IDE:App:history_write_u64(history.stream, node.inserted_bytes) ||
       !IDE:App:history_write_u64(history.stream, snapshot_bytes) ||
       !IDE:App:history_write_bytes(history.stream, node.deleted, node.deleted_bytes) ||
       !IDE:App:history_write_bytes(history.stream, node.inserted, node.inserted_bytes) ||
       !IDE:App:history_write_bytes(history.stream, node.snapshot, snapshot_bytes) {
        return 0
    }
    history.log_bytes += 56 + node.deleted_bytes + node.inserted_bytes + snapshot_bytes
    fflush(history.stream)
    return 1
}

let IDE:App:history_word_byte = fn (value:u8) -> i64 {
    if value >= 128 { return 1 }
    if value >= 48 && value <= 57 { return 1 }
    if value >= 65 && value <= 90 { return 1 }
    if value >= 97 && value <= 122 { return 1 }
    return value == 95
}

let IDE:App:history_word_insert = fn (data:u8*, bytes:u64) -> i64 {
    if !data || bytes == 0 { return 0 }
    var at:u64 = 0
    while at < bytes {
        if !IDE:App:history_word_byte(data[at]) { return 0 }
        at += 1
    }
    return 1
}

// Extends the current logical insertion node without creating another graph
// node. The extension record is append-only, so a partial/corrupt tail can be
// rejected on the next startup without mutating older history records.
let IDE:App:history_append_extend = fn (history:IDE:App:History*, node:IDE:App:HistoryNode*, data:u8*, bytes:u64) -> i64 {
    if !history || !node || !data || bytes == 0 || !history.enabled || !history.stream { return 0 }
    if !IDE:App:history_write_u64(history.stream, IDE:App:History:TagExtend()) ||
       !IDE:App:history_write_u64(history.stream, node.id) ||
       !IDE:App:history_write_u64(history.stream, bytes) ||
       !IDE:App:history_write_bytes(history.stream, data, bytes) {
        return 0
    }
    // Intentionally do not fflush every typed character. The next logical
    // history barrier (new node, save, undo/redo, checkout, close) flushes the
    // stdio stream, turning a word into one graph event without one fsync-like
    // flush per key press.
    history.log_bytes += 24 + bytes
    return 1
}

let IDE:App:history_capture = fn (state:IDE:App:State*, next_text:u8*) -> void {
    if !state || !next_text || state.history_replaying != 0 || !state.history { return }
    let history = state.history
    if !history.current { history.current = IDE:copy(next_text); return }
    if strcmp(history.current, next_text) == 0 { return }

    let old_bytes = cast(u64, strlen(history.current))
    let new_bytes = cast(u64, strlen(next_text))
    var prefix:u64 = 0
    while prefix < old_bytes && prefix < new_bytes && history.current[prefix] == next_text[prefix] { prefix += 1 }
    var suffix:u64 = 0
    while suffix < old_bytes - prefix && suffix < new_bytes - prefix &&
          history.current[old_bytes - suffix - 1] == next_text[new_bytes - suffix - 1] { suffix += 1 }

    let deleted_bytes = old_bytes - prefix - suffix
    let inserted_bytes = new_bytes - prefix - suffix
    if deleted_bytes == 0 && inserted_bytes == 0 { return }

    if !history.enabled {
        free(history.current)
        history.current = IDE:copy(next_text)
        return
    }

    // Coalesce only forward, word-like insertion into the current leaf. A
    // deletion/replacement is deliberately never coalesced: every backspace or
    // delete remains a separate undo/graph event. Save/undo/checkout are hard
    // barriers because they clear merge_node.
    let merge = history.merge_node
    if deleted_bytes == 0 && inserted_bytes > 0 && merge && merge == history.head &&
       merge.deleted_bytes == 0 && merge.snapshot_bytes == 0 &&
       prefix == merge.position + merge.inserted_bytes &&
       IDE:App:history_word_insert(merge.inserted, merge.inserted_bytes) &&
       IDE:App:history_word_insert(&next_text[prefix], inserted_bytes) &&
       history.log_bytes + 24 + inserted_bytes < IDE:App:History:MaxBytes() {
        let merged = cast(u8*, malloc(merge.inserted_bytes + inserted_bytes + 1))
        if merged {
            if merge.inserted_bytes > 0 { memcpy(merged, merge.inserted, merge.inserted_bytes) }
            memcpy(&merged[merge.inserted_bytes], &next_text[prefix], inserted_bytes)
            merged[merge.inserted_bytes + inserted_bytes] = 0
            if IDE:App:history_append_extend(history, merge, &next_text[prefix], inserted_bytes) {
                free(merge.inserted)
                merge.inserted = merged
                merge.inserted_bytes += inserted_bytes
                free(history.current)
                history.current = IDE:copy(next_text)
                // The graph topology did not change; avoid rebuilding the tree
                // on every character. The next logical event refreshes it.
                return
            }
            free(merged)
            history.enabled = 0
            history.merge_node = cast(IDE:App:HistoryNode*, 0)
            if history.stream { fclose(history.stream); history.stream = cast(u8*, 0) }
            free(history.current)
            history.current = IDE:copy(next_text)
            return
        }
    }
    history.merge_node = cast(IDE:App:HistoryNode*, 0)

    var projected_snapshot:u64 = 0
    if history.next_id % IDE:App:History:CheckpointEvery() == 0 { projected_snapshot = new_bytes }
    let projected = 56 + deleted_bytes + inserted_bytes + projected_snapshot
    if history.record_count + 1 >= IDE:App:History:MaxRecords() || history.log_bytes + projected >= IDE:App:History:MaxBytes() {
        // Compact the old graph before recording this edit, so even the edit
        // that crosses a limit remains undoable as node #1 of the new graph.
        IDE:App:history_compact(history)
        state.history_needs_refresh = 1
    }

    let node = alloc(IDE:App:HistoryNode)
    if !node { return }
    node.id = history.next_id
    node.parent_id = history.head_id
    node.position = prefix
    node.deleted_bytes = deleted_bytes
    node.inserted_bytes = inserted_bytes
    node.deleted = IDE:App:history_copy_bytes(history.current, prefix, deleted_bytes)
    node.inserted = IDE:App:history_copy_bytes(next_text, prefix, inserted_bytes)
    node.snapshot = cast(u8*, 0)
    node.snapshot_bytes = 0
    if !node.deleted || !node.inserted { IDE:App:history_node_free(node); return }
    if node.id % IDE:App:History:CheckpointEvery() == 0 {
        node.snapshot = IDE:copy(next_text)
        if node.snapshot { node.snapshot_bytes = new_bytes }
    }

    if !IDE:App:history_link_node(history, node) { IDE:App:history_node_free(node); return }
    if !IDE:App:history_append_node(history, node) {
        history.enabled = 0
        if history.stream { fclose(history.stream); history.stream = cast(u8*, 0) }
        IDE:App:history_clear_nodes(history)
        if history.baseline { free(history.baseline) }
        history.baseline = IDE:copy(next_text)
        history.baseline_bytes = new_bytes
        if history.current { free(history.current) }
        history.current = IDE:copy(next_text)
        state.history_needs_refresh = 1
        return
    }

    history.head = node
    history.head_id = node.id
    history.redo_target = cast(IDE:App:HistoryNode*, 0)
    history.next_id = node.id + 1
    history.merge_node = cast(IDE:App:HistoryNode*, 0)
    if node.deleted_bytes == 0 && node.snapshot_bytes == 0 && IDE:App:history_word_insert(node.inserted, node.inserted_bytes) {
        history.merge_node = node
    }
    if history.current { free(history.current) }
    history.current = IDE:copy(next_text)
    if node.id % IDE:App:History:CheckpointEvery() == 0 || deleted_bytes + inserted_bytes >= 1048576 {
        IDE:App:history_enforce_global(state, history.log_path)
    }

    if state.history_visible != 0 { state.history_needs_refresh = 1 }
}

let IDE:App:history_flush = fn (history:IDE:App:History*) -> void {
    if history && history.stream { fflush(history.stream) }
}

let IDE:App:history_mark_saved = fn (state:IDE:App:State*, text:u8*) -> void {
    if !state || !state.history || !text { return }
    let history = state.history
    history.merge_node = cast(IDE:App:HistoryNode*, 0)
    history.saved_id = history.head_id
    history.saved = history.head
    history.saved_valid = 1
    history.disk_hash = IDE:App:history_hash(text)
    history.disk_bytes = cast(u64, strlen(text))
    if history.enabled && history.stream {
        if history.log_bytes + 32 >= IDE:App:History:MaxBytes() {
            IDE:App:history_compact(history)
            state.history_needs_refresh = 1
            return
        }
        if IDE:App:history_write_u64(history.stream, IDE:App:History:TagSave()) &&
           IDE:App:history_write_u64(history.stream, history.saved_id) &&
           IDE:App:history_write_u64(history.stream, history.disk_hash) &&
           IDE:App:history_write_u64(history.stream, history.disk_bytes) {
            history.log_bytes += 32
            fflush(history.stream)
        }
    }
    state.history_needs_refresh = 1
}

let IDE:App:history_set_editor = fn (state:IDE:App:State*, text:u8*) -> void {
    if !state || !state.history || !text { return }
    let history = state.history
    if history.current { free(history.current) }
    history.current = IDE:copy(text)
    state.history_replaying = 1
    Gui:text_set(state.editor, text)
    state.history_replaying = 0
}

let IDE:App:history_undo = fn (state:IDE:App:State*) -> void {
    if !state || !state.history || !state.history.current || !state.history.head { return }
    let history = state.history
    let current = history.head
    if !history.redo_target { history.redo_target = current }
    let next = IDE:App:history_apply_inverse(history.current, current)
    if !next { return }
    history.head = current.parent
    history.head_id = current.parent_id
    IDE:App:history_set_editor(state, next)
    free(next)
    IDE:App:history_append_head(history)
    state.history_needs_refresh = 1
}

let IDE:App:history_redo = fn (state:IDE:App:State*) -> void {
    if !state || !state.history || !state.history.current { return }
    let history = state.history
    var child:IDE:App:HistoryNode* = cast(IDE:App:HistoryNode*, 0)

    // A chain of Ctrl+Z operations remembers the exact original head. Ctrl+Y
    // walks back along that branch even when the parent has newer branches.
    if history.redo_target {
        var cursor = history.redo_target
        while cursor && cursor.parent_id != history.head_id { cursor = cursor.parent }
        if cursor && cursor.parent_id == history.head_id { child = cursor }
    }
    if !child {
        if history.head { child = history.head.first_child }
        else {
            var node = history.nodes
            while node {
                if node.parent_id == 0 && (!child || node.id > child.id) { child = node }
                node = node.next
            }
        }
    }
    if !child { return }
    let next = IDE:App:history_apply_forward(history.current, child)
    if !next { return }
    history.head = child
    history.head_id = child.id
    if history.redo_target == child { history.redo_target = cast(IDE:App:HistoryNode*, 0) }
    IDE:App:history_set_editor(state, next)
    free(next)
    IDE:App:history_append_head(history)
    state.history_needs_refresh = 1
}

let IDE:App:history_checkout = fn (state:IDE:App:State*, id:u64) -> void {
    if !state || !state.history { return }
    let history = state.history
    history.merge_node = cast(IDE:App:HistoryNode*, 0)
    var target = cast(IDE:App:HistoryNode*, 0)
    if id != 0 {
        target = IDE:App:history_find(history, id)
        if !target { return }
    }
    let text = IDE:App:history_reconstruct(history, target)
    if !text { return }
    history.head = target
    history.head_id = id
    history.redo_target = cast(IDE:App:HistoryNode*, 0)
    IDE:App:history_set_editor(state, text)
    free(text)
    IDE:App:history_append_head(history)
    state.history_needs_refresh = 1
}

let IDE:App:on_undo = fn (widget:u8*, data:u8*) -> void {
    IDE:App:history_undo(cast(IDE:App:State*, data))
}

let IDE:App:on_redo = fn (widget:u8*, data:u8*) -> void {
    IDE:App:history_redo(cast(IDE:App:State*, data))
}

let IDE:App:history_status = fn (state:IDE:App:State*) -> void {
    if !state || !state.history_status { return }
    let text = LanguageKit:Text:new()
    if !text { return }
    if !state.history { text.append("No file selected") }
    else {
        text.append("HEAD #")
        IDE:append_u64(text, state.history.head_id)
        text.append("  |  saved ")
        if state.history.saved_valid {
            text.append("#")
            IDE:append_u64(text, state.history.saved_id)
        } else { text.append("outside retained history") }
        text.append("  |  records ")
        IDE:append_u64(text, state.history.record_count)
        text.append(" / ")
        IDE:append_u64(text, IDE:App:History:MaxRecords())
        text.append("  |  log ")
        IDE:append_u64(text, state.history.log_bytes / 1024)
        text.append(" KiB")
    }
    Gui:label_text(state.history_status, text.data)
    text.destroy()
}

let IDE:App:history_append_preview = fn (text:LanguageKit:Text*, data:u8*, bytes:u64, action:u8*) -> void {
    if !text || !data || bytes == 0 || !action { return }
    text.append("   ")
    text.append(action)
    text.append(" \"")
    var at:u64 = 0
    while at < bytes && at < 40 {
        let ch = data[at]
        if ch == 10 { text.append("\\n") }
        else if ch == 13 { text.append("\\r") }
        else if ch == 9 { text.append("\\t") }
        else if ch == 34 || ch == 92 { text.append_byte(92); text.append_byte(ch) }
        else if ch >= 32 && ch < 127 { text.append_byte(ch) }
        else { text.append("?") }
        at += 1
    }
    if bytes > 40 { text.append("...") }
    text.append("\"")
}

let IDE:App:history_node_label = fn (history:IDE:App:History*, node:IDE:App:HistoryNode*) -> u8* {
    if !history || !node { return cast(u8*, 0) }
    let text = LanguageKit:Text:new()
    if !text { return cast(u8*, 0) }
    var depth:u64 = 0
    while depth < node.branch_depth && depth < 12 { text.append("|  "); depth += 1 }
    if node.branch_depth > 12 { text.append("... ") }
    text.append("o #")
    IDE:append_u64(text, node.id)
    text.append(" <- #")
    IDE:append_u64(text, node.parent_id)
    text.append("   +")
    IDE:append_u64(text, node.inserted_bytes)
    text.append(" -")
    IDE:append_u64(text, node.deleted_bytes)
    if node.inserted_bytes > 0 { IDE:App:history_append_preview(text, node.inserted, node.inserted_bytes, "insert") }
    else if node.deleted_bytes > 0 { IDE:App:history_append_preview(text, node.deleted, node.deleted_bytes, "delete") }
    if node.id == history.head_id { text.append("   [HEAD]") }
    if history.saved_valid && node.id == history.saved_id { text.append("   [saved]") }
    if node.snapshot { text.append("   checkpoint") }
    let result = text.take()
    text.destroy()
    return result
}

let IDE:App:history_refresh = fn (state:IDE:App:State*) -> void {
    if !state || !state.history_tree { return }
    if state.history_refresh_idle_source != 0 {
        Gui:source_remove(state.history_refresh_idle_source)
        state.history_refresh_idle_source = 0
    }
    state.history_refreshing = 1
    Gui:tree_clear(state.history_tree)

    let root_text = LanguageKit:Text:new()
    if root_text {
        root_text.append("o #0   retained baseline")
        if state.history && state.history.head_id == 0 { root_text.append("   [HEAD]") }
        if state.history && state.history.saved_valid && state.history.saved_id == 0 { root_text.append("   [saved]") }
    }
    var root_label:u8* = "o #0   retained baseline"
    if root_text { root_label = root_text.data }
    let root_path = "0"
    let root = Gui:tree_append(state.history_tree, cast(u8*, 0), root_label, root_path, 0)
    if root_text { root_text.destroy() }
    Gui:tree_iter_free(root)

    if state.history {
        var id = state.history.next_id
        while id > 1 {
            id -= 1
            let node = IDE:App:history_find(state.history, id)
            if node {
                let label = IDE:App:history_node_label(state.history, node)
                let path = IDE:App:history_u64_text(node.id)
                if label && path {
                    let row = Gui:tree_append(state.history_tree, cast(u8*, 0), label, path, 0)
                    Gui:tree_iter_free(row)
                }
                if label { free(label) }
                if path { free(path) }
            }
        }
    }
    state.history_needs_refresh = 0
    IDE:App:history_status(state)
    state.history_refreshing = 0
}

let IDE:App:history_refresh_idle = fn (data:u8*) -> i32 {
    let state = cast(IDE:App:State*, data)
    if !state { return 0 }
    state.history_refresh_idle_source = 0
    if state.history_visible != 0 && state.history_needs_refresh != 0 {
        IDE:App:history_refresh(state)
    }
    return 0
}

let IDE:App:history_schedule_refresh = fn (state:IDE:App:State*) -> void {
    if !state || state.history_visible == 0 { return }
    if state.history_refresh_idle_source == 0 {
        // Never rebuild GtkTreeStore while its selection-changed signal is on
        // the stack. One deterministic main-loop turn is enough; there is no
        // timeout or debounce involved.
        state.history_refresh_idle_source = Gui:idle(IDE:App:history_refresh_idle, cast(u8*, state))
    }
}

let IDE:App:on_history_selected = fn (selection:u8*, data:u8*) -> void {
    let state = cast(IDE:App:State*, data)
    if !state || !selection || !state.history_tree || state.history_refreshing != 0 { return }
    let iterator = Gui:tree_selected_iter(selection)
    if !iterator { return }
    var directory:i32 = 0
    var loaded:i32 = 0
    let path = Gui:tree_iter_path(state.history_tree, iterator, &directory, &loaded)
    if !path {
        Gui:tree_iter_free(iterator)
        return
    }
    let id = IDE:App:history_parse_u64(path)
    if state.history && id == state.history.head_id {
        Gui:text_free(path)
        Gui:tree_iter_free(iterator)
        return
    }
    // Release everything tied to the current GtkTreeStore before checkout.
    // Rebuilding the model from inside this callback used to invalidate the
    // active iterator/selection and could segfault.
    Gui:text_free(path)
    Gui:tree_iter_free(iterator)
    IDE:App:history_checkout(state, id)
    IDE:App:history_schedule_refresh(state)
}

let IDE:App:on_history_refresh = fn (widget:u8*, data:u8*) -> void {
    IDE:App:history_refresh(cast(IDE:App:State*, data))
}

let IDE:App:show_history = fn (state:IDE:App:State*) -> void {
    if !state || !state.sidebar_stack || !state.history_pane { return }
    state.history_visible = 1
    state.search_visible = 0
    state.intelligence_visible = 0
    if state.history_needs_refresh != 0 { IDE:App:history_refresh(state) }
    else { IDE:App:history_status(state) }
    Gui:stack_select(state.sidebar_stack, state.history_pane)
}

let IDE:App:show_explorer = fn (state:IDE:App:State*) -> void {
    if !state || !state.sidebar_stack || !state.explorer_pane { return }
    state.history_visible = 0
    state.search_visible = 0
    state.intelligence_visible = 0
    Gui:stack_select(state.sidebar_stack, state.explorer_pane)
}

let IDE:App:on_show_history = fn (widget:u8*, data:u8*) -> void {
    IDE:App:show_history(cast(IDE:App:State*, data))
}

let IDE:App:on_show_explorer = fn (widget:u8*, data:u8*) -> void {
    IDE:App:show_explorer(cast(IDE:App:State*, data))
}

let IDE:App:create_history_view = fn (state:IDE:App:State*) -> u8* {
    let pane = Gui:column(0)
    Gui:class_add(pane, "explorer-pane")

    let header = Gui:row(0)
    Gui:class_add(header, "explorer-header")
    Gui:align_top(header)
    Gui:expand_x(header, 1)
    let title = Gui:label("HISTORY")
    Gui:label_align(title, cast(f32, 0.0))
    Gui:class_add(title, "explorer-title")
    Gui:append(header, title, 1, 0)

    let explorer = Gui:icon_button("folder-symbolic", "Back to Explorer")
    let refresh = Gui:icon_button("view-refresh-symbolic", "Refresh History")
    Gui:on_click(explorer, IDE:App:on_show_explorer, cast(u8*, state))
    Gui:on_click(refresh, IDE:App:on_history_refresh, cast(u8*, state))
    Gui:append_end(header, refresh, 0, 0)
    Gui:append_end(header, explorer, 0, 2)
    Gui:append(pane, header, 0, 0)

    state.history_status = Gui:label("No file selected")
    Gui:label_align(state.history_status, cast(f32, 0.0))
    Gui:class_add(state.history_status, "explorer-root")
    Gui:append(pane, state.history_status, 0, 0)

    state.history_tree = Gui:tree()
    Gui:on_tree_select(state.history_tree, IDE:App:on_history_selected, cast(u8*, state))
    Gui:append(pane, Gui:scroll(state.history_tree), 1, 0)
    state.history_pane = pane
    return pane
}

let IDE:App:history_retarget = fn (state:IDE:App:State*, new_path:u8*) -> void {
    if !state || !state.history || !new_path || !state.history.current { return }
    let history = state.history
    let old_log = IDE:copy(history.log_path)
    let current = IDE:copy(history.current)
    let clean = IDE:App:history_is_clean(history)
    let disk_hash = history.disk_hash
    let disk_bytes = history.disk_bytes
    IDE:App:history_destroy(history)
    state.history = cast(IDE:App:History*, 0)

    let next = alloc(IDE:App:History)
    if !next { if old_log { free(old_log) }; if current { free(current) }; return }
    next.path = IDE:copy(new_path)
    next.log_path = IDE:App:history_cache_path(state, new_path)
    next.stream = cast(u8*, 0)
    next.baseline = cast(u8*, 0)
    next.current = cast(u8*, 0)
    next.nodes = cast(IDE:App:HistoryNode*, 0)
    next.tail = cast(IDE:App:HistoryNode*, 0)
    next.index = cast(IDE:App:HistoryNode**, 0)
    next.index_capacity = 0
    next.head = cast(IDE:App:HistoryNode*, 0)
    next.head_id = 0
    next.redo_target = cast(IDE:App:HistoryNode*, 0)
    next.saved = cast(IDE:App:HistoryNode*, 0)
    next.saved_id = 0
    next.saved_valid = clean
    next.next_id = 1
    next.record_count = 0
    next.log_bytes = 0
    next.disk_hash = disk_hash
    next.disk_bytes = disk_bytes
    next.enabled = next.path && next.log_path && current
    next.merge_node = cast(IDE:App:HistoryNode*, 0)
    state.history = next
    if current && next.enabled { IDE:App:history_rewrite(next, current, clean) }
    else if current { next.current = IDE:copy(current) }
    if old_log { unlink(old_log); free(old_log) }
    if current { free(current) }
    state.history_needs_refresh = 1
}

// Project modules are cached as .rli images. Native addresses must always be
// rebound from libc when a cached module is loaded in another process.
set fflush.serializable = false
