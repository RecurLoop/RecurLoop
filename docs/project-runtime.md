# Project runtime

RecurLoop's Project runtime is the shared publication boundary used by servers,
terminals, and the source-defined IDE. A Project owns immutable published
lexicon generations; each client owns an independent mutable Session attached to
one of those generations.

Executable entries, target syntax, CLI actions and debugging are documented in
[projects.md](projects.md). These operations are shared by all clients.

## Session publication

VS Code starts this runtime only for workspace folders containing the saved
entry selected by `recurloop.projectFile` (default `recurloop.project.rl`). An
empty entry opts in; **RecurLoop: Initialize Project** simply creates that file
without overwriting existing source. Deleting the entry stops the editor's
shared server. Loose source files retain static highlighting without launching
the host. Custom entry paths and each workspace folder are checked separately.

An entry is normal RecurLoop source. `recurloop --project recurloop.project.rl
--serve` loads it with the project vocabulary and publishes its environment,
then opens a console. Add `--unix <socket>` for other clients. `--targets`,
`--target <name>`, `--debug-target <name>`, `--inspect <file>` and `--trace <file>`
discover the entry in parent directories or use an explicit `--project` path.
Independent scripts and REPLs continue to work without a project marker.

A session can publish its current portable language state with `:publish`.
Other sessions keep their existing generation until they execute `:refresh`.
`Session::refresh()` attaches directly to `Project::current()`, so all transports
observe the same publication graph.

The IDE uses one persistent `recurloop --library project --library ide --serve --unix ...`
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

Clients that send `:transport-stream-v2` use the same `O` output and empty `P`
completion frames. An `S` frame immediately before `P` contains the decimal
request status. VS Code uses this version so application output containing
`> `, `status=1`, NUL bytes or split UTF-8 cannot be mistaken for protocol state.
The v1 handshake and plain prompt transport remain available to existing clients.

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

Stamps include a content hash, so restoring a timestamp or replacing bytes with
the same file size still invalidates the cache. Writers recheck their inputs
before publication. A process-shared lock protects image/manifest replacement;
the manifest also identifies the image bytes, so an interrupted replacement is
a cache miss. Older manifest versions are rebuilt automatically.

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

## Terminal completion

Local consoles and `--connect` consoles (including the VS Code terminal) use
Tab to complete commands, language phrases, and paths. Connected consoles query
their existing server session, so session-defined phrases are available too.
Completion does not evaluate the input or add it to command history.

The host invokes the ordinary `Completion:complete` phrase. Core defines it as
an alias of `Completion:lexicon`, implemented in
`libraries/recurloop/core/completion.rl`. Shell loads its own provider from
`libraries/shell/completion.rl` and rebinds the same slot. The host has no Shell
namespace detection or language-specific completion dispatcher.

Completion follows the active lexicon's longest-prefix priority. With Shell
loaded, the first word can complete phrases or unshadowed executable names;
`run`, `capture`, `spawn`, and `shell` select command completion explicitly,
including aliases and assignment right-hand sides. Pipelines and shell list
separators start another command. Shell combines executable and Bash command
names with lexicon phrases. For arguments it queries the installed
`bash-completion` functions using the current command's decoded words, then
adds lexicon phrases. For example, Tab after `make build && make libr` suggests
the Makefile target `libraries`, rather than the directory `libraries/`.
When Bash supplies no matching candidates (or Bash/`bash-completion` is absent),
arguments fall back to paths. Redirection targets also complete paths.
Language expressions and Shell `{...}` interpolation complete phrases,
including qualified dictionary names. Loading Shell does not enable filesystem
suggestions inside every RecurLoop expression. The completion adapter passes
input words as arguments to Bash; it does not execute the edited command.

Other libraries can publish a provider in exactly the same way:

```rl
let MyLanguage:complete = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let cursor = context:completion:cursor(state)
        context:completion:start(state, cursor)
        context:completion:add(state, "my_suggestion")
    }
}
let Completion:complete = <MyLanguage:complete>
```

