recur {
    fn Safety:mark(target:i64*, digit:i64) -> i64 {
        target[0] = target[0] * 10 + digit
        return 0
    }
    fn Safety:work(marker:i64*) -> i64 {
        defer Safety:mark(marker, 1)
        defer Safety:mark(marker, 2)
        return 21
    }
    fn Safety:require(value:i64*) -> i64* {
        return value?
    }
    fn safety_example() -> i64 {
        var marker = 0
        let value = Safety:work(&marker)
        let present = cast(i64, Safety:require(&value)) != 0
        let absent = cast(i64, Safety:require(cast(i64*, 0))) == 0
        return value + marker + present - absent
    }
    const result = safety_example()
    if result != 42 { return 1 }
    printf("%lld\n", result)
}
