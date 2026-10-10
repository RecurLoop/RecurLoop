// Bitwise operations on 64-bit integers. Shift counts must be in 0..63.

extern strcmp(left:u8*, right:u8*) -> i32 abi sysv-amd64

let Bitwise = phrase { docs = "Bitwise operations on 64-bit integers. All shift counts must be in the range 0..63." dictionary = true }

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

set Bitwise:and_u64.docs = "Returns the bitwise AND of two unsigned 64-bit values."
set Bitwise:or_u64.docs = "Returns the bitwise OR of two unsigned 64-bit values."
set Bitwise:xor_u64.docs = "Returns the bitwise exclusive OR of two unsigned 64-bit values."
set Bitwise:not_u64.docs = "Inverts every bit of an unsigned 64-bit value."
set Bitwise:shl_u64.docs = "Shifts left by count bits, discarding overflow. Count must be in 0..63."
set Bitwise:shr_u64.docs = "Shifts right by count bits, filling with zeros. Count must be in 0..63."
set Bitwise:and.docs = "Returns the bitwise AND of the 64-bit representations of two signed integers."
set Bitwise:or.docs = "Returns the bitwise OR of the 64-bit representations of two signed integers."
set Bitwise:xor.docs = "Returns the bitwise exclusive OR of the 64-bit representations of two signed integers."
set Bitwise:not.docs = "Inverts every bit of a signed 64-bit integer."
set Bitwise:shl.docs = "Shifts a signed integer's bit pattern left, discarding overflow. Count must be in 0..63."
set Bitwise:shr.docs = "Shifts a signed integer right, preserving its sign bit. Count must be in 0..63."

include "../build/export.rl"
__recurloop_export_library
