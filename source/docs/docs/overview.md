# Documentation and package authoring

Public documentation has two layers: a short `.docs` description beside a definition, and longer Markdown pages in a dedicated public directory. The `docs` library combines them for terminal searches and portable exports.

Implementation notes are separate. In the RecurLoop repository, `source/docs` contains public usage and package manuals; the root `docs` directory contains implementation documentation and is not indexed by the public exporter or CLI.

## Short code help

```recurloop
let Example = []
let Example:answer = fn () -> i64 { return 42 }
set Example:answer.docs = "Returns the answer. No ownership transfer."
```

Keep code help to the effect, notable return values and ownership. Rich tutorials, rationale and larger examples belong in public Markdown pages. Code help is read through semantic runtime facts, so includes, aliases and library images use the language's own interpretation.

## Package layout

A source package can use `docs/` by default. To choose another public directory, create `recurloop.docs` at its repository root:

```text
name=example-package
version=1.0.0
directory=manual
repository=https://github.com/example/example-package
entry=recurloop.project.rl
```

Paths are relative to that repository. `entry` is the source entry used for semantic help. It defaults to `recurloop.project.rl`, then `library.rl` when present. A documentation-only repository does not need an entry. A configured directory replaces the default; private folders are not also scanned.

A source package included by another project is discovered from the runtime's source provenance. Its own `recurloop.docs` is used, even if the package lives in another repository outside the project directory. Packages already compiled into `.rli` expose their short code help; install or supply their public source manuals separately when rich documentation is needed.

## Ordering and sections

Without an index, Markdown files are discovered recursively and sorted by path. A public directory can contain `index.tsv` to control the complete navigation. Columns are separated by a tab:

```text
# id    title    section    file    original_source
introduction    Introduction    Getting started    introduction.md
usage    Usage    Guides    usage.md
```

The first listed page is the default. Section order and page order follow the index. The optional fifth column is an old/source path alias used to resolve relative documentation links. IDs must contain only ASCII letters, digits, `_` or `-`, with at most 120 characters. Duplicate IDs fail instead of silently replacing pages.

## Library API

Import the image before using the API:

```bash
recurloop --library docs program.rl
```

```recurloop
let DocumentationExample = []
let DocumentationExample:run = fn () -> i64 {
    let catalog = Docs:load(".", "")
    assert catalog != cast(Docs:Store*, 0)
    assert catalog.error == 0
    let match = Docs:search(catalog, "ownership", cast(Docs:Entry*, 0))
    while match {
        let text = Docs:as_text(match)
        print text
        free(text)
        match = Docs:search(catalog, "ownership", match)
    }
    assert Docs:export_file(catalog, "documentation.json") == 1
    Docs:destroy(catalog)
    return 0
}
assert DocumentationExample:run() == 0
```

`Docs:Entry` provides structured fields including `id`, `title`, `section`, `scope`, `body`, `inline_docs` and source paths. Entries and search results are borrowed from the catalog. `Docs:as_text` and `Docs:as_json` return owned strings; free them. `Docs:destroy` releases the catalog and its entries.

`Docs:add` copies page strings into the catalog. `Docs:set_body` edits an entry in memory. `Docs:save` writes its Markdown body to a chosen file. `Docs:save_directory` persists one package’s pages and ordered `index.tsv`, including newly added pages. `Docs:set_inline` updates short help in the catalog; change a source declaration’s `.docs` metadata directly to persist code help. `Docs:export_file` serializes the complete current catalog; edits are reflected in blocks, TOC, navigation and search.

## CLI for people and tools

```bash
recurloop --docs search "record" --json --limit 20
recurloop --docs show "Example:answer" --json
recurloop --docs list --json
recurloop --docs export documentation.json --no-standard
recurloop --docs search "routing" --root ./package --docs-dir manual
```

`--json` returns a machine-readable object. Searches report `total`, `shown` and `results`; `--limit` is from 1 to 1000. `show` accepts an exact phrase title, a page ID, or `scope/id`. Portable JSON qualifies IDs by package, allowing combined exports to contain several `overview` pages. Use `--` before a query starting with a dash. By default CLI queries also include installed public standard-library documentation. `--no-standard` restricts the catalog to the selected repository and its source dependencies. `--docs-dir` overrides the selected repository only; dependencies keep their own configuration. `RECURLOOP_DOCS_PATH` can point at an installed public manual collection.

Source entries are evaluated using normal project semantics to obtain authoritative code metadata. Project targets remain deferred. Use a package's normal declarative entry rather than a launcher with application side effects when querying it.

## Portable frontend format

Version 2 JSON contains package metadata, an explicit default page, ordered navigation, full pages with safe block trees, headings and TOC, previous/next links, source links and a full-text search index. Renderers do not infer sections from library names or reconstruct document structure from Markdown.

Supported blocks are headings, paragraphs, fenced code, lists, blockquotes, tables and separators. Inline text supports links, code and bold through a generic safe renderer; raw HTML is displayed as text. Markdown bodies and short code help remain in the export for CLI and other consumers.

The same format is used for engine, standard-library and community-package documentation. A package can publish the exported JSON on a public HTTPS endpoint such as GitHub's raw-content endpoint. The RecurLoop portal fetches approved package documentation in the reader's browser.

## Project targets

In the RecurLoop source repository:

```bash
make docs-check
make docs DOCS_OUTPUT=build/documentation
build/Release/bin/recurloop --project recurloop.project.rl --target docs
```

The exporter is RecurLoop source. Its output includes the site manifest, every public bundle, the portable format schema and an example generated by the same library. C++ implementation documentation is outside the public catalog.
