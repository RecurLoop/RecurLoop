// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:view_lifecycle = [
    id = phrase { payload = "view-lifecycle" }
    title = phrase { payload = "Views" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "30" }
    body = phrase {
        payload = "## Build and release a view generation

The lifecycle callback has shape `(action:i64, host:u8*) -> void`. During action `1`, construct the complete candidate and attach it once with `IDE:view_attach`. During action `2`, release application data. The runtime destroys the widget subtree before releasing that generation's data.

```recurloop
import ide
record ViewState { label:u8* }
let simple_view = fn (action:i64, raw_host:u8*) -> void {
    let host = cast(IDE:Host*, raw_host)
    if action == 1 {
        let state = alloc(ViewState)
        if !state { return }
        let root = Gui:column(8)
        if !root { free(cast(u8*, state)); return }
        state.label = Gui:label(\"Ready\")
        Gui:append(root, state.label, 0, 12)
        if !IDE:view_attach(host, root, cast(u8*, state)) {
            Gui:destroy(root)
            free(cast(u8*, state))
        }
    } else if action == 2 {
        let state = cast(ViewState*, IDE:view_data(host))
        if state { free(cast(u8*, state)) }
    }
}
```

## Attach a complete candidate

`view_attach` requires nonnull content and data and accepts only one attachment in the candidate phase. Failure leaves cleanup with the candidate's code. Successful attachment transfers the root's lifecycle to the runtime. A candidate that never attaches a valid root is rejected.

## Access the correct generation

Use `view_data` instead of reading internal host fields: it selects candidate, active or retiring data according to the lifecycle phase. Code invoked during destruction must not assume the active generation is the one being destroyed. The launcher replay uses action `5` for applying generated configuration; ordinary view construction and destruction remain actions `1` and `2`."
    }
]
