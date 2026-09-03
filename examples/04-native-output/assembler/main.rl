// RecurLoop's assembler is phrase-driven too. A `function` declaration gives
// the machine-code phrase a typed calling convention for normal calls.

let native_add = asm {
    mov rax, rdi
    add rax, rsi
    ret
}
function native_add(left:u64, right:u64) -> u64 abi sysv-amd64

assert native_add(20, 22) == 42
print "native_add(20, 22) = " + str(native_add(20, 22))

// This also writes a real ELF64 relocatable object for inspection with
// `readelf -h -s /tmp/recurloop-assembler-example.o`.
module auto
module clear
emit object "/tmp/recurloop-assembler-example.o" exported_add = asm {
    mov rax, rdi
    add rax, rsi
    ret
}
