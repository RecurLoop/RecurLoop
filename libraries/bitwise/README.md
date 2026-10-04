# Bitwise

Bitwise provides named 64-bit helper functions implemented with RecurLoop `asm`.
The standard language also supports `&`, `|`, `^`, `~`, `<<`, and `>>` directly
in compiled `fn` bodies and top-level expressions.

Build the image and load it before the program that uses it:

```bash
build/Release/bin/recurloop --file libraries/bitwise/library.rl -- /tmp/bitwise.rli
build/Release/bin/recurloop --import /tmp/bitwise.rli --file program.rl
```

The signed `i64` functions are `Bitwise:and`, `Bitwise:or`, `Bitwise:xor`,
`Bitwise:not`, `Bitwise:shl`, and `Bitwise:shr`. The `u64` functions have the
same names with an `_u64` suffix. Signed `shr` copies the sign bit; `shr_u64`
shifts in zeroes. Use shift counts from 0 through 63. Other counts follow
x86-64's masked shift-count behavior.

```rl
fn bit(index:i64, target:i64) -> i64 {
    return Bitwise:and(Bitwise:shr(index, target), 1)
}

fn flip(index:i64, target:i64) -> i64 {
    return Bitwise:xor(index, Bitwise:shl(1, target))
}

assert bit(10, 1) == 1
assert flip(10, 1) == 8
```

For new code, the built-in operators avoid the helper function calls. This
library remains useful when a named function is preferable.
