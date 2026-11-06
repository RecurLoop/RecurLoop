// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Docs" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Docs combines concise phrase descriptions with extended documentation objects.

## Extended information

```recurloop
let Docs:Pages:example = [
    symbol = phrase { payload = \"Example:answer\" }
    section = phrase { payload = \"API\" }
    body = phrase { payload = \"Returns an answer without transferring ownership.\" }
]
```

`symbol` associates the explanation with a phrase. Pages without a symbol use their own semantic identifier. Navigation and the search index are generated from the objects.

## Catalogs and indexes

`Docs:load` reads source objects and phrase metadata. `Docs:read_export` reads a portable JSON catalog and its existing index. `Docs:search` uses indexed word prefixes. `Docs:merge` combines catalogs without rebuilding valid indexes.

## Ownership and editing

Catalog entries and search results are borrowed. `Docs:as_text` and `Docs:as_json` return owned strings. `Docs:set_body` invalidates the affected catalog’s index, which is rebuilt on demand. `Docs:save_directory` persists authored objects as RecurLoop source. Destroy a catalog only after its borrowed entries are no longer needed."
    }
]

