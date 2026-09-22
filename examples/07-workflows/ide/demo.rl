engine import "build/Release/libraries/ide.rli"

let IDE:App:configure = fn (app:IDE:Config*) -> void {
    app.title("RecurLoop IDE")
    app.size(1360, 860)

    app.workspace("examples/07-workflows/ide")
    app.source("examples/07-workflows/ide/demo.rl")
    app.cache(".cache/recurloop")
    app.watch(".")
    app.reload("hot") // "hot", "manual", or "off"
}

let IDE:App:main = fn () -> i64 {
    return IDE:run(IDE:App:configure)
}

var IDE:App:status = IDE:App:main()
