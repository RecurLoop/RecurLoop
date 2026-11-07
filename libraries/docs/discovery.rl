extern opendir(path:u8*) -> u8* abi sysv-amd64
extern closedir(directory:u8*) -> i32 abi sysv-amd64
// Source repositories opt in with recurloop.docs; docs/ is the default.
let Docs:package_root = fn (source:u8*) -> u8* {
    let canonical = realpath(source, cast(u8*, 0))
    if !canonical { return cast(u8*, 0) }
    let handle = opendir(canonical)
    var directory = cast(u8*, 0)
    if handle { closedir(handle); directory = Docs:copy(canonical) } else { directory = Docs:parent(canonical) }
    free(canonical)
    var depth = 0; var fallback = cast(u8*, 0)
    while directory && strcmp(directory, "/") != 0 && depth < 32 {
        let config = Docs:join(directory, "recurloop.docs")
        let project = Docs:join(directory, "recurloop.project.rl")
        let git = Docs:join(directory, ".git")
        let docs = Docs:join(directory, "docs")
        let found = access(config, 4) == 0 || access(project, 4) == 0 || access(git, 0) == 0
        if !fallback && access(docs, 4) == 0 { fallback = Docs:copy(directory) }
        free(config); free(project); free(git); free(docs)
        if found { free(fallback); return directory }
        let parent = Docs:parent(directory); free(directory); directory = parent; depth += 1
    }
    free(directory); return fallback
}
let Docs:executable = fn () -> u8* {
    let out = malloc(4096)
    if !out { return out }
    let size = readlink("/proc/self/exe", out, 4095)
    if size < 0 { free(out); return cast(u8*, 0) }; out[size] = 0
    return out
}
let Docs:runtime_version = fn () -> u8* {
    let executable = Docs:executable(); if !executable { return cast(u8*, 0) }
    let command = spawn "{executable}" --version
    free(executable); if !command { return cast(u8*, 0) }; defer command.destroy()
    if command.exit_code() != 0 { return cast(u8*, 0) }
    let text = Docs:copy(command.stdout()); if !text { return text }; defer free(text); Docs:trim(text)
    var version = text; while version[0] != 0 && version[0] != 118 { version = &version[1] }
    if version[0] != 118 { return cast(u8*, 0) }; return Docs:copy(&version[1])
}
let Docs:package_version = fn (config:u8*) -> u8* {
    let version = Docs:setting(config, "version", "dev")
    if strcmp(version, "runtime") != 0 { return version }; free(version); return Docs:runtime_version()
}
// A source directory contains .rl objects only. Its index is built after evaluation.
let Docs:load_directory = fn (store:Docs:Store*, root:u8*, directory:u8*, scope:u8*) -> i64 {
    let full = Docs:join(root, directory); defer free(full)
    if access(full, 4) != 0 { return 1 }
    let canonical = realpath(full, cast(u8*, 0))
    if !canonical { store.error = 1; return 0 }; defer free(canonical)
    let marker = LanguageKit:Text:new(); marker.append("\n"); marker.append(canonical); marker.append("\n"); defer marker.destroy()
    if strstr(store.loaded.data, marker.data) { return 1 }
    let paths = capture find "{canonical}" -type f -name "*.rl" | sort
    if !paths { store.error = 1; return 0 }; defer free(paths)
    if paths[0] == 0 { store.loaded.append(marker.data); return 1 }
    let temporary = Docs:copy("/tmp/recurloop-doc-objects-XXXXXX")
    if !mkdtemp(temporary) { free(temporary); store.error = 1; return 0 }
    let entry = Docs:join(temporary, "recurloop.project.rl")
    let output = Docs:join(temporary, "objects.json")
    let source = LanguageKit:Text:new()
    var path = paths
    while path[0] != 0 {
        var end = 0; while path[end] != 0 && path[end] != 10 { end += 1 }
        let more = path[end] == 10; path[end] = 0
        source.append("include "); Docs:json(source, path); source.append("\nDocs:source ")
        let logical = Docs:join(directory, &path[strlen(canonical) + 1])
        Docs:json(source, logical); free(logical); source.append("\n")
        if !more { break }; path = &path[end + 1]
    }
    source.append("Docs:dump_objects\n")
    let written = Docs:write_file(entry, source.data); source.destroy()
    if !written { store.error = 1 }
    let executable = Docs:executable()
    let libraries = Docs:copy(getenv("RECURLOOP_DOCS_LIBRARY_PATH"))
    if !store.error {
        var command = cast(Shell:Invocation*, 0)
        if Docs:empty(libraries) { command = spawn "{executable}" --library docs --file "{entry}" -- "{scope}" "{store.version}" "{store.repository}" "{output}" }
        else { command = spawn "{executable}" --library-path "{libraries}" --library docs --file "{entry}" -- "{scope}" "{store.version}" "{store.repository}" "{output}" }
        if !command { Docs:diagnostic("cannot start object loader", canonical); store.error = 1 }
        else {
            if command.exit_code() != 0 { Docs:diagnostic("object loader failed", canonical); Docs:diagnostic("loader output", command.stdout()); store.error = 1 }
            else if !Docs:read_export(store, output) { Docs:diagnostic("cannot read evaluated objects", canonical); store.error = 1 }
            command.destroy()
        }
    }
    free(executable); free(libraries); free(entry); free(output)
    let cleanup = run rm -rf -- "{temporary}"
    free(temporary)
    if !store.error { store.loaded.append(marker.data) }; return !store.error
}

