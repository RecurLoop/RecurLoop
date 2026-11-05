// Regression checks for portable documentation, executed by the docs-check target.
let DocsTests = []
let DocsTests:run = fn () -> i64 {
    let out = LanguageKit:Text:new()
    defer out.destroy()
    if !Docs:json(out, "quote \" slash \\ line\n tab\t żółw") { return 1 }
    if strcmp(out.data, "\"quote \\\" slash \\\\ line\\n tab\\t żółw\"") != 0 { return 2 }
    let decoded = Docs:decode("c5bcc3b3c58277")
    if !decoded { return 3 }
    let valid = strcmp(decoded, "żółw") == 0
    free(decoded)
    if !valid { return 4 }
    if Docs:decode("0z") { return 5 }
    let trace = Docs:copy("P\t2\t73616d706c65\t706872617365\t4465736372697074696f6e2e\t\t\t\nG\t2\t73616d706c65\t\t636f72652e726c69\t0\nH\t1\t73616d706c65\t77726f6e67\t\t\t4f6c642068656c702e\t\nH\t2\t73616d706c65\t3c783a657870723e\t\t73616d706c652032\t48656c702e\t\nJ\t2\t73616d706c65\t78\t412076616c75652e\t\t\t\n")
    defer free(trace)
    let catalog = Docs:parse_trace(trace)
    if !catalog || catalog.error { return 6 }
    defer Docs:destroy_catalog(catalog)
    let item = catalog.first
    if !item || !Docs:documented(item, "core.rli") || Docs:documented(item, "other.rli") { return 7 }
    if strcmp(item.pattern, "<x:expr>") != 0 || strcmp(item.example, "sample 2") != 0 { return 8 }
    if strcmp(item.arguments.data, "\n- **x** — A value.") != 0 { return 9 }
    let body = Docs:body(item)
    defer free(body)
    if !body || strlen(body) < 50 { return 10 }
    let invalid = Docs:copy("E\t6661696c6564\n")
    let diagnostic = Docs:parse_trace(invalid)
    free(invalid)
    if !diagnostic || diagnostic.error != 1 { return 11 }
    Docs:destroy_catalog(diagnostic)
    printf("[docs-check] JSON escaping, UTF-8, trace versions, provenance, help and diagnostics passed\n")
    return 0
}
