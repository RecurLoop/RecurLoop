// Run after importing /tmp/recurloop-declarative-syntax.rli.

var from_unless = 0
unless false {
    from_unless = 1
}
assert from_unless == 1

// `syntax extend if ...` must preserve both the previous and the new form.
var plain_if = 0
if true {
    plain_if = 2
}
assert plain_if == 2

var parenthesized_if = 0
if (true) {
    parenthesized_if = 3
}
assert parenthesized_if == 3

let imported = fn (value:i64) -> i64 {
    unless value == 0 {
        if (value > 0) {
            return value
        }
    }
    return 7
}
assert imported(42) == 42
assert imported(0) == 7

print "declarative syntax import ok"
