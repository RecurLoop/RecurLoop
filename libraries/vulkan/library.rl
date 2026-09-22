// =============================================================================
// RecurLoop Vulkan library
//
// A deliberately small Vulkan 1.0 + VK_KHR_swapchain binding sufficient for a
// source-only hello-triangle. No Vulkan glue lives in the RecurLoop C++ host.
// =============================================================================

languagekit_native_begin

link shared "c"
link shared "vulkan"

// Instance / device / surface.
extern vkCreateInstance(create_info:u8*, allocator:u8*, instance:u8**) -> i32 abi sysv-amd64
extern vkDestroyInstance(instance:u8*, allocator:u8*) -> void abi sysv-amd64
extern vkEnumeratePhysicalDevices(instance:u8*, count:u32*, devices:u8**) -> i32 abi sysv-amd64
extern vkGetPhysicalDeviceQueueFamilyProperties(device:u8*, count:u32*, properties:u8*) -> void abi sysv-amd64
extern vkGetPhysicalDeviceSurfaceSupportKHR(device:u8*, queue_family:u32, surface:u64, supported:u32*) -> i32 abi sysv-amd64
extern vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device:u8*, surface:u64, capabilities:u8*) -> i32 abi sysv-amd64
extern vkGetPhysicalDeviceSurfaceFormatsKHR(device:u8*, surface:u64, count:u32*, formats:u8*) -> i32 abi sysv-amd64
extern vkCreateDevice(physical_device:u8*, create_info:u8*, allocator:u8*, device:u8**) -> i32 abi sysv-amd64
extern vkDestroyDevice(device:u8*, allocator:u8*) -> void abi sysv-amd64
extern vkGetDeviceQueue(device:u8*, queue_family:u32, queue_index:u32, queue:u8**) -> void abi sysv-amd64
extern vkDestroySurfaceKHR(instance:u8*, surface:u64, allocator:u8*) -> void abi sysv-amd64
extern vkDeviceWaitIdle(device:u8*) -> i32 abi sysv-amd64

// Swapchain / images.
extern vkCreateSwapchainKHR(device:u8*, create_info:u8*, allocator:u8*, swapchain:u64*) -> i32 abi sysv-amd64
extern vkDestroySwapchainKHR(device:u8*, swapchain:u64, allocator:u8*) -> void abi sysv-amd64
extern vkGetSwapchainImagesKHR(device:u8*, swapchain:u64, count:u32*, images:u64*) -> i32 abi sysv-amd64
extern vkAcquireNextImageKHR(device:u8*, swapchain:u64, timeout:u64, semaphore:u64, fence:u64, image_index:u32*) -> i32 abi sysv-amd64
extern vkQueuePresentKHR(queue:u8*, present_info:u8*) -> i32 abi sysv-amd64
extern vkCreateImageView(device:u8*, create_info:u8*, allocator:u8*, view:u64*) -> i32 abi sysv-amd64
extern vkDestroyImageView(device:u8*, view:u64, allocator:u8*) -> void abi sysv-amd64

// Pipeline / render pass.
extern vkCreateShaderModule(device:u8*, create_info:u8*, allocator:u8*, module:u64*) -> i32 abi sysv-amd64
extern vkDestroyShaderModule(device:u8*, module:u64, allocator:u8*) -> void abi sysv-amd64
extern vkCreateRenderPass(device:u8*, create_info:u8*, allocator:u8*, render_pass:u64*) -> i32 abi sysv-amd64
extern vkDestroyRenderPass(device:u8*, render_pass:u64, allocator:u8*) -> void abi sysv-amd64
extern vkCreatePipelineLayout(device:u8*, create_info:u8*, allocator:u8*, layout:u64*) -> i32 abi sysv-amd64
extern vkDestroyPipelineLayout(device:u8*, layout:u64, allocator:u8*) -> void abi sysv-amd64
extern vkCreateGraphicsPipelines(device:u8*, cache:u64, count:u32, create_infos:u8*, allocator:u8*, pipelines:u64*) -> i32 abi sysv-amd64
extern vkDestroyPipeline(device:u8*, pipeline:u64, allocator:u8*) -> void abi sysv-amd64
extern vkCreateFramebuffer(device:u8*, create_info:u8*, allocator:u8*, framebuffer:u64*) -> i32 abi sysv-amd64
extern vkDestroyFramebuffer(device:u8*, framebuffer:u64, allocator:u8*) -> void abi sysv-amd64

// Commands / synchronization.
extern vkCreateCommandPool(device:u8*, create_info:u8*, allocator:u8*, pool:u64*) -> i32 abi sysv-amd64
extern vkDestroyCommandPool(device:u8*, pool:u64, allocator:u8*) -> void abi sysv-amd64
extern vkAllocateCommandBuffers(device:u8*, allocate_info:u8*, buffers:u8**) -> i32 abi sysv-amd64
extern vkResetCommandBuffer(buffer:u8*, flags:u32) -> i32 abi sysv-amd64
extern vkBeginCommandBuffer(buffer:u8*, begin_info:u8*) -> i32 abi sysv-amd64
extern vkEndCommandBuffer(buffer:u8*) -> i32 abi sysv-amd64
extern vkCmdBeginRenderPass(buffer:u8*, begin_info:u8*, contents:i32) -> void abi sysv-amd64
extern vkCmdEndRenderPass(buffer:u8*) -> void abi sysv-amd64
extern vkCmdBindPipeline(buffer:u8*, bind_point:i32, pipeline:u64) -> void abi sysv-amd64
extern vkCmdDraw(buffer:u8*, vertex_count:u32, instance_count:u32, first_vertex:u32, first_instance:u32) -> void abi sysv-amd64
extern vkCreateSemaphore(device:u8*, create_info:u8*, allocator:u8*, semaphore:u64*) -> i32 abi sysv-amd64
extern vkDestroySemaphore(device:u8*, semaphore:u64, allocator:u8*) -> void abi sysv-amd64
extern vkCreateFence(device:u8*, create_info:u8*, allocator:u8*, fence:u64*) -> i32 abi sysv-amd64
extern vkDestroyFence(device:u8*, fence:u64, allocator:u8*) -> void abi sysv-amd64
extern vkWaitForFences(device:u8*, count:u32, fences:u64*, wait_all:u32, timeout:u64) -> i32 abi sysv-amd64
extern vkResetFences(device:u8*, count:u32, fences:u64*) -> i32 abi sysv-amd64
extern vkQueueSubmit(queue:u8*, count:u32, submits:u8*, fence:u64) -> i32 abi sysv-amd64

let Vulkan = phrase { dictionary = true permanent = true }
let Vulkan:StructureType = phrase { dictionary = true permanent = true }
let Vulkan:Result = phrase { dictionary = true permanent = true }

let Vulkan:Result:Success = fn () -> i32 { return 0 }
let Vulkan:Result:Suboptimal = fn () -> i32 { return 1000001003 }
let Vulkan:Result:OutOfDate = fn () -> i32 { return -1000001004 }

