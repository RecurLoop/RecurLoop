// Source objects, portable JSON and generated indexes must have the same semantics.
let DocsTests:index_roundtrip = fn () -> i64 {
    let store = Docs:new("sample", "1.0.0", "")
    if !store { return 1 }; defer Docs:destroy(store)
    let first = Docs:add(store, "sample", "intro", "Introduction", "Language", "# Introduction\n\n## Usage\n\nOwnership and borrowed data.\n\n```recurloop\n    print 42\n```", "", "")
    if !first { return 2 }; first.home = 1
    if !Docs:search(store, "OWNER", cast(Docs:Entry*, 0)) || store.index_builds != 1 { return 3 }
    if !Docs:search(store, "borrow", cast(Docs:Entry*, 0)) || store.index_builds != 1 { return 4 }
    let json = Docs:as_json(store, "doc:", "")
    if !json { return 5 }; defer free(json)
    let parsed = Docs:json_parse(json)
    if !parsed { return 6 }; defer Docs:json_destroy(parsed)
    let pages = Docs:json_field(parsed, "pages")
    let body = Docs:json_field(pages.first, "body")
    free(body.text); body.text = Docs:copy("This body deliberately differs from the supplied index.")
    let imported = Docs:decode_bundle(parsed)
    if !imported { return 7 }; defer Docs:destroy(imported)
    if imported.error || imported.index_builds != 0 || !Docs:search(imported, "ownership", cast(Docs:Entry*, 0)) || imported.index_builds != 0 { return 8 }
    if !Docs:set_body(imported.first, "Changed catalog newtoken.") || Docs:search(imported, "ownership", cast(Docs:Entry*, 0)) || !Docs:search(imported, "newtoken", cast(Docs:Entry*, 0)) || imported.index_builds != 1 { return 9 }
    let merged = Docs:new("sample", "1.0.0", "")
    if !merged { return 10 }; defer Docs:destroy(merged)
    if !Docs:merge(merged, store) || !Docs:merge(merged, store) || merged.first != merged.last || merged.index_builds != 0 { return 11 }
    if !Docs:export_file(store, ".cache/docs-export/roundtrip.json") { return 12 }
    let read = Docs:new("", "", "")
    if !read { return 13 }; defer Docs:destroy(read)
    if !Docs:read_export(read, ".cache/docs-export/roundtrip.json") || read.index_builds != 0 || !Docs:search(read, "ownership", cast(Docs:Entry*, 0)) || read.index_builds != 0 { return 14 }
    if !Docs:save_directory(store, ".", ".cache/docs-export/authored", "sample") { return 15 }
    let authored = Docs:new("sample", "1.0.0", "")
    if !authored { return 16 }; defer Docs:destroy(authored)
    if !Docs:load_directory(authored, ".", ".cache/docs-export/authored", "sample") || authored.error || !Docs:search(authored, "ownership", cast(Docs:Entry*, 0)) { return 17 }
    if access(".cache/docs-export/authored/index.tsv", 0) == 0 { return 18 }
    let created = run mkdir -p .cache/docs-export/collection
    if created != 0 || !Docs:write_file(".cache/docs-export/collection/manifest.json", "{\"schema_version\":2,\"bundles\":[]}") { return 19 }
    if Docs:Build:write_collection(store, ".cache/docs-export/collection") != 0 || access(".cache/docs-export/collection/manifest.json", 0) == 0 { return 20 }
    return 0
}
let DocsTests:json_reader = fn () -> i64 {
    let text = Docs:json_parse("{\"text\":\"zażółć \\ud83d\\ude80\",\"array\":[true,false,null,1,-2,3.5]}")
    if !text { return 1 }
    let correct = strcmp(Docs:json_text(text, "text", ""), "zażółć 🚀") == 0; Docs:json_destroy(text)
    if !correct { return 2 }
    if Docs:json_parse("{\"a\":1,\"a\":2}") || Docs:json_parse("[1,]") || Docs:json_parse("{} trailing") || Docs:json_parse("\"\\ud800\"") { return 3 }
    return 0
}
let DocsTests:source_packages = fn () -> i64 {
    let store = Docs:load("tests/fixtures/documentation/project", "")
    if !store { return 1 }; defer Docs:destroy(store)
    if store.error { return 2 }
    let local = Docs:search(store, "rootrichuniquemarker", cast(Docs:Entry*, 0))
    let dependency = Docs:search(store, "dependencyrichuniquemarker", cast(Docs:Entry*, 0))
    let code = Docs:search(store, "nativecodeuniquemarker", cast(Docs:Entry*, 0))
    if !local || !dependency || !code { return 3 }
    if strcmp(code.scope, "external-package") != 0 || strcmp(dependency.scope, "external-package") != 0 { return 4 }
    if Docs:search(store, "CPP_PRIVATE_SENTINEL", cast(Docs:Entry*, 0)) { return 5 }
    let override = Docs:load("tests/fixtures/documentation/project", "alternative")
    if !override { return 6 }; defer Docs:destroy(override)
    if override.error || !Docs:search(override, "alternativerootuniquemarker", cast(Docs:Entry*, 0)) || !Docs:search(override, "dependencyrichuniquemarker", cast(Docs:Entry*, 0)) { return 7 }
    if Docs:search(override, "rootrichuniquemarker", cast(Docs:Entry*, 0)) { return 8 }
    return 0
}
// One application's published bundle must not contain imported package help.
let DocsTests:package_export = fn () -> i64 {
    let path = ".cache/docs-export/application-package.json"
    if !Docs:export_package("tests/fixtures/documentation/project", path) { return 1 }
    let store = Docs:new("", "", "")
    if !store { return 2 }; defer Docs:destroy(store)
    if !Docs:read_export(store, path) || store.index_builds != 0 { return 3 }
    if strcmp(store.name, "source-fixture") != 0 || strcmp(store.version, "1.0.0") != 0 { return 4 }
    if !Docs:search(store, "rootrichuniquemarker", cast(Docs:Entry*, 0)) || !Docs:search(store, "local-code-token", cast(Docs:Entry*, 0)) { return 5 }
    if Docs:search(store, "dependencyrichuniquemarker", cast(Docs:Entry*, 0)) || Docs:search(store, "nativecodeuniquemarker", cast(Docs:Entry*, 0)) { return 6 }
    var page = store.first
    while page { if strcmp(page.scope, "source-fixture") != 0 { return 7 }; page = page.next }
    if Docs:export_package("tests/fixtures/documentation/not-a-package", path) { return 8 }
    // An existing directory cannot be opened as an output file.
    if Docs:export_package("tests/fixtures/documentation/project", ".cache/docs-export") { return 9 }
    let prepared = run mkdir -p .cache/docs-export/empty-package/docs
    if prepared != 0 { return 10 }
    if Docs:export_package(".cache/docs-export/empty-package", path) { return 11 }
    return 0
}

