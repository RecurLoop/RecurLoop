# Source-defined RecurLoop IDE

The IDE is a normal `.rli` library. There is no `recurloop-ide` executable and
no separately staged `application.so`.

Build the normal libraries:

```bash
make libraries
```

Then run the launcher source directly:

```bash
./build/Release/bin/recurloop --file examples/07-workflows/ide/demo.rl
```

`demo.rl` imports `ide.rli`, defines a small launcher function that creates
`IDE:Config`, chooses the workspace, cache, watch root and reload mode, and then
starts it from a top-level `var` initializer. Any `IDE_App:*` function can be
replaced before that final initializer.

## Configuration

```recurloop
let IDE_App:launch = fn () -> i64 {
    let app = IDE:Config:new()
    if !app { return 1 }

    app.workspace("examples/07-workflows/ide")
    app.source("examples/07-workflows/ide/demo.rl")
    app.cache(".cache/recurloop")
    app.watch(".")
    app.reload("hot")

    let status = app.open()
    app.destroy()
    return status
}

var IDE_App:launch_status = IDE_App:launch()
```

Reload modes are `"hot"` / `"hot-reload"`, `"manual"` / `"manually"`, and
`"off"` / `"no-reload"`. Manual mode shows a compact reload button in the
editor toolbar. Hot mode watches `.rl` files with inotify and debounces saves.
Heavy directories (`.git`, `build`, `.cache`, `node_modules`) are skipped.

The cache location is configured in source and defaults to
`<workspace>/.cache/recurloop`. Direct launcher loads are cumulative `.rli` step
checkpoints. Files reached through `include` are dependency-stamped into that
step, so editing an included file invalidates the cached step automatically;
imported `.rli` libraries are already compiled images.

## Hot reload and terminal generations

One persistent Project server is used for the whole IDE lifetime. A reload
starts from the immutable `project.rli` baseline, restores the longest valid
cache prefix, evaluates the launcher and optional `project.rl`, emits a new
lifecycle object, links it, publishes the Project generation, and only then
swaps the view.

After successful publication existing terminal sessions stay on their current
generation and retain local variables and execution context. Run `:refresh` in a
terminal when you deliberately want that session to attach to the latest Project
generation. New terminals attach to the current published generation.

Native hot-reload generations are linked against the GTK 3 runtime SONAMEs
(`libgtk-3.so.0`, `libgdk-3.so.0`, `libgobject-2.0.so.0`, and
`libglib-2.0.so.0`). This keeps worker-side validation deterministic without
requiring GTK development linker symlinks.

## Customizing the IDE

The default implementation is shipped as source under `libraries/ide/` and is
compiled into `ide.rli`. Its behavior is deliberately split into replaceable
functions. For example, a launcher may replace `IDE_App:create_editor`,
`IDE_App:create_explorer`, `IDE_App:create_terminal_panel`, `IDE_App:create_status`,
`IDE_App:mount`, save/file handlers, terminal handlers, or any lower-level
`IDE:*` function before the final `IDE_App:launch_status` initializer.

That keeps the standard IDE usable out of the box while allowing a project to
replace a single control, a panel, or the complete composition without adding a
C++ IDE mode.