let Vulkan:StructureType:ApplicationInfo = fn () -> i32 { return 0 }
let Vulkan:StructureType:InstanceCreateInfo = fn () -> i32 { return 1 }
let Vulkan:StructureType:DeviceQueueCreateInfo = fn () -> i32 { return 2 }
let Vulkan:StructureType:DeviceCreateInfo = fn () -> i32 { return 3 }
let Vulkan:StructureType:SubmitInfo = fn () -> i32 { return 4 }
let Vulkan:StructureType:FenceCreateInfo = fn () -> i32 { return 8 }
let Vulkan:StructureType:SemaphoreCreateInfo = fn () -> i32 { return 9 }
let Vulkan:StructureType:ImageViewCreateInfo = fn () -> i32 { return 15 }
let Vulkan:StructureType:ShaderModuleCreateInfo = fn () -> i32 { return 16 }
let Vulkan:StructureType:PipelineShaderStageCreateInfo = fn () -> i32 { return 18 }
let Vulkan:StructureType:PipelineVertexInputStateCreateInfo = fn () -> i32 { return 19 }
let Vulkan:StructureType:PipelineInputAssemblyStateCreateInfo = fn () -> i32 { return 20 }
let Vulkan:StructureType:PipelineViewportStateCreateInfo = fn () -> i32 { return 22 }
let Vulkan:StructureType:PipelineRasterizationStateCreateInfo = fn () -> i32 { return 23 }
let Vulkan:StructureType:PipelineMultisampleStateCreateInfo = fn () -> i32 { return 24 }
let Vulkan:StructureType:PipelineColorBlendStateCreateInfo = fn () -> i32 { return 26 }
let Vulkan:StructureType:GraphicsPipelineCreateInfo = fn () -> i32 { return 28 }
let Vulkan:StructureType:PipelineLayoutCreateInfo = fn () -> i32 { return 30 }
let Vulkan:StructureType:FramebufferCreateInfo = fn () -> i32 { return 37 }
let Vulkan:StructureType:RenderPassCreateInfo = fn () -> i32 { return 38 }
let Vulkan:StructureType:CommandPoolCreateInfo = fn () -> i32 { return 39 }
let Vulkan:StructureType:CommandBufferAllocateInfo = fn () -> i32 { return 40 }
let Vulkan:StructureType:CommandBufferBeginInfo = fn () -> i32 { return 42 }
let Vulkan:StructureType:RenderPassBeginInfo = fn () -> i32 { return 43 }
let Vulkan:StructureType:SwapchainCreateInfoKHR = fn () -> i32 { return 1000001000 }
let Vulkan:StructureType:PresentInfoKHR = fn () -> i32 { return 1000001001 }

let Vulkan:QueueGraphicsBit = fn () -> u32 { return 1 }
let Vulkan:ImageUsageColorAttachmentBit = fn () -> u32 { return 16 }
let Vulkan:ImageAspectColorBit = fn () -> u32 { return 1 }
let Vulkan:PipelineStageColorAttachmentOutputBit = fn () -> u32 { return 1024 }
let Vulkan:AccessColorAttachmentWriteBit = fn () -> u32 { return 256 }
let Vulkan:FenceSignaledBit = fn () -> u32 { return 1 }
let Vulkan:CommandPoolResetCommandBufferBit = fn () -> u32 { return 2 }
let Vulkan:ColorComponentRGBA = fn () -> u32 { return 15 }
let Vulkan:WholeTimeout = fn () -> u64 { return 9223372036854775807 }

record Vulkan:ApplicationInfo {
    sType:i32
    pNext:u8*
    pApplicationName:u8*
    applicationVersion:u32
    pEngineName:u8*
    engineVersion:u32
    apiVersion:u32
}

record Vulkan:InstanceCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    pApplicationInfo:Vulkan:ApplicationInfo*
    enabledLayerCount:u32
    ppEnabledLayerNames:u8**
    enabledExtensionCount:u32
    ppEnabledExtensionNames:u8**
}

record Vulkan:DeviceQueueCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    queueFamilyIndex:u32
    queueCount:u32
    pQueuePriorities:f32*
}

record Vulkan:DeviceCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    queueCreateInfoCount:u32
    pQueueCreateInfos:Vulkan:DeviceQueueCreateInfo*
    enabledLayerCount:u32
    ppEnabledLayerNames:u8**
    enabledExtensionCount:u32
    ppEnabledExtensionNames:u8**
    pEnabledFeatures:u8*
}

record Vulkan:Extent2D { width:u32 height:u32 }
record Vulkan:Offset2D { x:i32 y:i32 }
record Vulkan:Rect2D { offset:Vulkan:Offset2D extent:Vulkan:Extent2D }
record Vulkan:Extent3D { width:u32 height:u32 depth:u32 }

record Vulkan:QueueFamilyProperties {
    queueFlags:u32
    queueCount:u32
    timestampValidBits:u32
    minImageTransferGranularity:Vulkan:Extent3D
}

record Vulkan:SurfaceCapabilities {
    minImageCount:u32
    maxImageCount:u32
    currentExtent:Vulkan:Extent2D
    minImageExtent:Vulkan:Extent2D
    maxImageExtent:Vulkan:Extent2D
    maxImageArrayLayers:u32
    supportedTransforms:u32
    currentTransform:u32
    supportedCompositeAlpha:u32
    supportedUsageFlags:u32
}

record Vulkan:SurfaceFormat { format:i32 colorSpace:i32 }

record Vulkan:SwapchainCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    surface:u64
    minImageCount:u32
    imageFormat:i32
    imageColorSpace:i32
    imageExtent:Vulkan:Extent2D
    imageArrayLayers:u32
    imageUsage:u32
    imageSharingMode:i32
    queueFamilyIndexCount:u32
    pQueueFamilyIndices:u32*
    preTransform:u32
    compositeAlpha:u32
    presentMode:i32
    clipped:u32
    oldSwapchain:u64
}

record Vulkan:ComponentMapping { r:i32 g:i32 b:i32 a:i32 }
record Vulkan:ImageSubresourceRange { aspectMask:u32 baseMipLevel:u32 levelCount:u32 baseArrayLayer:u32 layerCount:u32 }
record Vulkan:ImageViewCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    image:u64
    viewType:i32
    format:i32
    components:Vulkan:ComponentMapping
    subresourceRange:Vulkan:ImageSubresourceRange
}

record Vulkan:ShaderModuleCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    codeSize:u64
    pCode:u32*
}

record Vulkan:AttachmentDescription {
    flags:u32
    format:i32
    samples:u32
    loadOp:i32
    storeOp:i32
    stencilLoadOp:i32
    stencilStoreOp:i32
    initialLayout:i32
    finalLayout:i32
}
record Vulkan:AttachmentReference { attachment:u32 layout:i32 }
record Vulkan:SubpassDescription {
    flags:u32
    pipelineBindPoint:i32
    inputAttachmentCount:u32
    pInputAttachments:u8*
    colorAttachmentCount:u32
    pColorAttachments:Vulkan:AttachmentReference*
    pResolveAttachments:u8*
    pDepthStencilAttachment:u8*
    preserveAttachmentCount:u32
    pPreserveAttachments:u32*
}
record Vulkan:SubpassDependency {
    srcSubpass:u32
    dstSubpass:u32
    srcStageMask:u32
    dstStageMask:u32
    srcAccessMask:u32
    dstAccessMask:u32
    dependencyFlags:u32
}
record Vulkan:RenderPassCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    attachmentCount:u32
    pAttachments:Vulkan:AttachmentDescription*
    subpassCount:u32
    pSubpasses:Vulkan:SubpassDescription*
    dependencyCount:u32
    pDependencies:Vulkan:SubpassDependency*
}

