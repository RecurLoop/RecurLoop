recur {
    fn mark(target:i64*, digit:i64) -> i64 {
        target[0] = target[0] * 10 + digit
        return 0
    }
    fn work(marker:i64*) -> i64 {
        defer mark(marker, 1)
        defer mark(marker, 2)
        return 21
    }
    var marker = 0
    const result = work(&marker)
    if result != 21 || marker != 21 { return 1 }
    printf("defer=%lld,%lld\n", result, marker)
}
