# AGENTS.md

Repository guidance for AI agents and contributors.

## Project

RecurLoop is an experimental system for building programming languages where
named phrases form both a program and its grammar. Source is resolved by
longest-prefix matching in the active dictionary. The C++ host implements the
radix store, phrase graph, runtime context, compiler, native output, and
command-line interface.

Start with `README.md`, `docs/architecture.md`, and `docs/language.md`.

## Build and test

RecurLoop uses CMake presets. Development requires CMake 3.25+, Ninja, Clang,
and a C++23 standard library. LLVM is a binary dependency and is never built
from source by RecurLoop.

Normal command-line work uses optimized hosts:

```bash
make build
make check
```

`make build`/`make check` use `RECURLOOP_LLVM_PROVIDER=AUTO`: a valid cached
checksum-pinned LLVM 22.1.8 archive is preferred, then a compatible installed
LLVM 22.x, and only when neither is available is the pinned archive downloaded
below `.cache/deps/`. Debian/Ubuntu developers can force the distro toolchain
with `RECURLOOP_LLVM_PROVIDER=SYSTEM` after installing
`llvm-22 llvm-22-dev clang-22 lld-22`.
Do not add an LLVM source build back to the ordinary CMake/Ninja graph.

C++ debugging uses the `debug` preset (`build/Debug`, LLVM off):

```bash
cmake --preset debug
cmake --build --preset debug --target Recurloop
```

Production verification uses `RECURLOOP_LLVM_PROVIDER=ARCHIVE`, exact LLVM
22.1.8 release URL/SHA-256 and native-only backend linking. `make package`
stages and tests the Linux x86-64 glibc artifact. Graphics extras remain
opt-in. See `docs/releases.md` for platform contracts and container strategy.

| Change | Verification |
|---|---|
| ordinary local change | `make check` |
| unit/feature behavior across the production backend | `make test` |
| libraries/examples/core/bootstrap or broad integration | `make verify` |
| standard-library images only | `make libraries` |

`make libraries` produces `language-kit`, `shell`, `inferred`, `http`, `gui`,
`ide`, `project`, and `embed`. `make install` installs the host and those images;
Clang/LLD are not bundled. The linked LLVM JIT/backend is in-process; native object/executable file output
intentionally uses host LLD/Clang rather than bundling a platform toolchain.

GoogleTest/Benchmark sources are cached below `.cache/deps/`. `make bundle`
creates a review zip without build trees/caches/debug output.

## Source layout

The static-library dependency order is:

`UtilitiesLib` → `RadixLib` → `LexiconLib` → `ContextLib` → `CompilerLib` →
`RecurloopLib` → `Recurloop`.

- `source/`, `include/` — C++ host implementation and public headers.
- `cmake/` — tracked CMake modules; generated build files never go here.
- `tests/` — unit, feature, benchmark, and LLVM-backend tests.
- `libraries/` — reusable RecurLoop source libraries and the semantic core.
- `examples/` — numbered learning path, showcases, and workflow fixtures.
- `docs/` — maintained design and language documentation.

## Conventions

- Use C++23 for C++ and C17 for C.
- Follow `.clang-format` and the existing `DECLARATION`/`INLINE` header pattern.
- Preserve user changes in a dirty worktree.
- Do not create branches or commits unless explicitly requested.
- Engine images store stable action names and phrase identifiers. Never persist
  process-local pointers, function addresses, or transient JIT state.
- `--import` must appear before source arguments that depend on the image.
