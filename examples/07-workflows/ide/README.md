# Native IDE workflow with one shared project runtime

The current `gui.rli` backend requires GTK 3 with the `libgtk-3.so` and
`libgdk-3.so` linker names, and the hot-reload module linker requires `clang`
in `PATH` (on Debian/Ubuntu, install `libgtk-3-dev` and `clang`). IDE source
itself does not call GTK.

Build RecurLoop and libraries:

```bash
make build
make libraries
```

Run the IDE with the repository as the workspace:

```bash
./build/Release/bin/recurloop \
  --file examples/07-workflows/ide/main.rl \
  -- "$(pwd)"
```

The workspace argument controls the explorer root. The reloadable IDE source is resolved from `examples/07-workflows/ide/application.rl` when the workspace itself does not contain `application.rl`.

The application is split into normal RecurLoop source modules:

- `main.rl` - imports `ide.rli` and starts the application,
- `application.rl` - reloadable composition root,
- `state.rl` - reloadable view behavior/state access,
- `editor.rl` - editor interaction,
- `files.rl` - hierarchical explorer,
- `terminals.rl` - integrated terminal widgets and callbacks,
- `view.rl` - layout plus mount/unmount lifecycle.

## Hot reload model

The IDE owns exactly one persistent `recurloop --serve` project process. A
reload uses short-lived sessions of that same project rather than launching a
new server generation:

1. one session loads `application.rl`, emits and links the native lifecycle
   module, but is never published;
2. after linking succeeds, a second session loads only `application.rl` and
   publishes that source state;
3. the GTK view is remounted from the new lifecycle module;
4. existing terminal sessions stay private until the user enters `:refresh`,
   which now attaches to the newly published generation of the same project.

Compiler-only `recurloop_ide_lifecycle` phrases therefore never enter the
published lexicon, and a failed compile/link leaves the previous project/view
untouched.

For a direct test, change this line in `state.rl`:

```rl
IDE_App:hot_reload_probe = 1
```

to `2`, save, then in an already-open terminal run:

```text
> print IDE_App:hot_reload_probe
1
> :refresh
refreshed project=... lexicon=... context=... session=... request=0
> print IDE_App:hot_reload_probe
2
```

## UI

The GTK backend installs a dark theme by default through `gui.rli`. The IDE
uses semantic `Gui:*` style classes and a compact VS Code-like terminal panel
with an inline `>` input row. The explorer now uses `Gui:tree`, backed by GTK `TreeView`/`TreeStore`.
It is lazy: startup reads only the project root, and each directory is populated
when it is opened. The application no longer creates one button/label widget
per path or recursively walks the repository before the window can appear.

The runner, watcher, process management and module loading are implemented in
`libraries/ide.rl`. All widgets/layout/events go through `Gui:*` from
`libraries/gui/library.rl`; no IDE-specific code is added to the C++ host.
