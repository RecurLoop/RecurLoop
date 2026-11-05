// Owned documentation catalog. No catalog or native pointer is stored in an image.
extern realpath(path:u8*, resolved:u8*) -> u8* abi sysv-amd64
extern readlink(path:u8*, buffer:u8*, size:u64) -> i64 abi sysv-amd64
extern mkdtemp(pattern:u8*) -> u8* abi sysv-amd64

record Docs:Entry {
    id:u8* title:u8* section:u8* body:u8* inline_docs:u8*
    source_path:u8* origin_path:u8* scope:u8* repository:u8* version:u8*
    previous:Docs:Entry* next:Docs:Entry*
}
record Docs:Store {
    name:u8* version:u8* repository:u8* root:u8*
    first:Docs:Entry* last:Docs:Entry* loaded:LanguageKit:Text* error:i64
}
let Docs:new = fn (name:u8*, version:u8*, repository:u8*) -> Docs:Store* {
    let store = cast(Docs:Store*, calloc(1, sizeof(Docs:Store)))
    if !store { return store }
    store.name = Docs:copy(name); store.version = Docs:copy(version); store.repository = Docs:copy(repository)
    store.root = Docs:copy(""); store.loaded = LanguageKit:Text:new()
    return store
}
let Docs:find = fn (store:Docs:Store*, scope:u8*, id:u8*) -> Docs:Entry* {
    if !store { return cast(Docs:Entry*, 0) }
    var entry = store.first
    while entry { if strcmp(entry.id, id) == 0 && (Docs:empty(scope) || strcmp(entry.scope, scope) == 0) { return entry }; entry = entry.next }
    return cast(Docs:Entry*, 0)
}
let Docs:set_body = fn (entry:Docs:Entry*, body:u8*) -> i64 {
    if !entry { return 0 }
    let copy = Docs:copy(body)
    if !copy { return 0 }
    free(entry.body); entry.body = copy
    return 1
}
let Docs:add = fn (store:Docs:Store*, scope:u8*, id:u8*, title:u8*, section:u8*, body:u8*, source:u8*, origin:u8*) -> Docs:Entry* {
    if !store || Docs:empty(id) || Docs:empty(title) { return cast(Docs:Entry*, 0) }
    let existing = Docs:find(store, scope, id)
    if existing { Docs:set_body(existing, body); return existing }
    let entry = cast(Docs:Entry*, calloc(1, sizeof(Docs:Entry)))
    if !entry { store.error = 1; return entry }
    entry.id = Docs:copy(id); entry.title = Docs:copy(title); entry.section = Docs:copy(section); entry.body = Docs:copy(body)
    entry.inline_docs = Docs:copy(""); entry.source_path = Docs:copy(source); entry.origin_path = Docs:copy(origin)
    entry.scope = Docs:copy(scope); entry.repository = Docs:copy(store.repository); entry.version = Docs:copy(store.version)
    entry.previous = store.last
    if store.last { store.last.next = entry } else { store.first = entry }
    store.last = entry
    return entry
}
let Docs:lower = fn (ch:u8) -> u8 { if ch >= 65 && ch <= 90 { return ch + 32 }; return ch }
let Docs:contains = fn (text:u8*, query:u8*) -> i64 {
    if !text || !query { return 0 }
    if query[0] == 0 { return 1 }
    var at = 0
    while text[at] != 0 {
        var i = 0
        while query[i] != 0 && text[at + i] != 0 && Docs:lower(text[at + i]) == Docs:lower(query[i]) { i += 1 }
        if query[i] == 0 { return 1 }; at += 1
    }
    return 0
}
// Returns the next borrowed matching object; pass null for the first result.
let Docs:search = fn (store:Docs:Store*, query:u8*, after:Docs:Entry*) -> Docs:Entry* {
    if !store { return cast(Docs:Entry*, 0) }
    var entry = store.first
    if after { entry = after.next }
    while entry {
        if Docs:contains(entry.title, query) || Docs:contains(entry.body, query) || Docs:contains(entry.inline_docs, query) || Docs:contains(entry.scope, query) { return entry }
        entry = entry.next
    }
    return cast(Docs:Entry*, 0)
}
let Docs:as_text = fn (entry:Docs:Entry*) -> u8* {
    if !entry { return cast(u8*, 0) }
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }; defer out.destroy()
    out.append("# "); out.append(entry.title); out.append("\n\n")
    if !Docs:empty(entry.inline_docs) { out.append(entry.inline_docs); out.append("\n\n") }
    var body = entry.body
    if body && body[0] == 35 && body[1] == 32 {
        var at = 0
        while entry.title[at] != 0 && body[at + 2] == entry.title[at] { at += 1 }
        if entry.title[at] == 0 && (body[at + 2] == 0 || body[at + 2] == 10 || body[at + 2] == 13) {
            body = &body[at + 2]; while body[0] == 10 || body[0] == 13 { body = &body[1] }
        }
    }
    out.append(body)
    return out.take()
}
let Docs:save = fn (entry:Docs:Entry*, path:u8*) -> i64 { if !entry { return 0 }; return Docs:write_file(path, entry.body) }
let Docs:destroy = fn (store:Docs:Store*) -> void {
    if !store { return }
    var entry = store.first
    while entry {
        let next = entry.next
        free(entry.id); free(entry.title); free(entry.section); free(entry.body); free(entry.inline_docs)
        free(entry.source_path); free(entry.origin_path); free(entry.scope); free(entry.repository); free(entry.version)
        free(cast(u8*, entry)); entry = next
    }
    free(store.name); free(store.version); free(store.repository); free(store.root)
    if store.loaded { store.loaded.destroy() }; free(cast(u8*, store))
}
let Docs:setting = fn (text:u8*, key:u8*, fallback:u8*) -> u8* {
    if !text { return Docs:copy(fallback) }
    var at = 0
    let size = cast(i64, strlen(key))
    while text[at] != 0 {
        var end = at
        while text[end] != 0 && text[end] != 10 { end += 1 }
        var i = 0
        while i < size && at + i < end && text[at + i] == key[i] { i += 1 }
        if i == size && at + i < end && text[at + i] == 61 { return Docs:trim(LanguageKit:copy_bytes(&text[at + i + 1], end - at - i - 1)) }
        if text[end] == 0 { break }; at = end + 1
    }
    return Docs:copy(fallback)
}
let Docs:valid_id = fn (id:u8*) -> i64 {
    if Docs:empty(id) || strlen(id) > 120 { return 0 }
    var i = 0
    while id[i] != 0 { let ch = id[i]; if !((ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 45 || ch == 95) { return 0 }; i += 1 }
    return 1
}
let Docs:title = fn (body:u8*, fallback:u8*) -> u8* {
    var at = 0
    while body[at] != 0 {
        if (at == 0 || body[at - 1] == 10) && body[at] == 35 && body[at + 1] == 32 {
            var end = at + 2
            while body[end] != 0 && body[end] != 10 && body[end] != 13 { end += 1 }
            return LanguageKit:copy_bytes(&body[at + 2], end - at - 2)
        }; at += 1
    }
    return Docs:copy(fallback)
}
let Docs:load_page = fn (store:Docs:Store*, root:u8*, directory:u8*, scope:u8*, id:u8*, title:u8*, section:u8*, filename:u8*, origin:u8*) -> i64 {
    if !Docs:valid_id(id) || Docs:find(store, scope, id) { store.error = 1; return 0 }
    let source = Docs:join(directory, filename)
    let absolute = Docs:join(root, source)
    defer free(source); defer free(absolute)
    let body = Docs:read_file(absolute)
    if !body { store.error = 1; return 0 }; defer free(body)
    let entry = Docs:add(store, scope, id, title, section, body, source, origin)
    return entry != cast(Docs:Entry*, 0)
}
let Docs:load_directory = fn (store:Docs:Store*, root:u8*, directory:u8*, scope:u8*) -> i64 {
    let full = Docs:join(root, directory)
    defer free(full)
    if access(full, 4) != 0 { return 1 }
    let canonical = realpath(full, cast(u8*, 0))
    if !canonical { store.error = 1; return 0 }; defer free(canonical)
    let marker = LanguageKit:Text:new()
    marker.append("\n"); marker.append(canonical); marker.append("\n")
    defer marker.destroy()
    if store.loaded.data && strstr(store.loaded.data, marker.data) { return 1 }
    store.loaded.append(marker.data)
    let indexpath = Docs:join(full, "index.tsv")
    defer free(indexpath)
    let index = Docs:read_file(indexpath)
    if index {
        defer free(index)
        let columns = cast(u8**, calloc(5, sizeof(u8*)))
        defer free(cast(u8*, columns))
        var line = index
        while line && line[0] != 0 {
            var end = 0
            while line[end] != 0 && line[end] != 10 { end += 1 }
            var next = cast(u8*, 0)
            if line[end] == 10 { line[end] = 0; next = &line[end + 1] }
            if line[0] != 35 && line[0] != 0 {
                var count = 1; columns[0] = line; columns[4] = ""
                var at = 0
                while at < end { if line[at] == 9 { line[at] = 0; if count < 5 { columns[count] = &line[at + 1]; count += 1 } }; at += 1 }
                if count < 4 || !Docs:load_page(store, root, directory, scope, columns[0], columns[1], columns[2], columns[3], columns[4]) { store.error = 1; return 0 }
            }
            line = next
        }
    } else {
        let paths = capture find "{full}" -type f -name "*.md" | sort
        if !paths { store.error = 1; return 0 }; defer free(paths)
        var line = paths
        while line[0] != 0 {
            var end = 0
            while line[end] != 0 && line[end] != 10 { end += 1 }
            let more = line[end] == 10; line[end] = 0
            let relative = &line[strlen(full) + 1]
            let id = Docs:copy(relative)
            var at = 0
            while id[at] != 0 { if id[at] == 47 || id[at] == 46 || id[at] == 32 { id[at] = 45 }; at += 1 }
            if at > 3 { id[at - 3] = 0 }
            let body = Docs:read_file(line)
            if !body { free(id); store.error = 1; return 0 }
            let title = Docs:title(body, id)
            let source = Docs:join(directory, relative)
            if !Docs:valid_id(id) || !Docs:add(store, scope, id, title, "Dokumentacja", body, source, source) { store.error = 1 }
            free(id); free(body); free(title); free(source)
            if store.error { return 0 }
            if !more { break }; line = &line[end + 1]
        }
    }
    return 1
}
