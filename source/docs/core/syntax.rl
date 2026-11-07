// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:syntax = [
    id = phrase { payload = "syntax" }
    title = phrase { payload = "Syntax extensions" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "170" }
    body = phrase {
        payload = "Syntax extensions build on [Phrases](phrase-model.rl). Begin with a rewrite; use an action only when the construct needs direct access to captures or emission.

## Declare a rewrite

Syntax fields and parser behaviors are phrases, so source can alias or install
statements, operators, delimiters, type spellings, assembler mnemonics, and
whole block rewrites. A compiled function with the exact signature
`(Context*, Phrase*) -> void` can act as a phrase action.

For ordinary language construction, `syntax` provides a declarative layer over
the same phrase/rewrite machinery. Layout between pattern items is ignored by
default. Named captures can parse expressions, blocks, identifiers, tokens, or
raw source:

```recurloop
syntax unless <condition:expr> <body:block> => if !(${condition}) ${body}
```

## Captures, choices and layout

The resulting phrase is serializable and rewritable, so the construct works at
top level and while compiled `fn` bodies are expanded. Optional pattern parts
use `[ ... ]`, choices use `(left | right)`, and exact punctuation can be
quoted. Common capture matchers are `expr`, `block`, `id`, `qualified-id`,
`token`, `string`, `number`, `raw`, `code`, and `rest`. Explicit layout controls
include `<whitespaces:ignore>`, `<space:required>`, `<space:none>`, and
`<line:newline>`.

Captures use the active phrase delimiters: aliases of grouping and block
boundaries work in patterns and `${body.body}` replacements as well as in the
native compiler. `token` captures the longest registered phrase, and `number`
uses the shared literal scanner. `raw` and `code` capture opaque bytes through
the next pattern item (or the physical line end for a final capture); `code`
preserves captured spacing. They accept syntax that does not follow the host's
quote, comment or bracket rules.

## Extend or replace an existing form

`syntax extend` adds a higher-priority pattern while preserving the previous
definition as a fallback when the new pattern does not match. `syntax replace`
intentionally shadows an existing spelling and treats a pattern mismatch as an
error. `as <phrase>` validates the declared pattern and reuses an existing
phrase's semantics. At top level the target phrase consumes the validated source tail directly; inside
compiled functions the target spelling and the same tail are handed back to the
ordinary function grammar. This is useful when changing the root spelling or
adding delimiters while keeping the target phrase's remaining source shape:

```recurloop
syntax replace if \"(\" <condition:expr> \")\" <body:block> [else <rejected:block>] as <if>
```

## Implement a syntax action

For constructs that cannot be expressed as a rewrite, `action fn` is the escape
hatch. The action reads named matches through `context:syntax:capture` and
`context:syntax:capture:exists`; during compiled-function expansion it can use
the existing `context:syntax:*` emission API.

The public Context API exposes named operations for phrase lookup, definition,
metadata, payloads, child iteration, source capture, diagnostics, and syntax
emission. Low-level variants accept explicit owners, offsets, bit lengths,
flags, and call modes. The API reference lists the `context:syntax:*` and `context:phrase:*` operations. Use [LanguageKit grammar parsing](../../../libraries/language-kit/docs/phrase-readers.rl) when extending a vocabulary with phrase-aware readers."
    }
]
