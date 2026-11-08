// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:metadata = [
    id = phrase { payload = "metadata" }
    title = phrase { payload = "Metadata" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "160" }
    body = phrase {
        payload = "Phrase metadata describes a resolved language or application binding. Keep short help beside its definition and put a longer explanation in a dedicated documentation object.

## Inherit kind, color and documentation

`kind`, `color`, and `docs` are ordinary phrase fields, not an editor-side
registry. Libraries can attach them to language phrases and prototypes; semantic
inspection clients inherit the nearest metadata through the normal prototype
chain. The source-defined IDE uses the same metadata for highlighting and hover
documentation, so custom syntax can describe itself without adding an AST or a
separate IntelliSense grammar.

Inspection resolves metadata after elaboration and applies it to all occurrences
of the resolved binding, including declarations and uses before the assignment.
The final assignment wins for that binding. Local scopes and successive phrase
definitions keep separate identities; prototype metadata is inherited normally.
Setting a color to `\"\"` suppresses both inherited and fallback coloring.

## Document a runtime binding

For a top-level runtime binding, attach documentation after its declaration:

```recurloop
var pi = 3.14
set pi.docs = \"Approximation of π: the ratio of a circle's circumference to its diameter.\"
print pi
```

Runtime inspection links the declaration and expression reads to that binding's
metadata. VS Code shows the description when hovering `pi` at either location.
The same assignment works for a top-level `const` binding.

## Document a local binding

Inside `fn`, documentation belongs to the local binding in its lexical scope:

```recurloop
let example = fn () -> i64 {
    var tick:i64 = 1
    set tick.docs = \"Current iteration number.\"
    set tick.color = \"#FF8800\"
    tick += 1
    return tick
}
assert example() == 2
```

Local `set name.docs = \"...\"` and `set name.color = \"#RRGGBB\"` assignments
require a string literal and are processed during elaboration, without generating
a runtime store. They also work for immutable `let`/`const` bindings, including
local function values. Inspection links declarations, reads and writes to the
same local binding, including uses before the metadata assignment. An empty
color clears explicit coloring. A shadowing declaration has its own metadata,
which does not modify an equally named global binding.

The fields accepted inside `phrase { ... }` are phrases too. Their standard
definitions carry semantic metadata, which means hovering `type`, `prototype`,
`successor`, `action`, `serializable`, and the other descriptor fields explains
the phrase contract directly in the editor.

## Write useful phrase help

Write `docs` as compact Markdown: show the invocation first in a fenced
`recurloop` code block, then explain its effect and any scope restriction.
Add one small example when the signature alone is insufficient. Fenced examples
remain plain text: their language context is not available for runtime inspection
in editor hovers and completions. In signatures, `...`
stands for additional parameters or statements unless described as variadic.

Document public constructs and meaningful grammar variants on their owning
phrases. Aliases inherit those docs through prototypes; override them when an
alias changes the usage. Internal continuation states, whitespace handlers and
compiler implementation hooks do not need independent usage documentation."
    }
]
