// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:resources = [
    id = phrase { payload = "resources" }
    title = phrase { payload = "Create and release the instance/device resource graph" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "Dispatchable handles such as an instance or native device are `u8*`; other Vulkan handles are represented as `u64`. Wrapper records own additional allocations and are released with their corresponding `destroy` functions.

```recurloop
import window
let inspect_device = fn (window:u8*) -> i64 {
    let extensions = Window:required_vulkan_extensions()
    let count = Window:required_vulkan_extension_count()
    if !extensions || count == 0 { return 1 }
    let instance = Vulkan:create_instance(\"Device example\", extensions, count)
    if !instance { return 2 }
    defer Vulkan:destroy_instance(instance)
    let surface = Window:create_vulkan_surface(instance, window)
    if surface == 0 { return 3 }
    defer Vulkan:destroy_surface(instance, surface)
    let selection = Vulkan:pick_device(instance, surface)
    if !selection { return 4 }
    defer free(cast(u8*, selection))
    let device = Vulkan:create_device(selection)
    if !device { return 5 }
    defer device.destroy()
    return 0
}
```

The caller owns an initialized window. The selected physical device and queue family must support graphics and presentation for this surface. `DeviceSelection` is an allocated descriptor, released with `free`; the Vulkan physical device itself is not destroyed by freeing that descriptor.

`Device` owns the logical device and borrows its physical-device identity. Keep the instance alive longer than its devices. Before destroying a device, finish GPU work and release every resource created from it. A null wrapper or zero resource handle indicates creation failure; inspect that result before dereferencing or registering dependent work."
    }
]
