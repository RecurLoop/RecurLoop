recur {
    fn factorial(value:i64) -> i64 {
        if value <= 1 {
            return 1
        }
        return value * factorial(value - 1)
    }

    fn sum_to(value:i64) -> i64 {
        var current = value
        var total = 0
        while current > 0 {
            total += current
            current -= 1
        }
        return total
    }

    let first = factorial(6)
    const second = sum_to(10)
    if first != 720 {
        return 11
    } else if second != 55 {
        return 12
    } else {
        printf("functions=%lld,%lld\n", first, second)
    }
}
