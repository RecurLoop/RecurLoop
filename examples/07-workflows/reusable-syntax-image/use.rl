// Run with:
//   Recurloop --import /tmp/recurloop-phrase-syntax.rli \
//     --file examples/07-workflows/reusable-syntax-image/use.rl

extern puts(text:u8*) -> i32 abi sysv-amd64

let answer = fn (enabled:number) -> number {
    // Rewrite keys inside comments are inert: integer plus truth unless all.
    let integer_value = 42
    unless all enabled {
        return truth off
    }
    return 20 plus integer_value - 20
}

let protected_text = fn () -> i64 {
    let text = "integer plus truth unless all"
    return text[0]
}

assert answer(1) == 42
assert answer(0) == 0
assert protected_text() == 105

let announce = fn () -> i64 {
    return puts("phrase-defined fn syntax loaded in a fresh process")
}
assert announce() > 0
