extern opendir(path:u8*) -> u8* abi sysv-amd64
extern closedir(directory:u8*) -> i32 abi sysv-amd64
// Source repositories opt in with recurloop.docs; docs/ is the default.
let Docs:parent = fn (path:u8*) -> u8* {
    let out = Docs:copy(path)
    if !out { return out }
    var size = cast(i64, strlen(out))
    while size > 1 && out[size - 1] == 47 { size -= 1 }
    while size > 1 && out[size - 1] != 47 { size -= 1 }
    if size > 1 { size -= 1 }; out[size] = 0
    return out
}
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
let Docs:load_package = fn (store:Docs:Store*, root:u8*, override:u8*) -> i64 {
    let path = Docs:join(root, "recurloop.docs")
    let config = Docs:read_file(path); free(path)
    defer free(config)
    let name = Docs:setting(config, "name", Docs:basename(root))
    let version = Docs:setting(config, "version", "dev")
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
    store.version = old_version; store.repository = old_repository
    return success
}
let Docs:executable = fn () -> u8* {
    let out = malloc(4096)
    if !out { return out }
    let size = readlink("/proc/self/exe", out, 4095)
    if size < 0 { free(out); return cast(u8*, 0) }; out[size] = 0
    return out
}
// Uses the runtime's semantic trace, never a regex approximation of .rl syntax.
// Libraries is a newline-delimited inventory, or empty for a project's default baseline.
let Docs:trace = fn (entry:u8*, libraries_text:u8*) -> u8* {
    let executable = Docs:executable()
    if !executable { return executable }; defer free(executable)
    let bindir = Docs:parent(executable)
    let libraries = Docs:join(bindir, "../libraries"); free(bindir)
    defer free(libraries)
    let pipeline = Shell:Pipeline:new()
    let command = Shell:Command:new()
    if !pipeline || !command { return cast(u8*, 0) }
    if !pipeline.add(command) { command.destroy(); pipeline.destroy(); return cast(u8*, 0) }
    defer pipeline.destroy()
    command.add(executable); command.add("--library-path"); command.add(libraries)
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
    if result.exit_code != 0 { return cast(u8*, 0) }
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
        var valid = !Docs:empty(item.description) || !Docs:empty(item.summary)
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
                entry = Docs:add(store, owner, id, item.name, "API", body, item.source, item.source)
                free(body)
            }
            if entry {
                free(entry.inline_docs)
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

let Docs:load_standard = fn (store:Docs:Store*) -> i64 {
    var directory = Docs:copy(getenv("RECURLOOP_DOCS_PATH"))
    if Docs:empty(directory) {
        free(directory)
        let executable = Docs:executable()
        if !executable { return 0 }
        let bindir = Docs:parent(executable); free(executable)
        directory = Docs:join(bindir, "../../../source/docs")
        if access(directory, 4) != 0 { free(directory); directory = Docs:join(bindir, "../share/recurloop/docs") }
        free(bindir)
    }
    defer free(directory)
    if access(directory, 4) != 0 { return 1 }
    let paths = capture find "{directory}" -mindepth 2 -maxdepth 2 -name index.tsv -type f | sort
    if !paths { return 0 }; defer free(paths)
    let old_version = store.version
    let executable = Docs:executable()
    let version_job = spawn "{executable}" --version
    free(executable)
    if !version_job { return 0 }
    let release = Docs:copy(version_job.stdout()); version_job.destroy(); Docs:trim(release)
    var version = release
    while version[0] != 0 && version[0] != 118 { version = &version[1] }
    if version[0] == 118 { store.version = &version[1] }
    let old_repo = store.repository
    store.repository = "https://github.com/RecurLoop/RecurLoop"
    var line = paths
    while line[0] != 0 {
        var end = 0
        while line[end] != 0 && line[end] != 10 { end += 1 }
        let more = line[end] == 10; line[end] = 0
        let folder = Docs:parent(line)
        let previous = store.last
        let loaded = Docs:load_directory(store, "/", folder, Docs:basename(folder))
        var added = store.first; if previous { added = previous.next }
        while added {
            if strlen(added.source_path) <= strlen(folder) { added = added.next; continue }
            let logical = LanguageKit:Text:new(); logical.append("source/docs/"); logical.append(Docs:basename(folder)); logical.append("/"); logical.append(&added.source_path[strlen(folder) + 1])
            free(added.source_path); added.source_path = logical.take(); logical.destroy(); added = added.next
        }
        free(folder)
        if !loaded { store.repository = old_repo; store.version = old_version; free(release); return 0 }
        if !more { break }; line = &line[end + 1]
    }
    store.repository = old_repo; store.version = old_version; free(release)
    return Docs:standard_trace(store, directory)
}
let Docs:load_options = fn (root:u8*, directory:u8*, standard:i64) -> Docs:Store* {
    let canonical = realpath(root, cast(u8*, 0))
    if !canonical { return cast(Docs:Store*, 0) }; defer free(canonical)
    let configpath = Docs:join(canonical, "recurloop.docs")
    let config = Docs:read_file(configpath); free(configpath)
    defer free(config)
    let name = Docs:setting(config, "name", Docs:basename(canonical))
    let version = Docs:setting(config, "version", "dev")
    let repository = Docs:setting(config, "repository", "")
    let entry = Docs:setting(config, "entry", "recurloop.project.rl")
    defer free(name); defer free(version); defer free(repository); defer free(entry)
    let store = Docs:new(name, version, repository)
    if !store { return store }
    free(store.root); store.root = Docs:copy(canonical)
    if !Docs:load_package(store, canonical, directory) { store.error = 1; return store }
    if standard && !Docs:load_standard(store) { store.error = 1; return store }
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
    return store
}

let Docs:load = fn (root:u8*, directory:u8*) -> Docs:Store* { return Docs:load_options(root, directory, 0) }
