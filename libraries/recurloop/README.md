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
make core-parity
make bootstrap-contract
```

After the image exists, run it without installing the compatibility language:

```sh
build/Debug/bin/recurloop --language-image /tmp/recurloop-core.rli \
  --file libraries/recurloop/tests/functions-control.rl
```

`--language-image` starts from the fixed bootstrap ABI and restores the source-defined
language image directly. It does not call the normal compatibility `Language::setup`.
The parity target currently covers eight areas. Four use the real getting-started examples as the compatibility reference: functions/recursion, ordinary control flow, records/methods, and lifetime/null. Focused cases additionally cover defer ordering, function values, pointer/null expressions, and native extern interop. See `PARITY.md`.

or directly:

```sh
build/Debug/bin/recurloop --bootstrap --file libraries/recurloop/core.rl
build/Debug/bin/recurloop --bootstrap --import /tmp/recurloop-core.rli \
  --file libraries/recurloop/tests/functions-control.rl
```

The fixed host surface is owned by `BootstrapLanguage::setup()` and is tested independently by `make bootstrap-contract`. The old language remains the default compatibility path.  It should only be
removed feature-by-feature after `core-parity`, the old complete test suite, and
all examples remain green.  The overlay applier supports explicit file deletion,
but no C++ language implementation is removed before that condition is met.
