// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Window" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Create a GLFW window for Vulkan, process events and obtain the extensions and surface required for presentation. Import `window`; its Vulkan dependency is loaded transitively. A display, GLFW and a usable Vulkan loader/driver are needed when graphics functions run.

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

Continue with [events](event-loop.rl), [surfaces and framebuffer sizes](surfaces.rl), or [input and timing](input-time.rl). Importing the vocabulary alone does not initialize GLFW or open windows."
    }
]
