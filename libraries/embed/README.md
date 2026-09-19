# Embedded data

`embed` is a small source-time utility for putting arbitrary generated binary
content into native RecurLoop output without a custom ELF section or runtime
loader.

A syntax action that already has bytes calls:

```rl
Embed:emit_bytes(state, data, byte_count)
```

The helper emits a normal RecurLoop `bits"..."` literal. The native compiler
already lowers that literal to read-only data, so the same mechanism works for
SPIR-V, generated lookup tables, fonts, images, serialized assets, or any other
binary producer.

At runtime an embedded value is a `BitString*`:

```rl
let data = Embed:data(blob)
let bytes = Embed:bytes(blob)
```

The returned memory belongs to the executable/JIT module and must not be freed.
