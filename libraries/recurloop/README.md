# RecurLoop core

`core.rli` is the standard RecurLoop language image. The final `recurloop`
executable embeds the **source-built** image and restores it automatically before
normal source input. There is no public bootstrap mode and an `.rli` file has no
special root/core kind.

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

## Canonical source

`core.rl` is the entry point for the standard language definition. It reads the
semantic modules in `core/`, replaces the current lexicon, builds a fresh core
from symbolic declarations, applies the source-defined control-flow layer, and
exports `core.rli`.

The source modules deliberately contain no numeric engine-image phrase ids and
no serialized payload dump. Phrase relationships and Host ABI actions are named
symbolically; physical C++ layout facts and native implementations remain in the
host.

Both forms below therefore rebuild the language from source:

```sh
recurloop --file libraries/recurloop/core.rl
recurloop --reset --import core.rli --file libraries/recurloop/core.rl
```

## Clean build

A clean checkout has no previous image, so CMake uses a private, non-installed
bootstrap under `bootstrap/` to create the first stage-0 image. That image is
used only to read `core.rl`.

The build then requires the following fixed point byte-for-byte:

```text
C++ bootstrap -> bootstrap-core.rli
bootstrap-core.rli + core.rl -> source-core.rli
source-core.rli + core.rl -> source-core-2.rli

bootstrap-core.rli == source-core.rli == source-core-2.rli
```

Only `source-core.rli` is embedded in the production executable. The production
`RecurloopLib` does not contain the C++ standard-language setup.
