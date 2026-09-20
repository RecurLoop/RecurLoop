# Native IDE workflow with source hot reload

The current `gui.rli` backend requires GTK 3 with the `libgtk-3.so` linker name,
and the hot-reload module linker requires `clang` in `PATH` (on Debian/Ubuntu,
install `libgtk-3-dev` and `clang`).  IDE source itself does not call GTK.

Build RecurLoop and libraries:

```bash
make build
make libraries
```

Run the IDE on its own source directory:

```bash
./build/Release/bin/recurloop \
  --file examples/07-workflows/ide/main.rl \
  -- "$(pwd)/examples/07-workflows/ide"
```

The application is split into normal RecurLoop source modules:

- `main.rl` - composition root and launch,
- `state.rl` - generation-owned view state,
- `editor.rl` - editor interaction,
- `files.rl` - explorer,
- `terminals.rl` - terminal widgets and callbacks,
- `view.rl` - layout plus mount/unmount lifecycle.

Saving any source file under the watched directory triggers a full replay of
`main.rl` in a fresh ordinary RecurLoop server. The source-defined runner emits
and loads a versioned native lifecycle module only after the project builds and
publishes successfully. It then unmounts the old view and lets `IDE_App:mount`
create fresh widgets and callback pointers. Existing terminals remain attached
to the generation and private session in which they were opened; newly created
terminals use the latest generation. A failed build leaves the old view mounted.

The runner, watcher, process management and module loading are implemented in
`libraries/ide.rl`.  All widgets/layout/events go through `Gui:*` from
`libraries/gui/library.rl`; the IDE source contains no GTK calls and adds no
IDE-specific code to the C++ host.

A simple visual test is to edit the `FILES - hot reload` label in `view.rl` and
press Save.  The window stays open and the changed label appears after reload.
For a lexicon test, add e.g. `const IDE_App:test_value = 123` to any included
module, save, then enter `print IDE_App:test_value` in the terminal.
