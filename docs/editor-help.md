# Help in the editor

Hover shows a short description and one example. Completion and signature help
show syntax and named arguments. **RecurLoop: Help** searches names, short
summaries and author-provided tags; selecting an entry inserts its snippet or
opens its help card when no snippet is provided.

Describe a custom phrase with an ordinary dictionary:

```recurloop
syntax show <value:id> => print Values:${value}
let ShowHelp = [
    summary = phrase { payload = "Print a named value." }
    snippet = phrase { payload = "${phrase} ${1:answer}" }
    example = phrase { payload = "show answer" }
    arguments = [
        value = phrase { dictionary = true docs = "A name from Values." }
    ]
]
let ShowHelp:arguments:value:dictionary = <Values>
set show.help = <ShowHelp>
```

`Values` must already exist. See the runnable
[example](../examples/03-phrases-and-syntax/editor-help/main.rl).

Every entry is optional. Text is stored in a data phrase's `payload`, so it
survives engine export/import. `arguments` keys match capture names. An argument
may select a `dictionary` reference, a `prototype` reference, or a `kind` text
phrase; selectors intersect. Without selectors, the editor offers a capture
placeholder rather than guessing suitable values. A `tags` text phrase adds
search terms. Keep `docs` to the effect and one caveat; use one small example.

`syntax` supplies the pattern automatically. A phrase implemented by an opaque
action can supply a `pattern` text phrase using the same capture, optional and
choice notation. That pattern describes help; it does not change the action's
parser. Its author must keep both consistent. The pattern excludes the owning
phrase's spelling.

`${phrase}` in a snippet uses the invoked name, including aliases. Other
placeholders use VS Code syntax (`${1:name}`, `${2|a,b|}`, `${0}`). Escape a
literal dollar sign in a snippet with `\\$` in its RecurLoop string.

Aliases inherit contracts through their prototypes, including argument docs
and selectors. Use `set show.help = none` to remove inherited help, or attach
another dictionary to replace it. Contracts can also be attached when creating
a phrase: `phrase { help = <ShowHelp> ... }`.

The editor inspects the source prefix at the cursor. Suggestions come from
actual phrase matches and the shared pattern matcher, including every viable
optional/choice branch. At a phrase boundary it enumerates the active dictionary
or an explicitly qualified dictionary. It does not rank usage frequency or
assume a particular standard language. Incomplete or opaque parser state may
provide less information; writing a contract supplies the missing guidance.

Patterns allow up to 512 items and 64 nested groups. Completion scans at most
16 MiB and 65,536 matcher steps; exceeding the work budget returns no hints.
