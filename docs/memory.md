# Memory model

RecurLoop uses different storage strategies for persistent language state,
temporary compiler state, and native execution.

## Flat phrase storage

The radix tree and lexicon share one contiguous buffer. Nodes and items store
offsets rather than pointers, allowing the buffer to move and making graph
serialization explicit. Allocation grows from the buffer ends according to the
radix layout. Checkpoints record an address that can be restored for scoped
rollback.

`utilities::Byte`, `Bit`, and `Size` provide byte/bit views and offset
arithmetic. They do not own memory.

## Temporary buffers

`Appender` owns growable byte storage used for source keys and generated code.
`Context::Workspace` contains temporary code, read-only data, writable data,
BSS size, and custom native sections. These buffers are reset between output
operations as required.

## Executable memory

`JitMemory` owns process-local executable mappings used by the JIT linker.
Native entry addresses are caches and are never portable image data. After an
image import, functions are resolved again from stored modules.

## Native function memory

Compiled functions use the target ABI: stack frames for locals, explicit
pointers for heap objects, and external allocators when linked by the program.
RecurLoop does not currently provide automatic ownership or garbage
collection for native records.

## Persistence rule

Only graph data with explicit relocation semantics may cross an engine-image
boundary. Raw process pointers, executable mappings, futures, streams, and
exceptions remain local to the current process.
