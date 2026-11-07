// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Window" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    order = phrase { payload = "10" }
    body = phrase {
        payload = "Create a GLFW window for Vulkan, process events and obtain the extensions and surface required for presentation. Import `window`; its Vulkan dependency is loaded transitively. A display, GLFW and a usable Vulkan loader/driver are needed when graphics functions run.

## First example

```recurloop
import window
let window_example = fn () -> i64 {
    if !Window:initialize() { return 1 }
    defer Window:shutdown()
    let window = Window:create_vulkan(800, 600, \"RecurLoop\", Window:True())
    if !window { return 2 }
    defer Window:destroy(window)
    while !Window:should_close(window) { Window:wait() }
    return 0
}
// Call window_example() in a graphical session.
```

This creates a window without a graphics context; it does not draw a Vulkan frame. Closing it exits the loop, destroys the window and then shuts GLFW down. `initialize` returns `0` when initialization or the Vulkan-support check fails.

Importing the vocabulary alone does not initialize GLFW or open windows.

## Learning path

1. [Event loop](event-loop.rl) — Choose polling or waiting and handle close requests.
2. [Input and time](input-time.rl) — Read cached input and measure elapsed time.
3. [Vulkan surfaces](surfaces.rl) — Create a surface with correct lifetime and pixel extent."
    }
]
