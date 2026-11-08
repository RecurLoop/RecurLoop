// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:cli = [
    id = phrase { payload = "cli" }
    title = phrase { payload = "Command line" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "60" }
    body = phrase {
        payload = "## Search and display documentation

The CLI can search live source documentation or read prebuilt JSON without evaluating documentation source. Use `--json` for machine-readable results.

```console
recurloop --docs search \"pipeline ownership\" --json
recurloop --docs show \"Shell:Invocation:stdout\"
```

From a writable directory, export the installed manuals and search the exported
file. These commands create `manual.json` and `combined.json` in that directory:

```console
recurloop --docs export manual.json
recurloop --docs search \"pipeline ownership\" --from manual.json --json
recurloop --docs merge combined.json manual.json manual.json
```

The repeated input demonstrates that identical pages deduplicate. For independent
packages, pass their separately exported JSON files instead.

## Work with your own source package

The following commands require an existing `my-package` source package. Replace
that path with your package directory. The `--docs-dir reference` example also
requires its documentation objects to be in that package's `reference` directory:

```console
recurloop --docs list --root ./my-package --no-standard
recurloop --docs search \"buffer\" --root ./my-package --docs-dir reference
recurloop --docs export package-manual.json --root ./my-package --no-standard
```

## Scope and result selection

`--root` selects a source package. `--docs-dir` overrides its configured public directory. `--no-standard` excludes the standard manuals. Otherwise standard documentation is available alongside project/source-package help. Included source dependencies can contribute their own configured documentation directories. Local authored pages take precedence over installed manuals; standard manuals fill in generated code help, while live inline descriptions remain available. Explicit `merge` commands reject conflicting exported pages.

`--from` reads an exported bundle or collection index and reuses its index. `search` uses word prefixes; `show` accepts a page identifier, a qualified scope/key or an exact phrase name. `--limit` accepts 1–1000 and defaults to 50. JSON search reports total and shown counts, so a client can distinguish no matches from a limited response.

## Keep public help separate from implementation notes

CLI output covers public RecurLoop usage and package APIs. A package's implementation or contributor notes are separate from its public object directory. The browser can render the same exported contract without reconstructing phrase help or inventing its own documentation tree."
    }
]
