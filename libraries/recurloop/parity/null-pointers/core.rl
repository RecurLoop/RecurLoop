recur {
    fn require(value:i64*) -> i64* { return value? }
    var value = 42
    const present = cast(i64, require(&value)) != 0
    const absent = cast(i64, require(cast(i64*, 0))) == 0
    if !present || !absent { return 1 }
    printf("null=%lld,%lld\n", present, absent)
}
