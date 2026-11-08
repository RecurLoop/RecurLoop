// Build composition lives here. Public documents contain phrase behavior only.
let Docs:Build = []

let Docs:Build:scope_catalog = fn (source:Docs:Store*, scope:u8*) -> Docs:Store* {
    if !Docs:build_index(source) { return cast(Docs:Store*, 0) }
    let selected = Docs:new(scope, source.version, source.repository)
    if !selected { return selected }
    free(selected.revision); selected.revision = Docs:copy(source.revision)
    var entry = source.first
    while entry {
        if strcmp(entry.scope, scope) == 0 {
            let added = Docs:add(selected, entry.scope, entry.id, entry.title, entry.section, entry.body, entry.source_path, entry.origin_path)
            if !added { selected.error = 1; return selected }; Docs:copy_details(added, entry)
        }; entry = entry.next
    }
    var bucket = 0
    while bucket < 4096 {
        var term = source.terms[bucket]
        while term {
            var posting = term.first
            while posting {
                if strcmp(posting.entry.scope, scope) == 0 {
                    let target = Docs:term(selected, term.word, 1)
                    if !Docs:posting(selected, target, Docs:find(selected, scope, posting.entry.id)) { selected.error = 1; return selected }
                }; posting = posting.next
            }; term = term.next
        }; bucket += 1
    }
    selected.index_ready = 1; Docs:sort(selected); return selected
}

// Application export keeps the configured package, excluding dependency scopes.
let Docs:export_package = fn (root:u8*, path:u8*) -> i64 {
    let catalog = Docs:load(root, "")
    if !catalog { return 0 }; defer Docs:destroy(catalog)
    if catalog.error { return 0 }
    let selected = Docs:Build:scope_catalog(catalog, catalog.name)
    if !selected { return 0 }; defer Docs:destroy(selected)
    if selected.error || !selected.first { return 0 }
    return Docs:export_file(selected, path)
}
set Docs:export_package.docs = "Exports one source package's configured manual objects and API help as portable v3 JSON. Reads recurloop.docs under root and excludes dependency scopes. The output directory must exist. Returns 1 on success, 0 on failure."

// Retire only recognized generated documentation files, never arbitrary JSON.
let Docs:Build:clean_obsolete = fn (output:u8*, scopes:u8*) -> void {
    let paths = capture find "{output}" -maxdepth 1 -type f -name "*.json"
    if !paths { return }; defer free(paths)
    var path = paths
    while path[0] != 0 {
        var end = 0; while path[end] != 0 && path[end] != 10 { end += 1 }
        let more = path[end] == 10; path[end] = 0
        let name = Docs:basename(path)
        if strcmp(name, "index.json") != 0 && strcmp(name, "documentation-format.json") != 0 && strcmp(name, "documentation-example.json") != 0 {
            let stem = LanguageKit:copy_bytes(name, cast(i64, strlen(name)) - 5)
            let marker = LanguageKit:Text:new(); marker.append("\n"); marker.append(stem); marker.append("\n"); free(stem)
            if !strstr(scopes, marker.data) {
                let text = Docs:read_file(path)
                if text {
                    let document = Docs:json_parse(text); free(text)
                    let version = Docs:json_field(document, "schema_version")
                    let pages = Docs:json_field(document, "pages"); let bundles = Docs:json_field(document, "bundles")
                    if version && version.kind == 4 && (strcmp(version.text, "2") == 0 || strcmp(version.text, "3") == 0) && ((pages && pages.kind == 2) || (bundles && bundles.kind == 2)) { unlink(path) }
                    Docs:json_destroy(document)
                }
            }; marker.destroy()
        }
        if !more { break }; path = &path[end + 1]
    }
}

