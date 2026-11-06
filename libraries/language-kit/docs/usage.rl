// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "LanguageKit" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "LanguageKit provides text buffers, phrase readers, scoped values and shared bindings for language extensions.

## Text ownership

Create an owned buffer with `LanguageKit:Text:new`. Append text with `append`, transfer its string with `take`, and release the buffer with `destroy`. The transferred string is released separately with `free`.

```recurloop
let TextExample = []
let TextExample:run = fn () -> i64 {
    let buffer = LanguageKit:Text:new()
    if !buffer { return 1 }
    buffer.append(\"hello\")
    let text = buffer.take()
    buffer.destroy()
    printf(\"%s\\n\", text)
    free(text)
    return 0
}
```"
    }
]

