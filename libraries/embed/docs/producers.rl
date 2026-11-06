// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:producers = [
    id = phrase { payload = "producers" }
    title = phrase { payload = "Produce embedded data from a syntax action" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`Embed:emit_bytes(state, data, count)` emits a literal from `count` bytes during elaboration. `emit_bits` accepts an exact bit count. Both return `1` on success and `0` on failure. They require a live syntax context.

```recurloop
import embed
syntax magic bytes action fn (state:Context*, called:Phrase*) -> void {
        if !Embed:emit_bytes(state, \"RL\", 2) {
            context:diagnostic:error(state, \"could not emit magic bytes\")
        }
}
let verify_magic = fn () -> i64 {
    let blob = magic bytes
    return Embed:bytes(blob) != 2 || Embed:data(blob)[0] != 82
}
assert verify_magic() == 0
```

The producer runs while its expression is elaborated. The final program reads the resulting embedded literal; it does not need to rerun the producer or load an asset from disk. If the producer allocates temporary input storage, release it after emission. The helper consumes bytes to form source; it does not transfer ownership of the input pointer.

Keep runtime and elaboration separate. Calling `emit_bytes` is not a runtime append operation, and it does not turn an arbitrary pointer into permanent executable-owned storage."
    }
]
