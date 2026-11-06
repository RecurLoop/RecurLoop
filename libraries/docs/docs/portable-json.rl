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

## Independent package indexes

Each exported bundle contains its own pages and inverted index. A collection index combines bundle metadata and search postings; creating it does not require importing every source library into one runtime. Existing postings can be merged without re-tokenizing documentation.

A registry can keep package metadata and a versioned documentation URL, while the package publishes its own bundle. A reader can load that bundle independently, or a publisher can merge selected package exports into a shared catalog. A plain JSON object merge is insufficient: preserve scoped page identities and translate posting references together with their entries.

Copying a new file beside an existing collection does not register it automatically. Include it in the merge input and regenerate the collection index; the index explicitly lists the bundles its reader should load. For two versions with conflicting scope/key identities, choose one version or use separate versioned catalogs.

## Merge identities, not filenames

An entry is identified by scope and key. `Docs:merge(destination, source)` copies entries and merges existing postings without taking ownership of the source store. Both stores must still be destroyed by their owners.

Identical entries deduplicate. Conflicting bodies, short descriptions, titles, symbols, sections or versions fail instead of silently overwriting one another. Use deliberately distinct package scopes when combining unrelated catalogs. Keep bundle files and their collection index from the same export revision.

Portable JSON is a generated artifact. Author `.rl` objects, regenerate bundles and serve those results to readers; do not maintain a second manual navigation or term index in the frontend."
    }
]
