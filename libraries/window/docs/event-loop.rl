// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:event_loop = [
    id = phrase { payload = "event-loop" }
    title = phrase { payload = "Event loop" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "20" }
    body = phrase {
        payload = "## Choose polling or waiting

`poll` processes available events immediately. Use it while continuously rendering or doing other bounded work. `wait` sleeps until an event is available; it is suitable for an idle window that does not need to redraw continuously.

```recurloop
import window
let process_until_closed = fn (window:u8*) -> void {
    while !Window:should_close(window) {
        Window:poll()
        // Render one bounded frame here when using a renderer.
    }
}
```

## Pace continuous rendering

The function borrows an initialized window. Without rendering or other pacing this polling loop can busy-spin; choose `wait` for event-driven idle work. Do not block the event-processing thread on unrelated long operations.

## Close is a request, not destruction

`Window:close` sets the close flag. `should_close` reads it. The caller still owns the window and must destroy it after leaving the loop. Destroy dependent Vulkan resources, including the presentation surface, before destroying the window. Shut down the window system only after all windows are released.

`create_vulkan` takes screen-coordinate width and height plus a title and `Window:True()` or `Window:False()` for resizing. A resizable window requires a renderer that handles framebuffer-size changes and swapchain recreation."
    }
]
