// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Embed" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    order = phrase { payload = "10" }
    body = phrase {
        payload = "Embed exposes binary literals and helps source-time producers create them. Importing the library does not run the embedded data. An embedded literal is represented by `BitString*`, with an exact bit count and a borrowed byte pointer.

## First example

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

## Learning path

1. [Bit layout](bit-layout.rl) — Understand exact lengths and partial bytes.
2. [Native data](native-data.rl) — Pass borrowed bytes across native interfaces.
3. [Syntax producers](producers.rl) — Generate literals while elaborating syntax."
    }
]
