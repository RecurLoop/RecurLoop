# Architecture

RecurLoop is split into six host layers. Each layer is a static library, and
dependencies point only toward lower layers.

```text
utilities → radix → lexicon → context → compiler → recurloop → CLI
```

## Execution flow

1. The CLI converts files, strings, or standard input into a `Context::Source`.
2. `Source` performs longest-prefix matching in the current dictionary.
3. The matched `Phrase` is elaborated or invoked according to its type.
4. The phrase may consume more source, update the lexicon, evaluate values, or
   emit native code.
5. Scoped dictionaries and value scopes are restored when their owning block
   ends.

There is no independent fixed grammar above this process. The final executable
restores its standard language from the embedded `core.rli`; source-defined
phrases and the standard language use the same lookup and dispatch path. The
legacy `recurloop::Language` builder exists only as a private clean-build tool
while the remaining language subsystems migrate to source libraries.

## Layers

### Utilities

`source/utilities` provides byte/bit views, append-only buffers, status and
exception helpers, executable memory, logging, and profiling support.

### Radix

`source/radix` stores bit-string keys in one flat caller-owned buffer. Nodes
and items are addressed by offsets, not C++ pointers. The layer supports exact,
first, and longest matching plus checkpoints used for rollback.

### Lexicon

`source/lexicon` maps radix items to phrases. A phrase may contain a parent,
prototype, type, successor, action, payload, and subdictionary. `Draft`
constructs phrases while preserving the metadata layout.

### Context

`source/context` owns one execution state: configuration, input, streams,
lexicon, runtime values, JIT memory, compiler workspace, lookup state, and
staging/reference stacks. Process-local compilation futures and the stable
Host ABI action registry are kept outside the serializable phrase graph.

### Compiler

`source/compiler` defines typed functions, ABI lowering, native modules,
sections, symbols, relocations, ELF readers/writers, archive loading, static
linking, dynamic linking, and JIT linking. `LanguageState` stores types,
functions, native modules, link inputs, and output policy in the lexicon.

### RecurLoop runtime layer

`source/recurloop` contains the runtime/image bridge, semantic source-core
interpreter, Host ABI actions, compiler-facing language services, and native
backend integration. The standard-language construction itself is not part of
the production runtime. `bootstrap/` contains only a minimal C++ seed capable
of entering the semantic `engine define` block; the canonical language
definition lives under `libraries/recurloop/core/`. The installed executable
starts from Host ABI registration plus the embedded self-hosted `core.rli`.

## Native module flow

Typed `fn` definitions and compiled phrase actions produce `compiler::Module`
instances through LLVM when it is enabled and through the built-in backend
otherwise. A module contains sections, symbols, and relocations. Depending on
the directive, it is:

- linked into executable memory for immediate invocation;
- serialized as an ELF64 relocatable object;
- combined with objects/archives into an executable;
- combined with LLVM-generated objects for optimized native output.

LLVM is a conditional implementation layer rather than part of the language
model. CMake keeps it disabled by default, while `make release` enables it.
Handwritten `asm` blocks retain their exact x86-64 instruction semantics; in
an LLVM build they still use the LLVM object/link toolchain, but their
instructions are not rewritten as optimizer IR.

The language state controls automatic dependency closure, manual includes and
excludes, entry selection, external link inputs, shared libraries, and whether
language metadata is embedded.

## Persistence boundary

Portable state uses identifiers and stable action names. Runtime addresses,
JIT mappings, in-flight compilation jobs, open streams, and C++ exceptions are
process-local and must be rebuilt or cleared after an image import.

See [engine-images.md](engine-images.md), [radix-tree.md](radix-tree.md),
[lexicon.md](lexicon.md), [context.md](context.md), and [memory.md](memory.md).
