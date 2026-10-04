engine import "build/Release/libraries/ide.rli"

// The reusable library owns the native window/project runtime. The concrete IDE
// is ordinary project source and every included file participates in the same
// dependency-stamped hot-reload cache.
include "app.rl"
include "terminal.rl"
include "history.rl"
include "find.rl"
include "debug.rl"
include "editor.rl"
include "analysis.rl"
include "intelligence.rl"
include "explorer.rl"
include "search.rl"
include "view-state.rl"
include "view.rl"

let IDE:App:configure = fn (app:IDE:Config*) -> void {
    app.title("RecurLoop IDE")
    app.size(1360, 860)
    app.workspace("examples/07-workflows/ide")
    app.source("examples/07-workflows/ide/ide.rl")
    app.cache(".cache/recurloop")
    app.watch(".")
    app.reload("hot")
    app.view(IDE:App:lifecycle)
}
