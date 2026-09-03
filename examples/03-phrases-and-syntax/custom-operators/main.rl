// =============================================================================
// Phrase-driven language syntax
//
// This example changes the language before compiling the functions below it.
// It reaches the same lexicon that the fn parser, type parser, expression
// parser, and `phrase { ... }` parser use internally.
//
// Expected output:
//   phrase assembled through field aliases
//   42
// =============================================================================

extern puts(text:u8*) -> i32 abi sysv-amd64


// Syntax is ordinary lexicon state. Parser actions, metadata and compiler
// behaviors follow prototypes, so aliases do not copy private parser data or
// hidden emitters. Even punctuation needs only one root phrase.
let bind = <var>
let mutable = <var>
let when = <if>
let change = <set>
let yield = <return>
let gets = <=>
let callable = <fn>
let ptr = <*>
let "%%" = <+>
let kind = <type>
let behavior = <action>
let scope = <dictionary>


// This callable phrase is written using aliases of the ordinary phrase fields.
let assembled_phrase = phrase {
    kind = <phrase-types:callable>
    scope = true
    behavior = fn (state:Context*, called:Phrase*) -> void {
        puts("phrase assembled through field aliases")
    }
}

assembled_phrase


let double_with_aliases = fn (value:i64) -> i64 {
    yield value %% value
}

// Both type constructors below were installed as phrases at elaboration time.
let apply_with_aliases = fn (callback:callable (i64) -> i64, value:i64) -> i64 {
    yield callback(value)
}

let read_with_aliases = fn (value:i64 ptr) -> i64 {
    yield value[0]
}

let phrase_driven_result = fn () -> i64 {
    mutable source = 21
    bind result = apply_with_aliases(double_with_aliases, read_with_aliases(&source))
    when result == 42 {
        change result gets result %% 0
        yield result
    }
    yield 0
}

// `%%` was also added to the top-level expression parser, not only to fn.
assert 20 %% 22 == 42
assert phrase_driven_result() == 42
print phrase_driven_result()
