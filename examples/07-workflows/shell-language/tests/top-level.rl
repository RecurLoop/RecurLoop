// A Bash-like top-level script using the imported shell language image.
//
// Build and run:
//   Recurloop --file examples/07-workflows/shell-language/library.rl
//   Recurloop --import /tmp/recurloop-shell-library.rli \
//       --file examples/07-workflows/shell-language/top_level.rl

var project = "RecurLoop"
var iteration = 5

// These are ordinary RecurLoop values. Shell interpolation evaluates normal
// expressions against the very same store used by print and set.
print iteration
run printf "hello {upper(project)} #{iteration + 1}\\n"

run true
var successful = status
assert successful == 0

capture printf "captured-{iteration}\\n"
print trim(captured)

iteration += 2
print iteration

directory "/tmp" {
    run pwd
}

var RECURLOOP_SHELL_VALUE = iteration
environment "RECURLOOP_SHELL_VALUE" {
    run printenv RECURLOOP_SHELL_VALUE
}

parallel {
    run printf "parallel-{iteration}\\n" > /tmp/recurloop-shell-top-a.txt
    run printf "second-{project}\\n" > /tmp/recurloop-shell-top-b.txt
}

run cat /tmp/recurloop-shell-top-a.txt /tmp/recurloop-shell-top-b.txt
