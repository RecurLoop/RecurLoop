// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:phrase_readers = [
    id = phrase { payload = "phrase-readers" }
    title = phrase { payload = "Grammar parsing" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "40" }
    body = phrase {
        payload = "## Parse using the active phrase grammar

Phrase readers resolve the active grammar with longest matching phrase identity. This is useful when punctuation has aliases or a language extends its tokens. Comparing canonical phrase identity avoids treating a quoted delimiter as syntax.

```recurloop
import language-kit
let DemoGrammar = phrase { dictionary = true }
let install_demo_grammar = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        LanguageKit:define_token(state, context:phrase:find(state, \"DemoGrammar\"), \"+\", 4)
    }
}
install_demo_grammar
let DemoGrammar:\"⊕\" = <DemoGrammar:\"+\">
let check_alias = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let grammar = context:phrase:find(state, \"DemoGrammar\")
        let reader = LanguageKit:SliceReader:new_phrases(state, grammar, \"⊕\", 3, 0)
        if !reader { context:diagnostic:error(state, \"reader allocation failed\"); return }
        defer reader.destroy()
        if !reader.is(\"+\") { context:diagnostic:error(state, \"alias did not resolve\") }
    }
}
check_alias
```

The slice length is in UTF-8 bytes: `⊕` occupies three. `is` checks without consuming. `take_canonical` consumes and returns an owned canonical token spelling, which must be freed. `new_phrases` requires a valid grammar identifier; null is not an implicit default grammar.

## Choose the matching source boundary

Use `Reader:new_phrases` to consume the live source instead. A `SliceReader:new_source` supports lookahead over the current source origin; its cursor is independent. Keep any source refill or cursor-commit policy explicit in a syntax action."
    }
]
