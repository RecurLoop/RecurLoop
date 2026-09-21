// RecurLoop IDE is a normal source-defined application.
//
// ide.rli owns the stable project runtime and GUI boundary. application.rl is
// the reloadable layer replayed in the same project for every hot reload.

engine import "build/Release/libraries/ide.rli"
include "application.rl"

// During project-server builds this phrase is a no-op. On command-line
// execution it owns the stable native window/watcher and mounts generations.
ide
