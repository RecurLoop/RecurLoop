engine import "build/Release/libraries/ide.rli"

IDE_App:hot_reload_probe = 29

let IDE_App:launch = fn () -> i64 {
    let app = IDE:Config:new()
    if !app { return 1 }

    app.workspace("examples/07-workflows/ide")
    app.source("examples/07-workflows/ide/demo.rl")
    app.cache(".cache/recurloop")
    app.watch(".")
    app.reload("hot") // "hot", "manual", or "off"

    let status = app.open()
    app.destroy()
    return status
}

var IDE_App:launch_status = IDE_App:launch()
