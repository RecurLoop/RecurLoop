// =============================================================================
// Standard project environment.
//
// A Project is the shared runtime opened by the source-defined IDE. The image contains the
// shared, immutable default environment (language/GUI/IDE facilities from
// its dependencies). A workspace only publishes the small local overlay from
// project.rl and launcher source, so standard projects do not copy the IDE or
// language libraries into every repository. The default IDE view is already
// part of ide.rli and project-specific overrides are ordinary source replay.
// =============================================================================

let Project = phrase { dictionary = true permanent = true }

let Project:root = fn () -> u8* { return getenv("RECURLOOP_PROJECT_ROOT") }

include "../build/export.rl"
__recurloop_export_library