record Vulkan:PipelineLayoutCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    setLayoutCount:u32
    pSetLayouts:u64*
    pushConstantRangeCount:u32
    pPushConstantRanges:u8*
}
record Vulkan:PipelineShaderStageCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    stage:u32
    module:u64
    pName:u8*
    pSpecializationInfo:u8*
}
record Vulkan:PipelineVertexInputStateCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    vertexBindingDescriptionCount:u32
    pVertexBindingDescriptions:u8*
    vertexAttributeDescriptionCount:u32
    pVertexAttributeDescriptions:u8*
}
record Vulkan:PipelineInputAssemblyStateCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    topology:i32
    primitiveRestartEnable:u32
}
record Vulkan:Viewport {
    x:f32
    y:f32
    width:f32
    height:f32
    minDepth:f32
    maxDepth:f32
}
record Vulkan:PipelineViewportStateCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    viewportCount:u32
    pViewports:Vulkan:Viewport*
    scissorCount:u32
    pScissors:Vulkan:Rect2D*
}
record Vulkan:PipelineRasterizationStateCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    depthClampEnable:u32
    rasterizerDiscardEnable:u32
    polygonMode:i32
    cullMode:u32
    frontFace:i32
    depthBiasEnable:u32
    depthBiasConstantFactor:f32
    depthBiasClamp:f32
    depthBiasSlopeFactor:f32
    lineWidth:f32
}
record Vulkan:PipelineMultisampleStateCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    rasterizationSamples:u32
    sampleShadingEnable:u32
    minSampleShading:f32
    pSampleMask:u32*
    alphaToCoverageEnable:u32
    alphaToOneEnable:u32
}
record Vulkan:PipelineColorBlendAttachmentState {
    blendEnable:u32
    srcColorBlendFactor:i32
    dstColorBlendFactor:i32
    colorBlendOp:i32
    srcAlphaBlendFactor:i32
    dstAlphaBlendFactor:i32
    alphaBlendOp:i32
    colorWriteMask:u32
}
record Vulkan:PipelineColorBlendStateCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    logicOpEnable:u32
    logicOp:i32
    attachmentCount:u32
    pAttachments:Vulkan:PipelineColorBlendAttachmentState*
    blendConstant0:f32
    blendConstant1:f32
    blendConstant2:f32
    blendConstant3:f32
}
record Vulkan:GraphicsPipelineCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    stageCount:u32
    pStages:Vulkan:PipelineShaderStageCreateInfo*
    pVertexInputState:Vulkan:PipelineVertexInputStateCreateInfo*
    pInputAssemblyState:Vulkan:PipelineInputAssemblyStateCreateInfo*
    pTessellationState:u8*
    pViewportState:Vulkan:PipelineViewportStateCreateInfo*
    pRasterizationState:Vulkan:PipelineRasterizationStateCreateInfo*
    pMultisampleState:Vulkan:PipelineMultisampleStateCreateInfo*
    pDepthStencilState:u8*
    pColorBlendState:Vulkan:PipelineColorBlendStateCreateInfo*
    pDynamicState:u8*
    layout:u64
    renderPass:u64
    subpass:u32
    basePipelineHandle:u64
    basePipelineIndex:i32
}

record Vulkan:FramebufferCreateInfo {
    sType:i32
    pNext:u8*
    flags:u32
    renderPass:u64
    attachmentCount:u32
    pAttachments:u64*
    width:u32
    height:u32
    layers:u32
}
record Vulkan:CommandPoolCreateInfo { sType:i32 pNext:u8* flags:u32 queueFamilyIndex:u32 }
record Vulkan:CommandBufferAllocateInfo { sType:i32 pNext:u8* commandPool:u64 level:i32 commandBufferCount:u32 }
record Vulkan:CommandBufferBeginInfo { sType:i32 pNext:u8* flags:u32 pInheritanceInfo:u8* }
record Vulkan:ClearValue { word0:u32 word1:u32 word2:u32 word3:u32 }
record Vulkan:RenderPassBeginInfo {
    sType:i32
    pNext:u8*
    renderPass:u64
    framebuffer:u64
    renderArea:Vulkan:Rect2D
    clearValueCount:u32
    pClearValues:Vulkan:ClearValue*
}
record Vulkan:SemaphoreCreateInfo { sType:i32 pNext:u8* flags:u32 }
record Vulkan:FenceCreateInfo { sType:i32 pNext:u8* flags:u32 }
record Vulkan:SubmitInfo {
    sType:i32
    pNext:u8*
    waitSemaphoreCount:u32
    pWaitSemaphores:u64*
    pWaitDstStageMask:u32*
    commandBufferCount:u32
    pCommandBuffers:u8**
    signalSemaphoreCount:u32
    pSignalSemaphores:u64*
}
record Vulkan:PresentInfo {
    sType:i32
    pNext:u8*
    waitSemaphoreCount:u32
    pWaitSemaphores:u64*
    swapchainCount:u32
    pSwapchains:u64*
    pImageIndices:u32*
    pResults:i32*
}

record Vulkan:DeviceSelection {
    physical:u8*
    queue_family:u32
}
record Vulkan:Device {
    handle:u8*
    queue:u8*
    physical:u8*
    queue_family:u32
}
record Vulkan:Swapchain {
    handle:u64
    format:i32
    color_space:i32
    width:u32
    height:u32
    image_count:u32
    images:u64*
    views:u64*
}
record Vulkan:Pipeline {
    render_pass:u64
    layout:u64
    handle:u64
    framebuffer_count:u32
    framebuffers:u64*
}
record Vulkan:FrameResources {
    command_pool:u64
    command_buffer:u8*
    image_available:u64
    render_finished:u64
    in_flight:u64
}

let Vulkan:has_flag = fn (flags:u32, flag:u32) -> i64 {
    if flag == 0 { return 0 }
    return ((flags / flag) % 2) != 0
}

let Vulkan:clamp_u32 = fn (value:u32, minimum:u32, maximum:u32) -> u32 {
    if value < minimum { return minimum }
    if value > maximum { return maximum }
    return value
}

let Vulkan:create_instance = fn (application_name:u8*, extensions:u8**, extension_count:u32) -> u8* {
    let app = alloc(Vulkan:ApplicationInfo)
    if !app { return cast(u8*, 0) }
    defer free(cast(u8*, app))
    app.sType = Vulkan:StructureType:ApplicationInfo()
    app.pNext = cast(u8*, 0)
    app.pApplicationName = application_name
    app.applicationVersion = 1
    app.pEngineName = "RecurLoop"
    app.engineVersion = 1
    app.apiVersion = 4194304 // VK_API_VERSION_1_0

    let create = alloc(Vulkan:InstanceCreateInfo)
    if !create { return cast(u8*, 0) }
    defer free(cast(u8*, create))
    create.sType = Vulkan:StructureType:InstanceCreateInfo()
    create.pNext = cast(u8*, 0)
    create.flags = 0
    create.pApplicationInfo = app
    create.enabledLayerCount = 0
    create.ppEnabledLayerNames = cast(u8**, 0)
    create.enabledExtensionCount = extension_count
    create.ppEnabledExtensionNames = extensions

    var instance = cast(u8*, 0)
    if vkCreateInstance(cast(u8*, create), cast(u8*, 0), &instance) != 0 { return cast(u8*, 0) }
    return instance
}

