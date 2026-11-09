import project
let Application = [
    answer = fn () -> i64 { return 42 }
]
target run { print Application:answer() }
target test { assert Application:answer() == 42 }
