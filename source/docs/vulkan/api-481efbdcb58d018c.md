Resets and records a command buffer to clear and draw three vertices into the selected swapchain image. The buffer must be idle and image_index valid. Returns 1 on success, 0 on failure.

## Signature

```recurloop
Vulkan:record_triangle(u8*, Vulkan:Pipeline*, Vulkan:Swapchain*, u32) -> i64
```


