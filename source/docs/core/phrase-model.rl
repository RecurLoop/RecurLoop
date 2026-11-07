// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:phrases = [
    id = phrase { payload = "phrases" }
    title = phrase { payload = "Phrases" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "150" }
    body = phrase {
        payload = "A phrase connects a name with data, a dictionary, or an action. Language constructs and application names share this mechanism. The active dictionary resolves the longest registered match; qualification selects the dictionary to search.

## Names and dictionaries

`let` defines language phrases rather than runtime values.

```recurloop
let Math = [
    double = fn (value:i64) -> i64 { return value * 2 }
]
assert Math:double(21) == 42
```

`[...]` creates a nested dictionary. `:` traverses dictionary paths. Phrase
keys are byte or bit strings and are not limited to C identifiers. A reference
such as `<if>` returns a phrase that can be used as a prototype.

## Aliases and scoped definitions

Aliases inherit behavior:

```recurloop
let branch = <if>
let otherwise = <else>
let done = <return>
let plus = <+>
```

An explicit `{ ... }` phrase block creates a lexicon checkpoint; phrases added
inside it disappear when the block ends. This is independent of runtime value
scopes.

## Phrase descriptors

Phrase descriptors can protect public language contracts and expose the same
phrase to compiled-function expansion:

```recurloop
let command = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        // Elaborate top-level source or emit core fn source.
    }
}
```

Aliases created with `<phrase>` or `context:phrase:define:alias` retain the
source phrase's native rewrite flag. Root rewrites respect `:` and `.`
qualification boundaries; a bare rewrite does not replace a component of a
resolved qualified function name. A colon introducing a type annotation still
allows the type's rewrite.

## Permanent and rewritable phrases

A permanent phrase cannot be redefined or modified. A rewritable root
phrase is matched directly while an `fn` body is expanded; there is no second
copy in a function-specific dictionary."
    }
]
