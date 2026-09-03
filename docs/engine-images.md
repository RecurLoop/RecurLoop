# Engine images

An engine image is a relocatable snapshot of the serializable phrase graph.
It is used by `engine export`, `engine import`, and the `--import` CLI option.

## Format

The current wire format is version 7. Its header records
the host `Size` and pointer widths, followed by phrase records. Each record can
contain:

- a stable image identifier and parent identifier;
- a bit-string key and its exact bit length;
- subdictionary, prototype, type, action, successor, permanent, and rewrite flags;
- referenced phrase identifiers;
- a stable action name;
- payload bytes and payload relocations.

Phrase addresses and function pointers are never written directly. Phrase
references become image identifiers, and registered behaviors become stable
action names. The importer rejects incompatible versions, ABI widths, invalid
bit padding, unknown flags, and unresolved actions.

## Operations

```rl
engine export "/tmp/state.rli"
engine import "/tmp/state.rli"
```

`engine export` writes the complete serializable graph. A phrase marked
`serializable = false` is omitted when no exported phrase references it; a
reference crossing that boundary is rejected. The internal encoder
also supports checkpoint-based partial images with reachable dependencies.
`engine import` replaces the restored portions of the active state and rebuilds
process-local caches as needed. Image merge can materialize a graph below an
existing dictionary.

At the CLI, imports must precede dependent source:

```bash
build/Debug/bin/recurloop --import /tmp/state.rli --file program.rl
```

## Language metadata in ELF files

Native modules may contain a `.recurloop.language` section. This is a separate
version-3 format containing type descriptions, function signatures, calling
conventions, imports, and native action names needed by emitted code. It does
not replace the engine image.

`module embed` enables the section and `module strip` disables it for the next
output. RecurLoop debug metadata is stored separately from both formats.

## Non-portable state

The following state is deliberately excluded or reconstructed:

- JIT code addresses and executable mappings;
- open streams and CLI argument pointers;
- current phrase pointers and pending exceptions;
- in-flight translation-unit jobs;
- external process state.

Images are currently ABI-specific because the header validates host width.
Treat the format as experimental until a stable compatibility policy is
published.
