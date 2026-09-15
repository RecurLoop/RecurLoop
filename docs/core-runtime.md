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

## Clean-build seed

A completely clean checkout has no previous `core.rli`, so the build contains a
private, non-installed stage-0 seed. Its C++ definition lives only under
`bootstrap/` and is not linked into the production runtime.

The seed contains only the phrase-type kernel, structural brace markers,
whitespace and `engine define`. It does not contain the standard language or a
compiler registry.

```text
empty kernel
  -> bootstrap::SeedLanguage::setup()      (bootstrap/ only)
  -> seed.rli
```

The private core runner restores `seed.rli` exactly, without the compatibility
compiler/value defaults that normal runtime image restore may provide. The seed
exists only so RecurLoop can enter the semantic `engine define { ... }` block in
`core.rl`.

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
by that newly built language and the result is exported as `core.rli`.

### Source-owned compiler registry schema

`core/compiler.rl` also owns the physical compiler-registry schema. It declares
the language-registry root, registry keys, setting/counter slots and defaults,
and the ABI-kind mapping. The image stores stable semantic role metadata beside
those source-chosen keys. Production `LanguageState` and `TypeRegistry` locate
registry objects through those roles; they do not spell the physical keys.

The C++ side still implements typed compiler algorithms and payload codecs at
this stage. Moving those algorithms/actions into `core.rli` is a later
self-hosting step; source ownership here means the lexicon topology/layout is no
longer a production-C++ schema.

## Self-hosting fixed point

The build intentionally does **not** require the seed to equal the final core.
Instead it proves that the source-built language reproduces itself:

```text
seed.rli + core.rl -> core.rli
core.rli + core.rl -> core-2.rli

core.rli == core-2.rli
```

A one-byte difference between `core.rli` and `core-2.rli` fails the build. A
separate build-time guard also fails if `seed.rli` is equal to, or not smaller
than, `core.rli`; this prevents accidental regression to bootstrap parity. The
source tree is still scanned to reject dump-like core declarations.

Only `core.rli` is embedded in the final executable:

```text
minimal C++ seed
  -> seed.rli
  -> core.rl
  -> core.rli
  -> core.rl
  -> core-2.rli
  -> byte-for-byte core/core fixed point
  -> embed core.rli
  -> final recurloop
```

The production `RecurloopLib` contains the kernel/runtime/Host ABI and the
semantic `engine define` interpreter, but not the C++ standard-language setup or
seed language.

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
  -> restore embedded core.rli
  -> bind process-local ContextAPI/native symbols
  -> process CLI operations
```

Stable action-name bindings are kernel state, not hidden phrases in the radix
lexicon and not serialized `.rli` data. `--reset` replaces the language graph
while restoring only the baseline Host ABI action set.
