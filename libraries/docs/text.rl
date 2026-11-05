link shared "c"
extern strstr(haystack:u8*, needle:u8*) -> u8* abi sysv-amd64
extern calloc(count:u64, size:u64) -> u8* abi sysv-amd64
extern fseek(stream:u8*, offset:i64, origin:i32) -> i32 abi sysv-amd64
extern ftell(stream:u8*) -> i64 abi sysv-amd64
extern fwrite(data:u8*, size:u64, count:u64, stream:u8*) -> u64 abi sysv-amd64
extern snprintf(buffer:u8*, size:u64, format:u8*, ...) -> i32 abi sysv-amd64
extern access(path:u8*, mode:i32) -> i32 abi sysv-amd64

let Docs = []

let Docs:copy = fn (text:u8*) -> u8* { return LanguageKit:copy_text(text) }
let Docs:empty = fn (text:u8*) -> i64 { return !text || text[0] == 0 }
let Docs:trim = fn (text:u8*) -> u8* {
    if !text { return text }
    var size = cast(i64, strlen(text))
    while size > 0 && (text[size - 1] == 10 || text[size - 1] == 13 || text[size - 1] == 32) { size -= 1 }
    text[size] = 0
    return text
}
let Docs:join = fn (left:u8*, right:u8*) -> u8* {
    if right && right[0] == 47 { return Docs:copy(right) }
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    defer out.destroy()
    if !out.append(left) || !out.append("/") || !out.append(right) { return cast(u8*, 0) }
    return out.take()
}
let Docs:read_file = fn (path:u8*) -> u8* {
    let stream = fopen(path, "rb")
    if !stream { return cast(u8*, 0) }
    defer fclose(stream)
    if fseek(stream, 0, 2) != 0 { return cast(u8*, 0) }
    let size = ftell(stream)
    if size < 0 || size > 16777216 || fseek(stream, 0, 0) != 0 { return cast(u8*, 0) }
    let out = malloc(cast(u64, size + 1))
    if !out { return out }
    if size > 0 && fread(out, 1, cast(u64, size), stream) != cast(u64, size) { free(out); return cast(u8*, 0) }
    out[size] = 0
    return out
}
let Docs:write_file = fn (path:u8*, text:u8*) -> i64 {
    let stream = fopen(path, "wb")
    if !stream { return 0 }
    let size = strlen(text)
    let written = fwrite(text, 1, size, stream)
    let closed = fclose(stream)
    return written == size && closed == 0
}
let Docs:nibble = fn (value:u8) -> i64 {
    if value >= 48 && value <= 57 { return value - 48 }
    if value >= 97 && value <= 102 { return value - 87 }
    if value >= 65 && value <= 70 { return value - 55 }
    return -1
}
let Docs:decode = fn (hex:u8*) -> u8* {
    let size = cast(i64, strlen(hex))
    if size % 2 != 0 { return cast(u8*, 0) }
    let out = malloc(cast(u64, size / 2 + 1))
    if !out { return out }
    var i = 0
    while i < size {
        let high = Docs:nibble(hex[i])
        let low = Docs:nibble(hex[i + 1])
        if high < 0 || low < 0 { free(out); return cast(u8*, 0) }
        out[i / 2] = cast(u8, high * 16 + low)
        i += 2
    }
    out[size / 2] = 0
    return out
}
let Docs:json = fn (out:LanguageKit:Text*, value:u8*) -> i64 {
    if !value { return out.append("null") }
    if !out.append("\"") { return 0 }
    let digits = "0123456789abcdef"
    var i = 0
    while value[i] != 0 {
        let ch = value[i]
        if ch == 34 { if !out.append("\\\"") { return 0 } }
        else if ch == 92 { if !out.append("\\\\") { return 0 } }
        else if ch == 10 { if !out.append("\\n") { return 0 } }
        else if ch == 13 { if !out.append("\\r") { return 0 } }
        else if ch == 9 { if !out.append("\\t") { return 0 } }
        else if ch < 32 {
            if !out.append("\\u00") || !out.append_byte(digits[ch / 16]) || !out.append_byte(digits[ch % 16]) { return 0 }
        } else { if !out.append_byte(ch) { return 0 } }
        i += 1
    }
    return out.append("\"")
}
let Docs:basename = fn (path:u8*) -> u8* {
    if !path { return cast(u8*, 0) }
    var result = path
    var i = 0
    while path[i] != 0 { if path[i] == 47 { result = &path[i + 1] }; i += 1 }
    return result
}
let Docs:page_id = fn (name:u8*) -> u8* {
    var hash = cast(u64, 5381)
    var i = 0
    while name[i] != 0 { hash = hash * 131 + cast(u64, name[i]); i += 1 }
    let out = malloc(32)
    if out { snprintf(out, 32, "api-%016llx", hash) }
    return out
}