let Vulkan:pick_device = fn (instance:u8*, surface:u64) -> Vulkan:DeviceSelection* {
    var count:u32 = 0
    if vkEnumeratePhysicalDevices(instance, &count, cast(u8**, 0)) != 0 || count == 0 { return cast(Vulkan:DeviceSelection*, 0) }
    let devices = cast(u8**, malloc(count * sizeof(u8*)))
    if !devices { return cast(Vulkan:DeviceSelection*, 0) }
    defer free(cast(u8*, devices))
    if vkEnumeratePhysicalDevices(instance, &count, devices) != 0 { return cast(Vulkan:DeviceSelection*, 0) }

    var d:u32 = 0
    while d < count {
        var queue_count:u32 = 0
        vkGetPhysicalDeviceQueueFamilyProperties(devices[d], &queue_count, cast(u8*, 0))
        if queue_count > 0 {
            let queues = cast(Vulkan:QueueFamilyProperties*, malloc(queue_count * sizeof(Vulkan:QueueFamilyProperties)))
            if queues {
                vkGetPhysicalDeviceQueueFamilyProperties(devices[d], &queue_count, cast(u8*, queues))
                var q:u32 = 0
                while q < queue_count {
                    var present:u32 = 0
                    if Vulkan:has_flag(queues[q].queueFlags, Vulkan:QueueGraphicsBit()) && queues[q].queueCount > 0 {
                        if vkGetPhysicalDeviceSurfaceSupportKHR(devices[d], q, surface, &present) == 0 && present != 0 {
                            let result = alloc(Vulkan:DeviceSelection)
                            if result {
                                result.physical = devices[d]
                                result.queue_family = q
                            }
                            free(cast(u8*, queues))
                            return result
                        }
                    }
                    q += 1
                }
                free(cast(u8*, queues))
            }
        }
        d += 1
    }
    return cast(Vulkan:DeviceSelection*, 0)
}

let Vulkan:create_device = fn (selection:Vulkan:DeviceSelection*) -> Vulkan:Device* {
    if !selection { return cast(Vulkan:Device*, 0) }
    var priority:f32 = cast(f32, 1)
    let queue_info = alloc(Vulkan:DeviceQueueCreateInfo)
    if !queue_info { return cast(Vulkan:Device*, 0) }
    defer free(cast(u8*, queue_info))
    queue_info.sType = Vulkan:StructureType:DeviceQueueCreateInfo()
    queue_info.pNext = cast(u8*, 0)
    queue_info.flags = 0
    queue_info.queueFamilyIndex = selection.queue_family
    queue_info.queueCount = 1
    queue_info.pQueuePriorities = &priority

    var extension:u8* = "VK_KHR_swapchain"
    let create = alloc(Vulkan:DeviceCreateInfo)
    if !create { return cast(Vulkan:Device*, 0) }
    defer free(cast(u8*, create))
    create.sType = Vulkan:StructureType:DeviceCreateInfo()
    create.pNext = cast(u8*, 0)
    create.flags = 0
    create.queueCreateInfoCount = 1
    create.pQueueCreateInfos = queue_info
    create.enabledLayerCount = 0
    create.ppEnabledLayerNames = cast(u8**, 0)
    create.enabledExtensionCount = 1
    create.ppEnabledExtensionNames = &extension
    create.pEnabledFeatures = cast(u8*, 0)

    var handle = cast(u8*, 0)
    if vkCreateDevice(selection.physical, cast(u8*, create), cast(u8*, 0), &handle) != 0 { return cast(Vulkan:Device*, 0) }
    let result = alloc(Vulkan:Device)
    if !result { vkDestroyDevice(handle, cast(u8*, 0)); return cast(Vulkan:Device*, 0) }
    result.handle = handle
    result.physical = selection.physical
    result.queue_family = selection.queue_family
    result.queue = cast(u8*, 0)
    vkGetDeviceQueue(handle, selection.queue_family, 0, &result.queue)
    return result
}

let Vulkan:choose_composite_alpha = fn (supported:u32) -> u32 {
    if Vulkan:has_flag(supported, 1) { return 1 }
    if Vulkan:has_flag(supported, 2) { return 2 }
    if Vulkan:has_flag(supported, 4) { return 4 }
    if Vulkan:has_flag(supported, 8) { return 8 }
    return 1
}

let Vulkan:create_swapchain = fn (device:Vulkan:Device*, surface:u64, requested_width:u32, requested_height:u32) -> Vulkan:Swapchain* {
    if !device { return cast(Vulkan:Swapchain*, 0) }
    let caps = alloc(Vulkan:SurfaceCapabilities)
    if !caps { return cast(Vulkan:Swapchain*, 0) }
    defer free(cast(u8*, caps))
    if vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device.physical, surface, cast(u8*, caps)) != 0 { return cast(Vulkan:Swapchain*, 0) }

    if !Vulkan:has_flag(caps.supportedUsageFlags, Vulkan:ImageUsageColorAttachmentBit()) {
        return cast(Vulkan:Swapchain*, 0)
    }

    var format_count:u32 = 0
    if vkGetPhysicalDeviceSurfaceFormatsKHR(device.physical, surface, &format_count, cast(u8*, 0)) != 0 || format_count == 0 { return cast(Vulkan:Swapchain*, 0) }
    let formats = cast(Vulkan:SurfaceFormat*, malloc(format_count * sizeof(Vulkan:SurfaceFormat)))
    if !formats { return cast(Vulkan:Swapchain*, 0) }
    defer free(cast(u8*, formats))
    if vkGetPhysicalDeviceSurfaceFormatsKHR(device.physical, surface, &format_count, cast(u8*, formats)) != 0 { return cast(Vulkan:Swapchain*, 0) }

    var format = formats[0].format
    var color_space = formats[0].colorSpace
    if format == 0 { format = 44; color_space = 0 } // B8G8R8A8_UNORM + SRGB_NONLINEAR

    var width = requested_width
    var height = requested_height
    if caps.currentExtent.width != 4294967295 {
        width = caps.currentExtent.width
        height = caps.currentExtent.height
    } else {
        width = Vulkan:clamp_u32(width, caps.minImageExtent.width, caps.maxImageExtent.width)
        height = Vulkan:clamp_u32(height, caps.minImageExtent.height, caps.maxImageExtent.height)
    }

    var image_count = caps.minImageCount + 1
    if caps.maxImageCount > 0 && image_count > caps.maxImageCount { image_count = caps.maxImageCount }

    let create = alloc(Vulkan:SwapchainCreateInfo)
    if !create { return cast(Vulkan:Swapchain*, 0) }
    defer free(cast(u8*, create))
    create.sType = Vulkan:StructureType:SwapchainCreateInfoKHR()
    create.pNext = cast(u8*, 0)
    create.flags = 0
    create.surface = surface
    create.minImageCount = image_count
    create.imageFormat = format
    create.imageColorSpace = color_space
    create.imageExtent.width = width
    create.imageExtent.height = height
    create.imageArrayLayers = 1
    create.imageUsage = Vulkan:ImageUsageColorAttachmentBit()
    create.imageSharingMode = 0
    create.queueFamilyIndexCount = 0
    create.pQueueFamilyIndices = cast(u32*, 0)
    create.preTransform = caps.currentTransform
    create.compositeAlpha = Vulkan:choose_composite_alpha(caps.supportedCompositeAlpha)
    create.presentMode = 2 // VK_PRESENT_MODE_FIFO_KHR, guaranteed by the spec
    create.clipped = 1
    create.oldSwapchain = 0

    var handle:u64 = 0
    if vkCreateSwapchainKHR(device.handle, cast(u8*, create), cast(u8*, 0), &handle) != 0 { return cast(Vulkan:Swapchain*, 0) }

    var actual_count:u32 = 0
    if vkGetSwapchainImagesKHR(device.handle, handle, &actual_count, cast(u64*, 0)) != 0 || actual_count == 0 {
        vkDestroySwapchainKHR(device.handle, handle, cast(u8*, 0))
        return cast(Vulkan:Swapchain*, 0)
    }
    let images = cast(u64*, malloc(actual_count * sizeof(u64)))
    let views = cast(u64*, malloc(actual_count * sizeof(u64)))
    if !images || !views {
        if images { free(cast(u8*, images)) }; if views { free(cast(u8*, views)) }
        vkDestroySwapchainKHR(device.handle, handle, cast(u8*, 0))
        return cast(Vulkan:Swapchain*, 0)
    }
    if vkGetSwapchainImagesKHR(device.handle, handle, &actual_count, images) != 0 {
        free(cast(u8*, images)); free(cast(u8*, views)); vkDestroySwapchainKHR(device.handle, handle, cast(u8*, 0))
        return cast(Vulkan:Swapchain*, 0)
    }

    var i:u32 = 0
    while i < actual_count {
        views[i] = 0
        let view = alloc(Vulkan:ImageViewCreateInfo)
        if !view {
            var j:u32 = 0
            while j < i { if views[j] != 0 { vkDestroyImageView(device.handle, views[j], cast(u8*, 0)) }; j += 1 }
            free(cast(u8*, images)); free(cast(u8*, views)); vkDestroySwapchainKHR(device.handle, handle, cast(u8*, 0))
            return cast(Vulkan:Swapchain*, 0)
        }
        view.sType = Vulkan:StructureType:ImageViewCreateInfo()
        view.pNext = cast(u8*, 0)
        view.flags = 0
        view.image = images[i]
        view.viewType = 1
        view.format = format
        view.components.r = 0; view.components.g = 0; view.components.b = 0; view.components.a = 0
        view.subresourceRange.aspectMask = Vulkan:ImageAspectColorBit()
        view.subresourceRange.baseMipLevel = 0; view.subresourceRange.levelCount = 1
        view.subresourceRange.baseArrayLayer = 0; view.subresourceRange.layerCount = 1
        if vkCreateImageView(device.handle, cast(u8*, view), cast(u8*, 0), &views[i]) != 0 {
            free(cast(u8*, view))
            var j:u32 = 0
            while j < i { if views[j] != 0 { vkDestroyImageView(device.handle, views[j], cast(u8*, 0)) }; j += 1 }
            free(cast(u8*, images)); free(cast(u8*, views)); vkDestroySwapchainKHR(device.handle, handle, cast(u8*, 0))
            return cast(Vulkan:Swapchain*, 0)
        }
        free(cast(u8*, view))
        i += 1
    }

    let result = alloc(Vulkan:Swapchain)
    if !result {
        i = 0; while i < actual_count { vkDestroyImageView(device.handle, views[i], cast(u8*, 0)); i += 1 }
        free(cast(u8*, images)); free(cast(u8*, views)); vkDestroySwapchainKHR(device.handle, handle, cast(u8*, 0))
        return cast(Vulkan:Swapchain*, 0)
    }
    result.handle = handle
    result.format = format
    result.color_space = color_space
    result.width = width
    result.height = height
    result.image_count = actual_count
    result.images = images
    result.views = views
    return result
}

