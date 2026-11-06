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
let DocsTests:all = fn () -> i64 {
    let status = run mkdir -p .cache/docs-export
    if status != 0 { return 1 }
    let trace = DocsTests:run(); if trace != 0 { return trace }
    let json = DocsTests:json_reader(); if json != 0 { printf("[docs-check] JSON reader: %ld\n", json); return json }
    let index = DocsTests:index_roundtrip(); if index != 0 { printf("[docs-check] source/index roundtrip: %ld\n", index); return index }
    let packages = DocsTests:source_packages(); if packages != 0 { printf("[docs-check] source packages: %ld\n", packages); return packages }
    let cli = DocsTests:cli_exports(); if cli != 0 { printf("[docs-check] CLI JSON/merge: %ld\n", cli); return cli }
    printf("[docs-check] source .rl objects, generated/reused indexes, edits, JSON, merge, CLI and private-doc exclusion passed\n")
    return 0
}
