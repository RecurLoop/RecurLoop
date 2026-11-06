// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "LanguageKit" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "LanguageKit supplies reusable tools for source-defined vocabularies: growable text, token readers, phrase-aware parsing, managed values and cross-language bindings. Import it when writing a language extension or using its native helpers directly.

```recurloop
import language-kit
let make_message = fn () -> u8* {
    let text = LanguageKit:Text:new()
    if !text { return cast(u8*, 0) }
    defer text.destroy()
    if !text.append(\"Hello, \") || !text.append(\"RecurLoop\") { return cast(u8*, 0) }
    return text.take()
}
let demonstrate = fn () -> i64 {
    let message = make_message()
    if !message { return 1 }
    defer free(message)
    return strcmp(message, \"Hello, RecurLoop\") != 0
}
assert demonstrate() == 0
```

## Choose a facility

| Facility | Use it for |
| --- | --- |
| `Text` | build owned null-terminated byte strings |
| `Reader` | consume the active source cursor |
| `SliceReader` | inspect a bounded, borrowed byte slice |
| Phrase readers | respect aliases and the active grammar |
| `Value` and `publish` | exchange data between vocabularies |
| `Lifetime` | scope-owned resources and weak handles |

The guides explain [text](text.rl), [readers](readers.rl), [phrase grammars](phrase-readers.rl), [shared values](shared-values.rl) and [managed lifetimes](lifetimes.rl). Native pointers and runtime values have different ownership; avoid replacing a documented release operation with `free` merely because the representation contains a pointer."
    }
]
