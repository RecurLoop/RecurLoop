// =============================================================================
// Lexical function lookup
//
// A function is a phrase and may therefore be a dictionary. A bare function
// name is searched from the current function phrase towards the root. For
// `Workshop:Nested:run`, `helper` is tested in this order:
//
//   Workshop:Nested:run:helper
//   Workshop:Nested:helper
//   Workshop:helper
//   helper
//
// The first matching phrase supplies the complete overload dictionary. Parent
// overloads are not merged into it, just as matchLongest does not merge a
// shorter match into the longest one.
// =============================================================================

let Workshop = []

let Workshop:increment = fn (value:i64) -> i64 {
    return value + 1
}

let Workshop:increment = fn (value:u8*) -> i64 {
    return 100
}

let Workshop:apply = fn (callback:fn (i64) -> i64, value:i64) -> i64 {
    return callback(value)
}

// A nested namespace can use functions from its parent without qualification.
let Workshop:Nested = []

let Workshop:Nested:from_parent = fn () -> i64 {
    return increment(41)
}

// A nearer phrase shadows the complete parent overload dictionary.
let Workshop:Nested:increment = fn (value:i64) -> i64 {
    return value + 2
}

let Workshop:Nested:from_nearest = fn () -> i64 {
    return increment(40)
}

// Function references and calls use exactly the same lexical resolver.
let Workshop:callback = fn () -> i64 {
    let selected:fn (i64) -> i64 = increment
    return apply(selected, 41)
}

// An inline function inherits the lexical scope of its enclosing function.
let Workshop:inline_callback = fn () -> i64 {
    return apply(fn (value:i64) -> i64 { return increment(value) }, 41)
}

// Since every function phrase can own a dictionary, lookup starts at the
// function itself. The placeholder creates that dictionary before `run` is
// compiled; replacing it with fn retains it through the phrase prototype.
let Workshop:run = []

let Workshop:run:increment = fn (value:i64) -> i64 {
    return value + 3
}

let Workshop:run = fn () -> i64 {
    return increment(39)
}

let lexical_lookup_example = fn () -> i64 {
    return Workshop:Nested:from_parent() + Workshop:Nested:from_nearest() + Workshop:callback() + Workshop:inline_callback() + Workshop:run()
}

assert lexical_lookup_example() == 210
print lexical_lookup_example()
