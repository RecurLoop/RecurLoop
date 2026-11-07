// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:native_output = [
    id = phrase { payload = "native-output" }
    title = phrase { payload = "Native output" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "210" }
    body = phrase {
        payload = "Output directives turn language-defined functions and data into files. Use them after you understand native interfaces and the resources required by your application.

## Emit bytes, objects and executables

The language can emit exact bytes, objects, and executables:

```rl
emit raw \"/tmp/data.bin\" = hex { 52 4c 0a }
emit object \"/tmp/module.o\" add = fn (a:i64, b:i64) -> i64 {
    return a + b
}
emit executable \"/tmp/app\" app_main = fn () -> i64 {
    return 0
}
emit executable debug \"/tmp/app-debug\" app_debug_main = fn () -> i64 {
    return 0
}
```

## Select release or debug output

`emit executable` defaults to release output: PIE, immediate binding with
full RELRO, a non-executable stack, x86-64 CET/IBT metadata and landing pads,
stack canaries in generated `fn` code, and a stripped static symbol table.
The `debug` form retains symbols and exact statement/local-layout metadata while
retaining the security properties. LLVM-enabled hosts use the built-in debug
generator for the entry and reachable source functions, linked by the configured
Clang/LLD toolchain. See [Project debugging](../../../libraries/project/docs/debug-targets.rl) for source and executable debug targets.
The built-in generator supports `f32` and `f64` arithmetic, numeric casts,
compound assignments, and scalar System V arguments and results. Variadic calls
promote `f32` to `f64` and narrow integers to `i32` in both backends.
Hand-written `asm` remains responsible for valid indirect-branch landing
pads inside the user-controlled instruction stream.


## Compose modules and link inputs

`module auto` closes native dependencies automatically. `module manual`,
`module include`, `module exclude`, `module dynamic`, `module entry`,
`module embed`, `module strip`, and `module clear` control composition
explicitly. `link object`, `link archive`, `link path`,
`link library`, and `link shared` configure external inputs.

## Resolve shared libraries

On Linux, `link shared \"name\"` first uses the normal `libname.so` lookup. If
only a runtime SONAME such as `libname.so.1` is installed, RecurLoop also
searches the configured runtime-loader directories (`link path`,
`LD_LIBRARY_PATH`, and `ld.so.conf`) for versioned `.so` files. JIT execution
loads that file directly; native executable emission passes its directory and
exact basename to the platform linker (`-L... -l:libname.so.1`). Neither path
therefore depends on a development-package `libname.so` linker symlink."
    }
]
