// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:input_time = [
    id = phrase { payload = "input-time" }
    title = phrase { payload = "Read input state and measure elapsed time" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "GLFW updates cached input while processing events. Poll or wait before relying on `glfwGetKey`. The `key` argument below is a GLFW key code chosen by the application.

```recurloop
import window
let close_when_pressed = fn (window:u8*, key:i32) -> void {
    Window:poll()
    if glfwGetKey(window, key) == 1 { Window:close(window) }
}
let elapsed_seconds = fn (started:u64) -> f64 {
    let frequency = glfwGetTimerFrequency()
    if frequency == 0 { return 0.0 }
    let ticks = glfwGetTimerValue() - started
    return cast(f64, ticks) / cast(f64, frequency)
}
```

Take `started` from `glfwGetTimerValue` after initialization. The frequency is ticks per second, not milliseconds. Subtract counters before converting to floating point; converting a large absolute counter first can lose precision.

The native binding also exposes framebuffer size, window attributes and physical-device presentation support. These are low-level GLFW interfaces: pass the documented native handle and pointer types, keep output storage alive for the call and interpret results using the relevant API's units."
    }
]
