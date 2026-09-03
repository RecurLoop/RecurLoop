// Real literals use the shared literal scanner. Arithmetic and casts in fn
// are still emitted by behaviors attached to operator and intrinsic phrases.

let scaled = fn () -> i64 {
    var value = 0.5
    return cast(i64, value * 10.0)
}

assert scaled() == 5
print scaled()
