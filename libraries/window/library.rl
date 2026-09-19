// =============================================================================
// RecurLoop window library - thin GLFW binding for Vulkan applications.
// Everything here is source-defined RecurLoop; GLFW is the only native window
// dependency.
// =============================================================================

languagekit_native_begin

link shared "c"
link shared "glfw"

extern glfwInit() -> i32 abi sysv-amd64
extern glfwTerminate() -> void abi sysv-amd64
extern glfwVulkanSupported() -> i32 abi sysv-amd64
extern glfwWindowHint(hint:i32, value:i32) -> void abi sysv-amd64
extern glfwCreateWindow(width:i32, height:i32, title:u8*, monitor:u8*, share:u8*) -> u8* abi sysv-amd64
extern glfwDestroyWindow(window:u8*) -> void abi sysv-amd64
extern glfwWindowShouldClose(window:u8*) -> i32 abi sysv-amd64
extern glfwSetWindowShouldClose(window:u8*, value:i32) -> void abi sysv-amd64
extern glfwPollEvents() -> void abi sysv-amd64
extern glfwWaitEvents() -> void abi sysv-amd64
extern glfwGetFramebufferSize(window:u8*, width:i32*, height:i32*) -> void abi sysv-amd64
extern glfwGetRequiredInstanceExtensions(count:u32*) -> u8** abi sysv-amd64
extern glfwGetPhysicalDevicePresentationSupport(instance:u8*, physical_device:u8*, queue_family:u32) -> i32 abi sysv-amd64
extern glfwCreateWindowSurface(instance:u8*, window:u8*, allocator:u8*, surface:u64*) -> i32 abi sysv-amd64

let Window = phrase { dictionary = true permanent = true }
let Window:Hint = phrase { dictionary = true permanent = true }

let Window:Hint:ClientApi = fn () -> i32 { return 139265 }
let Window:Hint:Resizable = fn () -> i32 { return 131075 }
let Window:NoApi = fn () -> i32 { return 0 }
let Window:True = fn () -> i32 { return 1 }
let Window:False = fn () -> i32 { return 0 }

let Window:initialize = fn () -> i64 {
    if glfwInit() == 0 { return 0 }
    if glfwVulkanSupported() == 0 {
        glfwTerminate()
        return 0
    }
    return 1
}

let Window:create_vulkan = fn (width:i32, height:i32, title:u8*, resizable:i32) -> u8* {
    glfwWindowHint(Window:Hint:ClientApi(), Window:NoApi())
    glfwWindowHint(Window:Hint:Resizable(), resizable)
    return glfwCreateWindow(width, height, title, cast(u8*, 0), cast(u8*, 0))
}

let Window:destroy = fn (window:u8*) -> void {
    if window { glfwDestroyWindow(window) }
}

let Window:shutdown = fn () -> void { glfwTerminate() }
let Window:poll = fn () -> void { glfwPollEvents() }
let Window:wait = fn () -> void { glfwWaitEvents() }
let Window:should_close = fn (window:u8*) -> i64 { return glfwWindowShouldClose(window) != 0 }
let Window:close = fn (window:u8*) -> void { glfwSetWindowShouldClose(window, 1) }

let Window:required_vulkan_extension_count = fn () -> u32 {
    var count:u32 = 0
    glfwGetRequiredInstanceExtensions(&count)
    return count
}

let Window:required_vulkan_extensions = fn () -> u8** {
    var count:u32 = 0
    return glfwGetRequiredInstanceExtensions(&count)
}

let Window:create_vulkan_surface = fn (instance:u8*, window:u8*) -> u64 {
    var surface:u64 = 0
    if glfwCreateWindowSurface(instance, window, cast(u8*, 0), &surface) != 0 { return 0 }
    return surface
}

set glfwInit.serializable = false
set glfwTerminate.serializable = false
set glfwVulkanSupported.serializable = false
set glfwWindowHint.serializable = false
set glfwCreateWindow.serializable = false
set glfwDestroyWindow.serializable = false
set glfwWindowShouldClose.serializable = false
set glfwSetWindowShouldClose.serializable = false
set glfwPollEvents.serializable = false
set glfwWaitEvents.serializable = false
set glfwGetFramebufferSize.serializable = false
set glfwGetRequiredInstanceExtensions.serializable = false
set glfwGetPhysicalDevicePresentationSupport.serializable = false
set glfwCreateWindowSurface.serializable = false

languagekit_native_end
include "../build/export.rl"
__recurloop_export_library
