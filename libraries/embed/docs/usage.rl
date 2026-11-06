// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Embed" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Embed exposes binary literals and helps source-time producers create them. Importing the library does not run the embedded data. An embedded literal is represented by `BitString*`, with an exact bit count and a borrowed byte pointer.

```recurloop
import embed
let check_blob = fn () -> i64 {
    let blob = bits\"10101010_11110000\"
    if Embed:bits(blob) != 16 || Embed:bytes(blob) != 2 { return 1 }
    let data = Embed:data(blob)
    return data[0] != 170 || data[1] != 240
}
assert check_blob() == 0
```

Use [bit and byte counts](bit-layout.rl) when the last byte is partial, [syntax producers](producers.rl) to generate a literal during elaboration, and [native API boundaries](native-data.rl) when passing embedded bytes to another API."
    }
]
