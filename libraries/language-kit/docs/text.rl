// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:text = [
    id = phrase { payload = "text" }
    title = phrase { payload = "Build text and transfer ownership" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`Text:new` returns an owned wrapper with `data`, `length` and `capacity`. `length` counts bytes before the terminating zero. `append`, `append_byte` and `reserve` return `1` on success, `0` on failure. Check appends when incomplete output would be harmful.

```recurloop
import language-kit
let join_label = fn (name:u8*) -> u8* {
    let text = LanguageKit:Text:new()
    if !text { return cast(u8*, 0) }
    defer text.destroy()
    if !text.append(\"package: \") || !text.append(name) { return cast(u8*, 0) }
    return text.take()
}
let check_label = fn () -> i64 {
    let result = join_label(\"example\")
    if !result { return 1 }
    defer free(result)
    return strcmp(result, \"package: example\") != 0
}
assert check_label() == 0
```

## Borrow or transfer

- `text.data` is borrowed. Mutation or destruction can invalidate it.
- `text.take()` transfers the allocated byte string and empties the wrapper.
- Destroy the emptied wrapper separately; release the transferred string with `free`.
- `LanguageKit:copy_text` copies null-terminated text; `copy_bytes` copies a bounded range and adds a terminator.

Do not free `data` and then destroy its still-owning wrapper. Do not use a borrowed pointer across an append that may reallocate. Byte offsets are not Unicode character offsets; the text helper preserves bytes and does not interpret grapheme clusters."
    }
]
