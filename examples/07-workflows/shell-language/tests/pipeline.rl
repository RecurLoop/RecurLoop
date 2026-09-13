// Pipelines, capture and redirection in a top-level automation script.
// Requires /tmp/recurloop-shell-library.rli built from library.rl.

var needle = "beta"
var output = "/tmp/recurloop-shell-filtered.txt"

run printf "alpha\\nbeta\\ngamma\\n" | grep "{needle}" > "{output}"
capture cat "{output}"

print trim(captured)
assert trim(captured) == needle