let Vulkan:create_shader_module = fn (device:u8*, words:u32*, bytes:u64) -> u64 {
    if !device || !words || bytes < 20 || (bytes % 4) != 0 { return 0 }
    let create = alloc(Vulkan:ShaderModuleCreateInfo)
    if !create { return 0 }
    defer free(cast(u8*, create))
    create.sType = Vulkan:StructureType:ShaderModuleCreateInfo()
    create.pNext = cast(u8*, 0)
    create.flags = 0
    create.codeSize = bytes
    create.pCode = words
    var module:u64 = 0
    if vkCreateShaderModule(device, cast(u8*, create), cast(u8*, 0), &module) != 0 { return 0 }
    return module
}

let Vulkan:create_render_pass = fn (device:u8*, format:i32) -> u64 {
    let attachment = alloc(Vulkan:AttachmentDescription)
    if !attachment { return 0 }
    defer free(cast(u8*, attachment))
    attachment.flags = 0
    attachment.format = format
    attachment.samples = 1
    attachment.loadOp = 1
    attachment.storeOp = 0
    attachment.stencilLoadOp = 2
    attachment.stencilStoreOp = 1
    attachment.initialLayout = 0
    attachment.finalLayout = 1000001002

    let color_ref = alloc(Vulkan:AttachmentReference)
    if !color_ref { return 0 }
    defer free(cast(u8*, color_ref))
    color_ref.attachment = 0
    color_ref.layout = 2

    let subpass = alloc(Vulkan:SubpassDescription)
    if !subpass { return 0 }
    defer free(cast(u8*, subpass))
    subpass.flags = 0
    subpass.pipelineBindPoint = 0
    subpass.inputAttachmentCount = 0
    subpass.pInputAttachments = cast(u8*, 0)
    subpass.colorAttachmentCount = 1
    subpass.pColorAttachments = color_ref
    subpass.pResolveAttachments = cast(u8*, 0)
    subpass.pDepthStencilAttachment = cast(u8*, 0)
    subpass.preserveAttachmentCount = 0
    subpass.pPreserveAttachments = cast(u32*, 0)

    let dependency = alloc(Vulkan:SubpassDependency)
    if !dependency { return 0 }
    defer free(cast(u8*, dependency))
    dependency.srcSubpass = 4294967295
    dependency.dstSubpass = 0
    dependency.srcStageMask = Vulkan:PipelineStageColorAttachmentOutputBit()
    dependency.dstStageMask = Vulkan:PipelineStageColorAttachmentOutputBit()
    dependency.srcAccessMask = 0
    dependency.dstAccessMask = Vulkan:AccessColorAttachmentWriteBit()
    dependency.dependencyFlags = 0

    let create = alloc(Vulkan:RenderPassCreateInfo)
    if !create { return 0 }
    defer free(cast(u8*, create))
    create.sType = Vulkan:StructureType:RenderPassCreateInfo()
    create.pNext = cast(u8*, 0)
    create.flags = 0
    create.attachmentCount = 1
    create.pAttachments = attachment
    create.subpassCount = 1
    create.pSubpasses = subpass
    create.dependencyCount = 1
    create.pDependencies = dependency

    var render_pass:u64 = 0
    if vkCreateRenderPass(device, cast(u8*, create), cast(u8*, 0), &render_pass) != 0 { return 0 }
    return render_pass
}