// Manuals follow their library, including when copied into a separate source tree.
let DocsTests:library_manuals = fn () -> i64 {
    let store = Docs:load_options("libraries/ide", "", 1)
    if !store { return 1 }; defer Docs:destroy(store)
    let id = Docs:page_id("IDE"); defer free(id)
    let entry = Docs:find(store, "ide", id)
    if store.error || !entry || !strstr(entry.body, "Source intelligence") || Docs:empty(entry.inline_docs) { return 2 }
    if strcmp(entry.source_path, "libraries/ide/docs/usage.rl") != 0 { return 3 }
    if access("source/docs/ide", 0) == 0 { return 4 }
    let copied = run mkdir -p .cache/docs-export/detached-ide/docs
    if copied != 0 { return 5 }
    let source = Docs:read_file("libraries/ide/docs/usage.rl"); if !source { return 6 }; defer free(source)
    if !Docs:write_file(".cache/docs-export/detached-ide/docs/usage.rl", source) { return 7 }
    if !Docs:write_file(".cache/docs-export/detached-ide/recurloop.docs", "name=ide\nversion=runtime\ndirectory=docs\nrepository=https://example.org/ide\nimage=ide\n") { return 8 }
    let detached = Docs:load_options(".cache/docs-export/detached-ide", "", 0)
    if !detached { return 9 }; defer Docs:destroy(detached)
    let manual = Docs:find(detached, "ide", id)
    if detached.error || !manual || strcmp(manual.body, entry.body) != 0 || Docs:empty(manual.inline_docs) { return 10 }
    if strcmp(manual.source_path, "docs/usage.rl") != 0 || strcmp(manual.repository, "https://example.org/ide") != 0 { return 11 }
    return 0
}
let DocsTests:cli_exports = fn () -> i64 {
    let executable = Docs:executable(); if !executable { return 1 }; defer free(executable)
    let bindir = Docs:parent(executable)
    var libraries = Docs:copy(getenv("RECURLOOP_DOCS_LIBRARY_PATH"))
    if Docs:empty(libraries) { free(libraries); libraries = Docs:join(bindir, "../libraries") }; free(bindir); defer free(libraries)
    let command = spawn "{executable}" --library-path "{libraries}" --docs search ownership --from .cache/docs-export/roundtrip.json --json
    if !command { return 2 }; defer command.destroy()
    if command.exit_code() != 0 || !strstr(command.stdout(), "\"total\":1") { return 3 }
    let merge_command = spawn "{executable}" --library-path "{libraries}" --docs merge .cache/docs-export/merged.json .cache/docs-export/roundtrip.json .cache/docs-export/roundtrip.json
    if !merge_command { return 4 }; defer merge_command.destroy()
    if merge_command.exit_code() != 0 { return 5 }
    let merged = Docs:new("", "", "")
    if !merged { return 6 }; defer Docs:destroy(merged)
    if !Docs:read_export(merged, ".cache/docs-export/merged.json") || merged.first != merged.last || merged.index_builds != 0 { return 7 }
    return 0
}
// Authored learning order survives portable JSON, source persistence and merges.
let DocsTests:reading_order = fn () -> i64 {
    let store = Docs:new("ordered", "1.0.0", "")
    if !store { return 1 }; defer Docs:destroy(store)
    let reference = Docs:add(store, "ordered", "api", "API", "API", "Reference.", "", "")
    let second = Docs:add(store, "ordered", "second", "Alpha comes later", "Guides", "Second step.", "", "")
    let first = Docs:add(store, "ordered", "first", "Zulu comes first", "Guides", "First step.", "", "")
    let home = Docs:add(store, "ordered", "home", "Overview", "Guides", "Start here.", "", "")
    if !reference || !second || !first || !home { return 2 }
    first.order = 10; second.order = 20; home.home = 1
    Docs:sort(store)
    if store.first != home || home.next != first || first.next != second || second.next != reference || second.previous != first { return 3 }
    let json = Docs:as_json(store, "doc:", "")
    if !json { return 4 }; defer free(json)
    let parsed = Docs:json_parse(json)
    if !parsed { return 5 }; defer Docs:json_destroy(parsed)
    let imported = Docs:decode_bundle(parsed)
    if !imported || imported.error { if imported { Docs:destroy(imported) }; return 6 }; defer Docs:destroy(imported)
    Docs:sort(imported)
    if strcmp(imported.first.next.id, "first") != 0 || imported.first.next.order != 10 || imported.first.next.next.order != 20 || imported.index_builds != 0 { return 7 }
    let merged = Docs:new("ordered", "1.0.0", "")
    if !merged { return 8 }; defer Docs:destroy(merged)
    if !Docs:merge(merged, imported) || merged.first.next.order != 10 || merged.index_builds != 0 { return 9 }
    if !Docs:save_directory(store, ".", ".cache/docs-export/ordered", "ordered") { return 10 }
    let authored = Docs:new("ordered", "1.0.0", "")
    if !authored { return 11 }; defer Docs:destroy(authored)
    if !Docs:load_directory(authored, ".", ".cache/docs-export/ordered", "ordered") || authored.error || authored.first.next.order != 10 || strcmp(authored.first.next.id, "first") != 0 { return 12 }
    first.order = 30
    if Docs:merge(merged, store) || !merged.error { return 13 }
    if Docs:parse_order("-1") != -1 || Docs:parse_order("1.5") != -1 || Docs:parse_order("1000001") != -1 || Docs:parse_order("1000000") != 1000000 { return 14 }
    let pages = Docs:json_field(parsed, "pages")
    let ordering = Docs:json_field(pages.first.next, "order")
    if !ordering { return 15 }; free(ordering.text); ordering.text = Docs:copy("-1")
    let invalid = Docs:decode_bundle(parsed)
    if !invalid { return 16 }; let rejected = invalid.error; Docs:destroy(invalid)
    if !rejected { return 17 }
    return 0
}

