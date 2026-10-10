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

extern glfwGetKey(window:u8*, key:i32) -> i32 abi sysv-amd64
extern glfwGetTimerValue() -> u64 abi sysv-amd64
extern glfwGetTimerFrequency() -> u64 abi sysv-amd64
extern glfwGetWindowAttrib(window:u8*, attribute:i32) -> i32 abi sysv-amd64

let Window = phrase { docs = "Window and event helpers for Vulkan applications, backed by GLFW. Initialize before creating windows; destroy windows before shutdown." dictionary = true permanent = true }
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

// Public hover documentation travels with the library image.
set Window:initialize.docs = "Initializes GLFW and checks Vulkan support. Returns 1 on success or 0 on failure."
set Window:create_vulkan.docs = "Creates a window without an OpenGL context. Width and height are in screen coordinates; resizable accepts Window:True() or Window:False(). Returns null on failure; release with Window:destroy."
set Window:destroy.docs = "Destroys a window. Accepts null; destroy its Vulkan surface first."
set Window:shutdown.docs = "Terminates GLFW. Call after releasing all windows and their Vulkan surfaces."
set Window:poll.docs = "Processes pending window and input events without waiting. Call regularly in a rendering loop."
set Window:wait.docs = "Waits for an event, then processes pending events. Useful when no frame needs rendering."
set Window:should_close.docs = "Returns 1 when the window's close flag is set, otherwise 0."
set Window:close.docs = "Sets the window's close flag. The caller still owns and must destroy the window."
set Window:required_vulkan_extension_count.docs = "Returns the number of instance extensions required by GLFW. Use with Window:required_vulkan_extensions after initialization."
set Window:required_vulkan_extensions.docs = "Returns GLFW-owned extension names for Vulkan:create_instance. Do not free them; use the accompanying extension count."
set Window:create_vulkan_surface.docs = "Creates a presentation surface for a window and instance. Returns 0 on failure; release with Vulkan:destroy_surface before destroying the window or instance."
set Window:Hint:ClientApi.docs = "GLFW hint selecting the window's client API. Window:NoApi() selects a Vulkan-only window."
set Window:Hint:Resizable.docs = "GLFW hint controlling whether a window can be resized."
set Window:NoApi.docs = "GLFW value for creating a window without a client graphics API."
set Window:True.docs = "GLFW boolean value for enabling a hint or attribute."
set Window:False.docs = "GLFW boolean value for disabling a hint or attribute."
set glfwGetFramebufferSize.docs = "Writes the framebuffer width and height in pixels through the output pointers. These may differ from the window size and become zero when minimized."
set glfwGetKey.docs = "Reads the cached state of a GLFW key code. Process events with Window:poll or Window:wait to refresh input state."
set glfwGetTimerValue.docs = "Returns the raw GLFW timer counter. Divide a counter difference by glfwGetTimerFrequency() to obtain elapsed seconds."
set glfwGetTimerFrequency.docs = "Returns the number of GLFW timer counter ticks per second."
set glfwGetWindowAttrib.docs = "Reads a GLFW window attribute selected by its numeric attribute code."
set glfwGetRequiredInstanceExtensions.docs = "Returns GLFW-owned Vulkan instance extension names and writes their count. Do not free the returned array or strings."
set glfwGetPhysicalDevicePresentationSupport.docs = "Checks whether a physical device's queue family can present through GLFW on this platform."
set glfwCreateWindowSurface.docs = "Creates a Vulkan surface through GLFW, writing its handle to surface. Returns a Vulkan result code; 0 means success."

languagekit_native_end
include "../build/export.rl"
__recurloop_export_library
