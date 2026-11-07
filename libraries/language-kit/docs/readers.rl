// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:readers = [
    id = phrase { payload = "readers" }
    title = phrase { payload = "Source readers" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "30" }
    body = phrase {
        payload = "## Choose a live or bounded source cursor

`Reader` consumes the current runtime source through a live `Context*`. `SliceReader` has its own cursor over supplied bytes and borrows that source storage. Keep the source alive until the slice reader is destroyed.

```recurloop
import language-kit
let read_integer = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let reader = LanguageKit:SliceReader:new(state, \"42\", 2, 0)
        if !reader { context:diagnostic:error(state, \"reader allocation failed\"); return }
        defer reader.destroy()
        if reader.number_of() != 42 { context:diagnostic:error(state, \"integer expected\"); return }
        reader.consume()
        if reader.kind_of() != 0 { context:diagnostic:error(state, \"unexpected trailing token\") }
    }
}
read_integer
```

## Ownership while reading

`text_of` returns cached, borrowed token text. It stays valid only until consumption or reader destruction. `take_text` consumes the token and transfers its allocated text; free the result yourself. `take_identifier` does the same only for an identifier, returning null for another kind.

## Separate lookahead from consumption

`match` consumes on success. Lookahead accessors such as `kind_of`, `number_of` and `text_of` inspect without consuming. Check token kind when accepting a number: a numeric accessor alone is not a complete parser for an application grammar.

## Interpret token kinds and flags

Token kinds are `0` end, `1` identifier, `2` number, `3` quoted text, `4` operator and `5` punctuation. Flags control tokenization behavior. Prefer a phrase-aware grammar for configurable operators instead of depending on a handwritten punctuation list."
    }
]