let Docs:Build:write_collection = fn (store:Docs:Store*, output:u8*) -> i64 {
    if !store || store.error || !store.first || !Docs:build_index(store) { return 1 }
    let status = run mkdir -p "{output}"
    if status != 0 { return 2 }
    Docs:sort(store)
    let index = LanguageKit:Text:new(); let scopes = LanguageKit:Text:new(); defer index.destroy(); defer scopes.destroy()
    index.append("{\"schema_version\":3,\"version\":"); Docs:json(index, store.version)
    index.append(",\"source_revision\":"); Docs:json(index, store.revision)
    index.append(",\"repository_url\":"); Docs:json(index, store.repository)
    index.append(",\"bundles\":[\n")
    var entry = store.first; var count = 0
    while entry {
        let marker = LanguageKit:Text:new(); marker.append("\n"); marker.append(entry.scope); marker.append("\n")
        if !strstr(scopes.data, marker.data) {
            scopes.append(marker.data)
            if !Docs:valid_id(entry.scope) { marker.destroy(); return 3 }
            let selected = Docs:Build:scope_catalog(store, entry.scope)
            if !selected || selected.error || !selected.first { if selected { Docs:destroy(selected) }; marker.destroy(); return 4 }
            let base = Docs:join("/docs", entry.scope)
            let filename = LanguageKit:Text:new(); filename.append(entry.scope); filename.append(".json")
            let destination = Docs:join(output, filename.data)
            let json = Docs:as_json(selected, base, store.revision)
            let written = json && Docs:write_file(destination, json)
            free(json); free(destination)
            if !written { free(base); filename.destroy(); Docs:destroy(selected); marker.destroy(); return 5 }
            if count { index.append(",\n") }
            index.append("{\"id\":"); Docs:json(index, entry.scope)
            index.append(",\"title\":")
            Docs:json(index, selected.first.title)
            index.append(",\"kind\":")
            if strcmp(entry.scope, "core") == 0 { Docs:json(index, "engine") } else { Docs:json(index, "library") }
            index.append(",\"version\":"); Docs:json(index, selected.version)
            index.append(",\"file\":"); Docs:json(index, filename.data)
            index.append(",\"href\":"); Docs:href(index, base, selected.first.id)
            index.append(",\"pages\":[")
            var page = selected.first; var pages = 0
            while page { if pages { index.append(",") }; Docs:summary_json(index, page, base); pages += 1; page = page.next }
            index.append("]}")
            printf("[docs] %s: %ld phrase/document objects\n", entry.scope, pages)
            free(base); filename.destroy(); Docs:destroy(selected); count += 1
        }
        marker.destroy(); entry = entry.next
    }
    index.append("\n],\"default_href\":")
    let home = Docs:join("/docs", store.first.scope); Docs:href(index, home, store.first.id); free(home)
    index.append(",\"index\":"); if !Docs:index_json(index, store, "site:") { return 6 }
    index.append(",\"assets\":[\"documentation-format.json\",\"documentation-example.json\"]}\n")
    let path = Docs:join(output, "index.json"); defer free(path)
    if !Docs:write_file(path, index.data) { return 7 }; Docs:Build:clean_obsolete(output, scopes.data); return 0
}
let Docs:Build:collection_assets = fn (root:u8*, output:u8*) -> i64 {
    let schema_path = Docs:join(root, "libraries/docs/contract.schema.json")
    let schema = Docs:read_file(schema_path); free(schema_path)
    if !schema { return 1 }; defer free(schema)
    let destination = Docs:join(output, "documentation-format.json")
    let written = Docs:write_file(destination, schema); free(destination)
    if !written { return 2 }
    let sample = Docs:new("example", "1.0.0", "")
    if !sample { return 3 }; defer Docs:destroy(sample)
    let page = Docs:add(sample, "example", "answer", "Example:answer", "API", "Returns an answer without transferring ownership.\n\n## Example\n\n```recurloop\nprint Example:answer()\n```", "", "")
    if !page { return 4 }; free(page.symbol); page.symbol = Docs:copy("Example:answer"); page.home = 1
    let example_path = Docs:join(output, "documentation-example.json"); defer free(example_path)
    if !Docs:export_file(sample, example_path) { return 5 }; return 0
}

