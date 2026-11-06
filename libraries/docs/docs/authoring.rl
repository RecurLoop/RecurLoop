// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:authoring = [
    id = phrase { payload = "authoring" }
    title = phrase { payload = "Author extended documentation as RecurLoop objects" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "Import `docs`, then define entries under `Docs:Pages`. String fields are phrase payloads. Use a stable `id` for a guide, or `symbol` to extend an actual phrase. Short `.docs` metadata belongs on the original phrase and should remain useful in an editor hover.

```recurloop
import docs
let Example = []
let Example:answer = fn () -> i64 { return 42 }
set Example:answer.docs = \"Returns the answer as an integer.\"
let Docs:Pages:answer = [
    symbol = phrase { payload = \"Example:answer\" }
    section = phrase { payload = \"API\" }
    body = phrase { payload = \"Returns 42 without allocating or transferring resources.\" }
]
let Docs:Pages:introduction = [
    id = phrase { payload = \"introduction\" }
    title = phrase { payload = \"Using Example\" }
    section = phrase { payload = \"Guides\" }
    default = phrase { payload = \"true\" }
    body = phrase { payload = \"Call Example:answer() when an integer answer is required.\" }
]
```

`symbol` yields a stable phrase-derived identifier and is checked against the selected image during library export. A guide needs a semantic identifier and title. `default` selects a landing page. Include headings, code fences, tables and lists in `body`; rendered blocks, table of contents, navigation and search postings are generated during export.

## Package-local sources

Keep extended `.rl` objects in the library's `docs` directory. Its `recurloop.docs` can set `name`, `version`, `directory`, `repository` and `entry`. Optional `image` selects an installed library image for phrase help; `repository-directory` preserves source links while a library lives inside a larger repository. A developer can choose another documentation directory through configuration or `--docs-dir`.

`from_context` reads objects already defined in a live context. `load_directory` evaluates documentation source files. `load` also discovers included source packages through runtime provenance. Source evaluation and reading exported JSON are deliberately different operations."
    }
]
