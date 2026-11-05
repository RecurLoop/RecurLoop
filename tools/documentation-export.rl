// Site composition only; parsing, catalogs, search and serialization belong to docs.rl.
include "../libraries/docs/api.rl"

let Docs:site_bundle = fn (root:u8*, output:u8*, scope:u8*, version:u8*, revision:u8*, manifest:LanguageKit:Text*, home:LanguageKit:Text*, first:i64) -> i64 {
    let store = Docs:new(scope, version, "https://github.com/RecurLoop/RecurLoop")
    if !store { return 0 }; defer Docs:destroy(store)
    let directory = Docs:join("source/docs", scope)
    defer free(directory)
    if !Docs:load_directory(store, root, directory, scope) { return 0 }
    let entry = Docs:join(root, ".cache/docs-export/recurloop.project.rl")
    defer free(entry)
    var library = scope
    if strcmp(scope, "core") == 0 { library = "project" }
    let trace = Docs:trace(entry, library)
    if !trace { return 0 }; defer free(trace)
    let image = LanguageKit:Text:new(); image.append(scope); image.append(".rli")
    defer image.destroy()
    if !Docs:import_trace(store, trace, image.data, scope, 0) { return 0 }
    let base = Docs:join("/docs", scope)
    let filename = LanguageKit:Text:new(); filename.append(scope); filename.append(".json")
    let destination = Docs:join(output, filename.data)
    defer free(base); defer free(destination); defer filename.destroy()
    let json = Docs:as_json(store, base, revision)
    if !json { return 0 }; defer free(json)
    if !Docs:write_file(destination, json) { return 0 }
    if first { Docs:href(home, base, store.first.id) }
    if !first { manifest.append(",\n") }
    manifest.append("{\"id\":"); Docs:json(manifest, scope)
    manifest.append(",\"title\":")
    if strcmp(scope, "core") == 0 { Docs:json(manifest, "RecurLoop") } else { Docs:json(manifest, scope) }
    manifest.append(",\"kind\":")
    if strcmp(scope, "core") == 0 { Docs:json(manifest, "engine") } else { Docs:json(manifest, "library") }
    manifest.append(",\"version\":"); Docs:json(manifest, version)
    manifest.append(",\"file\":"); Docs:json(manifest, filename.data)
    manifest.append(",\"href\":"); Docs:href(manifest, base, store.first.id)
    manifest.append(",\"pages\":[\n")
    var item = store.first; var count = 0
    while item { if count { manifest.append(",\n") }; Docs:summary_json(manifest, item, base); count += 1; item = item.next }
    manifest.append("\n]}")
    printf("[docs] %s: %ld public pages\n", scope, count)
    return 1
}
let Docs:export = fn (output:u8*) -> i64 {
    if Docs:empty(output) { return 1 }
    let status = run mkdir -p "{output}" .cache/docs-export
    if status != 0 || !Docs:write_file(".cache/docs-export/recurloop.project.rl", "") { return 2 }
    let root = capture pwd
    let revision = capture git rev-parse HEAD
    let release = capture ./build/Release/bin/recurloop --version
    if !root || !revision || !release { return 3 }
    defer free(root); defer free(revision); defer free(release)
    Docs:trim(root); Docs:trim(revision); Docs:trim(release)
    var version = release
    while version[0] != 0 && version[0] != 118 { version = &version[1] }
    if version[0] == 0 { return 4 }; version = &version[1]
    let manifest = LanguageKit:Text:new(); let home = LanguageKit:Text:new(); defer manifest.destroy(); defer home.destroy()
    manifest.append("{\"schema_version\":2,\"version\":"); Docs:json(manifest, version)
    manifest.append(",\"source_revision\":"); Docs:json(manifest, revision)
    manifest.append(",\"repository_url\":\"https://github.com/RecurLoop/RecurLoop\",\"bundles\":[\n")
    if !Docs:site_bundle(root, output, "core", version, revision, manifest, home, 1) { return 5 }
    let scopes = Docs:read_file("libraries/standard.txt")
    if !scopes { return 6 }; defer free(scopes)
    var scope = scopes
    while scope[0] != 0 {
        var end = 0
        while scope[end] != 0 && scope[end] != 10 { end += 1 }
        let more = scope[end] == 10; scope[end] = 0
        if scope[0] != 0 && scope[0] != 35 { if !Docs:site_bundle(root, output, scope, version, revision, manifest, home, 0) { return 7 } }
        if !more { break }; scope = &scope[end + 1]
    }
    manifest.append("\n],\"default_href\":"); manifest.append(home.data); manifest.append("}\n")
    let path = Docs:join(output, "manifest.json"); defer free(path)
    if !Docs:write_file(path, manifest.data) { return 8 }
    let schema = Docs:read_file("source/docs/documentation-format.json")
    let sample = Docs:load("source/docs/format-example", "")
    let example = Docs:as_json(sample, "doc:", "")
    Docs:destroy(sample)
    defer free(schema); defer free(example)
    let schema_path = Docs:join(output, "documentation-format.json")
    let example_path = Docs:join(output, "documentation-example.json")
    defer free(schema_path); defer free(example_path)
    if !schema || !example || !Docs:write_file(schema_path, schema) || !Docs:write_file(example_path, example) { return 9 }
    return 0
}
let Docs:export_from_environment = fn () -> i64 {
    var output = getenv("RECURLOOP_DOCS_OUTPUT")
    if !output || output[0] == 0 { output = "build/documentation" }
    return Docs:export(output)
}
