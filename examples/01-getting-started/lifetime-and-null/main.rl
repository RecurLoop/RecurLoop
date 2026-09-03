// `defer` is LIFO cleanup. `?` is deliberately small: it propagates null only
// from a pointer expression in a pointer-returning compiled function.

let Safety = []

let Safety:mark = fn (target:i64*, digit:i64) -> i64 {
    target[0] = target[0] * 10 + digit
    return 0
}

let Safety:work = fn (marker:i64*) -> i64 {
    // Bare names start at Safety:work and walk through Safety to the root.
    defer mark(marker, 1)
    defer mark(marker, 2)
    return 21
}

let Safety:require = fn (value:i64*) -> i64* {
    return value?
}

let safety_example = fn () -> i64 {
    var marker = 0
    let value = Safety:work(&marker)
    let present = cast(i64, Safety:require(&value)) != 0
    let absent = cast(i64, Safety:require(cast(i64*, 0))) == 0
    return value + marker + present - absent
}

assert safety_example() == 42
print safety_example()
