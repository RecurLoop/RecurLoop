// Behavior tests for live catalogs, editing, block export and source-package discovery.
let DocsTests:catalog = fn () -> i64 {
    let store = Docs:new("sample", "1.0.0", "https://github.com/example/sample")
    if !store { return 1 }; defer Docs:destroy(store)
    let first = Docs:add(store, "sample", "intro", "Introduction", "Start", "# Introduction\n\n## Same heading\n\nText with **bold**.\n\n## Same heading\n\n```recurloop\n    print 42\n```\n\n| Name | Value |\n| --- | --- |\n| one | two |\n\n- first\n- second\n\n> quoted\n\n---\n", "docs/intro.md", "README.md")
    let second = Docs:add(store, "sample", "usage", "Usage", "Guides", "A special Needle.", "docs/usage.md", "")
    if !first || !second || Docs:find(store, "sample", "intro") != first { return 2 }
    if Docs:search(store, "NEEDLE", cast(Docs:Entry*, 0)) != second || Docs:search(store, "NEEDLE", second) { return 3 }
    if !Docs:set_body(second, "Edited text.") || Docs:search(store, "Needle", cast(Docs:Entry*, 0)) { return 4 }
    let third = Docs:add(store, "dependency", "intro", "Dependency", "Start", "Another package.", "docs/intro.md", "")
    if !third || second.next != third || third.previous != second { return 5 }
    let json = Docs:as_json(store, "doc:", "")
    if !json { return 6 }; defer free(json)
    if !strstr(json, "same-heading-1") || !strstr(json, "\"type\":\"table\"") || !strstr(json, "\"type\":\"list\"") || !strstr(json, "    print 42") || !strstr(json, "\"type\":\"quote\"") { return 7 }
    let first_id = Docs:entry_id(first, "doc:"); let third_id = Docs:entry_id(third, "doc:")
    let unique = strcmp(first_id, third_id) != 0; free(first_id); free(third_id)
    if !unique { return 8 }
    let text = Docs:as_text(second)
    if !text { return 9 }
    let correct = strstr(text, "Edited text.") != cast(u8*, 0); free(text)
    if !correct { return 10 }
    if !Docs:export_file(store, ".cache/docs-export/test-catalog.json") || !Docs:save(second, ".cache/docs-export/test-page.md") { return 11 }
    if !Docs:save_directory(store, ".", ".cache/docs-export/roundtrip", "sample") { return 12 }
    let reloaded = Docs:new("sample", "1.0.0", "")
    if !reloaded { return 13 }; defer Docs:destroy(reloaded)
    if !Docs:load_directory(reloaded, ".", ".cache/docs-export/roundtrip", "sample") { return 14 }
    let edited = Docs:find(reloaded, "sample", "usage")
    if !edited || strcmp(edited.body, "Edited text.") != 0 || !Docs:find(reloaded, "sample", "intro") { return 15 }
    return 0
}
let DocsTests:source_packages = fn () -> i64 {
    let store = Docs:load("tests/fixtures/documentation/project", "")
    if !store { return 1 }; defer Docs:destroy(store)
    if store.error { return 2 }
    let local = Docs:search(store, "root-rich-token", cast(Docs:Entry*, 0))
    let dependency = Docs:search(store, "dependency-rich-token", cast(Docs:Entry*, 0))
    let code = Docs:search(store, "native-code-only-token", cast(Docs:Entry*, 0))
    if !local || !dependency || !code { return 3 }
    if strcmp(code.scope, "external-package") != 0 || strcmp(dependency.scope, "external-package") != 0 { return 4 }
    if Docs:search(store, "CPP_PRIVATE_SENTINEL", cast(Docs:Entry*, 0)) { return 5 }
    let override = Docs:load("tests/fixtures/documentation/project", "alternative")
    if !override { return 6 }; defer Docs:destroy(override)
    if override.error || !Docs:search(override, "override-root-token", cast(Docs:Entry*, 0)) || !Docs:search(override, "dependency-rich-token", cast(Docs:Entry*, 0)) { return 7 }
    if Docs:search(override, "root-rich-token", cast(Docs:Entry*, 0)) { return 8 }
    let executable = Docs:executable(); defer free(executable)
    let command = spawn "{executable}" --docs search dependency-rich-token --root tests/fixtures/documentation/project --no-standard --json
    if !command { return 9 }; defer command.destroy()
    if command.exit_code() != 0 || !strstr(command.stdout(), "dependency-rich-token") || !strstr(command.stdout(), "\"total\":1") { return 10 }
    if !Docs:export_file(store, ".cache/docs-export/test-package.json") { return 11 }
    return 0
}
let DocsTests:cli_catalogs = fn () -> i64 {
    let store = Docs:load("tests/fixtures/documentation/code-only", "")
    if !store { return 1 }; defer Docs:destroy(store)
    if store.error || !Docs:search(store, "code-only-help-token", cast(Docs:Entry*, 0)) { return 2 }
    let executable = Docs:executable(); defer free(executable)
    let api = spawn "{executable}" --docs show Docs:export_file --json
    if !api { return 3 }; defer api.destroy()
    if api.exit_code() != 0 || !strstr(api.stdout(), "\"scope\":\"docs\"") { return 4 }
    let guard = Shell:cwd_enter("tests/fixtures/documentation/project/alternative")
    if !guard { return 5 }; defer Shell:cwd_leave(guard)
    let nested = spawn "{executable}" --docs search root-rich-token --no-standard --json
    if !nested { return 6 }; defer nested.destroy()
    if nested.exit_code() != 0 || !strstr(nested.stdout(), "root-rich-token") { return 7 }
    return 0
}
let DocsTests:all = fn () -> i64 {
    let directory_status = run mkdir -p .cache/docs-export
    if directory_status != 0 { return 1 }
    let old = DocsTests:run()
    if old != 0 { printf("[docs-check] trace test failed: %ld\n", old); return old }
    let catalog = DocsTests:catalog()
    if catalog != 0 { printf("[docs-check] catalog test failed: %ld\n", catalog); return catalog }
    let packages = DocsTests:source_packages()
    if packages != 0 { printf("[docs-check] package test failed: %ld\n", packages); return packages }
    let cli = DocsTests:cli_catalogs()
    if cli != 0 { printf("[docs-check] CLI catalog test failed: %ld\n", cli); return cli }
    printf("[docs-check] catalog search/edit/export, safe blocks, unique package IDs, source dependencies, custom directories, CLI JSON and private-doc exclusion passed\n")
    return 0
}
