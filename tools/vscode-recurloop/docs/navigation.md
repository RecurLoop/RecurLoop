# Editor navigation index

The extension keeps one private LanguageKit analysis session per workspace.
The private session uses published project policy when LanguageKit is available;
a core-only project gets a private LanguageKit environment.
LanguageKit classifies real semantic traces and owns all query policy. The
extension only synchronizes document snapshots, converts positions and manages
cancellation. The same file constructor and queries serve the example IDE.

## Updates and scope

Runtime inspection is shared between providers, including requests in flight.
Snapshots are keyed by source and project revision; completed traces have a
bounded cache. Each caller can cancel independently. The last consumer leaving
an unfinished inspection closes its connection.

A private session retains its classified file fragments. The client sends only
changed source/semantic traces through one compiled request phrase. No temporary
program or new JIT function is generated per query. Fingerprints retain equality
information without retaining a second copy of each trace.

Document symbols, local references/renames and definitions found in the current
file synchronize that file only. Cross-file navigation synchronizes the saved
project processing graph plus its open buffers. Included files outside the
workspace are inspected in the requesting project context. Removed dependencies are removed
from the index. Type definitions can cross file boundaries even for locals.

A successful project publication invalidates inspection snapshots and the
cached dependency list. It preserves the private index and replaces only file
fragments whose source or semantic facts differ. Revalidating all participating
traces after publication is deliberately conservative: an earlier phrase or
syntax definition can change the meaning of unchanged source. A runtime restart
closes the private session and rebuilds lazily.

## Lookup and ownership

Resizable hash multimaps index paths, symbol names/identities, occurrence starts,
reference targets, containers and local declarations. Declaration lists bound
symbol searches to definitions. Target queries visit matching postings
in each participating file rather than scanning every occurrence. A sorted
interval array with prefix maximum ends finds symbols under the cursor by binary
search. Matching delimiters and enclosing blocks are recorded during tokenization.
Result sorting uses merge sort and deduplicates equal source ranges.

One serialized queue protects each private index. Cancelling queued work returns
immediately and does not interrupt another caller. Cancelling active work drops
its private session, so partially updated heap state cannot be reused. LanguageKit
polls the request's generic `context:process:interrupted()` flag during indexing
and result lookup; the host also stops source processing at phrase boundaries.
The next query opens a fresh session. The existing owned native-payload mechanism
releases the index on session teardown; heap pointers never enter published images.

Version/revision checks reject results if participating buffers or the project
changed during a request. Diagnostics in unrelated indexed files do not prevent
a local rename. Project-wide rename still requires complete, unambiguous analysis.

## Verification

`tests/navigation.cjs` runs against the real project server and counts protocol
commands. It covers cold local scope, warm reuse, one-file unsaved updates,
unchanged publication, dependency removal, Unicode positions, shadowing, rename,
workspace symbols, independent/queued/active cancellation and runtime restart.
Run `npm test` after building the host and standard libraries.
