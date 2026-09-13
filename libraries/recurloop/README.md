# RecurLoop core

`core.rli` is the standard RecurLoop language image. The final `recurloop`
executable embeds it and restores it automatically before normal source input.
There is no public bootstrap mode and an `.rli` file has no special root/core
kind.

Normal execution:

```sh
recurloop --file program.rl
recurloop --import shell.rli --file program.rl
```

`--reset` clears the language back to the host kernel. Imports that follow are
therefore responsible for supplying the language surface:

```sh
recurloop --reset --import core.rli --file program.rl
```

`core.rl` exports the currently loaded core. This makes both forms valid:

```sh
recurloop --file libraries/recurloop/core.rl
recurloop --reset --import core.rli --file libraries/recurloop/core.rl
```

A clean project build has one private bootstrapping step: the non-installed
`recurloop-core-builder` creates the first `core.rli`, CMake embeds those exact
bytes, and the final executable starts from that embedded image.

The source-defined pieces already migrated out of C++ live under `core/`.
Further migrations add files there and remove the corresponding compatibility
implementation from the private builder/host.