let Docs:Build:validate_references = fn (store:Docs:Store*, trace:u8*, image:u8*) -> i64 {
    let copy = Docs:copy(trace); if !copy { return 0 }; defer free(copy)
    let catalog = Docs:parse_trace(copy); if !catalog { return 0 }; defer Docs:destroy_catalog(catalog)
    if catalog.error { return 0 }; var entry = store.first
    while entry {
        if !Docs:empty(entry.symbol) {
            var symbol = catalog.first; var found = 0
            while symbol {
                if strcmp(symbol.name, entry.symbol) == 0 && !Docs:empty(symbol.image) && strcmp(Docs:basename(symbol.image), image) == 0 { found = 1; break }; symbol = symbol.next
            }
            if !found { printf("[docs] unresolved phrase %s in %s\n", entry.symbol, image); return 0 }
        }; entry = entry.next
    }; return 1
}
let Docs:Build:public_content = fn (store:Docs:Store*) -> i64 {
    var entry = store.first
    while entry {
        if Docs:contains(entry.body, "Makefile") || Docs:contains(entry.body, "CMake") || Docs:contains(entry.body, "build/Release") || Docs:contains(entry.body, "make docs") || Docs:contains(entry.body, "C++ host") || Docs:contains(entry.inline_docs, "CMake") || Docs:contains(entry.inline_docs, "C++ host") {
            printf("[docs] implementation/repository instructions in public page %s\n", entry.title); return 0
        }; entry = entry.next
    }; return 1
}
let Docs:Build:export_scope = fn (root:u8*, output:u8*, scope:u8*, version:u8*, revision:u8*) -> i64 {
    let store = Docs:new(scope, version, "https://github.com/RecurLoop/RecurLoop")
    if !store { return 1 }; defer Docs:destroy(store)
    free(store.revision); store.revision = Docs:copy(revision)
    var package = Docs:copy(root)
    if strcmp(scope, "core") != 0 {
        let libraries = Docs:join(root, "libraries")
        free(package); package = Docs:join(libraries, scope); free(libraries)
    }; defer free(package)
    if !Docs:load_package(store, package, "") { return 2 }
    let entry = Docs:join(root, ".cache/docs-export/recurloop.project.rl"); defer free(entry)
    var library = scope; if strcmp(scope, "core") == 0 { library = "project" }
    let trace = Docs:trace(entry, library)
    if !trace { return 3 }; defer free(trace)
    let image = LanguageKit:Text:new(); image.append(scope); image.append(".rli"); defer image.destroy()
    if !Docs:Build:validate_references(store, trace, image.data) { return 5 }
    if !Docs:import_trace(store, trace, image.data, scope, 0) { return 4 }
    if !Docs:Build:public_content(store) { return 6 }
    let result = Docs:Build:write_collection(store, output)
    if result != 0 { return result }; return Docs:Build:collection_assets(root, output)
}
let Docs:Build:export = fn (output:u8*, root:u8*, scope:u8*, merge_parts:u8*, version:u8*, revision:u8*) -> i64 {
    let directory_status = run mkdir -p "{output}" "{root}/.cache/docs-export"
    if directory_status != 0 { return 1 }
    let entry = Docs:join(root, ".cache/docs-export/recurloop.project.rl")
    let written = Docs:write_file(entry, ""); free(entry)
    if !written { return 2 }
    if !Docs:empty(scope) && strcmp(scope, "all") != 0 {
        let result = Docs:Build:export_scope(root, output, scope, version, revision)
        if result != 0 { return result }; return Docs:Build:collection_assets(root, output)
    }
    let merged = Docs:new("core", version, "https://github.com/RecurLoop/RecurLoop")
    if !merged { return 3 }; defer Docs:destroy(merged)
    free(merged.revision); merged.revision = Docs:copy(revision)
    if !Docs:empty(merge_parts) {
        let files = capture find "{merge_parts}" -mindepth 2 -maxdepth 2 -name index.json -type f | sort
        if !files { return 4 }; defer free(files)
        var path = files
        while path[0] != 0 {
            var end = 0; while path[end] != 0 && path[end] != 10 { end += 1 }
            let more = path[end] == 10; path[end] = 0
            if !Docs:read_export(merged, path) { return 5 }
            if !more { break }; path = &path[end + 1]
        }
    } else {
        let inventory_path = Docs:join(root, "libraries/standard.txt")
        let inventory = Docs:read_file(inventory_path); free(inventory_path)
        if !inventory { return 6 }; defer free(inventory)
        let parts = Docs:join(output, "parts"); defer free(parts)
        let core = Docs:join(parts, "core")
        let first = Docs:Build:export_scope(root, core, "core", version, revision)
        let core_index = Docs:join(core, "index.json"); free(core)
        if first != 0 || !Docs:read_export(merged, core_index) { free(core_index); return 7 }; free(core_index)
        var name = inventory
        while name[0] != 0 {
            var end = 0; while name[end] != 0 && name[end] != 10 { end += 1 }
            let more = name[end] == 10; name[end] = 0
            if name[0] != 0 && name[0] != 35 {
                let part = Docs:join(parts, name)
                let result = Docs:Build:export_scope(root, part, name, version, revision)
                let index_path = Docs:join(part, "index.json"); free(part)
                if result != 0 || !Docs:read_export(merged, index_path) { free(index_path); return 8 }; free(index_path)
            }
            if !more { break }; name = &name[end + 1]
        }
    }
    let result = Docs:Build:write_collection(merged, output)
    if result != 0 { return result }; return Docs:Build:collection_assets(root, output)
}
let Docs:Build:export_from_environment = fn () -> i64 {
    var output = getenv("RECURLOOP_DOCS_OUTPUT"); if Docs:empty(output) { output = "build/documentation" }
    var root = Docs:copy(getenv("RECURLOOP_DOCS_ROOT")); if Docs:empty(root) { free(root); root = capture pwd }; defer free(root); Docs:trim(root)
    let runtime = Docs:executable(); defer free(runtime)
    let release = capture "{runtime}" --version
    if !release { return 1 }; defer free(release); Docs:trim(release)
    var version = release; while version[0] != 0 && version[0] != 118 { version = &version[1] }; if version[0] != 118 { return 2 }; version = &version[1]
    var revision = Docs:copy(getenv("RECURLOOP_DOCS_REVISION"))
    if Docs:empty(revision) { free(revision); revision = capture git rev-parse HEAD }
    if !revision { return 3 }; defer free(revision); Docs:trim(revision)
    return Docs:Build:export(output, root, getenv("RECURLOOP_DOCS_SCOPE"), getenv("RECURLOOP_DOCS_MERGE_PARTS"), version, revision)
}

