// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:events = [
    id = phrase { payload = "events" }
    title = phrase { payload = "Events" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "40" }
    body = phrase {
        payload = "## Connect callbacks and userdata

`Gui:Signal` callbacks receive a borrowed widget and the data pointer supplied at registration. Keep that data alive until all registered users are disconnected or destroyed. The API does not copy arbitrary userdata.

```recurloop
import gui
let connect_button = fn (button:u8*, label:u8*) -> u64 {
    return Gui:on_click(button, fn (widget:u8*, data:u8*) -> void {
        Gui:label_text(data, \"Clicked\")
    }, label)
}
```

## Keep callback data alive

The label must remain alive while the button can emit the callback. `on_activate` handles input activation; `on_text_changed` observes edits; key and mouse event callbacks return nonzero when handled or zero to allow normal processing.

## Timers and idle sources

```recurloop
import gui
let schedule_refresh = fn (label:u8*) -> u32 {
    return Gui:timer(1000, fn (data:u8*) -> i32 {
        Gui:label_text(data, \"Updated\")
        return 1
    }, label)
}
let cancel_refresh = fn (source:u32) -> void { Gui:source_remove(source) }
```

A timer returns nonzero to continue or zero to remove itself. `idle` uses the same callback shape when the loop is idle. Store the source identifier and remove an active source before destroying the state or widgets it references. Removing identifier zero is safe. Do not later remove an already expired identifier as though it still named your source.

## Keep the event loop responsive

Run long operations outside event callbacks and marshal UI updates back through the event loop. A short timer interval does not make blocking work asynchronous."
    }
]
