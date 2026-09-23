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
