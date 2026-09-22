link shared "c"
extern free(pointer:u8*) -> void abi sysv-amd64

record AllocationProbe {
    first:i64
    second:i64
    next:AllocationProbe*
}

let allocation_probe = fn () -> i64 {
    let value = alloc(AllocationProbe)
    if !value { return 1 }
    value.first = 17
    value.second = 25
    value.next = cast(AllocationProbe*, 0)
    let result = value.first + value.second
    free(cast(u8*, value))
    if sizeof(AllocationProbe) != 24 { return 2 }
    if sizeof(AllocationProbe*) != 8 { return 3 }
    return result - 42
}

assert allocation_probe() == 0
