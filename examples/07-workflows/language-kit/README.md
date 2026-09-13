# RecurLoop LanguageKit

`LanguageKit` is a reusable source-defined substrate for workflows that need to
share source dispatch, symbols, values and callable bindings without adding a
language-specific parser or runtime to the C++ host.

The library provides:

- bounded source access and reusable `Reader` / `SliceReader` / `Cursor` helpers;
- a shared symbol universe and category aliases;
- merged top-level form/fallback arbitration;
- `context:source:hook`-backed pre-dispatch for unambiguous foreign forms;
- a small cross-language value/call ABI;
- deterministic scoped ownership helpers for workflow runtimes.

Build the reusable image:

```bash
build/Debug/bin/recurloop --file examples/07-workflows/language-kit/library.rl
```

This writes `/tmp/recurloop-language-kit.rli`. The image can then be imported by
a source-defined workflow, for example `inferred-language` or the shell workflow.

The host additions used by LanguageKit are generic Context API primitives. The
language-specific grammars, dispatch policy and runtime behavior stay in `.rl`
source.

## Regression check

```bash
examples/07-workflows/language-kit/run-tests.sh build/Debug/bin/recurloop
```

The focused regression verifies that the reusable image builds, imports in a
fresh process, does not steal an ordinary RecurLoop root form, and that migrated
workflows do not reintroduce the removed private Lexer API. The individual
workflow runners contain their semantic regression cases.
