# vulkan.rli

A source-defined Vulkan subset for the first RecurLoop graphics example. It
contains the native ABI records and calls needed for instance/device selection,
surface/swapchain/image views, a render pass and graphics pipeline, command
recording, synchronization, presentation, and deterministic cleanup.

No Vulkan-specific C++ is added to the RecurLoop host. The binding uses
RecurLoop's native `f32` type directly for Vulkan float fields, including queue
priorities, viewports, rasterization state, multisampling, and blend constants.

Installed with the runtime and loaded using `import vulkan`. Device queue
priority uses the IEEE-754 bits of `1.0f`, preserving the native f32 ABI without
requiring an integer-to-f32 conversion in the source-debug backend.
