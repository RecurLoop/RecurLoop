// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:swapchains = [
    id = phrase { payload = "swapchains" }
    title = phrase { payload = "Swapchains" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "40" }
    body = phrase {
        payload = "## Choose a surface extent

`create_swapchain(device, surface, width, height)` creates a FIFO presentation swapchain with image handles and views. The actual `width` and `height` in its result reflect supported surface capabilities and can differ from the requested size.

```recurloop
import window
let swapchain_for_window = fn (device:Vulkan:Device*, surface:u64, window:u8*) -> Vulkan:Swapchain* {
    var width:i32 = 0
    var height:i32 = 0
    glfwGetFramebufferSize(window, &width, &height)
    if width <= 0 || height <= 0 { return cast(Vulkan:Swapchain*, 0) }
    return Vulkan:create_swapchain(device, surface, cast(u32, width), cast(u32, height))
}
```

Here null can mean a minimized window as well as creation failure. The application should distinguish those conditions before deciding to wait, retry or report an error. The caller owns a successful result and releases it with `swapchain.destroy(device.handle)`.

## Handle presentation changes

`Result:OutOfDate()` means the current swapchain no longer fits the surface. Stop rendering against it and recreate dependent resources. `Result:Suboptimal()` permits presentation but signals that recreation may be appropriate. A framebuffer-size change is another useful trigger.

## Retire dependent GPU resources

Wait for outstanding GPU work before replacement. Destroy framebuffers and pipelines that depend on the old views before destroying the old swapchain, then rebuild them for the new format and extent. Zero pixel dimensions while minimized are a reason to wait for events, not to spin creating invalid resources."
    }
]
