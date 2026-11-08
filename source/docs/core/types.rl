// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:types = [
    id = phrase { payload = "types" }
    title = phrase { payload = "Native types" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "130" }
    body = phrase {
        payload = "Native types specify the representation used by compiled code. They complement the runtime value kinds introduced in [Values](values.rl).

## Scalar, pointer and array types

Built-in native types include signed and unsigned integers (`i8` through
`i64`, `u8` through `u64`), `f32`, `f64`, `void`, `Context`, and `Phrase`.
Pointers use `*`, arrays use `[N]`, and function types use
`fn (...) -> ...`.

## Compile-time constants

Array lengths may be non-negative integer constants, including qualified names
such as `u8[Layout:BrickCount]`. Compiled functions read `const` bindings in their
lexical dictionary scope and embed their values in native code; local variables
and parameters take precedence. Mutable interpreter bindings are not captured.

## Function types

Function types are structural: parameter types, result, calling convention,
and variadic state determine identity. A named signature phrase can be reused
as both a definition template and a type.

```recurloop
let Unary = fn (value:i64) -> i64

let increment = Unary {
    return value + 1
}

let apply = fn (callback:Unary, value:i64) -> i64 {
    return callback(value)
}
let check_callback = fn () -> i64 {
    return apply(increment, 41)
}
assert check_callback() == 42
```"
    }
]
