recur {
    var remaining = 10
    var total = 0
    while remaining > 0 {
        total += remaining
        remaining -= 1
    }
    if remaining != 0 { return 21 }
    if total != 55 { return 22 }
}