// Source manuals and live inline help overlap with installed JSON by design.
let DocsTests:standard_overlap = fn () -> i64 {
    let local = Docs:new("sample", "dev", ""); if !local { return 1 }; defer Docs:destroy(local)
    let guide = Docs:add(local, "sample", "guide", "Local guide", "Guides", "localonlytoken", "docs/guide.rl", "")
    let code = Docs:add(local, "sample", "api", "Call", "API", "generatedplaceholder", "library.rl", "")
    if !guide || !code { return 2 }; guide.authored = 1; guide.order = 10; code.authored = 0
    if !Docs:set_inline(code, "liveinlinetoken") { return 3 }
    let edited = Docs:add(local, "sample", "edited", "Edited", "API", "placeholder", "library.rl", "")
    if !edited { return 16 }; edited.authored = 0
    if !Docs:set_body(edited, "developeredittoken") || !edited.authored { return 17 }
    let standard = Docs:new("sample", "1.0.0", ""); if !standard { return 4 }; defer Docs:destroy(standard)
    let old = Docs:add(standard, "sample", "guide", "Old guide", "Guides", "staleguidetoken", "docs/guide.rl", "")
    let rich = Docs:add(standard, "sample", "api", "Call", "Guides", "richmanualtoken", "docs/call.rl", "")
    let extra = Docs:add(standard, "sample", "extra", "Extra", "Guides", "extramanualtoken", "docs/extra.rl", "")
    let previous = Docs:add(standard, "sample", "edited", "Edited", "Guides", "outdatededittoken", "docs/edited.rl", "")
    if !old || !rich || !extra || !previous { return 5 }
    old.authored = 1; rich.authored = 1; extra.authored = 1; rich.order = 20
    if !Docs:set_inline(old, "fallbackinlinetoken") || !Docs:set_inline(rich, "staleinlinetoken") { return 6 }
    if !Docs:export_file(standard, ".cache/docs-export/standard.json") { return 7 }
    let baseline = Docs:new("", "dev", ""); if !baseline { return 8 }; defer Docs:destroy(baseline)
    if !Docs:read_export(baseline, ".cache/docs-export/standard.json") || baseline.index_builds != 0 { return 9 }
    if !Docs:include_standard(local, baseline) || local.error || baseline.index_builds != 0 { return 10 }
    if strcmp(guide.title, "Local guide") != 0 || guide.order != 10 || strcmp(guide.version, "dev") != 0 { return 11 }
    if strcmp(code.body, "richmanualtoken") != 0 || strcmp(code.inline_docs, "liveinlinetoken") != 0 || code.order != 20 || !code.authored { return 12 }
    if !Docs:search(local, "localonlytoken", cast(Docs:Entry*, 0)) || !Docs:search(local, "richmanualtoken", cast(Docs:Entry*, 0)) || !Docs:search(local, "liveinlinetoken", cast(Docs:Entry*, 0)) || !Docs:search(local, "fallbackinlinetoken", cast(Docs:Entry*, 0)) || !Docs:search(local, "extramanualtoken", cast(Docs:Entry*, 0)) { return 13 }
    if Docs:search(local, "staleguidetoken", cast(Docs:Entry*, 0)) || Docs:search(local, "staleinlinetoken", cast(Docs:Entry*, 0)) || Docs:search(local, "generatedplaceholder", cast(Docs:Entry*, 0)) { return 14 }
    if !Docs:search(local, "developeredittoken", cast(Docs:Entry*, 0)) || Docs:search(local, "outdatededittoken", cast(Docs:Entry*, 0)) { return 18 }
    // Merging separately exported packages must still reject conflicting pages.
    if Docs:merge(local, baseline) || !local.error { return 15 }
    return 0
}
// A relocated installed executable must find its own images in child processes.
let DocsTests:installed_cli = fn () -> i64 {
    let executable = Docs:executable(); if !executable { return 1 }; defer free(executable)
    let parent = Docs:parent(executable); defer free(parent)
    var libraries = Docs:copy(getenv("RECURLOOP_DOCS_LIBRARY_PATH"))
    if Docs:empty(libraries) { free(libraries); libraries = Docs:join(parent, "../libraries") }
    if access(libraries, 4) != 0 { free(libraries); libraries = Docs:join(parent, "../share/recurloop/libraries") }
    defer free(libraries)
    let canonical = realpath(libraries, cast(u8*, 0)); if !canonical { return 2 }; defer free(canonical)
    let temporary = Docs:copy("/tmp/recurloop-docs-install-XXXXXX"); defer free(temporary)
    if !mkdtemp(temporary) { return 3 }
    let bin = Docs:join(temporary, "bin"); defer free(bin)
    let share = Docs:join(temporary, "share/recurloop"); defer free(share)
    let docs = Docs:join(share, "docs"); defer free(docs)
    let installed = Docs:join(bin, "recurloop"); defer free(installed)
    let images = Docs:join(share, "libraries"); defer free(images)
    let index = Docs:join(docs, "index.json"); defer free(index)
    var result = 0
    let mkdir = run mkdir -p "{bin}" "{docs}"
    let copy = run cp "{executable}" "{installed}"
    let link = run ln -s "{canonical}" "{images}"
    let exported = Docs:read_file(".cache/docs-export/standard.json")
    if !exported || mkdir != 0 || copy != 0 || link != 0 || !Docs:write_file(index, exported) { result = 4 }
    free(exported)
    if result == 0 {
        let path_guard = Shell:env_enter("RECURLOOP_LIBRARY_PATH", ""); defer Shell:env_leave(path_guard)
        let docs_guard = Shell:env_enter("RECURLOOP_DOCS_LIBRARY_PATH", ""); defer Shell:env_leave(docs_guard)
        let index_guard = Shell:env_enter("RECURLOOP_DOCS_INDEX", ""); defer Shell:env_leave(index_guard)
        let source_guard = Shell:env_enter("RECURLOOP_DOCS_PATH", ""); defer Shell:env_leave(source_guard)
        let command = spawn "{installed}" --docs search dependencyrichuniquemarker --root tests/fixtures/documentation/project --json
        if !command { result = 5 }
        else { if command.exit_code() != 0 || !strstr(command.stdout(), "\"total\":1") { result = 6 }; command.destroy() }
        let baseline = spawn "{installed}" --docs search extramanualtoken --root tests/fixtures/documentation/project --json
        if !baseline { result = 7 }
        else { if baseline.exit_code() != 0 || !strstr(baseline.stdout(), "\"total\":1") { result = 8 }; baseline.destroy() }
    }
    let cleanup = run rm -rf -- "{temporary}"
    return result
}

