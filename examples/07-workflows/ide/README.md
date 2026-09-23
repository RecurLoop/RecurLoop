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

The cache defaults to `<workspace>/.cache/recurloop`. Direct launcher loads are
cumulative `.rli` checkpoints. Files reached through `include` are dependency
stamped, so changing `editor.rl`, `explorer.rl`, `terminal.rl` or `view.rl`
invalidates the relevant project step without rebuilding `ide.rli`.

On a successful hot reload the replacement lifecycle module is loaded before
the visible generation is unmounted. The old view is then destroyed and a new
project-local view is mounted against the same `IDE:Host`. Failed rebuilds keep
the current visible view alive.

The worker prepares its Project publication before compiling the generated
lifecycle driver, then commits it only after linking succeeds. This keeps the
publication transactional without a second load of the project environment.

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
