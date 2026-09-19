// =============================================================================
// RecurLoop embedded binary data.
//
// Source-time producers call Embed:emit_bytes / Embed:emit_bits from a syntax
// action. The helper rewrites the current expression to a native bits"..."
// literal, which the normal RecurLoop compiler places directly in .rodata.
// There is no asset-specific format and no runtime loader.
// =============================================================================

languagekit_native_begin

let Embed = phrase { dictionary = true permanent = true }

let Embed:bit = fn (value:u8, index:u64) -> u8 {
    var divisor:u64 = 128
    var current:u64 = 0
    while current < index {
        divisor = divisor / 2
        current += 1
    }
    return cast(u8, (cast(u64, value) / divisor) % 2)
}

let Embed:emit_bits = fn (state:Context*, data:u8*, bits:u64) -> i64 {
    if !state || (!data && bits != 0) { return 0 }

    let source = LanguageKit:Text:new()
    if !source { return 0 }
    defer source.destroy()

    if !source.append("bits\"") { return 0 }
    var index:u64 = 0
    while index < bits {
        let bit = Embed:bit(data[index / 8], index % 8)
        if bit == 0 {
            if !source.append_byte(48) { return 0 }
        } else {
            if !source.append_byte(49) { return 0 }
        }
        index += 1
    }
    if !source.append("\"") { return 0 }

    context:syntax:emit(state, source.data)
    return 1
}

let Embed:emit_bytes = fn (state:Context*, data:u8*, bytes:u64) -> i64 {
    return Embed:emit_bits(state, data, bytes * 8)
}

// Runtime view of an embedded literal. The bytes stay owned by the executable
// (or JIT module) and therefore must not be freed.
let Embed:data = fn (blob:BitString*) -> u8* {
    if !blob { return cast(u8*, 0) }
    return blob.data
}

let Embed:bits = fn (blob:BitString*) -> u64 {
    if !blob { return 0 }
    return blob.bits
}

let Embed:bytes = fn (blob:BitString*) -> u64 {
    if !blob { return 0 }
    return (blob.bits + 7) / 8
}

languagekit_native_end
include "../build/export.rl"
__recurloop_export_library
