let Docs:cli = fn (count:i64, args:u8**) -> i64 {
    var command = "help"; var root = "."; var directory = ""; var json = 0; var standard = 1; var limit = 50
    let query = LanguageKit:Text:new(); defer query.destroy()
    var options = 1; var explicit_root = 0
    var i = 0
    if count > 0 && args[0][0] != 45 { command = args[0]; i = 1 }
    while i < count {
        let option = args[i]
        if !options { if query.length { query.append(" ") }; query.append(option); i += 1; continue }
        if strcmp(option, "--") == 0 { options = 0; i += 1; continue }
        if strcmp(option, "--help") == 0 || strcmp(option, "-h") == 0 { command = "help" }
        else if strcmp(option, "--json") == 0 { json = 1 }
        else if strcmp(option, "--no-standard") == 0 { standard = 0 }
        else if strcmp(option, "--root") == 0 || strcmp(option, "--docs-dir") == 0 || strcmp(option, "--limit") == 0 {
            i += 1; if i >= count { printf("Missing option value.\n"); return 2 }
            if strcmp(option, "--root") == 0 { root = args[i]; explicit_root = 1 }
            else if strcmp(option, "--docs-dir") == 0 { directory = args[i] }
            else { limit = LanguageKit:text_number(args[i]); if limit < 1 || limit > 1000 { printf("Limit must be 1..1000.\n"); return 2 } }
        } else if option[0] == 45 { printf("Unknown documentation option: %s\n", option); return 2 }
        else { if query.length { query.append(" ") }; query.append(option) }
        i += 1
    }
    if strcmp(command, "help") == 0 {
        printf("recurloop --docs search <text> [--json] [--limit 50]\nrecurloop --docs show <id | scope/id | exact phrase name> [--json]\nrecurloop --docs list [--json]\nrecurloop --docs export <file.json>\nOptions: --root <repository> --docs-dir <directory> --no-standard\nReads short code help and rich public docs, including included source packages.\nPaths in recurloop.docs are relative to their repository.\n")
        return 0
    }
    if strcmp(command, "search") != 0 && strcmp(command, "show") != 0 && strcmp(command, "list") != 0 && strcmp(command, "export") != 0 { printf("Unknown documentation command: %s\n", command); return 2 }
    if strcmp(command, "list") != 0 && !query.length { printf("This command requires a query, page identifier or export filename.\n"); return 2 }
    var discovered = cast(u8*, 0)
    if !explicit_root { discovered = Docs:package_root(root); if discovered { root = discovered } }
    defer free(discovered)
    let store = Docs:load_options(root, directory, standard)
    if !store { printf("Cannot open documentation root.\n"); return 1 }; defer Docs:destroy(store)
    if store.error { printf("Cannot load documentation; check recurloop.docs, index.tsv and project diagnostics.\n"); return 1 }
    if strcmp(command, "export") == 0 {
        if !Docs:export_file(store, query.data) { printf("Cannot export documentation.\n"); return 1 }
        printf("%s\n", query.data); return 0
    }
    if strcmp(command, "show") == 0 {
        var entry = store.first
        while entry {
            let name = LanguageKit:Text:new(); name.append(entry.scope); name.append("/"); name.append(entry.id)
            let portable_id = Docs:entry_id(entry, "doc:")
            let portable_match = strcmp(portable_id, query.data) == 0; free(portable_id)
            let matches = portable_match || strcmp(entry.id, query.data) == 0 || strcmp(entry.title, query.data) == 0 || strcmp(name.data, query.data) == 0
            name.destroy()
            if matches { break }; entry = entry.next
        }
        if !entry { printf("No matching documentation.\n"); return 1 }
        if json { let out = LanguageKit:Text:new(); Docs:page_json(out, entry, "doc:", ""); printf("%s\n", out.data); out.destroy() }
        else { let text = Docs:as_text(entry); printf("%s/%s\n%s\n", entry.scope, entry.id, text); free(text) }
        return 0
    }
    let out = LanguageKit:Text:new(); defer out.destroy()
    if json { out.append("{\"results\":[") }
    var entry = Docs:search(store, query.data, cast(Docs:Entry*, 0)); var found = 0; var shown = 0
    while entry {
        found += 1
        if shown < limit {
            if json { if shown { out.append(",") }; Docs:summary_json(out, entry, "doc:") }
            else { printf("%s/%s\t%s\t%s\n", entry.scope, entry.id, entry.title, entry.section) }
            shown += 1
        }
        entry = Docs:search(store, query.data, entry)
    }
    if json { let totals = malloc(96); snprintf(totals, 96, "],\"total\":%ld,\"shown\":%ld}\n", found, shown); out.append(totals); free(totals); printf("%s", out.data) }
    else { printf("%ld results (%ld shown).\n", found, shown) }
    return 0
}
// The host only routes --docs here; this source phrase owns all CLI semantics.
let Docs:command_line = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        var index = state.exec.args.index
        if index < state.exec.args.count && strcmp(state.exec.args.values[index], "--") == 0 { index += 1 }
        let count = state.exec.args.count - index
        state.exec.args.index = state.exec.args.count
        if Docs:cli(count, &state.exec.args.values[index]) != 0 { context:diagnostic:error(state, "documentation command failed") }
    }
}
set Docs.docs = "Public package documentation: owned catalogs, semantic code help, search, editing and portable export."
set Docs:new.docs = "Creates an owned catalog. Release with Docs:destroy; returned entries are borrowed from it."
set Docs:load.docs = "Loads public docs and semantic code help from a repository, discovering included source packages. Empty directory uses recurloop.docs or docs/."
set Docs:find.docs = "Returns a borrowed entry by scope and id, or null. Empty scope searches every package."
set Docs:search.docs = "Returns the next borrowed match in title, body, inline code help or package name. Pass null after for the first result. ASCII case-insensitive; UTF-8 is preserved."
set Docs:add.docs = "Adds a page and copies its strings, or replaces an existing page body with the same scope/id. Returns a borrowed structured entry."
set Docs:set_body.docs = "Replaces a page body in memory, copying the provided text. Export recompiles blocks and navigation."
set Docs:as_text.docs = "Returns an owned string with title, short code help and rich documentation. Free the string."
set Docs:as_json.docs = "Returns owned portable JSON with blocks, TOC, navigation, page links and full-text index. Free the string."
set Docs:save.docs = "Writes the rich Markdown body to a supplied file; does not write inline code help. Returns 1 on success."
set Docs:export_file.docs = "Exports an entire catalog as portable v2 JSON to a file. Returns 1 on success, 0 on failure."
set Docs:load_directory.docs = "Adds public Markdown from an explicit directory and optional ordered index.tsv. A catalog loads each canonical directory once."
set Docs:load_package.docs = "Loads a source repository's configured public documentation directory, without scanning its private implementation documentation."
set Docs:import_trace.docs = "Adds runtime-resolved P/G/H/J/F code metadata and discovers documentation of included source repositories. Trace buffer is consumed."
set Docs:load_standard.docs = "Adds installed public engine and standard-library manuals; RECURLOOP_DOCS_PATH overrides their location."
set Docs:destroy.docs = "Frees a catalog and every owned entry/string. Borrowed entries become invalid. Accepts null."
set Docs:Entry.docs = "Borrowed structured page: id, title, section, body, inline_docs, source_path, origin_path, scope, repository, version and linked previous/next."
set Docs:Store.docs = "Owned documentation catalog with metadata, ordered entries, loaded-directory registry and error flag."
