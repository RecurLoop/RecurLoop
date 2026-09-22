engine import "build/Release/libraries/ide.rli"

// The reusable library owns the native window/project runtime. The concrete IDE
// is ordinary project source and every included file participates in the same
// dependency-stamped hot-reload cache.
include "app.rl"
include "editor.rl"
include "explorer.rl"
include "terminal.rl"
include "view.rl"

let IDE:App:configure = fn (app:IDE:Config*) -> void {
    app.title("RecurLoop IDE")
    app.size(1360, 860)

    app.workspace("examples/07-workflows/ide")
    app.source("examples/07-workflows/ide/main.rl")
    app.cache(".cache/recurloop")
    app.watch(".")
    app.reload("hot") // "hot", "manual", or "off"
    app.view(IDE:App:lifecycle)
}

let IDE:App:main = fn () -> i64 {
    return IDE:run(IDE:App:configure)
}

var IDE:App:status = IDE:App:main()
