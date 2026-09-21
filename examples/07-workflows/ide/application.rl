// Reloadable IDE application layer.
//
// The persistent project server imports ide.rli once. Every hot reload replays
// this file in a fresh session of that same project and publishes it only after
// the generated lifecycle module links successfully.

include "state.rl"
include "editor.rl"
include "files.rl"
include "terminals.rl"
include "view.rl"
