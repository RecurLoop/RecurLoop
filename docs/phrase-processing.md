# Phrase processing and native compilation

Source recognition belongs to the active lexicon. Use `matchLongest` to choose
an eligible phrase, invoke its action, and let that action consume source or
lower it to native compiler operations. Grammar extensions must not introduce
an evaluator that walks a language-specific syntax tree on every execution.

## Processing boundaries

| Component | Role and boundary |
| --- | --- |
| `context::Source`, `Recurloop` | Streamed longest-prefix lookup and phrase dispatch. |
| `LanguageGrammar` | Shared longest matching, prototype resolution and filters. A rejected longer candidate must reveal shorter eligible candidates. `peekLongest` refills streamed input without consuming it. |
| `SyntaxCursor` | Phrase-backed tokens with native number, identifier and string-data fallbacks. Registered spellings precede those fallbacks; literal contents are never syntax tokens. Leading layout may belong to a registered phrase. |
| `SyntaxPattern` | The `syntax` declaration's pattern notation and capture matcher. Target-language block/group delimiters and token spellings come from the active phrase graph. Captures and editor expectations use the same matcher. |
| `PhraseNames`, `PhraseDefinition` | Shared phrase-name grammar for declarations and descriptor references, including quoted components and interpolation. Descriptor field aliases are longest-matched phrases. |
| `ExpressionParser`, `TypeSyntax` | Phrase parselets provide immediate value elaboration and type recognition. This immediate expression path serves staging and interactive actions; it is distinct from native function compilation. |
| `FunctionsParser`, `FunctionsGenerator`, `LlvmBackend` | Phrase parselets lower to temporary native compiler expressions/statements; both backends consume that representation. User syntax can lower through rewrites and compiled phrase actions. |
| `LanguageKit:Cursor`, phrase readers | Bounded and streamed longest lookup, inherited token identity, serializable token classes and explicit grammar selection. Native lexical-data helpers also remain available. |
| `HttpSyntax` | The routing grammar is `HttpSyntax:Grammar`. Aliases lower to canonical native server setup; native inline handlers use shared, non-executing block recognition. Wire HTTP parsing remains protocol data processing. |
| `Inferred` | Its grammar spellings and infix operation/precedence descriptors are serializable phrases. The temporary specialization tree lowers to typed native functions; subsequent calls use the cached native entry. |

The native data scanners, stage-0 `engine define` reader, ELF/ABI/assembler
machinery, CLI options and transport protocols remain host mechanisms. They
must not be used to reserve additional spellings in a user language. In
particular, a longer registered phrase starting with `//` or `/*` takes priority
over the standard comment opener.

A block capture recognizes aliases of `{` and `}`; expression captures balance
aliases of `()`, `[]` and `{}` with a matching closing stack. `${body.body}` strips
the actual matched delimiters, including multi-byte or word spellings. A `token`
capture consumes the longest registered key. A `number` capture uses the shared
number scanner, including base prefixes, fractions and exponents. `raw` and
`code` are opaque byte captures: they impose no host quote, comment or delimiter
rules. A following pattern item delimits the capture; a final capture ends at the
physical line boundary. `raw` trims its result; `code` preserves its captured
bytes. Use explicit layout controls when initial whitespace is part of the data.
Surrounding block/expression scanners recognize complete declared syntax phrases
without invoking their actions, so opaque payloads can contain host delimiters
inside native functions too.

## Building a native grammar in source

Use `LanguageKit:Cursor:phrase_at(state, grammar, source, length, position)`
for bounded, non-consuming lookup, and `Cursor:match_phrase` to consume a phrase
that inherits an expected grammar entry. Trivia is recognized through grammar
phrases and prototype aliases; longer registered phrases precede comment and
whitespace fallbacks. The slice coordinates are **bytes**.
`LanguageKit:Source:phrase_at` provides non-consuming lookup over streamed source;
it reacquires the source pointer after refill and sizes lookahead from the active
grammar. `LanguageKit:phrase_child` finds inherited grammar metadata, with cycle
detection.

`Reader:new_phrases(state, grammar, flags)` and
`SliceReader:new_phrases(state, grammar, source, length, flags)` provide the same
phrase-backed token interface for streamed and bounded source. Syntax checks use
phrase identity; quoted data never becomes a keyword or delimiter. Define token
classes with `LanguageKit:define_token(state, grammar, key, kind)` (1 identifier,
4 operator, 5 punctuation, 6 newline). The descriptor is an eight-byte integer
owned by the grammar phrase. Aliases inherit it. `take_canonical` returns owned
canonical token text; data identifiers retain their spelling. Numbers and quoted
text remain lexical data fallbacks. An unregistered punctuation/operator byte
reports an error rather than creating an implicit grammar token. Flags 8 and 256
enable phrase line/block comments; longer registered keys take priority. The
optional `fallback` dictionary is explicit and competes by key length, with the
selected grammar winning equal lengths.

