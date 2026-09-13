// RecurLoop source-defined core.
// Build with: recurloop --bootstrap --file libraries/recurloop/core.rl
//
// The fixed host bootstrap is intentionally small. These libraries grow the
// language left-to-right and export a reusable engine image.
include "bootstrap/seed.rl"
include "core/10-support.rl"
include "core/20-language-support.rl"
include "core/30-records.rl"
include "core/40-functions.rl"
include "core/50-program.rl"
