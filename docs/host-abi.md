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

Core expression calls have the same extension boundary. Source libraries can
publish dynamic expression callables through the generic
`context:expression:builtin:*` Context API. The host only transports ordinary
core values and invokes the source-defined phrase action; language-specific
dispatch, specialization and ownership remain in source libraries. LanguageKit
uses this bridge so callables from Inferred and other libraries do not require
language-specific C++ parser branches.

The `expressions.literal.recurloop-version` host action exposes the running
binary's build version as a core string. This host metadata is read on each
evaluation, so an imported language image does not override the host version.

Standalone expressions use that same core parser through the generic
`context:expression:recognizes` probe. The probe parses without evaluation,
source consumption or semantic tracing. LanguageKit registers it alongside its
other fallback grammars; root matching stays ordinary phrase lookup and does
not recognize function-call spellings itself.

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
responsibilities. `context:function:invoke:scalar` is the generic source-facing
entry to the host scalar-call bridge: it accepts an entry address plus a byte
buffer containing a dynamic array of raw machine-word arguments, so source libraries do not need arity-specific
native-call wrappers.

## Freeze rule

After this boundary is established, ordinary language/compiler evolution should
happen in `.rl`/`.rli`. C++ changes are reserved for kernel bugs, platform/backend
ports, new generic host mechanisms, or deliberate Host ABI revisions. Adding a
new registry, parser construct or ordinary compiler collection is not a Host ABI
revision.

## Shared syntax boundaries

`context:syntax:block:extent` exposes the kernel's existing phrase block matcher
for a bounded buffer. It reports a byte extent without consuming source or
executing actions. The grammar overload of `context:source:block:capture` uses an
explicit phrase dictionary with native root fallback for streamed capture. These
services share the lexicon and matcher; they introduce neither language-specific
parsers nor persistent host semantic state. Their signatures are declared in
`core/compiler.rl`; the direct action allowlist is unchanged.

`context:syntax:describe` attaches a declarative recognition pattern and a stable
grammar reference to a compiled phrase action. The shared matcher uses that
schema during surrounding capture without executing the action. This lets
source-defined DSL grammars describe their own boundaries; C++ stores no
language-specific parser or additional semantic registry.

## Embedded evaluation and completion

`context:source:evaluate(Context*, source:u8*, path:u8*, output:u8*, capacity:u64)`
executes null-terminated source in the caller's Context without a value scope, so
new bindings survive the request. It returns the request exit status (nonzero on
parse/runtime errors), consumes request-local pending exceptions into diagnostics,
and restores the caller's streams, lookup, invocation, exit status and completion
request. The output buffer receives a null-terminated tail of at most
`capacity - 1` bytes; all output still streams to the caller's output sink. A
capacity of one captures an empty string; zero capacity or null pointers fail.
A null path uses `<evaluate>`. Native formatted output follows the same sink.

`context:io:active()` returns the Context of the innermost embedded evaluation
or completion on the current thread, or null outside those operations. Embedded clients
can pass it to `Shell:run_pipeline_in_context` to stream subprocess output
through the active sink in direct CLI runs. Ordinary standalone Shell output
continues to use POSIX without requiring host symbols.

`context:completion:request(Context*, provider:u64, source:u8*, cursor:u64)`
elaborates a source-defined provider against a fresh request with the cursor
clamped to the input length. It suppresses provider output, contains provider
errors and restores caller state. The returned opaque `u8*` is null on failure.
`context:completion:result:start`, `:count`, and `:candidate(handle, index)` expose
its results. Candidate strings are borrowed until `:release(handle)`; an invalid
index returns null and releasing null is allowed. Sorting, duplicate removal,
common-prefix calculation and presentation belong to RecurLoop clients.
These process-local handles must never be persisted in engine images.
