// RecurLoop IDE is a normal source-defined application.
//
// The source library provides GTK bindings and the complete hot-reload runner.
// This file is the application root; its includes are replayed in a fresh
// RecurLoop process for every candidate generation.

engine import "build/Release/libraries/ide.rli"

include "state.rl"
include "editor.rl"
include "files.rl"
include "terminals.rl"
include "view.rl"

// During candidate builds this phrase is a no-op. On command-line execution it
// owns the stable native window/watcher and mounts versioned lifecycle modules.
ide
