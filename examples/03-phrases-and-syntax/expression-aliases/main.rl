// The same phrase-defined expression syntax is accepted at top level and in
// native fn bodies. Group delimiters can be replaced by ordinary aliases.

let open = <(>
let close = <)>
let scope = <":">

let Math = [
    answer = fn () -> i64 { return 42 }
]

const top_level_answer = open
    10 +
    20 +
    12
close

const top_level_qualified = Math scope answer()

let compiled_answer = fn () -> i64 {
    var value = open
        10 +
        20 +
        12
    close
    return value
}

let compiled_qualified = fn () -> i64 {
    return Math scope answer()
}

assert top_level_answer == 42
assert top_level_qualified == 42
assert compiled_answer() == 42
assert compiled_qualified() == 42
