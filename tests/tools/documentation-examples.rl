// Evaluate every executable public-manual example in a clean runtime.
// GUI/server examples define callable functions; they do not start loops here.
// Core API invocation templates are not standalone programs; guide examples are.
let DocsExamples = []
let DocsExamples:check = fn (store:Docs:Store*, executable:u8*, libraries:u8*, directory:u8*) -> i64 {
    var entry = store.first; var count = 0; var failed = 0
    while entry {
        var cursor = entry.body
        if strcmp(store.name, "core") == 0 && strcmp(entry.section, "API") == 0 { cursor = cast(u8*, 0) }
        while cursor && cursor[0] != 0 {
            let opening = strstr(cursor, "```recurloop\n")
            if !opening { break }
            let begin = &opening[strlen("```recurloop\n")]
            let finish = strstr(begin, "\n```")
            if !finish { printf("[docs-examples] unterminated example in %s\n", entry.title); return -1 }
            let source = LanguageKit:copy_bytes(begin, cast(i64, finish) - cast(i64, begin))
            if !source { return -1 }; count += 1
            let name = malloc(128); if !name { free(source); return -1 }
            snprintf(name, 128, "%s-%ld.rl", store.name, count)
            let file = Docs:join(directory, name); free(name)
            let written = Docs:write_file(file, source); free(source)
            if !written { free(file); return -1 }
            let process = spawn timeout 45 "{executable}" --library-path "{libraries}" --file "{file}"
            if !process { free(file); return -1 }
            let status = process.exit_code()
            if status != 0 {
                printf("[docs-examples] %s / %s failed (%ld), source: %s\n%s\n", store.name, entry.title, status, file, process.stdout())
                failed += 1
            }
            process.destroy(); free(file); cursor = &finish[4]
        }; entry = entry.next
    }; if failed { return -failed }; return count
}
let DocsExamples:all = fn () -> i64 {
    let generated = ".cache/docs-examples"
    let prepared = run mkdir -p "{generated}"
    if prepared != 0 { return 1 }
    let directory = realpath(generated, cast(u8*, 0))
    if !directory { return 1 }; defer free(directory)
    let executable = Docs:executable(); if !executable { return 3 }; defer free(executable)
    let bindir = Docs:parent(executable)
    var libraries = Docs:copy(getenv("RECURLOOP_DOCS_LIBRARY_PATH"))
    if Docs:empty(libraries) { free(libraries); libraries = Docs:join(bindir, "../libraries") }
    free(bindir); defer free(libraries)
    let inventory = Docs:read_file("libraries/standard.txt"); if !inventory { return 4 }; defer free(inventory)
    var line = inventory; var total = 0; var failed = 0
    while line[0] != 0 {
        var end = 0; while line[end] != 0 && line[end] != 10 { end += 1 }
        let more = line[end] == 10; line[end] = 0
        if line[0] != 0 && line[0] != 35 {
            let name = Docs:trim(line)
            let root = Docs:join("libraries", name)
            let store = Docs:new(name, "test", "")
            if !store { free(root); return 5 }
            let loaded = Docs:load_package(store, root, ""); free(root)
            if !loaded { Docs:destroy(store); return 6 }
            let count = DocsExamples:check(store, executable, libraries, directory)
            Docs:destroy(store)
            if count < 0 { failed -= count }
            if count == 0 { printf("[docs-examples] no executable examples in %s\n", name); return 8 }
            if count > 0 { printf("[docs-examples] %s: %ld examples passed\n", name, count); total += count }
        }
        if !more { break }; line = &line[end + 1]
    }
    let core = Docs:new("core", "test", "")
    if !core { return 9 }
    let core_loaded = Docs:load_package(core, ".", "")
    if !core_loaded { Docs:destroy(core); return 10 }
    let core_count = DocsExamples:check(core, executable, libraries, directory)
    Docs:destroy(core)
    if core_count <= 0 { printf("[docs-examples] core examples failed or missing\n"); return 11 }
    printf("[docs-examples] core: %ld examples passed\n", core_count); total += core_count
    if failed { printf("[docs-examples] %ld examples failed\n", failed); return 7 }
    printf("[docs-examples] %ld examples passed in isolated runtimes\n", total)
    return 0
}
