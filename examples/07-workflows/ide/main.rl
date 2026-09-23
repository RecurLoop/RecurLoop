engine import "build/Release/libraries/ide.rli"
include "launcher.rl"

let IDE:Launcher:configure = fn (app:IDE:Config*) -> void {
    app.title("RecurLoop IDE")
    app.size(1360, 860)

    app.workspace("examples/07-workflows/ide")
    app.source("examples/07-workflows/ide/ide.rl")
    app.cache(".cache/recurloop")
    app.watch(".")
    app.reload("manual")
    app.view(IDE:Launcher:lifecycle)
}
let IDE:Launcher:main = fn () -> i64 {
    return IDE:run(IDE:Launcher:configure)
}

var IDE:Launcher:status = IDE:Launcher:main()