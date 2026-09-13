recur {
    var remaining = 5
    var total = 0
    while remaining > 0 {
        total += remaining
        remaining -= 1
    }
    if remaining != 0 || total != 15 { return 1 }
    printf("sum computed correctly: %lld\n", total)
}
