// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Docs" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Combine concise phrase help with extended RecurLoop documentation objects, search a catalog, edit its content and export portable JSON. Source catalogs build their index automatically. Exported catalogs reuse the index supplied in the file.

```recurloop
import docs
let catalog_example = fn () -> i64 {
    let catalog = Docs:new(\"sample\", \"1.0.0\", \"\")
    if !catalog { return 1 }
    defer Docs:destroy(catalog)
    let page = Docs:add(catalog, \"sample\", \"ownership\", \"Ownership\", \"Guides\", \"Borrowed entries belong to their catalog.\", \"\", \"\")
    if !page { return 2 }
    let found = Docs:search(catalog, \"borrow\", cast(Docs:Entry*, 0))
    if !found { return 3 }
    let text = Docs:as_text(found)
    if !text { return 4 }
    defer free(text)
    return strstr(text, \"Borrowed\") == cast(u8*, 0)
}
assert catalog_example() == 0
```

## Ownership at a glance

| Value | Lifetime / release |
| --- | --- |
| `Docs:Store*` from `new`, `load`, `from_context` | owned; `Docs:destroy` |
| `Docs:Entry*` from `add`, `find`, `search` | borrowed from its store |
| strings from `as_text`, `as_json` | owned; `free` |
| objects persisted with `save_directory` | authored `.rl`, no authored index |

See [authoring](authoring.rl), [indexed search](search.rl), [JSON and merge](portable-json.rl), [editing](editing.rl) and [CLI usage](cli.rl). Do not destroy a catalog while a borrowed entry is still in use."
    }
]
