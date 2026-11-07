// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:editing = [
    id = phrase { payload = "editing" }
    title = phrase { payload = "Editing" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "40" }
    body = phrase {
        payload = "## Update body text and short help

`set_body` replaces an entry body and copies its string. `set_inline` updates short help in the catalog; it does not edit a source phrase automatically. Both invalidate the owning index. Modifying fields directly bypasses that behavior and can leave search stale.

```recurloop
import docs
let edit_example = fn () -> i64 {
    let store = Docs:new(\"sample\", \"1.0.0\", \"\")
    if !store { return 1 }
    defer Docs:destroy(store)
    let page = Docs:add(store, \"sample\", \"intro\", \"Introduction\", \"Guides\", \"Initial explanation.\", \"\", \"\")
    if !page { return 2 }
    if !Docs:set_body(page, \"Updated explanation with ownership details.\") { return 3 }
    if !Docs:set_inline(page, \"Explains ownership.\") { return 4 }
    let json = Docs:as_json(store, \"doc:\", \"\")
    if !json { return 5 }
    defer free(json)
    return strstr(json, \"ownership\") == cast(u8*, 0)
}
assert edit_example() == 0
```

## Save source or export rendered data

`save(entry, path)` writes a single `.rl` object. `save_directory(store, root, directory, scope)` writes the scope's objects to `documentation.rl` in that directory. Choose a destination deliberately: it writes the generated authored representation, not a patch into arbitrary existing source files.

`export_file` emits rendered JSON for readers. `as_text` emits readable text. `as_json` returns owned JSON in memory and accepts a link base plus optional revision. Free returned strings, but keep borrowed entries under their store's ownership. Saving source and exporting JSON are separate operations."
    }
]
