// Smoke test for /tmp/recurloop-amber-library.rli
//
// Build the image first:
//   build/Debug/bin/recurloop --file recurloop-amber-library.rl
// Then run:
//   build/Debug/bin/recurloop --import /tmp/recurloop-amber-library.rli \
//       --file recurloop-amber-smoke.rl

let project = "RecurLoop"
let iteration = 41

// Amber command statement + interpolation.
$ printf "hello-{project}-{iteration + 1}\\n" $
assert status() == 0

// Amber command expression: stdout becomes the value instead of being printed.
let captured_output = $ printf "alpha\\nbeta\\ngamma\\n" | grep beta $
echo(captured_output)
assert status() == 0

// Amber `let` is mutable. The compatibility layer lowers it to RecurLoop `var`.
let mutable = 40
mutable += 2
assert mutable == 42

// Outcome handlers.
$ sh -c "exit 7" $ failed(code) {
    assert code == 7
    echo(code)
}

$ true $ succeeded {
    echo("succeeded")
}

$ sh -c "exit 9" $ exited(code) {
    assert code == 9
}

// `trust` is accepted. It is a semantic no-op because RecurLoop does not yet
// require compile-time handling of every failable command.
trust $ sh -c "exit 5" $
assert status() == 5

// Output modifiers.
silent $ printf "this stdout is hidden\\n" $
suppress trust $ sh -c "printf hidden-error >&2; exit 3" $
assert status() == 3

// Parent-process builtin. Capture `pwd` as Text at top level.
assert cd("/tmp") == 0
let here = $ pwd $
echo(here)
assert status() == 0

// Phrase aliases usable by RecurLoop's compiled function syntax. This is the
// closest current mapping, NOT Amber's exact `fun name(...): Type` spelling.
let amber_add = fun (left:Int, right:Int) -> Int {
    if left > 0 and not (right < 0) {
        return left + right
    }
    return 0
}
assert amber_add(20, 22) == 42

echo("Amber compatibility smoke test complete")
