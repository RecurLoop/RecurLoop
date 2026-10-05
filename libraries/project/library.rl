// =============================================================================
// Standard project environment.
//
// Lightweight project vocabulary shared by the CLI, editors and servers.
// GUI and IDE facilities are selected separately by their consumers.
// =============================================================================

let Project = phrase { dictionary = true permanent = true }

include "targets.rl"

let Project:root = fn () -> u8* { return getenv("RECURLOOP_PROJECT_ROOT") }

include "../build/export.rl"
__recurloop_export_library
