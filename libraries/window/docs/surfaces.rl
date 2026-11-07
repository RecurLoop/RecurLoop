// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:surfaces = [
    id = phrase { payload = "surfaces" }
    title = phrase { payload = "Vulkan surfaces" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "40" }
    body = phrase {
        payload = "## Create a Vulkan presentation surface

After initialization, obtain both required extension names and their count. These names belong to GLFW; do not free them. Supply them when creating the Vulkan instance, then create the presentation surface for that instance and window.

```recurloop
import window
let with_surface = fn (window:u8*) -> i64 {
    let names = Window:required_vulkan_extensions()
    let count = Window:required_vulkan_extension_count()
    if !names || count == 0 { return 1 }
    let instance = Vulkan:create_instance(\"Surface example\", names, count)
    if !instance { return 2 }
    defer Vulkan:destroy_instance(instance)
    let surface = Window:create_vulkan_surface(instance, window)
    if surface == 0 { return 3 }
    defer Vulkan:destroy_surface(instance, surface)
    return 0
}
```

## Keep window and surface lifetimes aligned

The caller keeps the initialized window alive throughout the call. A zero surface handle indicates failure. The surface must be released before its instance or window. If you create swapchains, release those before the surface too.

## Framebuffer dimensions can differ from window dimensions

`glfwGetFramebufferSize(window, &width, &height)` writes pixel dimensions. Use them for swapchain extent requests. A high-density display may have more framebuffer pixels than screen-coordinate units. Minimized windows can report zero width or height: wait for events instead of creating a zero-sized swapchain or casting negative values to unsigned sizes."
    }
]
