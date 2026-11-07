// Portable JSON imports preserve the exported index; merging never re-tokenizes it.
let Docs:find_exported = fn (store:Docs:Store*, id:u8*) -> Docs:Entry* {
    var entry = store.first
    while entry { if strcmp(entry.exported_id, id) == 0 { return entry }; entry = entry.next }; return cast(Docs:Entry*, 0)
}
let Docs:copy_details = fn (to:Docs:Entry*, from:Docs:Entry*) -> void {
    free(to.inline_docs); to.inline_docs = Docs:copy(from.inline_docs)
    free(to.symbol); to.symbol = Docs:copy(from.symbol)
    free(to.exported_id); to.exported_id = Docs:copy(from.exported_id)
    free(to.source_url); to.source_url = Docs:copy(from.source_url)
    free(to.repository); to.repository = Docs:copy(from.repository)
    free(to.version); to.version = Docs:copy(from.version); to.home = from.home; to.order = from.order; to.authored = from.authored
}
let Docs:merge = fn (store:Docs:Store*, incoming:Docs:Store*) -> i64 {
    if !store || !incoming || store.error || incoming.error || !Docs:build_index(incoming) { return 0 }
    if Docs:empty(store.name) { free(store.name); store.name = Docs:copy(incoming.name); free(store.version); store.version = Docs:copy(incoming.version); free(store.repository); store.repository = Docs:copy(incoming.repository); free(store.revision); store.revision = Docs:copy(incoming.revision) }
    var entry = incoming.first
    while entry {
        let existing = Docs:find(store, entry.scope, entry.id)
        if existing && (strcmp(existing.body, entry.body) != 0 || strcmp(existing.inline_docs, entry.inline_docs) != 0 || strcmp(existing.title, entry.title) != 0 || strcmp(existing.symbol, entry.symbol) != 0 || strcmp(existing.section, entry.section) != 0 || strcmp(existing.version, entry.version) != 0 || existing.order != entry.order) { Docs:diagnostic("conflicting documentation page", entry.id); Docs:diagnostic("package", entry.scope); store.error = 1; return 0 }
        entry = entry.next
    }
    if !store.first { store.index_ready = 1 } else if !Docs:build_index(store) { return 0 }
    entry = incoming.first
    while entry {
        var added = Docs:find(store, entry.scope, entry.id)
        if !added {
            added = Docs:add(store, entry.scope, entry.id, entry.title, entry.section, entry.body, entry.source_path, entry.origin_path)
            if !added { return 0 }; Docs:copy_details(added, entry)
        }
        entry = entry.next
    }
    var bucket = 0
    while bucket < 4096 {
        var term = incoming.terms[bucket]
        while term {
            let target = Docs:term(store, term.word, 1); var posting = term.first
            while posting { if !Docs:posting(store, target, Docs:find(store, posting.entry.scope, posting.entry.id)) { return 0 }; posting = posting.next }
            term = term.next
        }; bucket += 1
    }
    store.index_ready = 1; free(store.query); store.query = cast(u8*, 0)
    Docs:sort(store); return !store.error
}
let Docs:decode_bundle = fn (document:Docs:Json*) -> Docs:Store* {
    let version = Docs:json_field(document, "schema_version")
    let metadata = Docs:json_field(document, "package")
    let pages = Docs:json_field(document, "pages")
    let index = Docs:json_field(document, "index")
    let terms = Docs:json_field(index, "terms")
    let index_version = Docs:json_field(index, "schema_version")
    if !version || version.kind != 4 || strcmp(version.text, "3") != 0 || !metadata || metadata.kind != 1 || !pages || pages.kind != 2 || !pages.first || !terms || terms.kind != 1 || !index_version || index_version.kind != 4 || strcmp(index_version.text, "1") != 0 || strcmp(Docs:json_text(index, "normalization", ""), "ascii-word-prefix-v1") != 0 { return cast(Docs:Store*, 0) }
    let name = Docs:json_text(metadata, "name", "")
    if Docs:empty(name) { return cast(Docs:Store*, 0) }
    let store = Docs:new(name, Docs:json_text(metadata, "version", "dev"), Docs:json_text(metadata, "repository_url", ""))
    if !store { return store }
    free(store.revision); store.revision = Docs:copy(Docs:json_text(document, "source_revision", ""))
    let default_page = Docs:json_text(document, "default_page", "")
    var page = pages.first; var count = 0
    while page {
        let id = Docs:json_text(page, "id", "")
        let key = Docs:json_text(page, "key", id)
        let scope = Docs:json_text(page, "scope", name)
        let title = Docs:json_text(page, "title", "")
        let body = Docs:json_text(page, "body", "")
        if !Docs:valid_id(id) || !Docs:valid_id(key) || Docs:empty(scope) || Docs:empty(title) || strlen(title) > 250 || strlen(body) > 500000 || Docs:find(store, scope, key) || Docs:find_exported(store, id) || count >= 5000 { store.error = 1; return store }
        let entry = Docs:add(store, scope, key, title, Docs:json_text(page, "section", "API"), body, Docs:json_text(page, "source_path", ""), Docs:json_text(page, "origin_path", ""))
        if !entry { return store }
        free(entry.exported_id); entry.exported_id = Docs:copy(id)
        free(entry.inline_docs); entry.inline_docs = Docs:copy(Docs:json_text(page, "inline_docs", ""))
        free(entry.symbol); entry.symbol = Docs:copy(Docs:json_text(page, "symbol", ""))
        free(entry.source_url); entry.source_url = Docs:copy(Docs:json_text(page, "source_url", ""))
        free(entry.repository); entry.repository = Docs:copy(Docs:json_text(page, "repository_url", store.repository))
        free(entry.version); entry.version = Docs:copy(Docs:json_text(page, "package_version", store.version))
        entry.home = strcmp(default_page, id) == 0; entry.authored = 1
        let ordering = Docs:json_field(page, "order")
        if ordering {
            if ordering.kind != 4 { store.error = 1; return store }
            entry.order = Docs:parse_order(ordering.text)
            if entry.order < 0 { store.error = 1; return store }
        }
        page = page.next; count += 1
    }
    if !Docs:find_exported(store, default_page) { store.error = 1; return store }
    var word = terms.first
    while word {
        if word.kind != 2 || Docs:empty(word.key) || strlen(word.key) > 512 { store.error = 1; return store }
        var at = 0
        while word.key[at] != 0 { if !Docs:word_byte(word.key[at]) || Docs:lower(word.key[at]) != word.key[at] { store.error = 1; return store }; at += 1 }
        let term = Docs:term(store, word.key, 1); var id = word.first
        while id {
            if id.kind != 3 { store.error = 1; return store }
            let entry = Docs:find_exported(store, id.text)
            if !entry || !Docs:posting(store, term, entry) { store.error = 1; return store }; id = id.next
        }; word = word.next
    }
    store.index_ready = 1; Docs:sort(store); return store
}
let Docs:json_filename = fn (filename:u8*) -> i64 {
    if Docs:empty(filename) { return 0 }
    let size = cast(i64, strlen(filename)); if size < 6 || strcmp(&filename[size - 5], ".json") != 0 { return 0 }
    let id = LanguageKit:copy_bytes(filename, size - 5); let valid = Docs:valid_id(id); free(id); return valid
}
let Docs:read_export = fn (store:Docs:Store*, path:u8*) -> i64 {
    let source = Docs:read_file(path)
    if !source { store.error = 1; return 0 }; defer free(source)
    let document = Docs:json_parse(source)
    if !document { store.error = 1; return 0 }; defer Docs:json_destroy(document)
    let bundles = Docs:json_field(document, "bundles")
    if bundles && bundles.kind == 2 {
        let directory = Docs:parent(path); defer free(directory)
        var bundle = bundles.first; var count = 0
        while bundle {
            let file = Docs:json_text(bundle, "file", "")
            if !Docs:json_filename(file) || strcmp(file, Docs:basename(path)) == 0 || count >= 100 { store.error = 1; return 0 }
            let destination = Docs:join(directory, file)
            let text = Docs:read_file(destination); free(destination)
            if !text { store.error = 1; return 0 }
            let data = Docs:json_parse(text); free(text)
            let incoming = Docs:decode_bundle(data); Docs:json_destroy(data)
            if !incoming { store.error = 1; return 0 }
            let success = Docs:merge(store, incoming); Docs:destroy(incoming)
            if !success { store.error = 1; return 0 }; bundle = bundle.next; count += 1
        }
        if count == 0 { store.error = 1; return 0 }; return 1
    }
    let incoming = Docs:decode_bundle(document)
    if !incoming { store.error = 1; return 0 }
    defer Docs:destroy(incoming)
    let success = Docs:merge(store, incoming)
    if !success { store.error = 1 }; return success
}
