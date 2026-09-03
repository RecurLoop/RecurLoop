// =============================================================================
// Phrase aliases
//
// An alias is an ordinary RecurLoop phrase. The compiler does not receive a
// new keyword for any of the names below: it follows the prototype chain in
// the lexicon and resolves the corresponding grammar entry.
//
// Expected output:
//   5
//   13
//   1
//   42
// =============================================================================

// Parser-only forms have data markers in the root lexicon. They are not
// executable phrases, but they can be referenced and aliased like any other
// phrase.
let branch = <if>
let otherwise = <else>
let done = <return>

// Operators and expression builtins use the same prototype mechanism.
let plus = <+>
let add = <+=>
let stringify = <str>

// `+=` works in ordinary root code as well as in compiled function bodies.
var total = 3
total add 2
assert total == 5
print stringify(total)

// The function literal itself is also aliasable. `make` still invokes the
// normal fn compiler action; only its user-facing spelling changed.
let make = <fn>

let calculate = make (value:i64) -> i64 {
    branch value > 2 {
        done value plus 10
    } otherwise {
        done 1
    }
}

let increment = make (value:i64) -> i64 {
    done value plus 1
}

assert calculate(3) == 13
assert calculate(1) == 1
assert increment(41) == 42

print stringify(calculate(3))
print stringify(calculate(1))
print stringify(increment(41))