let Vulkan:create_graphics_pipeline = fn (device:u8*, swapchain:Vulkan:Swapchain*, vertex_module:u64, fragment_module:u64) -> Vulkan:Pipeline* {
    if !device || !swapchain || vertex_module == 0 || fragment_module == 0 { return cast(Vulkan:Pipeline*, 0) }
    let render_pass = Vulkan:create_render_pass(device, swapchain.format)
    if render_pass == 0 { return cast(Vulkan:Pipeline*, 0) }

    let layout_info = alloc(Vulkan:PipelineLayoutCreateInfo)
    if !layout_info { vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, layout_info))
    layout_info.sType = Vulkan:StructureType:PipelineLayoutCreateInfo()
    layout_info.pNext = cast(u8*, 0); layout_info.flags = 0
    layout_info.setLayoutCount = 0; layout_info.pSetLayouts = cast(u64*, 0)
    layout_info.pushConstantRangeCount = 0; layout_info.pPushConstantRanges = cast(u8*, 0)
    var layout:u64 = 0
    if vkCreatePipelineLayout(device, cast(u8*, layout_info), cast(u8*, 0), &layout) != 0 {
        vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0)
    }

    let stages = alloc(Vulkan:PipelineShaderStageCreateInfo)
    if !stages {
        vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0)
    }
    defer free(cast(u8*, stages))
    stages[0].sType = Vulkan:StructureType:PipelineShaderStageCreateInfo()
    stages[0].pNext = cast(u8*, 0); stages[0].flags = 0; stages[0].stage = 1
    stages[0].module = vertex_module; stages[0].pName = "main"; stages[0].pSpecializationInfo = cast(u8*, 0)
    stages[1].sType = Vulkan:StructureType:PipelineShaderStageCreateInfo()
    stages[1].pNext = cast(u8*, 0); stages[1].flags = 0; stages[1].stage = 16
    stages[1].module = fragment_module; stages[1].pName = "main"; stages[1].pSpecializationInfo = cast(u8*, 0)

    let vertex_input = alloc(Vulkan:PipelineVertexInputStateCreateInfo)
    if !vertex_input { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, vertex_input))
    vertex_input.sType = Vulkan:StructureType:PipelineVertexInputStateCreateInfo()
    vertex_input.pNext = cast(u8*, 0); vertex_input.flags = 0
    vertex_input.vertexBindingDescriptionCount = 0; vertex_input.pVertexBindingDescriptions = cast(u8*, 0)
    vertex_input.vertexAttributeDescriptionCount = 0; vertex_input.pVertexAttributeDescriptions = cast(u8*, 0)

    let assembly = alloc(Vulkan:PipelineInputAssemblyStateCreateInfo)
    if !assembly { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, assembly))
    assembly.sType = Vulkan:StructureType:PipelineInputAssemblyStateCreateInfo()
    assembly.pNext = cast(u8*, 0); assembly.flags = 0; assembly.topology = 3; assembly.primitiveRestartEnable = 0

    let viewport = alloc(Vulkan:Viewport)
    if !viewport { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, viewport))
    viewport.x = cast(f32, 0); viewport.y = cast(f32, 0)
    viewport.width = cast(f32, swapchain.width)
    viewport.height = cast(f32, swapchain.height)
    viewport.minDepth = cast(f32, 0)
    viewport.maxDepth = cast(f32, 1)

    let scissor = alloc(Vulkan:Rect2D)
    if !scissor { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, scissor))
    scissor.offset.x = 0; scissor.offset.y = 0
    scissor.extent.width = swapchain.width; scissor.extent.height = swapchain.height

    let viewport_state = alloc(Vulkan:PipelineViewportStateCreateInfo)
    if !viewport_state { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, viewport_state))
    viewport_state.sType = Vulkan:StructureType:PipelineViewportStateCreateInfo()
    viewport_state.pNext = cast(u8*, 0); viewport_state.flags = 0
    viewport_state.viewportCount = 1; viewport_state.pViewports = viewport
    viewport_state.scissorCount = 1; viewport_state.pScissors = scissor

    let raster = alloc(Vulkan:PipelineRasterizationStateCreateInfo)
    if !raster { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, raster))
    raster.sType = Vulkan:StructureType:PipelineRasterizationStateCreateInfo()
    raster.pNext = cast(u8*, 0); raster.flags = 0
    raster.depthClampEnable = 0; raster.rasterizerDiscardEnable = 0
    raster.polygonMode = 0; raster.cullMode = 0; raster.frontFace = 0
    raster.depthBiasEnable = 0; raster.depthBiasConstantFactor = cast(f32, 0)
    raster.depthBiasClamp = cast(f32, 0); raster.depthBiasSlopeFactor = cast(f32, 0)
    raster.lineWidth = cast(f32, 1)

    let multisample = alloc(Vulkan:PipelineMultisampleStateCreateInfo)
    if !multisample { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, multisample))
    multisample.sType = Vulkan:StructureType:PipelineMultisampleStateCreateInfo()
    multisample.pNext = cast(u8*, 0); multisample.flags = 0
    multisample.rasterizationSamples = 1; multisample.sampleShadingEnable = 0
    multisample.minSampleShading = cast(f32, 0); multisample.pSampleMask = cast(u32*, 0)
    multisample.alphaToCoverageEnable = 0; multisample.alphaToOneEnable = 0

    let blend_attachment = alloc(Vulkan:PipelineColorBlendAttachmentState)
    if !blend_attachment { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, blend_attachment))
    blend_attachment.blendEnable = 0
    blend_attachment.srcColorBlendFactor = 1; blend_attachment.dstColorBlendFactor = 0; blend_attachment.colorBlendOp = 0
    blend_attachment.srcAlphaBlendFactor = 1; blend_attachment.dstAlphaBlendFactor = 0; blend_attachment.alphaBlendOp = 0
    blend_attachment.colorWriteMask = Vulkan:ColorComponentRGBA()

    let blend = alloc(Vulkan:PipelineColorBlendStateCreateInfo)
    if !blend { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, blend))
    blend.sType = Vulkan:StructureType:PipelineColorBlendStateCreateInfo()
    blend.pNext = cast(u8*, 0); blend.flags = 0; blend.logicOpEnable = 0; blend.logicOp = 3
    blend.attachmentCount = 1; blend.pAttachments = blend_attachment
    blend.blendConstant0 = cast(f32, 0); blend.blendConstant1 = cast(f32, 0); blend.blendConstant2 = cast(f32, 0); blend.blendConstant3 = cast(f32, 0)

    let create = alloc(Vulkan:GraphicsPipelineCreateInfo)
    if !create { vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0) }
    defer free(cast(u8*, create))
    create.sType = Vulkan:StructureType:GraphicsPipelineCreateInfo()
    create.pNext = cast(u8*, 0); create.flags = 0
    create.stageCount = 2; create.pStages = stages
    create.pVertexInputState = vertex_input; create.pInputAssemblyState = assembly
    create.pTessellationState = cast(u8*, 0); create.pViewportState = viewport_state
    create.pRasterizationState = raster; create.pMultisampleState = multisample
    create.pDepthStencilState = cast(u8*, 0); create.pColorBlendState = blend; create.pDynamicState = cast(u8*, 0)
    create.layout = layout; create.renderPass = render_pass; create.subpass = 0
    create.basePipelineHandle = 0; create.basePipelineIndex = -1

    var pipeline:u64 = 0
    if vkCreateGraphicsPipelines(device, 0, 1, cast(u8*, create), cast(u8*, 0), &pipeline) != 0 {
        vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0)
    }

    let framebuffers = cast(u64*, malloc(swapchain.image_count * sizeof(u64)))
    if !framebuffers {
        vkDestroyPipeline(device, pipeline, cast(u8*, 0)); vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0)
    }
    var i:u32 = 0
    while i < swapchain.image_count {
        framebuffers[i] = 0
        let framebuffer_info = alloc(Vulkan:FramebufferCreateInfo)
        if !framebuffer_info {
            var j:u32 = 0; while j < i { vkDestroyFramebuffer(device, framebuffers[j], cast(u8*, 0)); j += 1 }
            free(cast(u8*, framebuffers)); vkDestroyPipeline(device, pipeline, cast(u8*, 0)); vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0)
        }
        framebuffer_info.sType = Vulkan:StructureType:FramebufferCreateInfo()
        framebuffer_info.pNext = cast(u8*, 0); framebuffer_info.flags = 0; framebuffer_info.renderPass = render_pass
        framebuffer_info.attachmentCount = 1; framebuffer_info.pAttachments = &swapchain.views[i]
        framebuffer_info.width = swapchain.width; framebuffer_info.height = swapchain.height; framebuffer_info.layers = 1
        if vkCreateFramebuffer(device, cast(u8*, framebuffer_info), cast(u8*, 0), &framebuffers[i]) != 0 {
            free(cast(u8*, framebuffer_info))
            var j:u32 = 0; while j < i { vkDestroyFramebuffer(device, framebuffers[j], cast(u8*, 0)); j += 1 }
            free(cast(u8*, framebuffers)); vkDestroyPipeline(device, pipeline, cast(u8*, 0)); vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0)
        }
        free(cast(u8*, framebuffer_info))
        i += 1
    }

    let result = alloc(Vulkan:Pipeline)
    if !result {
        i = 0; while i < swapchain.image_count { vkDestroyFramebuffer(device, framebuffers[i], cast(u8*, 0)); i += 1 }
        free(cast(u8*, framebuffers)); vkDestroyPipeline(device, pipeline, cast(u8*, 0)); vkDestroyPipelineLayout(device, layout, cast(u8*, 0)); vkDestroyRenderPass(device, render_pass, cast(u8*, 0)); return cast(Vulkan:Pipeline*, 0)
    }
    result.render_pass = render_pass; result.layout = layout; result.handle = pipeline
    result.framebuffer_count = swapchain.image_count; result.framebuffers = framebuffers
    return result
}

