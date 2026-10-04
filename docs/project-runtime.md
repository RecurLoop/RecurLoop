# Project runtime

RecurLoop's Project runtime is the shared publication boundary used by servers,
terminals, and the source-defined IDE. A Project owns immutable published
lexicon generations; each client owns an independent mutable Session attached to
one of those generations.

## Session publication

A session can publish its current portable language state with `:publish`.
Other sessions keep their existing generation until they execute `:refresh`.
`Session::refresh()` attaches directly to `Project::current()`, so all transports
observe the same publication graph.

The IDE uses one persistent `recurloop --library project --serve --unix ...`
process for its entire lifetime. Candidate rebuild sessions and integrated
terminals connect to that same server. Publishing a candidate does not refresh
already-open terminal sessions: each terminal keeps its local state and current
generation until the user explicitly executes `:refresh`. New terminal sessions
attach to the current published generation.

A reload build prepares an unpublished semantic snapshot before compiling its
transient lifecycle driver and commits that snapshot only after the native
module links successfully. The same build session can therefore publish the
clean pre-driver state without loading the complete project a second time.

## Terminal output

Ordinary terminal requests stream output while source executes. Shell drains
process output in 4 KiB chunks into the request's output stream; the server
forwards those chunks immediately, and `--connect` writes received bytes directly
to its terminal. A slow reader applies socket/pipe backpressure instead of
accumulating the complete command output in memory. Explicit Shell `capture`
and Session calls without output streams still collect their requested results.

Unix connections initially receive the plain `> ` prompt. The terminal client
then sends `:transport-stream-v1` as its first line to select framed responses.
Each frame has a one-byte kind followed by a four-byte unsigned big-endian
payload length. `O` frames carry 1–4096 output bytes; an empty `P` frame marks
command completion. Payloads may include NUL bytes and prompt-looking text.
Status diagnostics remain output text. Input commands and Ctrl+C retain their
existing line/control-byte format. Clients that do not select framing retain
plain text responses and prompts.

## Source-module cache

`--project-cache <dir>` enables a persistent linked-module cache. `IDE:Config`
selects that directory from source and passes it to the project server.

The cache mirrors project source files under `<cache>/modules`: one `.rl` file
produces one `.rli` plus one small manifest. Linked entries are true semantic
deltas, not flattened snapshots: phrases owned by dependencies are addressed by
stable lexical references and are never copied into the child image.

1. a source file imports/loads its already compiled dependencies;
2. unchanged included `.rl` files are restored from their own module images;
3. the current file exports only phrases allocated after its dependency boundary;
4. references to older phrases are stored as deterministic lexical paths plus
   shadow depth, while image dependencies remain identity/path links;
5. a cache hit resolves those links and appends the local delta directly to the
   current lexicon without capturing/rebuilding the dependency graph.

The manifest stores the baseline identity plus source stamps for the complete
`.rl` dependency set. A change therefore invalidates every source module that
observed it, while unrelated workspace files remain outside the reload graph.
`:cache-dependencies` exposes that canonical source set to the IDE watcher.

Cache-build sessions compile ordinary in-memory functions with LLVM's quick
pipeline. Explicit `emit object` and `emit executable` directives keep their
normal output policy. This avoids spending production optimization time on
short-lived hot-reload generations without changing native artifact settings.

`include` no longer creates a second fragment/checkpoint cache. It is simply a
source-module dependency boundary. `engine import` is likewise treated as an
image dependency boundary and remains represented by normal `.rli` dependency
metadata. This keeps the persistent cache shape aligned with the project source
tree rather than with one particular execution order.

Most source files can be emitted as small linked images. If a file mutates
pre-existing semantic state in place, or contributes semantic state before a
later dependency boundary, that single file falls back to a self-contained
image because an append-only linked delta cannot represent the ordering safely.
The fallback is local to that file; it does not reintroduce cumulative
step/fragment snapshots for the rest of the project.

`:cache` and `:cache-exact` both use this module graph. The latter remains a
compatibility command for older IDE clients; linked module hits intentionally
compose with the current context exactly like ordinary image imports.

The cache contains only generated data under the configured cache directory;
IDE configuration itself is ordinary `.rl` source.

## Transactional source inspection

`:inspect<TAB>hex(path)<TAB>hex(source)` returns semantic style/documentation
spans (`S`) and diagnostics (`E`). `:trace` accepts the same payload and also
returns language facts, without implementing any client-specific queries:

- `R<TAB>start<TAB>end<TAB>line<TAB>version<TAB>hex(name)` is an actual phrase match.
- `P<TAB>version<TAB>hex(name)<TAB>hex(kind)<TAB>hex(docs)<TAB>hex(prototype)<TAB>hex(type)<TAB>hex(signatures)` is a visible dictionary entry. Overload signatures are separated by newlines inside the hex payload.

`:inspect-file` and `:trace-file` accept the same payload and return the same
records for an independent source target. They create a separate context from
the immutable baseline and elaborate the supplied buffer directly, including
its imports/includes, then roll back. They do not require the target to belong
to the published project's processing graph. Ordinary `:inspect`/`:trace`
continue to reconstruct that graph's source-entry environment.
The standalone context is created lazily per session and reused after rollback;
a baseline change recreates it. Only the context's resources are reused, not
previous analysis results or elaborated buffer state.

`start` and `end` are UTF-8 character offsets; `end` is exclusive. `line` is
one-based. `name` is the dictionary path; `version` counts older definitions of
the same phrase, so chronological shadows remain distinct without exporting
arena addresses. Compiler registries supply type names and signatures when
available; custom languages need not contain those registries.

A cache-backed inspection starts from the immutable baseline and images present
at source entry, falling back to source-prefix replay when needed. The edited
buffer replaces only its own source. Inspection uses a separate context and
rolls back the request; it does not switch the caller's ordinary Session to the
baseline or publish any analysis data. Permanent phrases retain their normal
protection. Clients can build indexes and query policies from the exported facts
in their own RecurLoop code.
