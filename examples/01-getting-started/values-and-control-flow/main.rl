// Runtime values use familiar expressions and lexical control flow.

var remaining = 5
var total = 0

while remaining > 0 {
    total += remaining
    remaining -= 1
}

var description = "unexpected result"
if total == 15 {
    description = "sum computed correctly"
}

assert remaining == 0
assert total == 15
print description + ": " + str(total)
