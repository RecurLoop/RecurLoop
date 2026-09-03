// Function types are structural values: parameters, result, ABI and variadic
// state are all part of the type. The expected callback type also selects an
// overload when a function name denotes more than one variant.

let increment = fn (value:i64) -> i64 {
    return value + 1
}

let increment = fn (value:u8*) -> i64 {
    return 100
}

let double = fn (value:i64) -> i64 {
    return value * 2
}

let apply_twice = fn (callback:fn (i64) -> i64, value:i64) -> i64 {
    return callback(callback(value))
}

let choose = fn (incrementing:i64) -> fn (i64) -> i64 {
    if incrementing != 0 {
        return increment
    } else {
        return double
    }
}

let callback_example = fn () -> i64 {
    let selected:fn (i64) -> i64 = choose(1)
    let selected_result = apply_twice(selected, 40)
    let inline_result = apply_twice(
        fn (value:i64) -> i64 { return value + 1 },
        40
    )
    return selected_result + inline_result - 42
}

assert callback_example() == 42
print callback_example()
debug:stats
