link shared "c"
extern printf(format:u8*, ...) -> i64 abi sysv-amd64
let add = fn (a:i64, b:i64) -> i64 { return a + b }
let function_value_parity = fn () -> i64 {
    let target:fn (i64, i64) -> i64 = add
    const result = target(20, 22)
    printf("function-value=%lld\n", result)
    if result != 42 { return 1 }
    return 0
}
assert function_value_parity() == 0