let Docs:load_package = fn (store:Docs:Store*, root:u8*, override:u8*) -> i64 {
    let path = Docs:join(root, "recurloop.docs")
    let config = Docs:read_file(path); free(path)
    defer free(config)
    let name = Docs:setting(config, "name", Docs:basename(root))
    let version = Docs:package_version(config)
    let repository = Docs:setting(config, "repository", "")
    var directory = Docs:setting(config, "directory", "docs")
    if !Docs:empty(override) { free(directory); directory = Docs:copy(override) }
    defer free(name); defer free(version); defer free(repository); defer free(directory)
    let old_version = store.version; let old_repository = store.repository
    store.version = version; store.repository = repository
    var success = 1
    let full = Docs:join(root, directory)
    let configured_directory = Docs:setting(config, "directory", "")
    if (!Docs:empty(override) || !Docs:empty(configured_directory)) && access(full, 4) != 0 { store.error = 1; success = 0 }
    free(full); free(configured_directory)
    if success { success = Docs:load_directory(store, root, directory, name) }
    // A package may live below its repository root without moving its docs out of the package.
    let prefix = Docs:setting(config, "repository-directory", ""); defer free(prefix)
    if success && !Docs:empty(prefix) {
        let boundary = Docs:join(prefix, ""); defer free(boundary)
        var entry = store.first
        while entry {
            if strcmp(entry.scope, name) == 0 && !Docs:empty(entry.source_path) && entry.source_path[0] != 47 && !Docs:prefix(entry.source_path, boundary) {
                let source = Docs:join(prefix, entry.source_path)
                free(entry.source_path); entry.source_path = source
                free(entry.source_url); entry.source_url = Docs:copy("")
            }; entry = entry.next
        }
    }
    store.version = old_version; store.repository = old_repository
    return success
}
// Uses the runtime's semantic trace, never a regex approximation of .rl syntax.
// Libraries is a newline-delimited inventory, or empty for a project's default baseline.
let Docs:trace = fn (entry:u8*, libraries_text:u8*) -> u8* {
    let executable = Docs:executable()
    if !executable { return executable }; defer free(executable)
    let libraries = Docs:copy(getenv("RECURLOOP_DOCS_LIBRARY_PATH"))
    defer free(libraries)
    let pipeline = Shell:Pipeline:new()
    let command = Shell:Command:new()
    if !pipeline || !command { return cast(u8*, 0) }
    if !pipeline.add(command) { command.destroy(); pipeline.destroy(); return cast(u8*, 0) }
    defer pipeline.destroy()
    command.add(executable)
    // Let the host resolve its own installed/build images; an override is explicit.
    if !Docs:empty(libraries) { command.add("--library-path"); command.add(libraries) }
    if !Docs:empty(libraries_text) {
        let copy = Docs:copy(libraries_text); defer free(copy)
        var line = copy
        while line[0] != 0 {
            var end = 0
            while line[end] != 0 && line[end] != 10 { end += 1 }
            let more = line[end] == 10; line[end] = 0
            if line[0] != 0 && line[0] != 35 { command.add("--library"); command.add(Docs:trim(line)) }
            if !more { break }; line = &line[end + 1]
        }
    }
    command.add("--project"); command.add(entry); command.add("--trace"); command.add(entry)
    let result = Shell:capture_pipeline(pipeline)
    if !result { return cast(u8*, 0) }; defer result.destroy()
    if result.exit_code != 0 { Docs:diagnostic("source inspection failed", entry); Docs:diagnostic("inspection output", result.output); return cast(u8*, 0) }
    return Docs:copy(result.output)
}
let Docs:import_trace = fn (store:Docs:Store*, trace:u8*, filter:u8*, scope:u8*, discover:i64) -> i64 {
    let catalog = Docs:parse_trace(trace)
    if !catalog { store.error = 1; return 0 }; defer Docs:destroy_catalog(catalog)
    if catalog.error { store.error = 1; return 0 }
    var item = catalog.first
    while item {
        if discover && item.project_source && !Docs:empty(item.source) {
            let root = Docs:package_root(item.source)
            if root { if strcmp(root, store.root) != 0 && !Docs:load_package(store, root, "") { free(root); return 0 }; free(root) }
        }
        item = item.next
    }
    item = catalog.first
    while item {
        var valid = (!Docs:empty(item.description) || !Docs:empty(item.summary)) && !Docs:prefix(item.name, "Docs:Pages") && !Docs:prefix(item.name, "Docs:Build")
        var at = 0
        while item.name[at] != 0 { if item.name[at] < 32 { valid = 0 }; at += 1 }
        if !Docs:empty(filter) && !Docs:documented(item, filter) { valid = 0 }
        if valid {
            var owner = Docs:copy(scope)
            if Docs:empty(owner) {
                free(owner); owner = Docs:copy(store.name)
                if item.project_source && !Docs:empty(item.source) {
                    let root = Docs:package_root(item.source)
                    if root {
                        let path = Docs:join(root, "recurloop.docs"); let config = Docs:read_file(path)
                        free(owner); owner = Docs:setting(config, "name", Docs:basename(root))
                        free(path); free(config); free(root)
                    }
                } else if !Docs:empty(item.image)  {
                    free(owner); owner = Docs:copy(Docs:basename(item.image))
                    let size = strlen(owner); if size > 4 { owner[size - 4] = 0 }
                }
            }
            let id = Docs:page_id(item.name)
            var entry = Docs:find(store, owner, id)
            if !entry {
                let body = Docs:body(item)
                var source_path = item.source
                if Docs:empty(source_path) { source_path = "" }
                else { let size = cast(i64, strlen(source_path)); if size < 3 || strcmp(&source_path[size - 3], ".rl") != 0 { source_path = "" } }
                entry = Docs:add(store, owner, id, item.name, "API", body, source_path, source_path)
                if entry { entry.authored = 0 }
                free(body)
            }
            if entry {
                free(entry.inline_docs)
                store.index_ready = 0
                if Docs:empty(entry.symbol) { free(entry.symbol); entry.symbol = Docs:copy(item.name) }
                let summary = LanguageKit:Text:new()
                if !Docs:empty(item.summary) { summary.append(item.summary); summary.append("\n\n") }
                if !Docs:empty(item.description) { summary.append(item.description) }
                entry.inline_docs = summary.take(); summary.destroy()
            }
            free(owner); free(id)
        }
        item = item.next
    }
    return !store.error
}
extern unlink(path:u8*) -> i32 abi sysv-amd64
extern rmdir(path:u8*) -> i32 abi sysv-amd64
// Inspect an installed library image without evaluating its image-build entry point.
let Docs:trace_library = fn (image:u8*) -> u8* {
    let temporary = Docs:copy("/tmp/recurloop-doc-library-XXXXXX")
    if !mkdtemp(temporary) { free(temporary); return cast(u8*, 0) }
    let entry = Docs:join(temporary, "recurloop.project.rl")
    var trace = cast(u8*, 0)
    if Docs:write_file(entry, "") { trace = Docs:trace(entry, image) }
    unlink(entry); free(entry); rmdir(temporary); free(temporary)
    return trace
}
// Resolve all installed standard-library code help in one isolated runtime.
let Docs:standard_trace = fn (store:Docs:Store*, directory:u8*) -> i64 {
    let source_inventory = Docs:join(directory, "../../libraries/standard.txt")
    let installed_inventory = Docs:join(directory, "../standard-libraries.txt")
    var inventory = Docs:read_file(source_inventory)
    if !inventory { inventory = Docs:read_file(installed_inventory) }
    free(source_inventory); free(installed_inventory)
    if !inventory { inventory = Docs:copy("docs\n") }; defer free(inventory)
    let temporary = Docs:copy("/tmp/recurloop-docs-XXXXXX")
    if !mkdtemp(temporary) { free(temporary); return 0 }
    let entry = Docs:join(temporary, "recurloop.project.rl")
    if !Docs:write_file(entry, "") { free(entry); rmdir(temporary); free(temporary); return 0 }
    let trace = Docs:trace(entry, inventory)
    unlink(entry)
    let cleanup = run rm -rf -- "{temporary}"
    free(entry); free(temporary)
    if !trace { return 0 }; defer free(trace)
    return Docs:import_trace(store, trace, "", "", 0)
}

