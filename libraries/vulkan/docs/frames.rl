// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:frames = [
    id = phrase { payload = "frames" }
    title = phrase { payload = "Synchronize one frame and interpret result codes" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`FrameResources` owns a command pool/buffer, image-available semaphore, render-finished semaphore and in-flight fence. `draw_triangle_frame` waits for the preceding frame, acquires an image, records commands, submits work and presents it.

```recurloop
import vulkan
let draw_one_frame = fn (device:Vulkan:Device*, swapchain:Vulkan:Swapchain*, pipeline:Vulkan:Pipeline*) -> i32 {
    let frame = Vulkan:create_frame_resources(device)
    if !frame { return -1 }
    defer frame.destroy(device.handle)
    defer Vulkan:wait_idle(device)
    return Vulkan:draw_triangle_frame(device, swapchain, pipeline, frame)
}
```

The deferred wait runs before frame destruction. This makes the single-call ownership example safe to release; for a continuous renderer keep frame resources and reuse them rather than allocating and waiting idle every frame.

## Results are not booleans

Success is `Result:Success()` (`0`). `OutOfDate` requests resource recreation. `Suboptimal` indicates a usable but imperfect presentation arrangement. Other result codes and the helper's `-1` indicate failure. The wrapper returns an acquisition error early or the final presentation result; it is not a complete event history for every operation.

`record_triangle` returns `1`/`0`, while `wait_idle` returns a Vulkan result code. Keep those conventions separate. A fence, semaphore, command buffer or framebuffer must not be destroyed or reused while queued work still uses it. The provided frame helper models one frame in flight; a multi-frame renderer needs additional per-frame ownership and synchronization."
    }
]
