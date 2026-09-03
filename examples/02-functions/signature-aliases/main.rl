// A signature without a body is an ordinary phrase. It can define functions,
// name their structural type, live in a namespace, and be aliased by prototype.

let Nullary = fn () -> i64
let Unary = fn (value:i64) -> i64

let answer = Nullary {
    return 42
}

// Signature phrases also support the direct, named form.
Unary increment {
    return value + 1
}

// A normal phrase alias retains both the compiler action and the signature.
let UnaryAlias = <Unary>

let double = UnaryAlias {
    return value * 2
}

// The alias is a transparent name for the existing structural function type.
let apply = fn (callback:Unary, value:i64) -> i64 {
    return callback(value)
}

let apply_structural = fn (callback:fn (i64) -> i64, value:i64) -> i64 {
    return callback(value)
}

// Different signature phrases can add variants to one overload dictionary.
let IntegerClassifier = fn (value:i64) -> i64
let TextClassifier = fn (value:u8*) -> i64

let classify = IntegerClassifier {
    return value + 100
}

let classify = TextClassifier {
    return 200
}

let Signature = []
let Signature:Unary = fn (value:i64) -> i64

let Signature:decrement = Signature:Unary {
    return value - 1
}

// Unqualified type lookup starts in the function namespace and walks upward.
let Signature:apply = fn (callback:Unary, value:i64) -> i64 {
    return callback(value)
}

let signature_alias_example = fn () -> i64 {
    let selected:Unary = increment
    return answer() + apply(selected, 41) + apply_structural(double, 21) + classify(7) + classify("seven") + Signature:apply(Signature:decrement, 43)
}

assert signature_alias_example() == 475
print signature_alias_example()
