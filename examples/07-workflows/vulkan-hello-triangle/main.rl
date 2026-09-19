// =============================================================================
// Vulkan hello triangle written in RecurLoop source.
//
// Required .rli libraries: shaders, window, vulkan.
// No graphics-specific C++ host code is used.
// =============================================================================

let Triangle = phrase { dictionary = true permanent = true }

let Triangle:vertex_spirv = fn () -> BitString* {
    return shader spirv vertex {
#version 450
layout(location = 0) out vec3 vColor;

vec2 positions[3] = vec2[](
    vec2( 0.00, -0.65),
    vec2( 0.65,  0.65),
    vec2(-0.65,  0.65)
);
vec3 colors[3] = vec3[](
    vec3(1.00, 0.15, 0.15),
    vec3(0.15, 1.00, 0.15),
    vec3(0.15, 0.35, 1.00)
);

void main() {
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    vColor = colors[gl_VertexIndex];
}
    }
}

let Triangle:fragment_spirv = fn () -> BitString* {
    return shader spirv fragment {
#version 450
layout(location = 0) in vec3 vColor;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(vColor, 1.0);
}
    }
}

let Triangle:run = fn () -> i64 {
    if !Window:initialize() {
        printf("GLFW initialization or Vulkan support check failed\n")
        return 1
    }
    defer Window:shutdown()

    let window = Window:create_vulkan(800, 600, "RecurLoop Vulkan triangle", Window:False())
    if !window {
        printf("glfwCreateWindow failed\n")
        return 2
    }
    defer Window:destroy(window)

    let extension_count = Window:required_vulkan_extension_count()
    let extensions = Window:required_vulkan_extensions()
    if !extensions || extension_count == 0 {
        printf("GLFW returned no Vulkan instance extensions\n")
        return 3
    }

    let instance = Vulkan:create_instance("RecurLoop triangle", extensions, extension_count)
    if !instance {
        printf("vkCreateInstance failed\n")
        return 4
    }
    defer Vulkan:destroy_instance(instance)

    let surface = Window:create_vulkan_surface(instance, window)
    if surface == 0 {
        printf("glfwCreateWindowSurface failed\n")
        return 5
    }
    defer Vulkan:destroy_surface(instance, surface)

    let selection = Vulkan:pick_device(instance, surface)
    if !selection {
        printf("No Vulkan device with a graphics+present queue was found\n")
        return 6
    }
    defer free(cast(u8*, selection))

    let device = Vulkan:create_device(selection)
    if !device {
        printf("vkCreateDevice failed\n")
        return 7
    }
    defer Vulkan:Device:destroy(device)

    let swapchain = Vulkan:create_swapchain(device, surface, 800, 600)
    if !swapchain {
        printf("Vulkan swapchain creation failed\n")
        return 8
    }
    defer Vulkan:Swapchain:destroy(swapchain, device.handle)

    // SPIR-V was compiled while this source was compiled. These pointers refer
    // directly to read-only data embedded in the JIT/native module.
    let vertex = Triangle:vertex_spirv()
    let fragment = Triangle:fragment_spirv()

    let vertex_module = Vulkan:create_shader_module(
        device.handle,
        cast(u32*, Embed:data(vertex)),
        Embed:bytes(vertex)
    )
    if vertex_module == 0 {
        printf("Vertex VkShaderModule creation failed\n")
        return 9
    }
    defer Vulkan:destroy_shader_module(device.handle, vertex_module)

    let fragment_module = Vulkan:create_shader_module(
        device.handle,
        cast(u32*, Embed:data(fragment)),
        Embed:bytes(fragment)
    )
    if fragment_module == 0 {
        printf("Fragment VkShaderModule creation failed\n")
        return 10
    }
    defer Vulkan:destroy_shader_module(device.handle, fragment_module)

    let pipeline = Vulkan:create_graphics_pipeline(device.handle, swapchain, vertex_module, fragment_module)
    if !pipeline {
        printf("Graphics pipeline creation failed\n")
        return 15
    }
    defer Vulkan:Pipeline:destroy(pipeline, device.handle)

    let frame = Vulkan:create_frame_resources(device)
    if !frame {
        printf("Command/synchronization resource creation failed\n")
        return 16
    }
    defer Vulkan:FrameResources:destroy(frame, device.handle)

    printf("Vulkan hello triangle is running. Close the window to exit.\n")
    var running:i64 = 1
    while running && !Window:should_close(window) {
        Window:poll()
        let result = Vulkan:draw_triangle_frame(device, swapchain, pipeline, frame)
        if result == Vulkan:Result:OutOfDate() {
            // The starter example uses a non-resizable window and deliberately
            // keeps swapchain recreation out of the first triangle.
            running = 0
        } else if result != Vulkan:Result:Success() && result != Vulkan:Result:Suboptimal() {
            printf("Vulkan frame failed with VkResult=%lld\n", cast(i64, result))
            running = 0
        }
    }

    Vulkan:wait_idle(device)
    return 0
}

var triangle_result = Triangle:run()
