// Evaluate every executable public-manual example in a clean runtime.
// GUI/server examples define callable functions; they do not start loops here.
// Core API invocation templates are not standalone programs; guide examples are.
let DocsExamples = []
// The first-project chapter is one workspace: execute its documented files together.
let DocsExamples:fenced_source = fn (body:u8*, opening:u8*, index:i64) -> u8* {
    var cursor = body; var at = 0
    while cursor {
        let found = strstr(cursor, opening); if !found { return cast(u8*, 0) }
        let begin = &found[strlen(opening)]
        let finish = strstr(begin, "\n```"); if !finish { return cast(u8*, 0) }
        if at == index { return LanguageKit:copy_bytes(begin, cast(i64, finish) - cast(i64, begin)) }
        at += 1; cursor = &finish[4]
    }; return cast(u8*, 0)
}
let DocsExamples:first_project = fn (entry:Docs:Entry*, executable:u8*, libraries:u8*, directory:u8*) -> i64 {
    let sandbox = Docs:join(directory, "first-project"); defer free(sandbox)
    let prepared = run mkdir -p "{sandbox}"
    if prepared != 0 { return 1 }
    let guard = Shell:cwd_enter(sandbox); if !guard { return 2 }; defer Shell:cwd_leave(guard)
    let folders = run mkdir -p src tests docs .vscode
    if folders != 0 { return 3 }
    let application = DocsExamples:fenced_source(entry.body, "```recurloop\n", 0)
    if !application { return 4 }; defer free(application)
    let project = DocsExamples:fenced_source(entry.body, "```recurloop\n", 1)
    if !project { return 5 }; defer free(project)
    let launch = DocsExamples:fenced_source(entry.body, "```json\n", 0)
    if !launch { return 6 }; defer free(launch)
    if !Docs:write_file("src/main.rl", application) || !Docs:write_file("recurloop.project.rl", project) || !Docs:write_file(".vscode/launch.json", launch) { return 7 }
    let tests = DocsExamples:fenced_source(entry.body, "```recurloop\n", 2)
    if !tests { return 20 }; defer free(tests)
    let manual = DocsExamples:fenced_source(entry.body, "```recurloop\n", 3)
    if !manual { return 21 }; defer free(manual)
    let settings = DocsExamples:fenced_source(entry.body, "```ini\n", 0)
    if !settings { return 22 }; defer free(settings)
    if !Docs:write_file("tests/main.rl", tests) || !Docs:write_file("docs/overview.rl", manual) || !Docs:write_file("recurloop.docs", settings) { return 23 }
    let config = Docs:json_parse(launch); if !config { return 8 }; defer Docs:json_destroy(config)
    let configurations = Docs:json_field(config, "configurations")
    if strcmp(Docs:json_text(config, "version", ""), "0.2.0") != 0 || !configurations || !configurations.first { return 9 }
    let selected = configurations.first
    if strcmp(Docs:json_text(selected, "type", ""), "recurloop") != 0 || strcmp(Docs:json_text(selected, "request", ""), "launch") != 0 || strcmp(Docs:json_text(selected, "target", ""), "debug") != 0 { return 10 }
    let targets = spawn timeout 45 "{executable}" --library-path "{libraries}" --targets
    if !targets { return 11 }; defer targets.destroy()
    if targets.exit_code() != 0 || !strstr(targets.stdout(), "build-debug") || !strstr(targets.stdout(), "debugExecutable") { return 12 }
    let check = spawn timeout 45 "{executable}" --library-path "{libraries}" --target test
    if !check { return 13 }; defer check.destroy()
    if check.exit_code() != 0 || strcmp(check.stdout(), "") != 0 { return 14 }
    let invocation = spawn timeout 45 "{executable}" --library-path "{libraries}" --project recurloop.project.rl --target run
    if !invocation { return 15 }; defer invocation.destroy()
    if invocation.exit_code() != 0 || strcmp(invocation.stdout(), "42\n") != 0 { return 16 }
    let build = spawn timeout 45 "{executable}" --library-path "{libraries}" --target build-debug
    if !build { return 17 }; defer build.destroy()
    if build.exit_code() != 0 { return 18 }
    let native = spawn timeout 10 ./build/app-debug
    if !native { return 19 }; defer native.destroy()
    if native.exit_code() != 0 || strcmp(native.stdout(), "42\n") != 0 { return 24 }
    let release = spawn timeout 45 "{executable}" --library-path "{libraries}" --target build
    if !release { return 25 }; defer release.destroy()
    if release.exit_code() != 0 { return 26 }
    let application_run = spawn timeout 10 ./build/app
    if !application_run { return 27 }; defer application_run.destroy()
    if application_run.exit_code() != 0 || strcmp(application_run.stdout(), "42\n") != 0 { return 28 }
    let exported = spawn timeout 45 "{executable}" --library-path "{libraries}" --target docs
    if !exported { return 29 }; defer exported.destroy()
    if exported.exit_code() != 0 || strcmp(exported.stdout(), "") != 0 { return 30 }
    let catalog = Docs:new("", "", "")
    if !catalog { return 31 }; defer Docs:destroy(catalog)
    if !Docs:read_export(catalog, "build/docs/my-application.json") { return 32 }
    if strcmp(catalog.name, "my-application") != 0 || strcmp(catalog.version, "0.1.0") != 0 || !Docs:find(catalog, "my-application", "overview") { return 33 }
    var page = catalog.first; var count = 0
    while page {
        if strcmp(page.scope, "my-application") != 0 { return 34 }
        count += 1; page = page.next
    }
    if count != 3 || !Docs:search(catalog, "answer", cast(Docs:Entry*, 0)) { return 35 }
    let cleanup = spawn timeout 10 "{executable}" --library-path "{libraries}" --target clean
    if !cleanup { return 36 }; defer cleanup.destroy()
    if cleanup.exit_code() != 0 || access("build", 0) == 0 || access("docs/overview.rl", 4) != 0 || access("src/main.rl", 4) != 0 { return 37 }
    printf("[docs-examples] first-project: workspace, targets, launch.json, native builds, own-package export and cleanup passed (%s)\n", sandbox)
    return 0
}
let DocsExamples:native_output = fn () -> i64 {
    let bytes = Docs:read_file("data.bin")
    if !bytes { return 1 }; defer free(bytes)
    if strcmp(bytes, "RL\n") != 0 { return 2 }
    let object = Docs:read_file("module.o")
    if !object { return 3 }; defer free(object)
    if object[0] != 127 || object[1] != 69 || object[2] != 76 || object[3] != 70 { return 4 }
    let release = run timeout 10 ./app
    if release != 0 { return release }
    return run timeout 10 ./app-debug
}
let DocsExamples:check = fn (store:Docs:Store*, executable:u8*, libraries:u8*, directory:u8*) -> i64 {
    Docs:sort(store)
    var entry = store.first; var count = 0; var failed = 0
    while entry {
        var cursor = entry.body
        if strcmp(store.name, "core") == 0 && strcmp(entry.section, "API") == 0 { cursor = cast(u8*, 0) }
        if strcmp(store.name, "core") == 0 && strcmp(entry.id, "first-project") == 0 {
            let status = DocsExamples:first_project(entry, executable, libraries, directory)
            if status != 0 { printf("[docs-examples] first-project failed (%ld), workspace: %s/first-project\n", status, directory); failed += 1 }
            else { count += 4 }
            cursor = cast(u8*, 0)
        }
        while cursor && cursor[0] != 0 {
            var opening = strstr(cursor, "```recurloop\n")
            var prefix_length = strlen("```recurloop\n")
            let short_opening = strstr(cursor, "```rl\n")
            if short_opening && (!opening || cast(i64, short_opening) < cast(i64, opening)) {
                opening = short_opening; prefix_length = strlen("```rl\n")
            }
            if !opening { break }
            let begin = &opening[prefix_length]
            let finish = strstr(begin, "\n```")
            if !finish { printf("[docs-examples] unterminated example in %s\n", entry.title); return -1 }
            let source = LanguageKit:copy_bytes(begin, cast(i64, finish) - cast(i64, begin))
            if !source { return -1 }; count += 1
            let name = malloc(128); if !name { free(source); return -1 }
            snprintf(name, 128, "%s-%ld", store.name, count)
            let sandbox = Docs:join(directory, name); free(name)
            let prepared = run mkdir -p "{sandbox}"
            if prepared != 0 { free(source); free(sandbox); return -1 }
            let file = Docs:join(sandbox, "example.rl")
            let written = Docs:write_file(file, source); free(source)
            if !written { free(file); free(sandbox); return -1 }
            let guard = Shell:cwd_enter(sandbox); free(sandbox)
            if !guard { free(file); return -1 }
            let process = spawn timeout 45 "{executable}" --library-path "{libraries}" --file "{file}"
            if !process { Shell:cwd_leave(guard); free(file); return -1 }
            var status = process.exit_code()
            if status == 0 && strcmp(store.name, "core") == 0 && strcmp(entry.id, "native-output") == 0 {
                status = DocsExamples:native_output()
            }
            Shell:cwd_leave(guard)
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
    let temporary = Docs:join(generated, "run-XXXXXX"); defer free(temporary)
    if !mkdtemp(temporary) { return 1 }
    let directory = realpath(temporary, cast(u8*, 0))
    if !directory { return 1 }; defer free(directory)
    let executable = Docs:executable(); if !executable { return 3 }; defer free(executable)
    let bindir = Docs:parent(executable)
    var libraries = Docs:copy(getenv("RECURLOOP_DOCS_LIBRARY_PATH"))
    if Docs:empty(libraries) { free(libraries); libraries = Docs:join(bindir, "../libraries") }
    if access(libraries, 4) != 0 { free(libraries); libraries = Docs:join(bindir, "../share/recurloop/libraries") }
    free(bindir); defer free(libraries)
    let canonical = realpath(libraries, cast(u8*, 0)); if !canonical { return 4 }; defer free(canonical)
    let core = Docs:new("core", "test", "")
    if !core { return 9 }
    let core_loaded = Docs:load_package(core, ".", "")
    if !core_loaded { Docs:destroy(core); return 10 }
    let core_count = DocsExamples:check(core, executable, canonical, directory)
    Docs:destroy(core)
    if core_count <= 0 { printf("[docs-examples] core examples failed or missing\n"); return 11 }
    printf("[docs-examples] core: %ld examples passed\n", core_count)
    let inventory = Docs:read_file("libraries/standard.txt"); if !inventory { return 4 }; defer free(inventory)
    var line = inventory; var total = core_count; var failed = 0
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
            let count = DocsExamples:check(store, executable, canonical, directory)
            Docs:destroy(store)
            if count < 0 { failed -= count }
            if count == 0 { printf("[docs-examples] no executable examples in %s\n", name); return 8 }
            if count > 0 { printf("[docs-examples] %s: %ld examples passed\n", name, count); total += count }
        }
        if !more { break }; line = &line[end + 1]
    }
    if failed { printf("[docs-examples] %ld examples failed\n", failed); return 7 }
    printf("[docs-examples] %ld examples passed in isolated runtimes\n", total)
    return 0
}
