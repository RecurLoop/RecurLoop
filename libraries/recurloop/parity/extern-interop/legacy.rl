link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64
let extern_parity = fn () -> i64 {
    const memory = malloc(8)
    if !memory { return 1 }
    const typed = cast(i64*, memory)
    typed[0] = 42
    const result = typed[0]
    free(memory)
    printf("extern=%lld\n", result)
    if result != 42 { return 2 }
    return 0
}
assert extern_parity() == 0
