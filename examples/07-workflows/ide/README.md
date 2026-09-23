# Source-defined RecurLoop IDE

The reusable `ide.rli` is an IDE runtime, not a concrete editor UI. It owns the
native window lifetime, Project server, dependency-stamped cache, hot reload,
workspace filesystem API and persistent terminal models. The explorer, editor,
terminal widgets, buttons and complete layout live next to this launcher.

Build the normal libraries, then run the source directly:

```bash
make libraries
./build/Release/bin/recurloop --file examples/07-workflows/ide/main.rl
```

There is no `recurloop-ide` executable and no UI baked into `ide.rli`.

## Project-local view

`main.rl` imports `ide.rli` and includes:

- `app.rl` - application/view records owned by one mounted generation,
- `editor.rl` - code editor behavior,
- `explorer.rl` - file-tree presentation and controls,
- `terminal.rl` - terminal widgets bound to persistent runtime models,
- `view.rl` - layout plus the single `IDE:App:lifecycle` callback.

The launcher selects that lifecycle explicitly with:

```recurloop
app.view(IDE:App:lifecycle)
```

The runtime never knows whether the project uses a tree, tabs, a toolbar, a
status bar or any particular editor layout. `host.user_data` belongs only to
the currently mounted view object; there is no global/singleton application
state shared between generations.

## Configuration and reload

`IDE:Config` chooses the workspace, launcher source, cache, watch root, reload
mode, native window properties and project view. Reload modes are `"hot"`,
`"manual"`, and `"off"`.

The cache defaults to `<workspace>/.cache/recurloop`. Project sources are
compiled one-to-one into linked images under `<cache>/modules`: `app.rl` becomes
`app.rli`, `editor.rl` becomes `editor.rli`, and so on. Includes use those
module images as EngineImage dependencies instead of creating cumulative
full-project checkpoints. Each linked `.rli` contains only source-owned phrases;
references into earlier modules are resolved without copying their implementation.
Changing `view.rl`, for example, leaves the unchanged
`app/editor/explorer/terminal` modules reusable and does not rebuild `ide.rli`.

Candidate builds reset to the immutable Project baseline and enable the normal
linked module cache. The status bar shows the duration of the most recent reload
in milliseconds, which makes cache behavior visible while editing the IDE
itself.

On a successful hot reload the replacement lifecycle module is loaded before
the visible generation is unmounted. The old view is then destroyed and a new
project-local view is mounted against the same `IDE:Host`. Failed rebuilds keep
the current visible view alive.

The worker prepares its Project publication before compiling the generated
lifecycle driver, then commits it only after linking succeeds. This keeps the
publication transactional without a second load of the project environment.


## Source intelligence

The editor does not keep a separate RecurLoop parser or AST. It sends the
current unsaved buffer to the persistent Project runtime for rollback-only
semantic inspection. The returned spans use phrase-owned `kind`, `color`, and
`docs` metadata for highlighting and hover help, including the standard fields
inside `phrase { ... }` descriptors.

Inspection also returns parser/elaboration diagnostics. The project-local editor
shows the current diagnostic directly below the source buffer; a successful
inspection clears it. Because the inspection transaction is rolled back, typing
in the editor cannot mutate the published Project generation or terminal state.

## Persistent runtime state

The window, Project server, cache, watcher and `IDE:Terminal` models live in
`ide.rli` and survive view replacement. Existing terminal sessions therefore
keep their transcript and execution generation across UI reloads. `:refresh`
explicitly moves a terminal session to the latest published Project generation;
new terminals start on the latest generation.

Filesystem mutation also stays behind the runtime API (`IDE:read_file`,
`IDE:write_file`, create/rename/remove helpers, and `IDE:visit_directory`). In
particular `explorer.rl` no longer knows libc `dirent` offsets. That keeps the
source-defined UI independent of the platform-specific filesystem backend.

## Ownership boundary

`ide.rli` should contain infrastructure that must survive or be reusable:
window lifetime, project/cache/hot-reload machinery, workspace/filesystem
operations and persistent terminal/runtime state. Concrete controls and layout
belong in this directory. Adding a button, replacing the file tree, changing
the editor composition or redesigning the terminal panel is therefore a normal
source edit followed by hot reload, not a library rebuild.

## Find and persistent edit history

`Ctrl+F` opens the project-local find bar. Plain search supports an independent
case-sensitive toggle plus delimiter-boundary or whitespace-boundary modes; the
regex toggle switches matching to GLib regular expressions. Previous/next
buttons wrap through the current file and select/scroll to the match.

Undo/redo is also project source. `Ctrl+Z`, `Ctrl+Y`, and `Ctrl+Shift+Z` operate
on a branching per-file history stored below `<cache>/ide/history`. Each record
stores the minimal text splice rather than a full source snapshot. Consecutive
word-character insertions are coalesced into one logical history node, while
backspace/delete edits intentionally remain separate nodes. Save, undo/redo and
explicit history checkout end the current insertion group. A checkpoint is
stored every 128 logical edits so checking out an arbitrary graph node does not
need to replay an unbounded chain. The Explorer header switches to a History view;
selecting a row checks out that node, and editing from there creates a branch.

History is bounded at 20,000 edit records or 128 MiB of log data per file, with a
512 MiB emergency cap for the workspace history directory. When the workspace
cap is crossed, inactive history logs are discarded while the active file is
kept. When a per-file limit would be crossed, the retained graph is compacted to the current buffer as one baseline before recording the new edit. Compaction never writes the source
file, so an unsaved buffer stays unsaved. The on-disk source hash is recorded at
save points; if another process changes the file, stale cached history is reset
instead of being replayed onto unrelated contents.


## Workspace search and replace

`Ctrl+Shift+F` opens a third left-sidebar view beside Explorer and History. It
walks the workspace iteratively and shows clickable `path:line` matches with a
line preview. The workspace search has the same independent case-sensitive,
delimiter-boundary, whitespace-boundary and regex modes as `Ctrl+F`.

Both `Ctrl+F` and workspace search expose Replace and Replace All. Replacements
in the currently open editor are normal buffer edits, so they participate in
the persistent branching undo/redo history and remain unsaved until the user
saves. Workspace replacements in other files are written directly to disk; if
those files later have a stale cached editor history, the existing disk-hash
check resets that history before opening them.

Workspace walking uses the runtime directory policy (`.git`, `build`, `.cache`
and `node_modules` are skipped), ignores files over 16 MiB and rejects files
containing NUL bytes before search or replacement. Results are capped at 10,000
entries per search to keep the tree and matching work bounded.
