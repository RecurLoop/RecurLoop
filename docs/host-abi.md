# Frozen Host ABI

The production RecurLoop host is a kernel and backend boundary. New language
constructs, compiler registries and compiler working collections must not require
new C++ state or a second semantic store.

## Canonical semantic state

`context.lexicon` is the one persistent/indexed semantic graph. `core.rli` owns
the standard language, compiler-registry schema, source-defined control flow,
compiled source actions, typed declarations and compiler collection code.

A clean build uses a private minimal C++ seed only to enter `engine define`:

```text
minimal seed -> core.rl -> core.rli -> core.rl -> core-2.rli
                         core.rli == core-2.rli
```

Only `core.rli` is embedded in the production executable.

## Runtime memory versus semantic state

Compiled `fn` code executes as generated native/LLVM code. Ordinary locals,
blocks, `if`, `while`, heap objects and collection instances are runtime memory,
not lexicon transactions. A compiled function touches `Context`/lexicon only
when it explicitly invokes a Context API.

Compiler scratch structures are implemented in `core/collections.rl` using the
raw memory boundary (`allocate`, `reallocate`, `release`, `copy`, `move`). The
source core provides `ByteBuffer`, `U64Vector`, `U64Deque`, `U64Map` and an arena.
Named/serializable compiler state remains in the lexicon.

## Actions

Actions that are expressible without private C++ compiler state are compiled as
ordinary RecurLoop `fn(Context*, Phrase*)` implementations and persisted in
`core.rli`. Final core phrases no longer reference the migrated callbacks
directly. The process-local action-name registry still retains the corresponding
build-compatibility names because the public `recurloop --file core.rl` path must
be able to materialize a fresh core before `core/actions.rl` rebinds those phrases
to their compiled source implementations. The final image does not depend on
those compatibility callbacks after the binding pass.

`core/host-actions.allow` is the reviewed set of direct host actions still used
by the final image. `ValidateSourceActions.cmake` makes that set exact: an
unreviewed new direct action or a stale entry fails the build. This is the frozen
compiler-kernel/backend ABI, not an invitation to add new language semantics to
C++.

The remaining direct actions are existing parser/compiler kernel, assembler,
debugger and process/backend services. `syntax.define` is a generic kernel
mechanism: it compiles declarative syntax patterns into ordinary serializable
phrases; generated patterns use the process-registered `syntax.pattern` action
name when user language images are exported. The mechanism does not hard-code
individual language constructs. RecurLoop extensions should prefer
source-defined phrase actions plus the generic Context API rather than extending
this set.

## Compiler registry

The physical compiler-registry root, child keys, setting slots, counters and ABI
kind mapping are declared by `core/compiler.rl`. Production C++ locates them by
stable semantic roles stored in the lexicon and is forbidden from depending on
the source-selected physical names.

## Images and transactions

Semantic rollback uses radix watermarks. State that must escape a rollback uses
selective promotion (`capture -> rollback -> replay`) with image relocation.
Image payload schemas distinguish relocatable phrase references from native
process pointers, so source-defined object graphs can round-trip safely.

## Backend boundary

LLVM's C++ API is confined to `source/recurloop/LlvmBackend.cpp`. Both the
built-in generator and LLVM consume the compiler's typed statement/expression
representation; LLVM does not parse RecurLoop source or own compiler-registry
schema. The build audit fails if LLVM headers/namespaces leak into another
production source file.

Assembler encoding, debugger/process control, executable memory, filesystem/IO,
native calls and LLVM/toolchain integration remain intentional host/backend
responsibilities.

## Freeze rule

After this boundary is established, ordinary language/compiler evolution should
happen in `.rl`/`.rli`. C++ changes are reserved for kernel bugs, platform/backend
ports, new generic host mechanisms, or deliberate Host ABI revisions. Adding a
new registry, parser construct or ordinary compiler collection is not a Host ABI
revision.
