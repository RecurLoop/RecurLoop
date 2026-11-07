// Generated inverted index: UTF-8 words, prefix queries, stable document identities.
let Docs:word_byte = fn (ch:u8) -> i64 {
    return (ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95 || ch >= 128
}
let Docs:word_hash = fn (word:u8*) -> u64 {
    var hash = cast(u64, 5381); var at = 0
    while word[at] != 0 { hash = hash * 131 + cast(u64, word[at]); at += 1 }; return hash % 4096
}
let Docs:term = fn (store:Docs:Store*, word:u8*, create:i64) -> Docs:Term* {
    let bucket = Docs:word_hash(word)
    var previous = cast(Docs:Term*, 0); var term = store.terms[bucket]
    while term { let order = strcmp(term.word, word); if order == 0 { return term }; if order > 0 { break }; previous = term; term = term.next }
    if !create { return cast(Docs:Term*, 0) }
    let added = cast(Docs:Term*, calloc(1, sizeof(Docs:Term)))
    if !added { store.error = 1; return added }; added.word = Docs:copy(word); added.next = term
    if previous { previous.next = added } else { store.terms[bucket] = added }; return added
}
let Docs:posting = fn (store:Docs:Store*, term:Docs:Term*, entry:Docs:Entry*) -> i64 {
    if !term || !entry { return 0 }; if term.last_seen == entry { return 1 }; term.last_seen = entry
    var previous = cast(Docs:Posting*, 0); var item = term.first
    while item {
        let scope_order = strcmp(item.entry.scope, entry.scope)
        let id_order = strcmp(item.entry.id, entry.id)
        if scope_order == 0 && id_order == 0 { return 1 }
        if scope_order > 0 || (scope_order == 0 && id_order > 0) { break }; previous = item; item = item.next
    }
    let added = cast(Docs:Posting*, calloc(1, sizeof(Docs:Posting)))
    if !added { store.error = 1; return 0 }; added.entry = entry; added.next = item
    if previous { previous.next = added } else { term.first = added }; return 1
}
let Docs:clear_index = fn (store:Docs:Store*) -> void {
    var bucket = 0
    while bucket < 4096 {
        var term = store.terms[bucket]
        while term {
            let next = term.next; var posting = term.first
            while posting { let following = posting.next; free(cast(u8*, posting)); posting = following }
            free(term.word); free(cast(u8*, term)); term = next
        }
        store.terms[bucket] = cast(Docs:Term*, 0); bucket += 1
    }
    store.index_ready = 0; free(store.query); store.query = cast(u8*, 0)
}
let Docs:index_text = fn (store:Docs:Store*, entry:Docs:Entry*, text:u8*) -> i64 {
    if !text { return 1 }; var at = 0
    while text[at] != 0 {
        if !Docs:word_byte(text[at]) { at += 1; continue }
        let start = at; while Docs:word_byte(text[at]) { at += 1 }
        if at - start > 512 { continue }
        let word = LanguageKit:copy_bytes(&text[start], at - start)
        if !word { store.error = 1; return 0 }
        var i = 0; while word[i] != 0 { word[i] = Docs:lower(word[i]); i += 1 }
        let term = Docs:term(store, word, 1); free(word)
        if !Docs:posting(store, term, entry) { return 0 }
    }; return 1
}
let Docs:build_index = fn (store:Docs:Store*) -> i64 {
    if !store || store.error { return 0 }; if store.index_ready { return 1 }
    Docs:clear_index(store); var entry = store.first
    while entry {
        if !Docs:index_text(store, entry, entry.title) || !Docs:index_text(store, entry, entry.scope) || !Docs:index_text(store, entry, entry.symbol) || !Docs:index_text(store, entry, entry.inline_docs) || !Docs:index_text(store, entry, entry.body) { return 0 }
        entry = entry.next
    }
    store.index_ready = 1; store.index_builds += 1; return 1
}
let Docs:prefix = fn (text:u8*, prefix:u8*) -> i64 {
    var i = 0; while prefix[i] != 0 { if text[i] != prefix[i] { return 0 }; i += 1 }; return 1
}
let Docs:prepare_query = fn (store:Docs:Store*, query:u8*) -> i64 {
    if !Docs:build_index(store) { return 0 }
    if store.query && strcmp(store.query, query) == 0 { return 1 }
    free(store.query); store.query = Docs:copy(query)
    var entry = store.first; while entry { entry.hits = 0; entry.seen = 0; entry.matches = 0; entry = entry.next }
    var at = 0; var words = 0
    while query[at] != 0 {
        if !Docs:word_byte(query[at]) { at += 1; continue }
        let start = at; while Docs:word_byte(query[at]) { at += 1 }
        let word = LanguageKit:copy_bytes(&query[start], at - start)
        var i = 0; while word[i] != 0 { word[i] = Docs:lower(word[i]); i += 1 }; words += 1
        var bucket = 0
        while bucket < 4096 {
            var term = store.terms[bucket]
            while term {
                if Docs:prefix(term.word, word) {
                    var posting = term.first
                    while posting { if posting.entry.seen != words { posting.entry.hits += 1; posting.entry.seen = words }; posting = posting.next }
                }; term = term.next
            }; bucket += 1
        }; free(word)
    }
    entry = store.first
    while entry {
        entry.matches = entry.hits == words
        if words == 0 && !Docs:empty(query) { entry.matches = Docs:contains(entry.title, query) }
        entry = entry.next
    }; return 1
}
let Docs:search = fn (store:Docs:Store*, query:u8*, after:Docs:Entry*) -> Docs:Entry* {
    if !store || !Docs:prepare_query(store, query) { return cast(Docs:Entry*, 0) }
    var entry = store.first; if after { entry = after.next }
    while entry { if entry.matches { return entry }; entry = entry.next }; return cast(Docs:Entry*, 0)
}
let Docs:sort = fn (store:Docs:Store*) -> void {
    var input = store.first; var first = cast(Docs:Entry*, 0)
    while input {
        let next = input.next; var previous = cast(Docs:Entry*, 0); var cursor = first
        while cursor {
            var order:i64 = strcmp(input.scope, cursor.scope)
            if strcmp(input.scope, store.name) == 0 && strcmp(cursor.scope, store.name) != 0 { order = -1 }
            else if strcmp(cursor.scope, store.name) == 0 && strcmp(input.scope, store.name) != 0 { order = 1 }
            if order == 0 {
                if input.home != cursor.home { order = cursor.home - input.home }
                else if input.order != cursor.order {
                    if input.order == 0 { order = 1 }
                    else if cursor.order == 0 { order = -1 }
                    else { order = input.order - cursor.order }
                }
                else { order = strcmp(input.section, cursor.section); if order == 0 { order = strcmp(input.title, cursor.title) }; if order == 0 { order = strcmp(input.id, cursor.id) } }
            }
            if order < 0 { break }; previous = cursor; cursor = cursor.next
        }
        input.previous = previous; input.next = cursor
        if previous { previous.next = input } else { first = input }; if cursor { cursor.previous = input }
        input = next
    }
    store.first = first; store.last = first; while store.last && store.last.next { store.last = store.last.next }
}

let Docs:destroy = fn (store:Docs:Store*) -> void {
    if !store { return }
    Docs:clear_index(store); free(cast(u8*, store.terms)); free(store.revision)
    var entry = store.first
    while entry {
        let next = entry.next
        free(entry.id); free(entry.title); free(entry.section); free(entry.body); free(entry.inline_docs)
        free(entry.symbol); free(entry.exported_id); free(entry.source_url); free(entry.source_path); free(entry.origin_path); free(entry.scope); free(entry.repository); free(entry.version)
        free(cast(u8*, entry)); entry = next
    }
    free(store.name); free(store.version); free(store.repository); free(store.root)
    if store.loaded { store.loaded.destroy() }; free(cast(u8*, store))
}
