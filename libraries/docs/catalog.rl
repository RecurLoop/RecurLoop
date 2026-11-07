// Owned documentation catalog. No catalog or native pointer is stored in an image.
extern realpath(path:u8*, resolved:u8*) -> u8* abi sysv-amd64
extern readlink(path:u8*, buffer:u8*, size:u64) -> i64 abi sysv-amd64
extern mkdtemp(pattern:u8*) -> u8* abi sysv-amd64

record Docs:Entry {
    id:u8* title:u8* section:u8* body:u8* inline_docs:u8*
    source_path:u8* origin_path:u8* scope:u8* repository:u8* version:u8*
    symbol:u8* exported_id:u8* source_url:u8* owner:u8* home:i64 order:i64 hits:i64 seen:i64 matches:i64
    previous:Docs:Entry* next:Docs:Entry*
}
record Docs:Posting { entry:Docs:Entry* next:Docs:Posting* }
record Docs:Term { word:u8* first:Docs:Posting* last_seen:Docs:Entry* next:Docs:Term* }
record Docs:Store {
    name:u8* version:u8* repository:u8* root:u8*
    first:Docs:Entry* last:Docs:Entry* loaded:LanguageKit:Text* error:i64
    terms:Docs:Term** index_ready:i64 index_builds:i64 query:u8* revision:u8*
}
let Docs:new = fn (name:u8*, version:u8*, repository:u8*) -> Docs:Store* {
    let store = cast(Docs:Store*, calloc(1, sizeof(Docs:Store)))
    if !store { return store }
    store.name = Docs:copy(name); store.version = Docs:copy(version); store.repository = Docs:copy(repository)
    store.root = Docs:copy(""); store.loaded = LanguageKit:Text:new(); store.revision = Docs:copy("")
    store.terms = cast(Docs:Term**, calloc(4096, sizeof(Docs:Term*)))
    if !store.terms { store.error = 1 }
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
    let owner = cast(Docs:Store*, entry.owner); if owner { owner.index_ready = 0 }
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
    entry.symbol = Docs:copy(""); entry.exported_id = Docs:copy(""); entry.source_url = Docs:copy(""); entry.owner = cast(u8*, store)
    store.index_ready = 0
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
// Zero keeps legacy alphabetical fallback; positive ranks define a reading path.
let Docs:parse_order = fn (text:u8*) -> i64 {
    if !text || text[0] == 0 { return -1 }
    var value:i64 = 0; var at = 0
    while text[at] != 0 {
        let digit = text[at]
        if digit < 48 || digit > 57 { return -1 }
        value = value * 10 + cast(i64, digit - 48)
        if value > 1000000 { return -1 }; at += 1
    }
    return value
}
let Docs:valid_id = fn (id:u8*) -> i64 {
    if Docs:empty(id) || strlen(id) > 120 { return 0 }
    var i = 0
    while id[i] != 0 { let ch = id[i]; if !((ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 45 || ch == 95) { return 0 }; i += 1 }
    return 1
}
