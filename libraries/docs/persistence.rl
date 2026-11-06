// Save authored RecurLoop objects. Generated indexes never belong in source directories.
let Docs:set_inline = fn (entry:Docs:Entry*, text:u8*) -> i64 {
    if !entry { return 0 }; let copy = Docs:copy(text); if !copy { return 0 }
    free(entry.inline_docs); entry.inline_docs = copy
    let owner = cast(Docs:Store*, entry.owner); if owner { owner.index_ready = 0 }; return 1
}
let Docs:source_literal = fn (out:LanguageKit:Text*, value:u8*) -> void {
    out.append("\""); var at = 0
    while value[at] != 0 {
        let ch = value[at]
        if ch == 34 || ch == 92 { out.append_byte(92); out.append_byte(ch) }
        else if ch == 13 { out.append("\\r") }
        else if ch == 9 { out.append("\\t") }
        else { out.append_byte(ch) }; at += 1
    }; out.append("\"")
}
let Docs:source_field = fn (out:LanguageKit:Text*, key:u8*, value:u8*) -> void {
    out.append("    "); out.append(key); out.append(" = phrase { payload = "); if strcmp(key, "body") == 0 { Docs:source_literal(out, value) } else { Docs:json(out, value) }; out.append(" }\n")
}
let Docs:source_object = fn (out:LanguageKit:Text*, entry:Docs:Entry*) -> i64 {
    if !Docs:valid_id(entry.id) { return 0 }
    let key = Docs:copy(entry.id); var at = 0
    while key[at] != 0 { if key[at] == 45 { key[at] = 95 }; at += 1 }
    out.append("let Docs:Pages:"); out.append(key); out.append(" = [\n"); free(key)
    Docs:source_field(out, "id", entry.id); Docs:source_field(out, "scope", entry.scope)
    if !Docs:empty(entry.symbol) { Docs:source_field(out, "symbol", entry.symbol) }
    Docs:source_field(out, "title", entry.title); Docs:source_field(out, "section", entry.section)
    if entry.home { Docs:source_field(out, "default", "true") }
    Docs:source_field(out, "body", entry.body); out.append("]\n\n"); return 1
}
let Docs:save = fn (entry:Docs:Entry*, path:u8*) -> i64 {
    if !entry { return 0 }; let source = LanguageKit:Text:new(); defer source.destroy()
    if !Docs:source_object(source, entry) { return 0 }; return Docs:write_file(path, source.data)
}
let Docs:save_directory = fn (store:Docs:Store*, root:u8*, directory:u8*, scope:u8*) -> i64 {
    if !store || store.error || Docs:empty(directory) { return 0 }
    let full = Docs:join(root, directory); defer free(full)
    let status = run mkdir -p "{full}"
    if status != 0 { return 0 }
    let source = LanguageKit:Text:new(); defer source.destroy()
    var entry = store.first; var count = 0
    while entry {
        if strcmp(entry.scope, scope) == 0 { if !Docs:source_object(source, entry) { return 0 }; count += 1 }; entry = entry.next
    }
    if !count { return 0 }; let path = Docs:join(full, "documentation.rl"); defer free(path)
    return Docs:write_file(path, source.data)
}
set Docs:set_inline.docs = "Updates short code help in a live catalog and invalidates its generated index. Source phrase metadata is edited with .docs."
set Docs:save_directory.docs = "Saves one scope as RecurLoop documentation objects. Its search/navigation index is generated when the objects are loaded or exported."