let DocsTests:all = fn () -> i64 {
    let status = run mkdir -p .cache/docs-export
    if status != 0 { return 1 }
    let trace = DocsTests:run(); if trace != 0 { return trace }
    let json = DocsTests:json_reader(); if json != 0 { printf("[docs-check] JSON reader: %ld\n", json); return json }
    let ordered = DocsTests:reading_order(); if ordered != 0 { printf("[docs-check] reading order: %ld\n", ordered); return ordered }
    let index = DocsTests:index_roundtrip(); if index != 0 { printf("[docs-check] source/index roundtrip: %ld\n", index); return index }
    let overlap = DocsTests:standard_overlap(); if overlap != 0 { printf("[docs-check] source/standard overlap: %ld\n", overlap); return overlap }
    let installed = DocsTests:installed_cli(); if installed != 0 { printf("[docs-check] installed CLI: %ld\n", installed); return installed }
    let packages = DocsTests:source_packages(); if packages != 0 { printf("[docs-check] source packages: %ld\n", packages); return packages }
    let application = DocsTests:package_export(); if application != 0 { printf("[docs-check] application package export: %ld\n", application); return application }
    let manuals = DocsTests:library_manuals(); if manuals != 0 { printf("[docs-check] library-owned manuals: %ld\n", manuals); return manuals }
    let cli = DocsTests:cli_exports(); if cli != 0 { printf("[docs-check] CLI JSON/merge: %ld\n", cli); return cli }
    printf("[docs-check] source .rl objects, generated/reused indexes, edits, JSON, merge, CLI and private-doc exclusion passed\n")
    return 0
}