let Vulkan:create_frame_resources = fn (device:Vulkan:Device*) -> Vulkan:FrameResources* {
    if !device { return cast(Vulkan:FrameResources*, 0) }
    let result = alloc(Vulkan:FrameResources)
    if !result { return result }
    result.command_pool = 0; result.command_buffer = cast(u8*, 0); result.image_available = 0; result.render_finished = 0; result.in_flight = 0

    let pool_info = alloc(Vulkan:CommandPoolCreateInfo)
    if !pool_info { free(cast(u8*, result)); return cast(Vulkan:FrameResources*, 0) }
    defer free(cast(u8*, pool_info))
    pool_info.sType = Vulkan:StructureType:CommandPoolCreateInfo(); pool_info.pNext = cast(u8*, 0)
    pool_info.flags = Vulkan:CommandPoolResetCommandBufferBit(); pool_info.queueFamilyIndex = device.queue_family
    if vkCreateCommandPool(device.handle, cast(u8*, pool_info), cast(u8*, 0), &result.command_pool) != 0 { free(cast(u8*, result)); return cast(Vulkan:FrameResources*, 0) }

    let allocation = alloc(Vulkan:CommandBufferAllocateInfo)
    if !allocation { vkDestroyCommandPool(device.handle, result.command_pool, cast(u8*, 0)); free(cast(u8*, result)); return cast(Vulkan:FrameResources*, 0) }
    defer free(cast(u8*, allocation))
    allocation.sType = Vulkan:StructureType:CommandBufferAllocateInfo(); allocation.pNext = cast(u8*, 0)
    allocation.commandPool = result.command_pool; allocation.level = 0; allocation.commandBufferCount = 1
    if vkAllocateCommandBuffers(device.handle, cast(u8*, allocation), &result.command_buffer) != 0 {
        vkDestroyCommandPool(device.handle, result.command_pool, cast(u8*, 0)); free(cast(u8*, result)); return cast(Vulkan:FrameResources*, 0)
    }

    let semaphore_info = alloc(Vulkan:SemaphoreCreateInfo)
    if !semaphore_info { vkDestroyCommandPool(device.handle, result.command_pool, cast(u8*, 0)); free(cast(u8*, result)); return cast(Vulkan:FrameResources*, 0) }
    defer free(cast(u8*, semaphore_info))
    semaphore_info.sType = Vulkan:StructureType:SemaphoreCreateInfo(); semaphore_info.pNext = cast(u8*, 0); semaphore_info.flags = 0
    let fence_info = alloc(Vulkan:FenceCreateInfo)
    if !fence_info { vkDestroyCommandPool(device.handle, result.command_pool, cast(u8*, 0)); free(cast(u8*, result)); return cast(Vulkan:FrameResources*, 0) }
    defer free(cast(u8*, fence_info))
    fence_info.sType = Vulkan:StructureType:FenceCreateInfo(); fence_info.pNext = cast(u8*, 0); fence_info.flags = Vulkan:FenceSignaledBit()
    if vkCreateSemaphore(device.handle, cast(u8*, semaphore_info), cast(u8*, 0), &result.image_available) != 0 ||
       vkCreateSemaphore(device.handle, cast(u8*, semaphore_info), cast(u8*, 0), &result.render_finished) != 0 ||
       vkCreateFence(device.handle, cast(u8*, fence_info), cast(u8*, 0), &result.in_flight) != 0 {
        if result.image_available != 0 { vkDestroySemaphore(device.handle, result.image_available, cast(u8*, 0)) }
        if result.render_finished != 0 { vkDestroySemaphore(device.handle, result.render_finished, cast(u8*, 0)) }
        if result.in_flight != 0 { vkDestroyFence(device.handle, result.in_flight, cast(u8*, 0)) }
        vkDestroyCommandPool(device.handle, result.command_pool, cast(u8*, 0)); free(cast(u8*, result)); return cast(Vulkan:FrameResources*, 0)
    }
    return result
}

let Vulkan:record_triangle = fn (command_buffer:u8*, pipeline:Vulkan:Pipeline*, swapchain:Vulkan:Swapchain*, image_index:u32) -> i64 {
    if vkResetCommandBuffer(command_buffer, 0) != 0 { return 0 }
    let begin = alloc(Vulkan:CommandBufferBeginInfo)
    if !begin { return 0 }
    defer free(cast(u8*, begin))
    begin.sType = Vulkan:StructureType:CommandBufferBeginInfo(); begin.pNext = cast(u8*, 0); begin.flags = 0; begin.pInheritanceInfo = cast(u8*, 0)
    if vkBeginCommandBuffer(command_buffer, cast(u8*, begin)) != 0 { return 0 }

    let clear = alloc(Vulkan:ClearValue)
    if !clear { return 0 }
    defer free(cast(u8*, clear))
    clear.word0 = 0; clear.word1 = 0; clear.word2 = 0; clear.word3 = 1065353216
    let render = alloc(Vulkan:RenderPassBeginInfo)
    if !render { return 0 }
    defer free(cast(u8*, render))
    render.sType = Vulkan:StructureType:RenderPassBeginInfo(); render.pNext = cast(u8*, 0)
    render.renderPass = pipeline.render_pass; render.framebuffer = pipeline.framebuffers[image_index]
    render.renderArea.offset.x = 0; render.renderArea.offset.y = 0
    render.renderArea.extent.width = swapchain.width; render.renderArea.extent.height = swapchain.height
    render.clearValueCount = 1; render.pClearValues = clear
    vkCmdBeginRenderPass(command_buffer, cast(u8*, render), 0)
    vkCmdBindPipeline(command_buffer, 0, pipeline.handle)
    vkCmdDraw(command_buffer, 3, 1, 0, 0)
    vkCmdEndRenderPass(command_buffer)
    return vkEndCommandBuffer(command_buffer) == 0
}

