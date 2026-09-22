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

## Step cache

`--project-cache <dir>` enables persistent source checkpoints. `IDE:Config`
selects that directory from source and passes it to the project server.

Each direct `.rl` load is a cumulative cache step:

1. start from the immutable baseline hash;
2. validate the step manifest, source stamp, and all observed source dependencies;
3. restore the cached `.rli` when the complete prefix is valid;
4. otherwise evaluate the source and write a new cumulative `.rli` checkpoint;
5. continue until all direct source steps are complete.

Nested `include` files are also cached as graph fragments. A fragment key
contains its input semantic chain and canonical source path; its manifest
contains the complete transitive source set observed below that include. When
one included file changes, the direct checkpoint is rejected, but unchanged
earlier fragments are restored and execution resumes at the first affected
part of the graph. The rebuilt direct checkpoint then becomes the next fast
path.

`:cache-dependencies` prints the canonical files observed by the active cache
walk. The IDE uses that list as its reload filter, so unrelated `.rl` files in
the workspace do not schedule a view rebuild. Imported `.rli` images remain
compiled engine images and use their normal dependency metadata.

The cache contains only generated data under the configured cache directory;
IDE configuration itself is ordinary `.rl` source.
