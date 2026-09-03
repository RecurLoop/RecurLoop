# Execution context

`context::Context` is the complete mutable state of one RecurLoop execution.
It is composed rather than inherited, which keeps ownership and persistence
boundaries explicit.

| Component | Responsibility |
|---|---|
| `Config` | Source, lexicon, runtime, workspace, and exception settings |
| `Exec` | Exit status, CLI arguments, current invocation, timing, pending native errors |
| `IOStreams` | Input and output streams |
| `Source` | Current path, line/column, input buffer, and radix matching |
| `Lexicon` | Phrase graph and language-owned persistent state |
| `Values` | Lexically scoped runtime values |
| `Actions` | Stable action-name registry |
| `JitMemory` | Process-local executable mappings |
| `Workspace` | Temporary code, key, data, BSS, and custom sections |
| `Lookup` | Active dictionary and phrase-resolution state |
| `Staging` | Temporary phrase construction state |
| `Reference` | Phrase-reference traversal state |

## Source matching

`Source::matchFirst`, `matchLongest`, and `matchExact` delegate to the active
dictionary. A successful match advances the bit-aware source cursor and
updates line/column information. Longest matching is the normal language
dispatch rule.

Source-defined state-machine grammars can return to the root dictionary with
`context:source:root`. The operation also clears completed lookup frames, so a
phrase grammar can finish without exposing or reconstructing the host lookup
stack.

During compiled-function expansion, `context:syntax:elaborate` drives the same
kind of phrase graph from a selected dictionary: longest-match chooses a
phrase, its action runs, and its `successor` selects the next dictionary. This
keeps extension libraries declarative instead of embedding their own token
loops.

## Runtime values

`Values` stores `null`, boolean, integer, real, and string values in lexical
scopes. It provides define, assign, lookup, and scope push/pop operations.
Values are language state; native stack locals inside compiled functions are
separate machine-level storage.

The public API exposes type-preserving text and integer definitions and
assignments (`context:value:define:*` and `context:value:assign:*`) for compiled
phrase actions that cooperate with the same store.

## Actions and native calls

Phrase actions have the host signature `(Context&, Phrase&)`. Compiled action
implementations use the corresponding public RecurLoop type
`(Context*, Phrase*) -> void`. The action registry maps these behaviors to
stable names for image serialization.

A C++ exception cannot unwind through generated machine code. Native
invocation trampolines capture pending exceptions in `Exec`; the phrase
boundary rethrows them after control returns to the host.

## Serialization

The phrase graph, runtime values stored in it, and `LanguageState` are
serializable. Streams, executable memory, pending exceptions, current phrase
pointers, and translation-unit futures are process-local.
