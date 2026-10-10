// =============================================================================
// Standard project environment.
//
// Lightweight project vocabulary shared by the CLI, editors and servers.
// GUI and IDE facilities are selected separately by their consumers.
// =============================================================================

let Project = phrase { docs = "Project vocabulary shared by the CLI and editors, including deferred targets and the project root." dictionary = true permanent = true }

include "targets.rl"

let Project:root = fn () -> u8* { return getenv("RECURLOOP_PROJECT_ROOT") }
set Project:root.docs = "Returns the project root from RECURLOOP_PROJECT_ROOT, or null when unset. The returned environment string is borrowed; do not free it."

include "../build/export.rl"
__recurloop_export_library
