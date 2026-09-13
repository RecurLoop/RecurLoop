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

    fn nested(marker:i64*, enabled:i64) -> i64 {
        defer mark(marker, 1)
        if enabled {
            defer mark(marker, 2)
            return 7
        }
        defer mark(marker, 3)
        return 8
    }

    var marker = 0
    const result = work(&marker)
    if result != 21 || marker != 21 { return 21 }

    marker = 0
    const nested_result = nested(&marker, 1)
    if nested_result != 7 || marker != 21 { return 22 }

    printf("defer=%lld,%lld\n", result, marker)
}
