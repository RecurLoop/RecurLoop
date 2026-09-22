# Project environment and source-defined IDE

The IDE is not a separate host executable. `ide.rli` contains the standard IDE
runtime and default view; a normal `.rl` launcher imports that image, configures
an `IDE:Config`, optionally replaces functions, and opens the window.

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

The persistent Project cache stores cumulative `.rli` checkpoints under
`<cache>/steps`. The launcher source is a direct cache step. Any files reached
through `include` are dependency-stamped into its manifest, so an included file
change invalidates that step. `engine import` loads an already compiled `.rli`
image and its image dependencies normally.

Included files also have graph-fragment checkpoints under `<cache>/fragments`.
After a dependency change, the cache restores the unchanged prefix of the
include graph and rebuilds from the first affected fragment. The Project reports
the canonical dependency set to the IDE watcher; files outside that set do not
trigger hot reload.

## Reload

`app.reload("hot")` recursively watches the configured watch tree with inotify,
skipping `.git`, `build`, `.cache`, and `node_modules`. Stable write, rename and
delete events schedule a rebuild only when their canonical path belongs to the
active source dependency graph. Rebuilds start from the immutable `project.rli`
baseline plus the longest valid cache path.

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
