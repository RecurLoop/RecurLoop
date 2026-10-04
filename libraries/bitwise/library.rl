// Bitwise operations on 64-bit integers. Shift counts must be in 0..63.

extern strcmp(left:u8*, right:u8*) -> i32 abi sysv-amd64

let Bitwise = phrase { dictionary = true }

let bitwise_and_u64 = asm {
    mov rax, rdi
    and rax, rsi
    ret
}
function bitwise_and_u64(left:u64, right:u64) -> u64 abi sysv-amd64

let bitwise_or_u64 = asm {
    mov rax, rdi
    or rax, rsi
    ret
}
function bitwise_or_u64(left:u64, right:u64) -> u64 abi sysv-amd64

let bitwise_xor_u64 = asm {
    mov rax, rdi
    xor rax, rsi
    ret
}
function bitwise_xor_u64(left:u64, right:u64) -> u64 abi sysv-amd64

let bitwise_not_u64 = asm {
    mov rax, rdi
    not rax
    ret
}
function bitwise_not_u64(value:u64) -> u64 abi sysv-amd64

let bitwise_shl_u64 = asm {
    mov rax, rdi
    mov rcx, rsi
    shl rax, cl
    ret
}
function bitwise_shl_u64(value:u64, count:u64) -> u64 abi sysv-amd64

let bitwise_shr_u64 = asm {
    mov rax, rdi
    mov rcx, rsi
    shr rax, cl
    ret
}
function bitwise_shr_u64(value:u64, count:u64) -> u64 abi sysv-amd64

let bitwise_sar_i64 = asm {
    mov rax, rdi
    mov rcx, rsi
    sar rax, cl
    ret
}
function bitwise_sar_i64(value:i64, count:i64) -> i64 abi sysv-amd64

let Bitwise:and_u64 = fn (left:u64, right:u64) -> u64 {
    return bitwise_and_u64(left, right)
}

let Bitwise:or_u64 = fn (left:u64, right:u64) -> u64 {
    return bitwise_or_u64(left, right)
}

let Bitwise:xor_u64 = fn (left:u64, right:u64) -> u64 {
    return bitwise_xor_u64(left, right)
}

let Bitwise:not_u64 = fn (value:u64) -> u64 {
    return bitwise_not_u64(value)
}

let Bitwise:shl_u64 = fn (value:u64, count:u64) -> u64 {
    return bitwise_shl_u64(value, count)
}

let Bitwise:shr_u64 = fn (value:u64, count:u64) -> u64 {
    return bitwise_shr_u64(value, count)
}

let Bitwise:and = fn (left:i64, right:i64) -> i64 {
    return cast(i64, bitwise_and_u64(cast(u64, left), cast(u64, right)))
}

let Bitwise:or = fn (left:i64, right:i64) -> i64 {
    return cast(i64, bitwise_or_u64(cast(u64, left), cast(u64, right)))
}

let Bitwise:xor = fn (left:i64, right:i64) -> i64 {
    return cast(i64, bitwise_xor_u64(cast(u64, left), cast(u64, right)))
}

let Bitwise:not = fn (value:i64) -> i64 {
    return cast(i64, bitwise_not_u64(cast(u64, value)))
}

let Bitwise:shl = fn (value:i64, count:i64) -> i64 {
    return cast(i64, bitwise_shl_u64(cast(u64, value), cast(u64, count)))
}

let Bitwise:shr = fn (value:i64, count:i64) -> i64 {
    return bitwise_sar_i64(value, count)
}

include "../build/export.rl"
__recurloop_export_library
