// Primary and postfix syntax is resolved through the lexicon just like
// statements and operators. These aliases therefore change compiled fn syntax
// without adding another parser rule.

let open = <(>
let close = <)>
let at = <[>
let end_at = <]>
let member = <.>
let or_null = <?>
let convert = <cast>
let when = <if>
let otherwise = <else>
let begin = <{>
let end = <}>

record Cell {
    value:i64
}

let read = fn (cell:Cell*) -> i64 {
    return cell member value
}

let first = fn (values:i64*) -> i64 {
    return values at 0 end_at
}

let identity = fn (value:i64) -> i64 {
    return value
}

let require = fn (value:i64*) -> i64* {
    return value or_null
}

let phrase_driven_parselets = fn () -> i64 {
    var value = 42
    var real = 42.5
    return when identity open first open require open &value close close close == convert open i64, real close begin
        42
    end otherwise begin
        0
    end
}

assert phrase_driven_parselets() == 42
