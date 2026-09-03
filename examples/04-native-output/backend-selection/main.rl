// The same source works with both backends. `make release` enables LLVM for fn
// compilation, compiled phrase blocks, and native artifacts. Direct CMake
// configurations keep LLVM disabled unless explicitly requested.

extern llvm_example_assembly_value() -> i64 abi sysv-amd64
let llvm_example_assembly_value = asm {
    mov rax, 37
    ret
}

// This function is compiled for immediate use and reused as a dependency of
// the emitted entry point.
fn llvm_example_dependency(value:i64) -> i64 {
    return value
}

emit object "/tmp/recurloop-llvm-example.o" llvm_example_add = fn (left:i64, right:i64) -> i64 {
    return left + right
}

emit executable "/tmp/recurloop-llvm-example" llvm_example_main = fn () -> i64 {
    var fraction = 0.5
    return llvm_example_assembly_value() + llvm_example_dependency(cast(i64, fraction * 10.0)) - 42
}

fn llvm_example_runtime_add(left:i64, right:i64) -> i64 {
    return left + right
}
assert llvm_example_runtime_add(20, 22) == 42
