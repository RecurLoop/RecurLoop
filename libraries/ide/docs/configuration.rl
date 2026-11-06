// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:configuration = [
    id = phrase { payload = "configuration" }
    title = phrase { payload = "Launcher configuration and path lifetimes" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`Config:new` creates an owned configuration. String setters copy their arguments and return the same configuration for chaining. Destroy it after `open` has returned, or use `IDE:run`, which creates, configures, opens and releases one for you.

```recurloop
import ide
let make_configuration = fn (workspace:u8*, source:u8*) -> IDE:Config* {
    let config = IDE:Config:new()
    if !config { return cast(IDE:Config*, 0) }
    config.workspace(workspace)
    config.source(source)
    config.cache(\".cache/editor\")
    config.watch(\".\")
    config.title(\"Workspace editor\")
    config.size(1200, 800)
    config.maximized(0)
    config.reload(\"hot\")
    return config
}
```

The caller owns the returned pointer and must eventually call `destroy`. Set `view` before opening. `size` ignores unsupported dimensions; unknown reload mode strings leave the old mode unchanged. Defaults include hot reload and a 1360×860 window.

Relative cache and watch paths resolve against the workspace. A watch path must identify an existing directory. Choose a cache outside generated source watched as application input to avoid unnecessary reload work. A source path identifies the application source that can reproduce its configuration and view; it is not a documentation file or an arbitrary widget label."
    }
]
