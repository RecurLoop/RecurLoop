# Core image runtime

RecurLoop has one public runtime model:

```text
host kernel -> embedded source-built core.rli -> optional imports -> source
```

The installed executable automatically restores the embedded standard language:

```sh
recurloop --file program.rl
recurloop --import shell.rli --file program.rl
```

`--reset` clears language state back to the empty host kernel while preserving
the process-local ABI needed to restore engine images:

```sh
recurloop --reset --import core.rli --file program.rl
```

An `.rli` image has no special root/core/bootstrap kind. Its role comes from the
state into which it is imported.

## Clean-build bootstrap

A completely clean checkout has no previous `core.rli`, so the build contains a
private, non-installed stage-0 bootstrap. Its C++ language definition lives only
under `bootstrap/` and is not linked into the production runtime.

```text
empty kernel
  -> bootstrap::Language::setup()          (bootstrap/ only)
  -> bootstrap-core.rli
```

`bootstrap-core.rli` exists only so RecurLoop can read the source definition of
the same language.

## Source-defined core

`libraries/recurloop/core.rl` is the canonical language definition. It captures
one semantic `engine define { ... }` declaration, replaces the current lexicon,
and rebuilds a fresh core from symbolic source modules under
`libraries/recurloop/core/`.

The source intentionally does not contain engine-image records such as numeric
phrase ids, numeric parent/prototype references, or serialized hex payloads.
Host implementation details such as C++ `sizeof`, `alignof`, `offsetof`, native
addresses, radix internals, JIT memory, LLVM APIs, and file IO remain Host ABI.
The source names the host primitives and materializes the language-level graph,
calling conventions, compiler types, typed host-function declarations, linker
paths, and compiler settings. C++ supplies only the physical layout facts and
process-local native implementations required by those source declarations.

After the fresh stage-0 graph exists, source-defined `control-flow.rl` is parsed
by that newly built language and the result is exported as `source-core.rli`.

## Fixed point

The build requires both of these comparisons to succeed byte-for-byte:

```text
bootstrap-core.rli == source-core.rli
source-core.rli    == source-core-2.rli
```

A one-byte difference fails the build. The source tree is also scanned to reject
dump-like core declarations before the comparison runs.

Only `source-core.rli` is embedded in the final executable:

```text
C++ bootstrap
  -> bootstrap-core.rli
  -> core.rl
  -> source-core.rli
  -> byte-for-byte fixed point
  -> embed source-core.rli
  -> final recurloop
```

The production `RecurloopLib` contains the kernel/runtime/Host ABI and the
semantic `engine define` interpreter, but not the C++ standard-language setup.

## Self-hosted rebuild

Once the final executable exists, rebuilding core is fully source-driven:

```sh
recurloop --file libraries/recurloop/core.rl
```

or explicitly from an external prior image:

```sh
recurloop --reset --import core.rli --file libraries/recurloop/core.rl
```

Both forms must reproduce the embedded source-built `core.rli` byte-for-byte.

## Public state operations

The public language-state interface is intentionally small:

- `--reset` — clear the current language back to the host kernel;
- `--import <image.rli>` — import an image into the current language state;
- `--file`, `--string`, or stdin — process source using that state.

State selection happens before the first source input. Removed transitional
options (`--bootstrap`, `--language-image`, `--engine-image`) are rejected with
a diagnostic rather than retained as aliases.

## Host ABI boundary

Production startup is:

```text
empty kernel
  -> register process-local Host ABI actions
  -> restore embedded source-core.rli
  -> bind process-local ContextAPI/native symbols
  -> process CLI operations
```

Stable action-name bindings are kernel state, not hidden phrases in the radix
lexicon and not serialized `.rli` data. `--reset` replaces the language graph
while restoring only the baseline Host ABI action set.
