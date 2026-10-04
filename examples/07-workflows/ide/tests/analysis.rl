// Headless integration assertions, executed by run-analysis-tests.py after the
// IDE definitions have loaded. No GTK widgets or display server are required.
extern calloc(count:u64, bytes:u64) -> u8* abi sysv-amd64
extern strncmp(left:u8*, right:u8*, bytes:u64) -> i32 abi sysv-amd64

let IDE:Analysis:Test = phrase { dictionary = true }

let IDE:Analysis:Test:position = fn (source:u8*, text:u8*) -> u64 {
    var at:u64 = 0
    let bytes = strlen(text)
    while source[at] != 0 {
        if strncmp(&source[at], text, bytes) == 0 { return cast(u64, IDE:App:find_byte_to_char(source, at)) }
        at += 1
    }
    return strlen(source)
}

let IDE:Analysis:Test:location_count = fn (response:u8*) -> u64 {
    var at:i64 = 0
    var count:u64 = 0
    while response[at] != 0 {
        if response[at] == 76 && response[at + 1] == 9 { count += 1 }
        at = IDE:App:find_byte(response, at, 10); if response[at] == 10 { at += 1 }
    }
    return count
}

let IDE:Analysis:Test:descending = fn (response:u8*) -> i64 {
    var at:i64 = 0
    var previous:i64 = 9223372036854775807
    while response[at] != 0 {
        let end = IDE:App:find_byte(response, at, 10)
        if response[at] == 76 && response[at + 1] == 9 {
            let f1 = IDE:App:find_byte(response, at + 2, 9)
            let f2 = IDE:App:find_byte(response, f1 + 1, 9)
            let start = IDE:App:parse_decimal(response, f1 + 1, f2)
            if start >= previous { return 0 }
            previous = start
        }
        at = end; if response[at] == 10 { at += 1 }
    }
    return 1
}