// Standard manuals supplement source help. Explicit JSON merges remain strict.
// A source-authored page wins; rich manuals replace generated code-only bodies.
let Docs:include_standard = fn (store:Docs:Store*, baseline:Docs:Store*) -> i64 {
    if !store || !baseline || store.error || baseline.error || !Docs:build_index(baseline) { return 0 }
    let extra = Docs:new(baseline.name, baseline.version, baseline.repository)
    if !extra { return 0 }; defer Docs:destroy(extra)
    var entry = baseline.first
    while entry {
        let existing = Docs:find(store, entry.scope, entry.id)
        if existing {
            if !existing.authored && entry.authored {
                if !Docs:set_body(existing, entry.body) { return 0 }
                free(existing.title); existing.title = Docs:copy(entry.title)
                free(existing.section); existing.section = Docs:copy(entry.section)
                free(existing.source_path); existing.source_path = Docs:copy(entry.source_path)
                free(existing.origin_path); existing.origin_path = Docs:copy(entry.origin_path)
                free(existing.source_url); existing.source_url = Docs:copy(entry.source_url)
                free(existing.repository); existing.repository = Docs:copy(entry.repository)
                free(existing.version); existing.version = Docs:copy(entry.version)
                existing.order = entry.order; existing.home = entry.home; existing.authored = 1
            }
            if Docs:empty(existing.inline_docs) && !Docs:empty(entry.inline_docs) {
                free(existing.inline_docs); existing.inline_docs = Docs:copy(entry.inline_docs); store.index_ready = 0
            }
        } else {
            let added = Docs:add(extra, entry.scope, entry.id, entry.title, entry.section, entry.body, entry.source_path, entry.origin_path)
            if !added { return 0 }; Docs:copy_details(added, entry)
        }
        entry = entry.next
    }
    // Copy postings only for new pages. Existing pages use their own current text.
    var bucket = 0
    while bucket < 4096 {
        var term = baseline.terms[bucket]
        while term {
            var posting = term.first
            while posting {
                let added = Docs:find(extra, posting.entry.scope, posting.entry.id)
                if added { let target = Docs:term(extra, term.word, 1); if !target || !Docs:posting(extra, target, added) { return 0 } }
                posting = posting.next
            }
            term = term.next
        }; bucket += 1
    }
    extra.index_ready = 1
    return Docs:merge(store, extra)
}
let Docs:load_standard = fn (store:Docs:Store*) -> i64 {
    let exported = getenv("RECURLOOP_DOCS_INDEX")
    if !Docs:empty(exported) {
        let baseline = Docs:new("", "dev", ""); if !baseline { return 0 }; defer Docs:destroy(baseline)
        if !Docs:read_export(baseline, exported) { return 0 }; return Docs:include_standard(store, baseline)
    }
    let executable = Docs:executable(); if !executable { return 0 }
    let bindir = Docs:parent(executable); free(executable)
    var directory = Docs:copy(getenv("RECURLOOP_DOCS_PATH"))
    if Docs:empty(directory) { free(directory); directory = Docs:join(bindir, "../../../source/docs") }
    let installed = Docs:join(bindir, "../share/recurloop/docs/index.json"); free(bindir)
    defer free(directory); defer free(installed)
    if access(directory, 4) != 0 {
        if access(installed, 4) == 0 {
            let baseline = Docs:new("", "dev", ""); if !baseline { return 0 }; defer Docs:destroy(baseline)
            if !Docs:read_export(baseline, installed) { return 0 }; return Docs:include_standard(store, baseline)
        }; return 1
    }
    let version = Docs:runtime_version(); if !version { return 0 }
    let baseline = Docs:new("core", version, "https://github.com/RecurLoop/RecurLoop"); free(version)
    if !baseline { return 0 }; defer Docs:destroy(baseline)
    let source_parent = Docs:parent(directory)
    let source_root = Docs:parent(source_parent); free(source_parent); defer free(source_root)
    if !Docs:load_package(baseline, source_root, "") { return 0 }
    let inventory_path = Docs:join(source_root, "libraries/standard.txt")
    let inventory = Docs:read_file(inventory_path); free(inventory_path)
    if !inventory { return 0 }; defer free(inventory)
    var line = inventory
    while line[0] != 0 {
        var end = 0; while line[end] != 0 && line[end] != 10 { end += 1 }
        let more = line[end] == 10; line[end] = 0
        if line[0] != 0 && line[0] != 35 {
            let libraries = Docs:join(source_root, "libraries")
            let package = Docs:join(libraries, Docs:trim(line)); free(libraries)
            let success = Docs:load_package(baseline, package, ""); free(package)
            if !success { return 0 }
        }
        if !more { break }; line = &line[end + 1]
    }
    if !Docs:standard_trace(baseline, directory) { return 0 }; return Docs:include_standard(store, baseline)
}
let Docs:load_options = fn (root:u8*, directory:u8*, standard:i64) -> Docs:Store* {
    let canonical = realpath(root, cast(u8*, 0))
    if !canonical { return cast(Docs:Store*, 0) }; defer free(canonical)
    let configpath = Docs:join(canonical, "recurloop.docs")
    let config = Docs:read_file(configpath); free(configpath)
    defer free(config)
    let name = Docs:setting(config, "name", Docs:basename(canonical))
    let version = Docs:package_version(config)
    let repository = Docs:setting(config, "repository", "")
    let entry = Docs:setting(config, "entry", "recurloop.project.rl")
    defer free(name); defer free(version); defer free(repository); defer free(entry)
    let store = Docs:new(name, version, repository)
    if !store { return store }
    free(store.root); store.root = Docs:copy(canonical)
    if !Docs:load_package(store, canonical, directory) { store.error = 1; return store }
    let image = Docs:setting(config, "image", ""); defer free(image)
    if !Docs:empty(image) {
        let trace = Docs:trace_library(image)
        if !trace { store.error = 1; return store }; defer free(trace)
        let filter = LanguageKit:Text:new(); filter.append(image); filter.append(".rli"); defer filter.destroy()
        Docs:import_trace(store, trace, filter.data, name, 0)
        if standard && !Docs:load_standard(store) { store.error = 1; return store }
        Docs:sort(store); Docs:build_index(store); return store
    }
    let entrypath = Docs:join(canonical, entry)
    defer free(entrypath)
    if access(entrypath, 4) != 0 && strcmp(entry, "recurloop.project.rl") == 0 {
        let fallback = Docs:join(canonical, "library.rl")
        if access(fallback, 4) == 0 {
            let trace = Docs:trace(fallback, "")
            if trace { Docs:import_trace(store, trace, "", "", 1); free(trace) } else { store.error = 1 }
        }
        free(fallback)
    }
    if access(entrypath, 4) == 0 {
        let trace = Docs:trace(entrypath, "")
        if !trace { store.error = 1; return store }; defer free(trace)
        Docs:import_trace(store, trace, "", "", 1)
    }
    if standard && !Docs:load_standard(store) { store.error = 1; return store }
    Docs:sort(store); Docs:build_index(store)
    return store
}

let Docs:load = fn (root:u8*, directory:u8*) -> Docs:Store* { return Docs:load_options(root, directory, 0) }
