# Project environment and source-defined IDE

The IDE is not a separate host executable. `ide.rli` contains the stable IDE
runtime; a normal `.rl` launcher imports that image, configures an `IDE:Config`,
can register a source-defined view lifecycle, and opens the window.

A typical launcher is:

```rl
engine import "build/Release/libraries/ide.rli"

let app = IDE:Config:new()
app.workspace("my-project")
app.source("tools/ide.rl")
app.cache(".cache/recurloop")
app.watch(".")
app.reload("hot")
app.open()
app.destroy()
```

The workspace is the filesystem root shown by Explorer and exposed to project
code through `RECURLOOP_PROJECT_ROOT`. `project.rl` remains optional and, when
present, is loaded after the IDE launcher into the persistent Project runtime.
There is no hidden `.recurloop` IDE configuration directory.

## Cache

The cache directory is selected by `app.cache(...)`; relative paths are resolved
inside the workspace. The default is `.cache/recurloop`.

Project source is cached as linked engine images under `<cache>/modules`. The
mapping is intentionally file-shaped: `main.rl`, `editor.rl`, and `view.rl`
produce their own `.rli`/manifest pairs instead of cumulative step snapshots.
A linked module stores only its own semantic delta; dependency phrases are
resolved by stable lexical references after dependency images have loaded.

When one source file changes, its module and every dependent source module are
rebuilt, while unchanged dependencies are loaded directly from their `.rli`
images. There is no separate per-include fragment cache and no increasing full
snapshot written after every include. Imported library images continue to use
the same EngineImage dependency metadata, so project modules and normal
libraries share one dependency model.

A file that performs an in-place mutation of older semantic state, or emits
state before a later dependency, is conservatively cached as one self-contained
image. This preserves source ordering without splitting that file into hidden
cache fragments; ordinary declaration-only IDE modules stay linked and small.

The Project reports the canonical `.rl` dependency set to the IDE watcher, so
files outside that set do not trigger hot reload.

## Source intelligence

The editor asks the persistent Project runtime to inspect its unsaved buffer.
The runtime reconstructs the source's entry environment in a separate context
and rolls back the analysis afterwards. Inspection preserves both the current
client session and the published Project generation.

Phrase metadata fields `kind`, `color`, and `docs` drive highlighting and hover
and follow normal prototype inheritance. Diagnostics come from source processing.
The generic `:trace` transport additionally exports phrase matches, dictionary
entries and compiler signatures; it has no navigation/refactoring operations.

The example's `examples/07-workflows/ide/analysis.rl` implements its own workspace
index, syntax classifiers, local scopes, completion and navigation/refactoring
queries. This index is view-local working memory, excluded from core and project
images. The standard surface-syntax policy can be changed in `.rl` without
modifying the host or rebuilding `ide.rli`.

## Reload

`app.reload("hot")` recursively watches the configured watch tree with inotify,
skipping `.git`, `build`, `.cache`, and `node_modules`. Stable write, rename and
delete events schedule a rebuild only when their canonical path belongs to the
active source dependency graph. Rebuilds start from the immutable `project.rli`
baseline and restore unchanged source modules through their linked `.rli` graph.

`app.reload("manual")` records source changes but does not rebuild automatically;
a compact reload button is shown in the editor toolbar. `app.reload("off")`
disables the watcher.

A successful hot/manual reload links a new lifecycle module, publishes the new
Project generation, and swaps the view. Already-open IDE terminal sessions are
left untouched so their variables and execution context remain stable. A terminal
attaches to the current published Project only when the user explicitly runs
`:refresh`.

## Customization

`ide.rli` contains only the stable IDE runtime. The concrete application source
lives under `examples/07-workflows/ide/`: `main.rl` includes the project-local
explorer, editor, terminal and layout files and registers one lifecycle with
`app.view(...)`. Those included files are dependency-stamped by the project
cache, so changing a control or replacing the complete composition is a normal
hot reload and does not require rebuilding `ide.rli`.

Workspace mutation and directory enumeration stay behind the `IDE:*` runtime
API. In particular the source-defined explorer does not depend on native
`dirent` layout, which keeps the view boundary suitable for platform-specific
filesystem backends.
