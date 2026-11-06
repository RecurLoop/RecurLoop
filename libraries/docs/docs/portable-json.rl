// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:portable_json = [
    id = phrase { payload = "portable-json" }
    title = phrase { payload = "Read exported JSON and merge catalogs" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`Docs:export_file` writes a complete v3 bundle with pages, rendered blocks, navigation and the inverted index. `read_export` accepts either a bundle or a collection `index.json`, including its referenced bundles.

```recurloop
import docs
let write_and_read = fn (path:u8*) -> i64 {
    let original = Docs:new(\"sample\", \"1.0.0\", \"\")
    if !original { return 1 }
    defer Docs:destroy(original)
    if !Docs:add(original, \"sample\", \"intro\", \"Introduction\", \"Guides\", \"Catalog roundtrip example.\", \"\", \"\") { return 2 }
    if !Docs:export_file(original, path) { return 3 }
    let restored = Docs:new(\"\", \"\", \"\")
    if !restored { return 4 }
    defer Docs:destroy(restored)
    if !Docs:read_export(restored, path) { return 5 }
    return Docs:find(restored, \"sample\", \"intro\") == cast(Docs:Entry*, 0)
}
// Call with a writable destination chosen by the application.
```

## Merge identities, not filenames

An entry is identified by scope and key. `Docs:merge(destination, source)` copies entries and merges existing postings without taking ownership of the source store. Both stores must still be destroyed by their owners.

Identical entries deduplicate. Conflicting bodies, short descriptions, titles, symbols, sections or versions fail instead of silently overwriting one another. Use deliberately distinct package scopes when combining unrelated catalogs. Keep bundle files and their collection index from the same export revision.

Portable JSON is a generated artifact. Author `.rl` objects, regenerate bundles and serve those results to readers; do not maintain a second manual navigation or term index in the frontend."
    }
]
