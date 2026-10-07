# Memory model

RecurLoop uses different storage strategies for persistent language state,
temporary compiler state, and native execution.

## Flat phrase storage

The radix tree and lexicon share one contiguous buffer. Nodes and items store
offsets rather than pointers, allowing the buffer to move and making graph
serialization explicit. Allocation grows from the buffer ends according to the
radix layout. Checkpoints record an address that can be restored for scoped
rollback.

Arena records are byte-aligned, including subdictionaries embedded in phrase
metadata. Phrase fields and scalar payloads use `memcpy` rather than dereferencing
typed pointers into that storage; a key of odd byte length must not change the
validity of the following record.

`utilities::Byte`, `Bit`, and `Size` provide byte/bit views and offset
arithmetic. They do not own memory.

## Temporary buffers

`Appender` is a non-owning view over fixed-capacity byte storage used for source
keys and generated code. The engine allocates and frees both workspace buffers.
`Context::Workspace` contains temporary code, read-only data, writable data,
BSS size, and custom native sections. These buffers are reset between output
operations as required.

Interpreted value scopes keep allocation checkpoints in the execution context.
Closing a scope restores its checkpoint when the new graph records belong only
to that scope. In-place updates to outer scalar values survive this restore.
New definitions or resized outer values retain their graph records instead.
The checkpoint stack is request-local, participates in rollback, and is cleared
when an engine image replaces the graph.

## Executable memory

`JitMemory` views process-local executable mappings owned by the engine.
Native entry addresses are caches and are never portable image data. After an
image import, functions are resolved again from stored modules.

## Native function memory

Compiled functions use the target ABI: stack frames for locals, explicit
pointers for heap objects, and external allocators when linked by the program.
RecurLoop does not currently provide automatic ownership or garbage
collection for native records.

Generated functions check integer division by zero and signed division overflow
before executing the operation. In the host, they record the error and return
through ordinary native frames; the host boundary then reports it as a request
failure. Function entries, calls, and loop backedges also check pending errors
and request cancellation. Standalone executables report arithmetic faults on
stderr and exit with status 1. These checks apply to generated functions;
explicit assembler and external native code retain their own fault behavior.

## Persistence rule

Only graph data with explicit relocation semantics may cross an engine-image
boundary. Raw process pointers, executable mappings, futures, streams, and
exceptions remain local to the current process.

Source-backed lexicons do not keep a process-local result cache. The source
descriptor is stored in the phrase graph and compilation happens on demand in a
temporary worker when a fragment is merged or exported. The resulting byte
vector is consumed by that operation and then released. This removes the old
`shared_future` cache, avoids stale results when a radix address is reused after
rollback, and lets the worker destructor release all engine-owned arenas,
including `workspace.code`.

LanguageKit native state uses `LanguageKit:state_pointer_set`, separate from
ordinary integer counters. Existing pointer slots are updated in place through
`context:phrase:write`, so repeatedly changing a process pointer does not create
shadow payload phrases. These payloads declare a native-pointer field to the
image encoder. Export rejects nonzero pointers, including an active Inferred
database or transient Shell builder state, rather than persisting invalid
process addresses.

A process pointer that owns heap state can instead use
`LanguageKit:state_pointer_set_owned`. Its schema carries a cleanup action. The
engine runs such actions before clearing the lexicon or unmapping JIT memory;
the action releases the heap graph and zeros its pointer slot. Inferred uses
this for its function/AST/specialization database, including temporary typed
AST and type-environment cleanup during specialization. Serializing that live
heap graph is still intentionally unsupported: while the pointer is non-zero,
image export fails rather than representing a process address as portable data.
