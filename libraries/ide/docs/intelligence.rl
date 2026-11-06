// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:intelligence = [
    id = phrase { payload = "intelligence" }
    title = phrase { payload = "Inspect source with the project vocabulary" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`IDE:intelligence_refresh` refreshes the source-inspection runtime from the current project environment. `intelligence_analyze(host, path, source)` inspects a buffer and returns an allocated protocol response or null.

```recurloop
import ide
let inspect_buffer = fn (host:IDE:Host*, path:u8*, source:u8*) -> i64 {
    if !IDE:intelligence_refresh(host) { return 0 }
    let result = IDE:intelligence_analyze(host, path, source)
    if !result { return 0 }
    defer free(result)
    printf(\"%s\", result)
    return 1
}
```

Pass the actual buffer contents, including unsaved changes, and its intended path so project-relative resolution remains meaningful. The response is protocol data; parse it according to its format instead of displaying it as trusted HTML or treating it as source to execute.

## Keep documentation useful in the editor

Concise `.docs` descriptions travel with phrases and support hovers or source inspection. Extended manuals live in each library's `docs` directory and describe usage, ownership and examples. Refresh the project environment when imports or relevant definitions change. Do not invent a separate token grammar merely to render help for the active language."
    }
]
