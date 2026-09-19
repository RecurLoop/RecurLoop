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

RecurLoop's current runtime/native output targets Linux, while the build
orchestration uses CMake presets so it can be reused on other hosts as runtime
backends are ported. Development requires CMake 3.25+, Ninja, Clang, and a C++23
standard library. Python is not part of the build/check/package toolchain.

Normal command-line work uses optimized hosts:

```bash
make build
make check
```

`make build` and `make check` use the same optimized `build/Release` tree with
LLVM enabled. Their toolchain policy is `AUTO`: prefer the already prepared
pinned LLVM/zlib/zstd toolchain, otherwise use a compatible system LLVM and
system compression libraries. Incremental check selection is expressed in the
CMake/Ninja graph itself: unit stamps depend on unit executables and feature /
example stamps use explicit CMake `DEPENDS` inputs. Do not add filename, git-diff,
or test-timing heuristics to `make check`. Do not replace it with a Debug build:
running `.rl` workloads on an `-O0` host is intentionally avoided.

C++ debugging is separate from Make. VS Code/CMake Tools uses the `debug` preset
(`build/Debug`, LLVM off) together with LLDB. The portable equivalent is:

```bash
cmake --preset debug
cmake --build --preset debug --target Recurloop
```

Production verification uses Release + LLVM. `make release` and `make verify`
force the exact pinned LLVM 22.1.8, zlib 1.3.1, and zstd 1.5.7 toolchain:

| Change | Verification |
|---|---|
| ordinary local change | `make check` |
| unit/feature behavior across the production backend | `make test` |
| libraries/examples/core/bootstrap or broad integration | `make verify` |
| standard-library images only | `make libraries` |

`make libraries` writes `language-kit.rli`, `shell.rli`, `inferred.rli`, and
`http.rli` below `build/Release/libraries/`. `make install` installs the Release
binary and those compiled images using normal CMake/GNUInstallDirs semantics;
`PREFIX=/usr DESTDIR=/tmp/pkg` is the packaging/staging form.

Dependency sources are cached once below `.cache/deps/` and shared by all
presets. Pinned LLVM is an upstream prebuilt archive; pinned zlib/zstd are built
once in a separate helper build below `.cache/deps/` and imported into the main
project, so they do not appear in RecurLoop's normal Ninja graph. AUTO builds
prefer that cache and fall back to compatible system packages.
GoogleTest/Benchmark keep configuration-local build artifacts while reusing the
same downloaded sources. Google Benchmark is opt-in through `make benchmark`.
`make bundle` creates a compact review zip without `.git`, build trees, caches,
or debug output and includes a source-matched cached core image when available.
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
