// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:reload = [
    id = phrase { payload = "reload" }
    title = phrase { payload = "Reload modes and persistent application state" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`Config:reload` accepts `hot`, `manual` or `off`. Hot mode observes source changes. Manual mode exposes an explicit reload action. Off mode leaves the initial view in place. Query the active mode through `view_reload_mode` rather than inferring it from a widget.

```recurloop
import ide
let request_manual_reload = fn (host:IDE:Host*) -> void {
    if IDE:view_reload_mode(host) == IDE:Reload:Manual() {
        IDE:manual_reload(host)
    }
}
```

## Replacement is a lifecycle transaction

The runtime builds a candidate before selecting it as visible. It keeps the existing view when construction fails. Once a replacement is committed, the previous widget subtree is destroyed and its lifecycle cleanup runs.

Keep editor buffers, terminal models and other persistent runtime state outside short-lived widget userdata when they must survive replacement. Keep generation-specific signal callbacks, timers and widget pointers with that generation. Cancel sources before releasing the data they reference.

Do not retain pointers into retired code or widgets in a longer-lived callback. A successful native compilation is not sufficient if a candidate cannot attach a complete view. Avoid making externally visible side effects part of a constructor that may be discarded."
    }
]
