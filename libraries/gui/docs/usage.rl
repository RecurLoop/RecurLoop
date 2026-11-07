// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Gui" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    order = phrase { payload = "10" }
    body = phrase {
        payload = "Compose desktop interfaces from windows, containers, controls and callbacks. `Gui` exposes the application-facing API; its current GTK3 backend requires a graphical session. Importing definitions does not open a window.

## A complete window lifecycle

```recurloop
import gui
let open_window = fn () -> i64 {
    if !Gui:initialize() { return 1 }
    let window = Gui:window(\"Example\", 640, 400)
    if !window { return 2 }
    Gui:add(window, Gui:label(\"Hello from RecurLoop\"))
    Gui:on_destroy(window, fn (widget:u8*, data:u8*) -> void { Gui:quit() }, cast(u8*, 0))
    Gui:show(window)
    Gui:run()
    return 0
}
// Call open_window() in a graphical session; closing the window ends the loop.
```

The root window owns attached descendants. Its destruction releases them. `quit` stops the event loop; it does not itself destroy every widget. If your own code stops the loop while the window is still alive, destroy that root explicitly.

GUI callbacks run on the event-loop thread; keep blocking work out of them.

## Learning path

1. [Layouts](layout.rl) — Compose containers before adding interactive behavior.
2. [Text and inputs](text-inputs.rl) — Read and update text with explicit ownership.
3. [Events](events.rl) — Connect callbacks and manage timer lifetimes.
4. [Shortcuts and dialogs](shortcuts.rl) — Reuse actions for keyboard shortcuts and dialogs.
5. [Trees](trees.rl) — Represent rows, selection and lazy directory contents."
    }
]
