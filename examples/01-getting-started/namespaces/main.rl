// A dictionary is also a namespace. No separate `namespace` keyword is needed.

let Math = [
    gcd = fn (left:i64, right:i64) -> i64 {
        var a = left
        var b = right
        while b != 0 {
            var remainder = a % b
            a = b
            b = remainder
        }
        return a
    }

    fibonacci = fn (n:i64) -> i64 {
        if n < 2 {
            return n
        }
        // The nearest matching function dictionary is Math:fibonacci itself.
        return fibonacci(n - 1) + fibonacci(n - 2)
    }
]

let namespace_example = fn () -> i64 {
    return Math:gcd(84, 30) + Math:fibonacci(10)
}

assert namespace_example() == 61
print namespace_example()

debug:stats
