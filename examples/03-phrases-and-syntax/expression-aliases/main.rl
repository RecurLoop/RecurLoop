// The same phrase-defined expression syntax is accepted at top level and in
// native fn bodies. Group delimiters can be replaced by ordinary aliases.

let open = <(>
let close = <)>

const top_level_answer = open
    10 +
    20 +
    12
close

let compiled_answer = fn () -> i64 {
    var value = open
        10 +
        20 +
        12
    close
    return value
}

assert top_level_answer == 42
assert compiled_answer() == 42
