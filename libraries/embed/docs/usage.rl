// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Embed" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Embed exposes compile-time binary data through RecurLoop bit strings.

Use `Embed:bits` when the exact bit length matters and `Embed:bytes` for a byte sequence. Keep the data’s lifetime and alignment requirements in mind when passing it to native functions. Embedded bytes are data; they do not execute on import."
    }
]

