// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:native_abi = [
    id = phrase { payload = "native-abi" }
    title = phrase { payload = "Use native records, flags and clear values" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "Native records mirror Vulkan ABI fields. Set required structure tags and pointer/count pairs correctly, initialize optional pointers explicitly and keep input storage alive for each native call. Handles are not interchangeable merely because two share an integer representation.

```recurloop
import vulkan
let verify_clear_value = fn () -> i64 {
    let color = alloc(Vulkan:ClearValue)
    if !color { return 1 }
    defer free(cast(u8*, color))
    color.word0 = 0
    color.word1 = 0
    color.word2 = 0
    color.word3 = 1065353216
    return color.word3 != 1065353216
}
assert verify_clear_value() == 0
```

`ClearValue` stores four raw words. `1065353216` is the IEEE-754 bit pattern for `1.0f`, giving opaque alpha here; numeric integer `1` would represent different bits. Other ABI records use native `f32` fields where declared.

Low-level calls such as `vkQueueSubmit`, `vkQueuePresentKHR`, `vkWaitForFences` and `vkAcquireNextImageKHR` accept native pointers and return result codes. Timeouts for fence/image waits are nanoseconds. Check counts against actual arrays and avoid borrowing stack storage beyond the duration permitted by that native API. Prefer the wrapper helpers when their single-queue rendering model fits the application."
    }
]
