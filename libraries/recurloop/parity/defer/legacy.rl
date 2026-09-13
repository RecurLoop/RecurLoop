link shared "c"
extern printf(format:u8*, ...) -> i64 abi sysv-amd64
let mark = fn (target:i64*, digit:i64) -> i64 {
    target[0] = target[0] * 10 + digit
    return 0
}
let work = fn (marker:i64*) -> i64 {
    defer mark(marker, 1)
    defer mark(marker, 2)
    return 21
}
let defer_parity = fn () -> i64 {
    var marker = 0
    const result = work(&marker)
    printf("defer=%lld,%lld\n", result, marker)
    if result != 21 || marker != 21 { return 1 }
    return 0
}
assert defer_parity() == 0
