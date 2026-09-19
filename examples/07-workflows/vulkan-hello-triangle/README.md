# Vulkan hello triangle

This example keeps all graphics integration out of the RecurLoop C++ host.
RecurLoop source talks to three source-defined libraries:

- `window.rli` — thin GLFW C-ABI binding;
- `shaders.rli` — phrase-extensible GLSL compiled to embedded SPIR-V during
  source compilation, plus the RecurLoop-native `Shaders:Spirv:Builder`;
- `vulkan.rli` — the Vulkan 1.0 + `VK_KHR_swapchain` subset required by this
  example.

Install the native shared libraries once. Fedora:

```bash
sudo dnf install glfw-devel vulkan-loader-devel libshaderc-devel
```

Ubuntu 24.04+:

```bash
sudo apt update
sudo apt install libglfw3-dev libvulkan-dev libshaderc-dev
```

Build RecurLoop as usual, then build only the optional graphics libraries:

```bash
make build
make graphics-libraries
```

Run the example:

```bash
build/Release/bin/recurloop \
  --library-path build/Release/libraries \
  --library shaders \
  --library window \
  --library vulkan \
  --file examples/07-workflows/vulkan-hello-triangle/main.rl
```

The first example deliberately uses a non-resizable 800x600 window. It handles
`VK_ERROR_OUT_OF_DATE_KHR` by ending the loop instead of rebuilding the
swapchain. That keeps the initial example focused on the complete
source-defined Vulkan path rather than resize policy.

## Shader path

The triangle uses compile-time shader expressions:

```rl
let vertex = fn () -> BitString* {
    return shader spirv vertex {
        // phrase-extensible GLSL
    }
}
```

The GLSL body is expanded through `Shaders:Source:GLSL`, compiled by shaderc
while the RecurLoop function is being compiled, and emitted as native read-only
data. The render loop only creates `VkShaderModule` from `Embed:data` +
`Embed:bytes`; it does not compile shader source at runtime.

The high-level runtime compiler remains available for dynamic shader use cases:

```text
Shaders:compile_glsl(source, Shaders:Stage:Vertex())
Shaders:compile_hlsl(source, Shaders:Stage:Fragment())
```

Convenience functions are available for vertex and fragment stages. Returned
`Shaders:Binary` owns an aligned/copyable SPIR-V byte buffer and an owned error
message on failure.

HLSL currently uses shaderc/glslang too. Upstream has deprecated HLSL support,
so the library deliberately hides that backend behind `Shaders:compile_hlsl`; a
future DXC/Slang backend can replace it without changing application code.

`Shaders:Spirv:Builder` is the custom RecurLoop part. It does not pretend to be
a full GLSL/HLSL parser: it implements the lower layer a future RecurLoop shader
language can target directly — SPIR-V module header management, result-id
allocation, a growable word buffer, generic instruction encoding, and final
binary ownership. That lets new source-defined shader syntax bypass shaderc
without changing the host.
