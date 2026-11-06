// Bounded JSON reader for portable documentation, implemented in RecurLoop.
record Docs:Json { kind:i64 text:u8* key:u8* first:Docs:Json* last:Docs:Json* next:Docs:Json* }
record Docs:JsonReader { source:u8* at:i64 depth:i64 nodes:i64 error:i64 }
let Docs:json_space = fn (reader:Docs:JsonReader*) -> void {
    while reader.source[reader.at] == 32 || reader.source[reader.at] == 9 || reader.source[reader.at] == 10 || reader.source[reader.at] == 13 { reader.at += 1 }
}
let Docs:json_utf8 = fn (out:LanguageKit:Text*, value:i64) -> i64 {
    if value < 0 || value > 1114111 || (value >= 55296 && value <= 57343) { return 0 }
    if value < 128 { return out.append_byte(cast(u8, value)) }
    if value < 2048 { return out.append_byte(cast(u8, 192 + value / 64)) && out.append_byte(cast(u8, 128 + value % 64)) }
    if value < 65536 { return out.append_byte(cast(u8, 224 + value / 4096)) && out.append_byte(cast(u8, 128 + value / 64 % 64)) && out.append_byte(cast(u8, 128 + value % 64)) }
    return out.append_byte(cast(u8, 240 + value / 262144)) && out.append_byte(cast(u8, 128 + value / 4096 % 64)) && out.append_byte(cast(u8, 128 + value / 64 % 64)) && out.append_byte(cast(u8, 128 + value % 64))
}
let Docs:json_hex4 = fn (reader:Docs:JsonReader*) -> i64 {
    var value = 0; var count = 0
    while count < 4 {
        let digit = Docs:nibble(reader.source[reader.at])
        if digit < 0 { reader.error = 1; return -1 }
        value = value * 16 + digit; reader.at += 1; count += 1
    }; return value
}
let Docs:json_string = fn (reader:Docs:JsonReader*) -> u8* {
    if reader.source[reader.at] != 34 { reader.error = 1; return cast(u8*, 0) }
    reader.at += 1
    let out = LanguageKit:Text:new(); if !out { reader.error = 1; return cast(u8*, 0) }; defer out.destroy()
    while reader.source[reader.at] != 0 && reader.source[reader.at] != 34 {
        let ch = reader.source[reader.at]; reader.at += 1
        if ch < 32 { reader.error = 1; return cast(u8*, 0) }
        if ch != 92 { out.append_byte(ch); continue }
        let escape = reader.source[reader.at]; if escape == 0 { reader.error = 1; return cast(u8*, 0) }; reader.at += 1
        if escape == 34 || escape == 92 || escape == 47 { out.append_byte(escape) }
        else if escape == 110 { out.append_byte(10) }
        else if escape == 114 { out.append_byte(13) }
        else if escape == 116 { out.append_byte(9) }
        else if escape == 98 { out.append_byte(8) }
        else if escape == 102 { out.append_byte(12) }
        else if escape == 117 {
            var value = Docs:json_hex4(reader)
            if reader.error { return cast(u8*, 0) }
            if value >= 55296 && value <= 56319 {
                if reader.source[reader.at] != 92 || reader.source[reader.at + 1] != 117 { reader.error = 1; return cast(u8*, 0) }
                reader.at += 2; let low = Docs:json_hex4(reader)
                if reader.error || low < 56320 || low > 57343 { reader.error = 1; return cast(u8*, 0) }
                value = 65536 + (value - 55296) * 1024 + low - 56320
            }
            if value == 0 || !Docs:json_utf8(out, value) { reader.error = 1; return cast(u8*, 0) }
        } else { reader.error = 1; return cast(u8*, 0) }
    }
    if reader.source[reader.at] != 34 { reader.error = 1; return cast(u8*, 0) }
    reader.at += 1; return out.take()
}
let Docs:json_destroy = fn (node:Docs:Json*) -> void {
    if !node { return }; var child = node.first
    while child { let next = child.next; Docs:json_destroy(child); child = next }
    free(node.text); free(node.key); free(cast(u8*, node))
}
let Docs:json_field = fn (node:Docs:Json*, key:u8*) -> Docs:Json* {
    if !node || node.kind != 1 { return cast(Docs:Json*, 0) }
    var child = node.first
    while child { if child.key && strcmp(child.key, key) == 0 { return child }; child = child.next }; return cast(Docs:Json*, 0)
}
let Docs:json_value = fn (reader:Docs:JsonReader*) -> Docs:Json* {
    Docs:json_space(reader)
    if reader.depth >= 64 || reader.nodes >= 250000 { reader.error = 1; return cast(Docs:Json*, 0) }
    let node = cast(Docs:Json*, calloc(1, sizeof(Docs:Json)))
    if !node { reader.error = 1; return node }; reader.nodes += 1; reader.depth += 1
    let ch = reader.source[reader.at]
    if ch == 123 || ch == 91 {
        node.kind = 1; var close = 125
        if ch == 91 { node.kind = 2; close = 93 }; reader.at += 1; Docs:json_space(reader)
        if reader.source[reader.at] != close {
            while !reader.error {
                var key = cast(u8*, 0)
                if node.kind == 1 {
                    key = Docs:json_string(reader); Docs:json_space(reader)
                    if reader.error || reader.source[reader.at] != 58 || Docs:json_field(node, key) { free(key); reader.error = 1; break }; reader.at += 1
                }
                let child = Docs:json_value(reader)
                if !child { free(key); break }; child.key = key
                if node.last { node.last.next = child } else { node.first = child }; node.last = child
                Docs:json_space(reader)
                if reader.source[reader.at] == close { break }
                if reader.source[reader.at] != 44 { reader.error = 1; break }
                reader.at += 1; Docs:json_space(reader)
            }
        }
        if reader.source[reader.at] != close { reader.error = 1 } else { reader.at += 1 }
    } else if ch == 34 { node.kind = 3; node.text = Docs:json_string(reader) }
    else if ch == 110 || ch == 116 || ch == 102 {
        var literal = "null"; node.kind = 5
        if ch == 116 { literal = "true"; node.kind = 6 }; if ch == 102 { literal = "false"; node.kind = 7 }
        var at = 0
        while literal[at] != 0 { if reader.source[reader.at] != literal[at] { reader.error = 1; break }; reader.at += 1; at += 1 }
    } else {
        node.kind = 4; let start = reader.at
        if ch == 45 { reader.at += 1 }
        if reader.source[reader.at] == 48 { reader.at += 1 }
        else if reader.source[reader.at] >= 49 && reader.source[reader.at] <= 57 {
            while reader.source[reader.at] >= 48 && reader.source[reader.at] <= 57 { reader.at += 1 }
        } else { reader.error = 1 }
        if reader.source[reader.at] == 46 {
            reader.at += 1; let decimal = reader.at
            while reader.source[reader.at] >= 48 && reader.source[reader.at] <= 57 { reader.at += 1 }
            if reader.at == decimal { reader.error = 1 }
        }
        if reader.source[reader.at] == 101 || reader.source[reader.at] == 69 {
            reader.at += 1; if reader.source[reader.at] == 43 || reader.source[reader.at] == 45 { reader.at += 1 }
            let exponent = reader.at
            while reader.source[reader.at] >= 48 && reader.source[reader.at] <= 57 { reader.at += 1 }
            if reader.at == exponent { reader.error = 1 }
        }
        node.text = LanguageKit:copy_bytes(&reader.source[start], reader.at - start)
    }
    reader.depth -= 1
    if reader.error { Docs:json_destroy(node); return cast(Docs:Json*, 0) }; return node
}
let Docs:json_parse = fn (source:u8*) -> Docs:Json* {
    if !source || strlen(source) > 16777216 { return cast(Docs:Json*, 0) }
    let reader = cast(Docs:JsonReader*, calloc(1, sizeof(Docs:JsonReader)))
    if !reader { return cast(Docs:Json*, 0) }; defer free(cast(u8*, reader)); reader.source = source
    let node = Docs:json_value(reader); Docs:json_space(reader)
    if reader.error || source[reader.at] != 0 { Docs:json_destroy(node); return cast(Docs:Json*, 0) }; return node
}
let Docs:json_text = fn (node:Docs:Json*, key:u8*, fallback:u8*) -> u8* {
    let field = Docs:json_field(node, key)
    if !field || field.kind != 3 { return fallback }; return field.text
}
