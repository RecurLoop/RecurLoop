// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:native_data = [
    id = phrase { payload = "native-data" }
    title = phrase { payload = "Pass embedded data to native APIs safely" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`Embed:data` returns storage owned by the executable or JIT module. Do not free or modify it. Copy the bytes into an owned mutable buffer if an API writes into its input. The data pointer is valid only while its owning module remains alive.

```recurloop
import embed
let copy_bytes = fn () -> i64 {
    let blob = bits\"01010010_01001100\"
    let size = Embed:bytes(blob)
    let copy = cast(u8*, malloc(size))
    if !copy { return 1 }
    defer free(copy)
    memcpy(copy, Embed:data(blob), size)
    copy[0] = 0
    return Embed:data(blob)[0] != 82
}
assert copy_bytes() == 0
```

Binary data is not automatically null-terminated text. Pass an explicit length. Casting a byte pointer to a word pointer does not establish suitable alignment, endianness or a valid binary format. A shader module, for example, needs valid SPIR-V words and a byte length divisible by four; an arbitrary literal is not a valid shader simply because it can be cast to `u32*`."
    }
]
