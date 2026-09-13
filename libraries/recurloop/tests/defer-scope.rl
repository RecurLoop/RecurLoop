recur {
    fn mark(target:i64*, digit:i64) -> i64 {
        target[0] = target[0] * 10 + digit
        return 0
    }

    fn scoped(marker:i64*) -> i64 {
        defer mark(marker, 1)
        if 1 {
            defer mark(marker, 2)
            mark(marker, 3)
        }
        mark(marker, 4)
        return 9
    }

    var marker = 0
    const result = scoped(&marker)
    if result != 9 || marker != 3241 { return 41 }
    printf("scope=%lld\n", marker)
}
