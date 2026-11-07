// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:pipelines = [
    id = phrase { payload = "pipelines" }
    title = phrase { payload = "Pipelines" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "50" }
    body = phrase {
        payload = "## Create shader modules and a triangle pipeline

Shader modules require valid SPIR-V words. `create_shader_module` takes a `u32*` and a byte count, not a word count. The data must have the required word layout and alignment; arbitrary text or a cast alone does not create valid SPIR-V.

```recurloop
import vulkan
let pipeline_from_spirv = fn (
    device:Vulkan:Device*, swapchain:Vulkan:Swapchain*,
    vertex:u32*, vertex_bytes:u64, fragment:u32*, fragment_bytes:u64
) -> Vulkan:Pipeline* {
    if vertex_bytes % 4 != 0 || fragment_bytes % 4 != 0 { return cast(Vulkan:Pipeline*, 0) }
    let vertex_module = Vulkan:create_shader_module(device.handle, vertex, vertex_bytes)
    if vertex_module == 0 { return cast(Vulkan:Pipeline*, 0) }
    defer Vulkan:destroy_shader_module(device.handle, vertex_module)
    let fragment_module = Vulkan:create_shader_module(device.handle, fragment, fragment_bytes)
    if fragment_module == 0 { return cast(Vulkan:Pipeline*, 0) }
    defer Vulkan:destroy_shader_module(device.handle, fragment_module)
    return Vulkan:create_graphics_pipeline(device.handle, swapchain, vertex_module, fragment_module)
}
```

## Transfer ownership and clean up on failure

The function borrows the device, swapchain and input words. On success the caller owns the returned `Pipeline`. Temporary shader modules can be destroyed after pipeline creation; the pipeline owns its render pass, layout and framebuffers, not these modules.

## Respect the helper pipeline contract

The helper expects shader entry points named `main` and configures the library's triangle renderer. To implement a different rendering model, use the relevant native records/calls and establish your own ownership and synchronization. Do not assume that changing shader words automatically changes vertex input, descriptors or render-pass compatibility."
    }
]