let IDE:Analysis:Test:run = fn () -> i64 {
    let root = getenv("RECURLOOP_ANALYSIS_TEST_ROOT")
    let socket = getenv("RECURLOOP_ANALYSIS_TEST_SOCKET")
    let program = getenv("RECURLOOP_ANALYSIS_TEST_PROGRAM")
    let main_path = IDE:join(root, "main.rl")
    let definitions_path = IDE:join(root, "definitions.rl")
    let calls_path = IDE:join(root, "calls.rl")
    let definitions = IDE:read_file(definitions_path)
    let calls = IDE:read_file(calls_path)
    if !definitions || !calls { return 1 }
    let runner = IDE:Runner:allocate(program, root, main_path)
    runner.socket_path = IDE:copy(socket)
    let host = cast(IDE:Host*, calloc(1, sizeof(IDE:Host)))
    let state = cast(IDE:App:State*, calloc(1, sizeof(IDE:App:State)))
    host.root = root; host.runner = runner; state.host = host
    let paths = LanguageKit:Text:new()
    paths.append(definitions_path); paths.append("\n"); paths.append(calls_path); paths.append("\n")
    host.watch_sources = paths.data

    let definition = IDE:Analysis:query(state, "definition", calls_path, calls,
        IDE:Analysis:Test:position(calls, "add(cast"), "")
    if !definition || !IDE:text_contains(definition, "L\t") { printf("definition: %s\n", definition); return 2 }
    if !IDE:text_contains(definition, "\t2\t616464") { printf("definition role: %s\n", definition); return 3 }
    free(definition)

    let references = IDE:Analysis:query(state, "references", definitions_path, definitions,
        IDE:Analysis:Test:position(definitions, "add ="), "")
    if !references || !IDE:text_contains(references, "\t3\t616464") { printf("references: %s\n", references); return 4 }
    free(references)

    let rename = IDE:Analysis:query(state, "rename", definitions_path, definitions,
        IDE:Analysis:Test:position(definitions, "add ="), "sum")
    if !rename || IDE:text_contains(rename, "E\t") || !IDE:text_contains(rename, "\t3\t616464") { printf("rename: %s\n", rename); return 5 }
    free(rename)

    let local = IDE:Analysis:query(state, "definition", definitions_path, definitions,
        IDE:Analysis:Test:position(definitions, "return result") + 7, "")
    if !local || !IDE:text_contains(local, "\t2\t726573756c74") { printf("local definition: %s\n", local); return 6 }
    free(local)

    let local_rename = IDE:Analysis:query(state, "rename", definitions_path, definitions,
        IDE:Analysis:Test:position(definitions, "return result") + 7, "answer")
    if !local_rename || IDE:Analysis:Test:location_count(local_rename) != 3 || !IDE:Analysis:Test:descending(local_rename) {
        printf("local rename: %s\n", local_rename); return 17
    }
    free(local_rename)
    let shadow = IDE:Analysis:query(state, "references", definitions_path, definitions,
        IDE:Analysis:Test:position(definitions, "ignored:i64 = result") + 14, "")
    if !shadow || IDE:Analysis:Test:location_count(shadow) != 2 { printf("shadow: %s\n", shadow); return 18 }
    free(shadow)

    let type = IDE:Analysis:query(state, "type-definition", definitions_path, definitions,
        IDE:Analysis:Test:position(definitions, "copy:Box"), "")
    if !type || !IDE:text_contains(type, "\t2\t426f78") { printf("type definition: %s\n", type); return 7 }
    free(type)

    let incoming = IDE:Analysis:query(state, "incoming-calls", definitions_path, definitions,
        IDE:Analysis:Test:position(definitions, "add ="), "")
    if !incoming || !IDE:text_contains(incoming, "\t3\t616464") { printf("incoming: %s\n", incoming); return 8 }
    free(incoming)

    let outgoing = IDE:Analysis:query(state, "outgoing-calls", calls_path, calls,
        IDE:Analysis:Test:position(calls, "caller ="), "")
    if !outgoing || !IDE:text_contains(outgoing, "\t3\t616464") { printf("outgoing: %s\n", outgoing); return 9 }
    free(outgoing)

    let completion = IDE:Analysis:query(state, "completion", calls_path, calls,
        IDE:Analysis:Test:position(calls, "add(cast") + 2, "")
    if !completion || !IDE:text_contains(completion, "\t616464\t616464\t") { printf("completion: %s\n", completion); return 10 }
    free(completion)

    let signature = IDE:Analysis:query(state, "signature", calls_path, calls,
        IDE:Analysis:Test:position(calls, "41)") + 1, "")
    if !signature || !IDE:text_contains(signature, "G\t") { printf("signature: %s\n", signature); return 11 }
    free(signature)

    let symbols = IDE:Analysis:query(state, "workspace-symbols", calls_path, calls, 0, "CALLER")
    if !symbols || !IDE:text_contains(symbols, "\t2\t63616c6c6572") { printf("symbols: %s\n", symbols); return 12 }
    free(symbols)

    let implementations = IDE:Analysis:query(state, "implementations", definitions_path, definitions,
        IDE:Analysis:Test:position(definitions, "base ="), "")
    if !implementations || !IDE:text_contains(implementations, "\t2\t64657269766564") { printf("implementations: %s\n", implementations); return 13 }
    free(implementations)

    // UTF-8 character positions are independent of byte offsets.
    if LanguageKit:Analysis:byte_offset("ąb", 1) != 2 { return 14 }
    if LanguageKit:Analysis:byte_offset("ąb", 2) != 3 { return 15 }

    // An unsaved erroneous buffer can never propose a workspace rename.
    let broken = LanguageKit:Text:new()
    broken.append(definitions); broken.append("undefined_analysis_test_phrase\n")
    let invalid = IDE:Analysis:query(state, "rename", definitions_path, broken.data,
        IDE:Analysis:Test:position(definitions, "add ="), "sum")
    if !invalid || !IDE:text_contains(invalid, "E\t") { return 16 }
    free(invalid); broken.destroy()

    LanguageKit:Analysis:destroy(cast(LanguageKit:Analysis:Index*, state.intelligence_index))
    IDE:free_terminals(host)
    paths.destroy()
    free(cast(u8*, state)); free(cast(u8*, host))
    free(definitions); free(calls); free(definitions_path); free(calls_path); free(main_path)
    // This runner borrows the test server; do not stop it through destroy().
    free(runner.program); free(runner.root); free(runner.application); free(runner.socket_path); free(cast(u8*, runner))
    printf("IDE analysis tests passed\n")
    return 0
}

var IDE:Analysis:Test:status = IDE:Analysis:Test:run()
assert IDE:Analysis:Test:status == 0
