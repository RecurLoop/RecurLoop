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

There is no independent fixed grammar above this process. Built-in syntax is a
set of phrases installed by `recurloop::Language`; source-defined phrases use
the same lookup and dispatch path.

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
staging/reference stacks. Process-local compilation futures are kept outside
the serializable phrase graph.

### Compiler

`source/compiler` defines typed functions, ABI lowering, native modules,
sections, symbols, relocations, ELF readers/writers, archive loading, static
linking, dynamic linking, and JIT linking. `LanguageState` stores types,
functions, native modules, link inputs, and output policy in the lexicon.

### RecurLoop language layer

`source/recurloop` installs core phrases and implements expressions, blocks,
functions, type syntax, syntax extensions, the assembler, engine images,
translation units, output directives, and the debugger.

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
