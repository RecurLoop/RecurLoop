# Core image runtime

RecurLoop has one public runtime model.

```text
host kernel -> embedded core.rli -> optional imports -> source
```

The final executable automatically restores the embedded standard language:

```sh
recurloop --file program.rl
recurloop --import shell.rli --file program.rl
```

`--reset` clears the language state back to the empty host kernel while keeping
the process-local ABI needed to restore engine images:

```sh
recurloop --reset --import core.rli --file program.rl
```

An `.rli` image has no special root/core/bootstrap kind. Its role comes only
from the state into which it is imported.

## Building core

`libraries/recurloop/core.rl` exports the current language state as `core.rli`.
A completely clean project build needs one private bootstrap step because no
previous image exists yet:

```text
C++ compatibility builder
    -> core.rl
    -> generated/core/core.rli
    -> embed exact image bytes
    -> final recurloop
```

`recurloop-core-builder` is a CMake build tool only. It is not installed and has
no separate public bootstrap CLI.

After the final executable exists, rebuilding is self-hosted:

```sh
recurloop --file libraries/recurloop/core.rl
```

or, explicitly using an external previous image:

```sh
recurloop --reset --import core.rli --file libraries/recurloop/core.rl
```

Both forms are required to reproduce the current core image byte-for-byte.

## Public state operations

The public language-state interface is intentionally small:

- `--reset` — clear the current language back to the host kernel;
- `--import <image.rli>` — import an image into the current language state;
- `--file`, `--string`, or stdin — process source using that state.

State selection happens before the first source input. Removed transitional
options (`--bootstrap`, `--language-image`, `--engine-image`) are rejected with
a diagnostic rather than retained as aliases.

## Host ABI boundary

The final runtime does not call `Language::setup()` and does not construct a
temporary compatibility lexicon. Startup is:

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

The private clean-build builder still contains compatibility C++ language
subsystems because a completely clean checkout has no previous `core.rli` yet.
That builder is the remaining migration boundary; it is not used by the final
runtime or translation-unit workers.

Each remaining subsystem is migrated by adding its source implementation to the
core build, verifying tests/examples/image round trips, then deleting the old
C++ implementation. The target is:

```text
C++: kernel + host ABI + image/runtime + compiler/native/LLVM primitives
core.rli: RecurLoop language and language policy
```
