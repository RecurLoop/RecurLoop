// Declarative syntax compiles to ordinary rewritable, serializable phrases.

syntax unless <condition:expr> <body:block> => if (!(${condition})) ${body}

var top_level = 0
unless false {
    top_level = 42
}
assert top_level == 42

let choose = fn (value:i64) -> i64 {
    unless value == 0 {
        return value
    }
    return 7
}

assert choose(42) == 42
assert choose(0) == 7