`SliceReader:new_source(state, grammar, flags)` provides non-consuming lookahead
over live input with the same interface. It refills on demand, reacquires source
pointers, and keeps byte positions relative to the current source origin. Commit
the final position with `context:source:advance`; avoid advancing live input while
that reader is active. Amber uses it for assignments, arrays and echo arguments,
without fixed lookahead limits.

`LanguageKit:define_infix(state, grammar, key, operation, precedence, right)`
stores three integer values on a token: the library's operation identifier,
binding power and right-associativity flag. `infix_value` reads inherited fields.
A token with its own dictionary can override these fields; repeated definitions
update the existing payload. The Haskell and Erlang compatibility builders use
this metadata in precedence-climbing recognition. Identifier flags 16 and 32
also apply to phrase boundaries, protecting apostrophes and `@` within names.

`LanguageKit:Source:take_form(state, grammar, terminator, flags, quote, include_end)`
uses the streaming phrase reader to capture a tokenized form, balancing grammar
groups and recognizing terminator aliases. It returns normalized source, omits
comments, and escapes quoted data again using the requested quote byte. It has
no fixed statement-size limit. Prolog and Erlang use this compatibility capture;
opaque native DSL payloads use `raw`/`code` captures instead.

`context:source:block:capture(state, grammar)` captures a streamed block using an
explicit grammar plus native root phrases. The bounded
`context:syntax:block:extent(state, source, bytes, position)` returns the byte
offset immediately after a complete native block, or zero on failure. It neither
consumes live source nor invokes phrase actions. HTTP uses this mechanism to
protect complete declared syntax, including opaque captures, inside native
handlers instead of counting braces independently.

Compiled phrase actions can publish their recognition boundary with
`context:syntax:describe(state, phrase, pattern, grammar)`. The phrase must own a
dictionary. The descriptor stores the pattern and a relocatable grammar phrase
reference, not a native callback address. Surrounding block/expression capture
uses it without invoking the action; aliases inherit the description. The
selected grammar competes with native root phrases by longest key, and literal
pattern items recognize inherited grammar identity. The action still performs
its normal native lowering. HTTP publishes
`[once] [<address:string>] <port:number> [limits <limits:block>] <routes:block>`
against `HttpSyntax:Grammar`, so comments and delimiters local to HTTP cannot
terminate an enclosing native function accidentally.

Inferred exposes its token dictionary as `Inferred:Grammar:Tokens`:

```rl
let Inferred:Grammar:Tokens:done = <Inferred:Grammar:Tokens:return>
let Inferred:Grammar:Tokens:plus = phrase {
    dictionary = true
    prototype = <Inferred:Grammar:Tokens:"+">
}
```

A compiled phrase action can call
`Inferred:define_operator(state, "plus", 1, 100)` to select native addition with
precedence 100. An override needs its own dictionary for the `infix` descriptor;
a plain prototype alias inherits its existing descriptor. Descriptors store two
integer values, never native addresses. The regression
`examples/07-workflows/inferred-language/tests/phrase-grammar.infer` exercises
word delimiters, keyword aliases, a Unicode operator, comment aliases and custom
precedence through native specialization.

## Necessary kernel boundaries and compatibility scope

The host compiler's `Expression`/`Statement` types are temporary typed lowering
structures consumed by native backends. They are not a runtime foreign-language
AST evaluator. Native parselets, type syntax, the stage-0 reader and the
meta-syntax of `syntax` remain kernel mechanisms. Extensions can define arbitrary
surface syntax through dictionary phrases, compiled actions and opaque captures,
and lower it to native code. The current implementation does not claim that the
entire compiler IR is phrase-owned.

Core top-level compatibility actions, including `if` and `while`, execute source
through phrase dispatch and immediate expression evaluation. They serve staging
and interactive use. Native `fn` bodies and Inferred specializations use the
compilation path described above.

Inferred's `poly` entry is an ordinary root phrase: longest-prefix lookup selects
it before its action recognizes the remaining form. A longer user root phrase
wins regardless of how many bytes the Inferred parser could consume. `infer`
selects the grammar explicitly; recognition within an explicitly selected block
uses the existing compatibility dispatcher.

The Prolog, Haskell, Erlang and Amber workflows now recognize syntax through
`<Language>:Grammar:Tokens` and the shared phrase readers. Aliases inherit token
identity, so delimiters, separators, keywords and comment markers can change
without editing byte scanners. Haskell and Erlang infix binding powers and
associativity are phrase metadata. Their recursive semantic builders and existing
compatibility runtimes remain; this recognition migration does not turn those
legacy evaluators into native language compilers.

Amber arrays, assignments, `for` headers, echo arguments and outcome bindings use
the same readers. Its command grammar already dispatches phrases with successors.
Native outcome/modifier bodies use shared block extent recognition, and their
source-defined recognition descriptions protect the local header grammar in
surrounding blocks. Native body delimiters are root phrase aliases.

LanguageKit retains the opt-in structural probe dispatcher and older character
reader API for compatibility callers. Its generic expression fallback respects
an explicitly installed language fallback, so Prolog compounds are not claimed
as native expression statements. Protocol, filesystem, transport and native ABI
readers remain data-processing boundaries.
