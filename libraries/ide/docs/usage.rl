// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "IDE" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    order = phrase { payload = "10" }
    body = phrase {
        payload = "IDE supplies the stable application runtime for a source-defined editor: a workspace, project execution, view replacement, terminal state and source intelligence. It does not prescribe the layout of editor widgets. Import `ide` and compose the view using `Gui`.

## Configure before opening

```recurloop
import ide
let configure_editor = fn (config:IDE:Config*) -> void {
    config.workspace(\".\")
    config.source(\"editor.rl\")
    config.title(\"My editor\")
    config.size(1200, 800)
    config.reload(\"manual\")
}
```

This example only configures a launcher. Before opening, also set a valid view callback; `workspace`, `source` and `view` are required. `Config:open` blocks in the GUI event loop and returns `0` on success or `1` on setup failure.

Source intelligence uses the active vocabulary and phrase metadata, including `.docs`. Keep calls tied to the appropriate project runtime rather than a second, divergent parser.

Keep persistent runtime state separate from the widget generation that displays it.

## Learning path

1. [Configuration](configuration.rl) — Set the workspace, source and required callbacks.
2. [Views](view-lifecycle.rl) — Construct a candidate view and release its generation data.
3. [Reloading](reload.rl) — Replace a view while keeping application state alive.
4. [Source inspection](intelligence.rl) — Analyze buffers using the active project vocabulary."
    }
]