let Vulkan:draw_triangle_frame = fn (device:Vulkan:Device*, swapchain:Vulkan:Swapchain*, pipeline:Vulkan:Pipeline*, frame:Vulkan:FrameResources*) -> i32 {
    var fence = frame.in_flight
    if vkWaitForFences(device.handle, 1, &fence, 1, Vulkan:WholeTimeout()) != 0 { return -1 }

    var image_index:u32 = 0
    let acquired = vkAcquireNextImageKHR(device.handle, swapchain.handle, Vulkan:WholeTimeout(), frame.image_available, 0, &image_index)
    if acquired == Vulkan:Result:OutOfDate() { return acquired }
    if acquired != Vulkan:Result:Success() && acquired != Vulkan:Result:Suboptimal() { return acquired }
    if !Vulkan:record_triangle(frame.command_buffer, pipeline, swapchain, image_index) { return -1 }
    if vkResetFences(device.handle, 1, &fence) != 0 { return -1 }

    var wait_stage:u32 = Vulkan:PipelineStageColorAttachmentOutputBit()
    var wait_semaphore = frame.image_available
    var signal_semaphore = frame.render_finished
    var command_buffer = frame.command_buffer
    let submit = alloc(Vulkan:SubmitInfo)
    if !submit { return -1 }
    defer free(cast(u8*, submit))
    submit.sType = Vulkan:StructureType:SubmitInfo(); submit.pNext = cast(u8*, 0)
    submit.waitSemaphoreCount = 1; submit.pWaitSemaphores = &wait_semaphore; submit.pWaitDstStageMask = &wait_stage
    submit.commandBufferCount = 1; submit.pCommandBuffers = &command_buffer
    submit.signalSemaphoreCount = 1; submit.pSignalSemaphores = &signal_semaphore
    if vkQueueSubmit(device.queue, 1, cast(u8*, submit), frame.in_flight) != 0 { return -1 }

    var swapchain_handle = swapchain.handle
    let present = alloc(Vulkan:PresentInfo)
    if !present { return -1 }
    defer free(cast(u8*, present))
    present.sType = Vulkan:StructureType:PresentInfoKHR(); present.pNext = cast(u8*, 0)
    present.waitSemaphoreCount = 1; present.pWaitSemaphores = &signal_semaphore
    present.swapchainCount = 1; present.pSwapchains = &swapchain_handle; present.pImageIndices = &image_index; present.pResults = cast(i32*, 0)
    return vkQueuePresentKHR(device.queue, cast(u8*, present))
}

let Vulkan:FrameResources:destroy = fn (self:Vulkan:FrameResources*, device:u8*) -> void {
    if !self { return }
    if self.in_flight != 0 { vkDestroyFence(device, self.in_flight, cast(u8*, 0)) }
    if self.render_finished != 0 { vkDestroySemaphore(device, self.render_finished, cast(u8*, 0)) }
    if self.image_available != 0 { vkDestroySemaphore(device, self.image_available, cast(u8*, 0)) }
    if self.command_pool != 0 { vkDestroyCommandPool(device, self.command_pool, cast(u8*, 0)) }
    free(cast(u8*, self))
}

let Vulkan:Pipeline:destroy = fn (self:Vulkan:Pipeline*, device:u8*) -> void {
    if !self { return }
    var i:u32 = 0
    while i < self.framebuffer_count { if self.framebuffers[i] != 0 { vkDestroyFramebuffer(device, self.framebuffers[i], cast(u8*, 0)) }; i += 1 }
    if self.framebuffers { free(cast(u8*, self.framebuffers)) }
    if self.handle != 0 { vkDestroyPipeline(device, self.handle, cast(u8*, 0)) }
    if self.layout != 0 { vkDestroyPipelineLayout(device, self.layout, cast(u8*, 0)) }
    if self.render_pass != 0 { vkDestroyRenderPass(device, self.render_pass, cast(u8*, 0)) }
    free(cast(u8*, self))
}

let Vulkan:Swapchain:destroy = fn (self:Vulkan:Swapchain*, device:u8*) -> void {
    if !self { return }
    var i:u32 = 0
    while i < self.image_count { if self.views[i] != 0 { vkDestroyImageView(device, self.views[i], cast(u8*, 0)) }; i += 1 }
    if self.views { free(cast(u8*, self.views)) }; if self.images { free(cast(u8*, self.images)) }
    if self.handle != 0 { vkDestroySwapchainKHR(device, self.handle, cast(u8*, 0)) }
    free(cast(u8*, self))
}

let Vulkan:wait_idle = fn (device:Vulkan:Device*) -> i32 {
    if !device || !device.handle { return -1 }
    return vkDeviceWaitIdle(device.handle)
}

let Vulkan:destroy_shader_module = fn (device:u8*, module:u64) -> void {
    if device && module != 0 { vkDestroyShaderModule(device, module, cast(u8*, 0)) }
}

let Vulkan:destroy_surface = fn (instance:u8*, surface:u64) -> void {
    if instance && surface != 0 { vkDestroySurfaceKHR(instance, surface, cast(u8*, 0)) }
}

let Vulkan:destroy_instance = fn (instance:u8*) -> void {
    if instance { vkDestroyInstance(instance, cast(u8*, 0)) }
}

let Vulkan:Device:destroy = fn (self:Vulkan:Device*) -> void {
    if !self { return }
    if self.handle { vkDestroyDevice(self.handle, cast(u8*, 0)) }
    free(cast(u8*, self))
}

// External phrases contain process-local native addresses and must not be
// serialized into a portable .rli image. Compiled RecurLoop functions retain
// their stable external symbol contracts, exactly like the shell/http libs.
set vkCreateInstance.serializable = false
set vkDestroyInstance.serializable = false
set vkEnumeratePhysicalDevices.serializable = false
set vkGetPhysicalDeviceQueueFamilyProperties.serializable = false
set vkGetPhysicalDeviceSurfaceSupportKHR.serializable = false
set vkGetPhysicalDeviceSurfaceCapabilitiesKHR.serializable = false
set vkGetPhysicalDeviceSurfaceFormatsKHR.serializable = false
set vkCreateDevice.serializable = false
set vkDestroyDevice.serializable = false
set vkGetDeviceQueue.serializable = false
set vkDestroySurfaceKHR.serializable = false
set vkDeviceWaitIdle.serializable = false
set vkCreateSwapchainKHR.serializable = false
set vkDestroySwapchainKHR.serializable = false
set vkGetSwapchainImagesKHR.serializable = false
set vkAcquireNextImageKHR.serializable = false
set vkQueuePresentKHR.serializable = false
set vkCreateImageView.serializable = false
set vkDestroyImageView.serializable = false
set vkCreateShaderModule.serializable = false
set vkDestroyShaderModule.serializable = false
set vkCreateRenderPass.serializable = false
set vkDestroyRenderPass.serializable = false
set vkCreatePipelineLayout.serializable = false
set vkDestroyPipelineLayout.serializable = false
set vkCreateGraphicsPipelines.serializable = false
set vkDestroyPipeline.serializable = false
set vkCreateFramebuffer.serializable = false
set vkDestroyFramebuffer.serializable = false
set vkCreateCommandPool.serializable = false
set vkDestroyCommandPool.serializable = false
set vkAllocateCommandBuffers.serializable = false
set vkResetCommandBuffer.serializable = false
set vkBeginCommandBuffer.serializable = false
set vkEndCommandBuffer.serializable = false
set vkCmdBeginRenderPass.serializable = false
set vkCmdEndRenderPass.serializable = false
set vkCmdBindPipeline.serializable = false
set vkCmdDraw.serializable = false
set vkCreateSemaphore.serializable = false
set vkDestroySemaphore.serializable = false
set vkCreateFence.serializable = false
set vkDestroyFence.serializable = false
set vkWaitForFences.serializable = false
set vkResetFences.serializable = false
set vkQueueSubmit.serializable = false

languagekit_native_end
include "../build/export.rl"
__recurloop_export_library
