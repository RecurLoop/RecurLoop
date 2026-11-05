// Persists catalog edits together with their ordered navigation for the next load.
let Docs:index_text = fn (value:u8*) -> i64 {
    if !value { return 0 }
    var at = 0
    while value[at] != 0 { if value[at] == 9 || value[at] == 10 || value[at] == 13 { return 0 }; at += 1 }
    return 1
}
let Docs:set_inline = fn (entry:Docs:Entry*, text:u8*) -> i64 {
    if !entry { return 0 }
    let copy = Docs:copy(text); if !copy { return 0 }
    free(entry.inline_docs); entry.inline_docs = copy; return 1
}
let Docs:save_directory = fn (store:Docs:Store*, root:u8*, directory:u8*, scope:u8*) -> i64 {
    if !store || store.error || Docs:empty(directory) { return 0 }
    let full = Docs:join(root, directory); defer free(full)
    let status = run mkdir -p "{full}"
    if status != 0 { return 0 }
    let index = LanguageKit:Text:new(); defer index.destroy()
    index.append("# id\ttitle\tsection\tfile\toriginal_source\n")
    var entry = store.first; var count = 0
    while entry {
        if strcmp(entry.scope, scope) == 0 {
            if !Docs:valid_id(entry.id) || !Docs:index_text(entry.title) || !Docs:index_text(entry.section) || (!Docs:empty(entry.origin_path) && !Docs:index_text(entry.origin_path)) { return 0 }
            let filename = LanguageKit:Text:new(); filename.append(entry.id); filename.append(".md")
            let path = Docs:join(full, filename.data)
            let success = Docs:write_file(path, entry.body); free(path)
            if !success { filename.destroy(); return 0 }
            index.append(entry.id); index.append("\t"); index.append(entry.title); index.append("\t"); index.append(entry.section); index.append("\t"); index.append(filename.data); index.append("\t"); index.append(entry.origin_path); index.append("\n")
            free(entry.source_path); entry.source_path = Docs:join(directory, filename.data)
            filename.destroy(); count += 1
        }
        entry = entry.next
    }
    if !count { return 0 }
    let path = Docs:join(full, "index.tsv"); defer free(path)
    return Docs:write_file(path, index.data)
}
set Docs:set_inline.docs = "Copies replacement short code help into a catalog entry. To change the source declaration's help, set its .docs metadata in RecurLoop source."
set Docs:save_directory.docs = "Persists one package's rich pages and complete ordered index.tsv to a public directory, including newly added pages. Does not rewrite source code help."
