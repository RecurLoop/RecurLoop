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

RecurLoop currently targets Linux. It requires CMake 3.28+, Ninja, Clang with
lld, and a C++23 standard library.

```bash
make build
make examples
make test
```

The default Debug build is written below `build/Debug/`:

- executable: `build/Debug/bin/recurloop`
- libraries: `build/Debug/lib/`
- unit tests and benchmarks: `build/Debug/tests/`
- CMake state and `compile_commands.json`: `build/Debug/`

Downloaded dependency sources are shared by all configurations in
`build/_deps/`. Generated dependency objects remain configuration-local.

Use a separate directory for another configuration:

```bash
make release
```

`make release` enables the LLVM backend and writes to `build/Release/`. CMake
itself defaults LLVM to `OFF` for every configuration; pass
`-DRECURLOOP_ENABLE_LLVM=ON` explicitly when configuring without Make.
Other build types use the same `build/<CMAKE_BUILD_TYPE>/` layout.

The first test-enabled configure may download GoogleTest and Google Benchmark.
For an offline host-only build, use `make build ENABLE_TESTS=OFF`.

Useful targets:

| Change | Verification |
|---|---|
| `source/radix` | `make unit` |
| `source/lexicon`, `source/context`, `source/compiler` | `make showcase` and `make test` |
| `source/recurloop` | `make showcase`, `make examples`, and `make test` |
| CLI behavior | `make feature` |
| examples or documentation | `make examples` |

## Source layout

The static-library dependency order is:

`UtilitiesLib` → `RadixLib` → `LexiconLib` → `ContextLib` → `CompilerLib` →
`RecurloopLib` → `Recurloop`.

- `source/`, `include/` — C++ host implementation and public headers.
- `cmake/` — tracked CMake modules; generated build files never go here.
- `tests/` — unit, feature, benchmark, and LLVM-backend tests.
- `examples/` — numbered learning path and larger applications.
- `docs/` — maintained design and language documentation.

## Conventions

- Use C++23 for C++ and C17 for C.
- Follow `.clang-format` and the existing `DECLARATION`/`INLINE` header pattern.
- Preserve user changes in a dirty worktree.
- Do not create branches or commits unless explicitly requested.
- Engine images store stable action names and phrase identifiers. Never persist
  process-local pointers, function addresses, or transient JIT state.
- `--import` must appear before source arguments that depend on the image.