The most recently installed provider owns the request. Restore the default with
`let Completion:complete = <Completion:lexicon>`. Providers can reuse
`Completion:phrases(state, start)` to append qualified lexicon candidates.

The generic Context API supplies request data and platform enumeration:

| API | Contract |
| --- | --- |
| `context:completion:source`, `cursor` | Borrowed source bytes and cursor byte offset. |
| `context:completion:start(state, offset)` | Set the start of the replacement range. |
| `context:completion:add(state, text)` | Copy a candidate encoded by the provider; control bytes are rejected. |
| `context:completion:dictionary:count`, `dictionary` | Read current, enclosing, and root dictionary handles without changing lookup. |
| `context:completion:children(state, owner, prefix, consumer)` | Enumerate matching raw lexicon keys through a phrase callback. |
| `context:completion:paths(state, prefix, executable, consumer)` | Enumerate raw paths, optionally restricted to executables and directories. |
| `context:completion:programs(state, prefix, consumer)` | Enumerate executable names from `PATH`. |
| `context:completion:candidate(state)` | Borrow the raw candidate during an enumeration callback. |
| `context:completion:data(state[, value])` | Read or set request-local scratch data for a provider's callbacks. |

Enumeration callbacks use the usual `fn(Context*, Phrase*)` action contract.
The provider chooses whether to enumerate, filter, or quote candidates. Request
pointers and scratch data expire when completion returns and must never be
stored in phrases or engine images. Providers should only inspect the unfinished
input and avoid changing session language or runtime state.

The console request is `:complete<TAB>cursor<TAB>hex(source)`, where the cursor
is a byte offset. Its output starts with `completion<TAB>start` followed by one
hex-encoded candidate per line. `start` is the byte offset of the replacement
range, which ends at the cursor. Responses use the current transport's usual
output and completion frames. Invalid cursor offsets are rejected.

After updating the executable, restart the VS Code language runtime and reopen
its terminals so both the server and console client use the new version.

### Interactive console presentation

The local console and `--connect` client render input colors from the active
session's phrase/type metadata and inspection's lexical coloring, including
session-local phrases. The `:highlight<TAB>hex(source)` request returns ordinary
`S` inspection spans without elaborating input or running language actions.
Colors use RGB ANSI sequences and respect a nonempty `NO_COLOR` on the client.
Input wraps across terminal rows, and Enter retains the complete command in
scrollback. Cursor movement and history operate on the uncolored source.

In VS Code (`TERM_PROGRAM=vscode`), the console emits OSC 633 prompt, command,
execution and completion markers. The socket client negotiates transport v2 to
obtain the actual command status. These markers support command decorations,
navigation and sticky scroll, subject to VS Code's terminal settings.

Console palettes are cached per session generation and rebuilt after committed
requests, refresh/publish, or custom completion. Keystrokes scan only the current
input against the cached palette. Highlight requests use a synchronous socket
path without command-worker interrupt polling; queued input is coalesced before
redrawing, so pasted text does not make one request per byte.

Connected terminal consoles negotiate `:transport-console-v3<TAB>rows<TAB>columns`.
They send an entire edited block as `:evaluate<TAB>hex(source)` and forward
command input as `:stdin<TAB>hex(bytes)`. The server gives each request a private
pseudoterminal for stdin and `/dev/tty`; ordinary stdout/stderr still stream
through the existing output frames. Ctrl+C interrupts the request's process
groups and resumes stopped children; a second Ctrl+C forces termination.
The terminal client and server must come from the same updated installation.

The editor enables bracketed paste while reading input. Pasted newlines and tabs
stay in one editable buffer, and Enter submits the complete block. Ctrl+C before
submission discards the block. During command execution, keyboard input goes to
the command's terminal rather than being interpreted as RecurLoop source.
