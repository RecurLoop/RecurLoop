// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:authoring = [
    id = phrase { payload = "authoring" }
    title = phrase { payload = "Authoring" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "20" }
    body = phrase {
        payload = "## Define concise phrase help and extended objects

Import `docs`, then define entries under `Docs:Pages`. String fields are phrase payloads. Use a stable `id` for a guide, or `symbol` to extend an actual phrase. Short `.docs` metadata belongs on the original phrase and should remain useful in an editor hover.

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
    order = phrase { payload = \"10\" }
    body = phrase { payload = \"Call Example:answer() when an integer answer is required.\" }
]
```

`symbol` yields a stable phrase-derived identifier and is checked against the selected image during library export. A guide needs a semantic identifier and title. `default` selects a landing page. Include headings, code fences, tables and lists in `body`; rendered blocks, table of contents, navigation and search postings are generated during export.

## Define the learning order

Set `order = phrase { payload = \"20\" }` on a chapter to place it after rank 10 and before rank 30. Positive ranks form the reading path; zero or an omitted field uses alphabetical fallback after ordered chapters. The default page always comes first. Keep the chapters of a section together in the sequence.

Use short concept titles, such as Configuration or Views. Put detailed tasks under `##` and `###` headings in `body`; export generates their table of contents. Both source persistence and JSON merges preserve each page's rank, so separate packages can own their own reading paths.

## Export your application's documentation

The [First project](../../../source/docs/core/first-project.rl#author-and-export-documentation)
starter includes a `docs` target, a `recurloop.docs` configuration, authored
manual objects and short API descriptions beside the application functions.
From that project directory, run:

```console
recurloop --target docs
recurloop --docs search \"answer\" --from build/docs/my-application.json
```

Its target calls `Docs:export_package(\".\", \"build/docs/my-application.json\")`
to export only the application's configured package as a v3 bundle. Loading discovers
configured manual objects and documented source definitions; exporting produces
rendered blocks, navigation and a search index. It does not run application
targets or require the runtime's source repository. A website reader can render
the exported data; HTML generation is a separate step.

## Include manual sources for editor analysis

Import `docs` and include the manual's source files outside deferred target
bodies in `recurloop.project.rl`. For example, the application starter begins
with `import docs` and `include \"docs/overview.rl\"`. This supplies the Docs
vocabulary and makes the manual part of the saved processing graph used for
semantic colors, diagnostics and navigation. Add each new manual source through
an include from that graph. Loading documentation objects does not export files
or start the application.

`directory=docs` in `recurloop.docs` selects files for export discovery. It does
not add those files to the editor's processing graph by itself. A manual loaded
only inside a deferred `docs` target is unavailable to ordinary editor analysis
until its source is included in the project graph.

## Package-local sources

Keep extended `.rl` objects in the library's `docs` directory. Its `recurloop.docs` can set `name`, `version`, `directory`, `repository` and `entry`. Optional `image` selects an installed library image for phrase help; `repository-directory` preserves source links while a library lives inside a larger repository. A developer can choose another documentation directory through configuration or `--docs-dir`.

`from_context` reads objects already defined in a live context. `load_directory` evaluates documentation source files. `load` also discovers included source packages through runtime provenance. Source evaluation and reading exported JSON are deliberately different operations."
    }
]
