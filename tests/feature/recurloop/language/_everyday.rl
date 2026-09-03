const name = "  recurloop  "
var value = 2 + 3 * 4
set value += 7

fn identity(number:i64) -> i64 {
    return number
}

var index = 0
var sequence = ""
while index < 3 {
    set sequence += str(index)
    set index += 1
}

assert true || 1 / 0 == 0
assert identity(value) == 21
print upper(trim(name)) + ":ok"
print sequence
