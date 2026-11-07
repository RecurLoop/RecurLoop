// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:bit_layout = [
    id = phrase { payload = "bit-layout" }
    title = phrase { payload = "Bit layout" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "20" }
    body = phrase {
        payload = "## Measure exact bit and byte lengths

`Embed:bits` returns the exact number of bits. `Embed:bytes` rounds that count up to whole bytes. Bits are stored most-significant bit first in each byte; unused trailing bits do not become meaningful data merely because the byte is allocated.

```recurloop
import embed
let check_partial_byte = fn () -> i64 {
    let blob = bits\"101\"
    if Embed:bits(blob) != 3 { return 1 }
    if Embed:bytes(blob) != 1 { return 2 }
    return Embed:data(blob)[0] != 160
}
assert check_partial_byte() == 0
```

## Interpret padding bits

Here `101` occupies the high bits of the byte, giving `10100000` (`160`). Use the exact bit count for bit-oriented protocols. Use the rounded byte count only for an API whose unit is bytes and which can interpret any padding correctly.

## Handle optional blobs

`data`, `bits` and `bytes` accept a null blob and return null, zero and zero respectively. This makes probing optional data possible; it does not make null a valid buffer for an unrelated native operation."
    }
]
