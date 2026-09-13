recur {
    fn add(a:i64, b:i64) -> i64 { return a + b }
    fn function_value_parity() -> i64 {
        let target:fn (i64, i64) -> i64 = add
        const result = target(20, 22)
        printf("function-value=%lld\n", result)
        if result != 42 { return 1 }
        return 0
    }
    if function_value_parity() != 0 { return 1 }
}
