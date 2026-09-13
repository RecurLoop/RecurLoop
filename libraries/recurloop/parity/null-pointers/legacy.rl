link shared "c"
extern printf(format:u8*, ...) -> i64 abi sysv-amd64
let require = fn (value:i64*) -> i64* { return value? }
let null_parity = fn () -> i64 {
    var value = 42
    const present = cast(i64, require(&value)) != 0
    const absent = cast(i64, require(cast(i64*, 0))) == 0
    printf("null=%lld,%lld\n", present, absent)
    if !present || !absent { return 1 }
    return 0
}
assert null_parity() == 0
