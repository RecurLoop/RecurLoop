# Engine images

An engine image is a relocatable snapshot of the serializable phrase graph.
It is used by `engine export`, `engine import`, and the `--import` CLI option.

## Format

The current wire format is version 8. The loader also accepts version-7 images.
Version 8 keeps the phrase-record layout but marks runtimes that understand
image dependencies, so an older runtime cannot silently treat a dependency
delta as a standalone image. The header records the host `Size` and pointer
widths, followed by phrase records. Each record can contain:

- a stable image identifier and parent identifier;
- a bit-string key and its exact bit length;
- subdictionary, prototype, type, action, successor, permanent, and rewrite flags;
- referenced phrase identifiers;
- a stable action name;
- payload bytes and payload relocations.

Phrase addresses and function pointers are never written directly. Phrase
references become image identifiers, and registered behaviors become stable
action names. The importer rejects incompatible versions, ABI widths, invalid
bit padding, unknown flags, unresolved actions, and invalid dependency
metadata.

## Operations

```rl
engine export "/tmp/state.rli"
engine import "/tmp/state.rli"
```

Without a startup image base, `engine export` writes a complete standalone
serializable graph. A phrase marked `serializable = false` is omitted when no
exported phrase references it; a reference crossing that boundary is rejected.
The internal encoder also supports checkpoint-based partial images with
reachable dependencies.

Startup images loaded through `--import` or `--library` are remembered before
source execution begins. A later export can therefore write only the state
added after those imports plus the graph records needed to relocate that state.
The resulting image carries dependency descriptors rather than duplicating the
unrelated contents of its base images. This is how the standard `shell.rli`,
`inferred.rli`, and `http.rli` images share `language-kit.rli`.

Dependency loading is recursive and deterministic:

- every referenced image has a content-derived identity and a path;
- dependency descriptors are processed in a stable order;
- relative paths are resolved from the image that declares them;
- export stores paths relative to the output directory when possible;
- an image whose identity is already loaded is reused without opening the old
  dependency path again;
- cycles, missing files, and content-identity mismatches are rejected.

Compiler type IDs are local to each language registry. Imports match types by
name, retain the IDs of existing types, and rebase incoming field, pointer,
array and function references before applying the image. An incompatible
definition of an existing type is rejected before applying that image. Partial
and linked images include their type name/ID tables, including inherited types,
so loading another library first cannot change a function's signature.

A full export remains standalone even if `engine import` was executed earlier
at runtime. The loaded-image registry is useful for duplicate suppression in
that process, but it is not serialized as a requirement when the export already
contains the complete graph. Exporting over one of the loaded dependency paths
also falls back to a complete standalone image to avoid a self-dependency.

`engine import` restores dependencies first and then applies the requested
image as an overlay. Process-local executable state is rebuilt as needed.

A source-backed `lexicon` can instead be exported as its compiled fragment:

```rl
let routes = lexicon {
    let api = [ health = <debug:ping> ]
}

engine export <routes> "/tmp/routes.rli"

let application = [
    merge "/tmp/routes.rli"
]
```

Compilation of a source-backed lexicon is on demand. Its source descriptor
lives in the lexicon, while the compiled fragment is only a temporary value
used by that `merge` or `engine export`; completed fragment images are not kept
in a process-local result cache. The fragment does not include the complete
active engine.

At the CLI, imports must precede dependent source:

```bash
build/Release/bin/recurloop --import /tmp/state.rli --file program.rl
```

## Language metadata in ELF files

Native modules may contain a `.recurloop.language` section. This is a separate
version-3 format containing type descriptions, function signatures, calling
conventions, imports, and native action names needed by emitted code. It does
not replace the engine image.

`module embed` enables the section and `module strip` disables it for the next
output. RecurLoop debug metadata is stored separately from both formats.

## Non-portable state

The following state is deliberately excluded, rejected, or reconstructed:

- JIT code addresses and executable mappings;
- open streams and CLI argument pointers;
- current phrase pointers and pending exceptions;
- temporary source-backed-lexicon compilation workers;
- external process state.

Payload layouts may explicitly declare a field as a native pointer. Export is
rejected while such a field is non-zero; a process address is never serialized
as an ordinary integer. A native-pointer schema may also provide a cleanup
action. The engine invokes that action for a live owned field before resetting
or destroying the phrase graph, while executable actions are still available.
LanguageKit uses this ownership form for the Inferred database; transient Shell
state remains non-owning and must be zero before export.

Images are currently ABI-specific because the header validates host width.
Treat the format as experimental until a stable compatibility policy is
published.
