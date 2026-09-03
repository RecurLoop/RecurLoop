// `fn` creates a compiled, typed function phrase. Functions can call
// themselves and other functions using ordinary expressions.

fn factorial(value:i64) -> i64 {
    if value <= 1 {
        return 1
    }
    return value * factorial(value - 1)
}

fn sum_to(value:i64) -> i64 {
    var current = value
    var total = 0
    while current > 0 {
        total += current
        current -= 1
    }
    return total
}

assert factorial(6) == 720
assert sum_to(10) == 55
print "factorial(6) = " + str(factorial(6))
print "sum_to(10) = " + str(sum_to(10))
