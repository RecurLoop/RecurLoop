var remaining = 10
var total = 0
while remaining > 0 {
    total += remaining
    remaining -= 1
}
assert remaining == 0
assert total == 55
