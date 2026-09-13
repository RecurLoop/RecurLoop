# Source-defined RecurLoop core

This directory is the migration path from the compatibility C++ language to a
small fixed host bootstrap plus source libraries.

The host bootstrap is selected explicitly with `--bootstrap`.  It contains only
the implementation language needed to author libraries: native typed
functions/declarations, expressions, structured function control flow,
`let`, `phrase`, phrase references, `include`, engine image operations, and the
Context API.  It does **not** install the debugger, assembler language, emit
commands, lexicon merge syntax, or the normal compatibility surface.

The source layers are deliberately small and readable:

- `bootstrap/seed.rl` defines the irreducible source surface: `proc`, `form`,
  and the first self-hosted `shape` form.
- `core/10-support.rl` provides reusable buffers/scanning helpers.
- `core/20-language-support.rl` provides source translation/control helpers.
- `core/30-records.rl` defines record parsing/layout from ContextAPI primitives.
- `core/40-functions.rl` defines the function declaration shell.
- `core/50-program.rl` defines the top-level `recur` form and exports
  `/tmp/recurloop-core.rli`.

Build and verify:

```sh
make minimal-core
make minimal-core-test
```

or directly:

```sh
build/Debug/bin/recurloop --bootstrap --file libraries/recurloop/core.rl
build/Debug/bin/recurloop --bootstrap --import /tmp/recurloop-core.rli \
  --file libraries/recurloop/tests/functions-control.rl
```

The old language remains the default compatibility path.  It should only be
removed after source libraries reach feature parity and the old complete test
suite remains green.
