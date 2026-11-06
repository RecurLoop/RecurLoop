// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Vulkan" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Vulkan provides typed records, native calls and helpers for a single graphics/presentation queue and a triangle renderer. It is a focused subset, not a promise that every Vulkan feature or rendering architecture is wrapped.

## Resource creation order

1. Create a window system and window when presenting to a display.
2. Create an instance with the required surface extensions.
3. Create a surface and select a compatible physical device/queue family.
4. Create a logical device, swapchain, shader modules and graphics pipeline.
5. Create frame resources, render and present.
6. Finish GPU work and release resources in reverse dependency order.

```recurloop
import vulkan
let check_helpers = fn () -> i64 {
    if Vulkan:clamp_u32(900, 64, 800) != 800 { return 1 }
    if !Vulkan:has_flag(5, 4) { return 2 }
    return 0
}
assert check_helpers() == 0
```

The helpers above need no graphics device. `clamp_u32` requires ordered minimum/maximum bounds; `has_flag` expects a single power-of-two flag.

Use [resource ownership](resources.rl), [swapchains and resize](swapchains.rl), [shader pipelines](pipelines.rl), [frame synchronization](frames.rl) and [native ABI records](native-abi.rl) together. Graphics examples define callable functions so reading or checking the manual does not start a render loop."
    }
]
