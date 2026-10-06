// Project-local analysis policy. The host exports dictionary facts and actual
// source matches through :trace; all indexing and editor operations live here.
// Grammar extensions can replace the classifiers below without changing C++.

let LanguageKit:Analysis = phrase { dictionary = true permanent = true }

let LanguageKit:Analysis:hex_nibble = fn (value:u8) -> i64 {
    if value >= 48 && value <= 57 { return value - 48 }
    if value >= 97 && value <= 102 { return value - 97 + 10 }
    if value >= 65 && value <= 70 { return value - 65 + 10 }
    return -1
}

let LanguageKit:Analysis:decode_hex = fn (text:u8*, begin:i64, finish:i64) -> u8* {
    if !text || begin < 0 || finish < begin || ((finish - begin) % 2) != 0 { return cast(u8*, 0) }
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    var at = begin
    while at < finish {
        let high = LanguageKit:Analysis:hex_nibble(text[at])
        let low = LanguageKit:Analysis:hex_nibble(text[at + 1])
        if high < 0 || low < 0 { out.destroy(); return cast(u8*, 0) }
        if !out.append_byte(cast(u8, high * 16 + low)) { out.destroy(); return cast(u8*, 0) }
        at += 2
    }
    let result = out.take()
    out.destroy()
    return result
}

let LanguageKit:Analysis:parse_decimal = fn (text:u8*, begin:i64, finish:i64) -> i64 {
    if !text || begin >= finish { return -1 }
    var value:i64 = 0
    var at = begin
    while at < finish {
        let digit = text[at]
        if digit < 48 || digit > 57 { return -1 }
        value = value * 10 + digit - 48
        at += 1
    }
    return value
}

let LanguageKit:Analysis:find_byte = fn (text:u8*, begin:i64, value:u8) -> i64 {
    if !text || begin < 0 { return -1 }
    var at = begin
    while text[at] != 0 {
        if text[at] == value { return at }
        at += 1
    }
    return at
}

let LanguageKit:Analysis:find_ascii_lower = fn (value:u8) -> u8 {
    if value >= 65 && value <= 90 { return value + 32 }
    return value
}

let LanguageKit:Analysis:find_byte_to_char = fn (text:u8*, byte_offset:u64) -> i64 {
    if !text { return 0 }
    var at:u64 = 0
    var chars:i64 = 0
    while text[at] != 0 && at < byte_offset {
        if text[at] < 128 || text[at] >= 192 { chars += 1 }
        at += 1
    }
    return chars
}

let LanguageKit:Analysis:append_u64 = fn (text:LanguageKit:Text*, input:u64) -> i64 {
    if !text { return 0 }
    let digits = cast(u8*, malloc(32))
    if !digits { return 0 }
    defer free(digits)
    var value = input
    var count = 0
    if value == 0 { digits[0] = 48; count = 1 }
    while value > 0 {
        digits[count] = cast(u8, 48 + value % 10)
        value = value / 10
        count += 1
    }
    var i = 0
    while i < count / 2 {
        let temporary = digits[i]
        digits[i] = digits[count - i - 1]
        digits[count - i - 1] = temporary
        i += 1
    }
    digits[count] = 0
    return text.append(digits)
}

let LanguageKit:Analysis:append_hex = fn (out:LanguageKit:Text*, text:u8*) -> i64 {
    if !out || !text { return 0 }
    let digits = "0123456789abcdef"
    var i = 0
    while text[i] != 0 {
        let value = cast(i64, text[i])
        if !out.append_byte(digits[value / 16]) { return 0 }
        if !out.append_byte(digits[value % 16]) { return 0 }
        i += 1
    }
    return 1
}


// A resizable multimap shared by symbol, position and target lookups. Keys are
// borrowed from the owning file; clearing the tables precedes freeing its facts.
record LanguageKit:Analysis:Entry {
    key:u8*
    position:u64
    value:u8*
    next:LanguageKit:Analysis:Entry*
}
record LanguageKit:Analysis:Table {
    buckets:LanguageKit:Analysis:Entry**
    capacity:u64
    count:u64
}
let LanguageKit:Analysis:hash = fn (key:u8*, position:u64) -> u64 {
    var hash:u64 = 5381
    var at:u64 = 0
    while key[at] != 0 { hash = hash * 33 + cast(u64, key[at]); at += 1 }
    return Core:Work:hash_u64(hash * 33 + position)
}
let LanguageKit:Analysis:table_init = fn (table:LanguageKit:Analysis:Table*) -> void {
    table.buckets = cast(LanguageKit:Analysis:Entry**, 0); table.capacity = 0; table.count = 0
}
let LanguageKit:Analysis:table_remove = fn (table:LanguageKit:Analysis:Table*, key:u8*, position:u64) -> void {
    if !table.capacity { return }
    let slot = LanguageKit:Analysis:hash(key, position) % table.capacity
    var previous = cast(LanguageKit:Analysis:Entry*, 0)
    var entry = table.buckets[slot]
    while entry {
        let next = entry.next
        if entry.position == position && strcmp(entry.key, key) == 0 {
            if previous { previous.next = next } else { table.buckets[slot] = next }
            free(cast(u8*, entry)); table.count -= 1
        } else { previous = entry }
        entry = next
    }
}
let LanguageKit:Analysis:table_clear = fn (table:LanguageKit:Analysis:Table*) -> void {
    var at:u64 = 0
    while at < table.capacity {
        var entry = table.buckets[at]
        while entry { let next = entry.next; free(cast(u8*, entry)); entry = next }
        at += 1
    }
    free(cast(u8*, table.buckets))
    table.buckets = cast(LanguageKit:Analysis:Entry**, 0); table.capacity = 0; table.count = 0
}
let LanguageKit:Analysis:table_add = fn (table:LanguageKit:Analysis:Table*, key:u8*, position:u64, value:u8*) -> void {
    if table.count >= table.capacity {
        var capacity:u64 = 32
        if table.capacity != 0 { capacity = table.capacity * 2 }
        let buckets = cast(LanguageKit:Analysis:Entry**, malloc(capacity * 8))
        if !buckets { return }
        var at:u64 = 0
        while at < capacity { buckets[at] = cast(LanguageKit:Analysis:Entry*, 0); at += 1 }
        at = 0
        while at < table.capacity {
            var entry = table.buckets[at]
            var reversed = cast(LanguageKit:Analysis:Entry*, 0)
            while entry { let next = entry.next; entry.next = reversed; reversed = entry; entry = next }
            entry = reversed
            while entry {
                let next = entry.next
                let slot = LanguageKit:Analysis:hash(entry.key, entry.position) % capacity
                entry.next = buckets[slot]; buckets[slot] = entry; entry = next
            }
            at += 1
        }
        free(cast(u8*, table.buckets)); table.buckets = buckets; table.capacity = capacity
    }
    let slot = LanguageKit:Analysis:hash(key, position) % table.capacity
    let entry = alloc(LanguageKit:Analysis:Entry)
    if !entry { return }
    entry.key = key; entry.position = position; entry.value = value
    entry.next = table.buckets[slot]; table.buckets[slot] = entry; table.count += 1
}
let LanguageKit:Analysis:table_find = fn (table:LanguageKit:Analysis:Table*, key:u8*, position:u64) -> LanguageKit:Analysis:Entry* {
    if !table.capacity { return cast(LanguageKit:Analysis:Entry*, 0) }
    var entry = table.buckets[LanguageKit:Analysis:hash(key, position) % table.capacity]
    while entry {
        if entry.position == position && strcmp(entry.key, key) == 0 { return entry }
        entry = entry.next
    }
    return cast(LanguageKit:Analysis:Entry*, 0)
}
let LanguageKit:Analysis:table_next = fn (entry:LanguageKit:Analysis:Entry*) -> LanguageKit:Analysis:Entry* {
    let key = entry.key
    let position = entry.position
    entry = entry.next
    while entry {
        if entry.position == position && strcmp(entry.key, key) == 0 { return entry }
        entry = entry.next
    }
    return cast(LanguageKit:Analysis:Entry*, 0)
}

record LanguageKit:Analysis:Symbol {
    id:u64
    key:u8*
    name:u8*
    kind:u8*
    docs:u8*
    prototype:u8*
    type:u8*
    signature:u8*
    next:LanguageKit:Analysis:Symbol*
}

record LanguageKit:Analysis:Token {
    text:u8*
    start:u64
    finish:u64
    byte_start:u64
    byte_finish:u64
    line:u64
    depth:i64
    identifier:i64
    previous:LanguageKit:Analysis:Token*
    matching:LanguageKit:Analysis:Token*
    opening:LanguageKit:Analysis:Token*
    block:LanguageKit:Analysis:Token*
    container:u8*
    next:LanguageKit:Analysis:Token*
}

record LanguageKit:Analysis:Occurrence {
    target:u8*
    container:u8*
    label:u8*
    start:u64
    finish:u64
    line:u64
    role:i64
    exact:i64
    local:i64
    depth:i64
    scope_finish:u64
    declaration_next:LanguageKit:Analysis:Occurrence*
    next:LanguageKit:Analysis:Occurrence*
}


record LanguageKit:Analysis:File {
    path:u8*
    source:u8*
    diagnostic:u8*
    symbols:LanguageKit:Analysis:Symbol*
    tokens:LanguageKit:Analysis:Token*
    occurrences:LanguageKit:Analysis:Occurrence*
    declarations:LanguageKit:Analysis:Occurrence*
    symbols_by_name:LanguageKit:Analysis:Table
    by_position:LanguageKit:Analysis:Table
    by_target:LanguageKit:Analysis:Table
    by_container:LanguageKit:Analysis:Table
    locals_by_name:LanguageKit:Analysis:Table
    ranges:LanguageKit:Analysis:Occurrence**
    range_ends:u64*
    range_count:u64
    previous:LanguageKit:Analysis:File*
    next:LanguageKit:Analysis:File*
}

record LanguageKit:Analysis:Result {
    file:LanguageKit:Analysis:File*
    item:LanguageKit:Analysis:Occurrence*
    next:LanguageKit:Analysis:Result*
}

record LanguageKit:Analysis:Index {
    revision:u64
    standalone:i64
    files:LanguageKit:Analysis:File*
    by_path:LanguageKit:Analysis:Table
}

let LanguageKit:Analysis:equal = fn (left:u8*, right:u8*) -> i64 {
    return left && right && strcmp(left, right) == 0
}

let LanguageKit:Analysis:identifier = fn (ch:u8) -> i64 {
    return LanguageKit:is_alpha(ch) || LanguageKit:is_digit(ch) || ch == 95
}


let LanguageKit:Analysis:byte_offset = fn (text:u8*, position:u64) -> u64 {
    var at:u64 = 0
    var count:u64 = 0
    while text[at] != 0 && count < position {
        at += 1
        while text[at] / 64 == 2 { at += 1 }
        count += 1
    }
    return at
}

let LanguageKit:Analysis:definition_word = fn (word:u8*) -> i64 {
    return LanguageKit:Analysis:equal(word, "let") || LanguageKit:Analysis:equal(word, "record") ||
           LanguageKit:Analysis:equal(word, "dictionary") || LanguageKit:Analysis:equal(word, "type") || LanguageKit:Analysis:equal(word, "fn")
}

let LanguageKit:Analysis:local_word = fn (word:u8*) -> i64 {
    return LanguageKit:Analysis:equal(word, "let") || LanguageKit:Analysis:equal(word, "var") || LanguageKit:Analysis:equal(word, "const")
}

let LanguageKit:Analysis:file_clear = fn (file:LanguageKit:Analysis:File*) -> void {
    if !file { return }
    free(cast(u8*, file.ranges)); free(cast(u8*, file.range_ends))
    file.ranges = cast(LanguageKit:Analysis:Occurrence**, 0); file.range_ends = cast(u64*, 0); file.range_count = 0
    LanguageKit:Analysis:table_clear(&file.symbols_by_name)
    LanguageKit:Analysis:table_clear(&file.by_position)
    LanguageKit:Analysis:table_clear(&file.by_target)
    LanguageKit:Analysis:table_clear(&file.by_container)
    LanguageKit:Analysis:table_clear(&file.locals_by_name)
    var symbol = file.symbols
    while symbol {
        let next = symbol.next
        free(symbol.key); free(symbol.name); free(symbol.kind); free(symbol.docs)
        free(symbol.prototype); free(symbol.type); free(symbol.signature)
        free(cast(u8*, symbol)); symbol = next
    }
    var token = file.tokens
    while token { let next = token.next; free(token.text); free(cast(u8*, token)); token = next }
    var occurrence = file.occurrences
    while occurrence {
        let next = occurrence.next
        free(occurrence.target); free(occurrence.container); free(occurrence.label)
        free(cast(u8*, occurrence)); occurrence = next
    }
    if file.source { free(file.source) }
    if file.diagnostic { free(file.diagnostic) }
    file.source = cast(u8*, 0); file.diagnostic = cast(u8*, 0)
    file.symbols = cast(LanguageKit:Analysis:Symbol*, 0)
    file.tokens = cast(LanguageKit:Analysis:Token*, 0)
    file.occurrences = cast(LanguageKit:Analysis:Occurrence*, 0); file.declarations = cast(LanguageKit:Analysis:Occurrence*, 0)
}

let LanguageKit:Analysis:new = fn () -> LanguageKit:Analysis:Index* {
    let index = alloc(LanguageKit:Analysis:Index)
    if !index { return cast(LanguageKit:Analysis:Index*, 0) }
    index.files = cast(LanguageKit:Analysis:File*, 0); index.revision = 0; index.standalone = 0
    LanguageKit:Analysis:table_init(&index.by_path)
    return index
}

let LanguageKit:Analysis:destroy = fn (index:LanguageKit:Analysis:Index*) -> void {
    if !index { return }
    LanguageKit:Analysis:table_clear(&index.by_path)
    var file = index.files
    while file {
        let next = file.next
        LanguageKit:Analysis:file_clear(file); free(file.path); free(cast(u8*, file)); file = next
    }
    free(cast(u8*, index))
}

let LanguageKit:Analysis:tokenize = fn (file:LanguageKit:Analysis:File*) -> void {
    let source = file.source
    var at:u64 = 0
    var chars:u64 = 0
    var line:u64 = 1
    var depth:i64 = 0
    var tail = cast(LanguageKit:Analysis:Token*, 0)
    var opening = cast(LanguageKit:Analysis:Token*, 0)
    var block = cast(LanguageKit:Analysis:Token*, 0)
    while source[at] != 0 {
        if context:process:interrupted() { return }
        let ch = source[at]
        if LanguageKit:is_space(ch) {
            if ch == 10 { line += 1 }
            at += 1; chars += 1
        } else if ch == 47 && source[at + 1] == 47 {
            while source[at] != 0 && source[at] != 10 { at += 1; if (source[at - 1] / 64) != 2 { chars += 1 } }
        } else if ch == 47 && source[at + 1] == 42 {
            at += 2; chars += 2
            while source[at] != 0 && !(source[at] == 42 && source[at + 1] == 47) {
                if source[at] == 10 { line += 1 }
                if (source[at] / 64) != 2 { chars += 1 }
                at += 1
            }
            if source[at] != 0 { at += 2; chars += 2 }
        } else if ch == 34 {
            at += 1; chars += 1
            var escaped:i64 = 0
            var done:i64 = 0
            while source[at] != 0 && done == 0 {
                let value = source[at]
                if value == 10 { line += 1 }
                if value / 64 != 2 { chars += 1 }
                at += 1
                if escaped != 0 { escaped = 0 }
                else if value == 92 { escaped = 1 }
                else if value == 34 { done = 1 }
            }
        } else {
            let begin = at
            let char_begin = chars
            let source_line = line
            let is_id = LanguageKit:is_alpha(ch) || ch == 95
            if is_id {
                at += 1; chars += 1
                var scanning:i64 = 1
                while source[at] != 0 && scanning != 0 {
                    if LanguageKit:Analysis:identifier(source[at]) { at += 1; chars += 1 }
                    else if source[at] == 58 && source[at + 1] != 58 && (LanguageKit:is_alpha(source[at + 1]) || source[at + 1] == 95) { at += 1; chars += 1 }
                    else { scanning = 0 }
                }
            } else {
                at += 1
                if ch / 64 != 2 { chars += 1 }
                while source[at] / 64 == 2 { at += 1 }
            }
            if ch == 125 && depth > 0 { depth -= 1 }
            let token = alloc(LanguageKit:Analysis:Token)
            if !token { return }
            token.text = LanguageKit:copy_bytes(&source[begin], cast(i64, at - begin))
            if !token.text { free(cast(u8*, token)); return }
            token.start = char_begin; token.finish = chars
            token.byte_start = begin; token.byte_finish = at
            token.line = source_line; token.depth = depth; token.identifier = is_id
            token.matching = cast(LanguageKit:Analysis:Token*, 0)
            token.opening = opening; token.block = block; token.container = ""
            if ch == 40 || ch == 91 || ch == 123 { opening = token }
            else if opening && ((ch == 41 && opening.text[0] == 40) || (ch == 93 && opening.text[0] == 91) || (ch == 125 && opening.text[0] == 123)) {
                opening.matching = token; token.matching = opening; opening = opening.opening
            }
            if ch == 123 { block = token }
            else if ch == 125 && block { block = block.block }
            token.previous = tail; token.next = cast(LanguageKit:Analysis:Token*, 0)
            if tail { tail.next = token } else { file.tokens = token }
            tail = token
            if ch == 123 { depth += 1 }
        }
    }
}

let LanguageKit:Analysis:key = fn (name:u8*, version:u64) -> u8* {
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    out.append(name); out.append_byte(31); LanguageKit:Analysis:append_u64(out, version)
    let result = out.take(); out.destroy(); return result
}

let LanguageKit:Analysis:symbol = fn (file:LanguageKit:Analysis:File*, name:u8*) -> LanguageKit:Analysis:Symbol* {
    let entry = LanguageKit:Analysis:table_find(&file.symbols_by_name, name, 0)
    if entry { return cast(LanguageKit:Analysis:Symbol*, entry.value) }
    return cast(LanguageKit:Analysis:Symbol*, 0)
}

let LanguageKit:Analysis:add = fn (file:LanguageKit:Analysis:File*, target:u8*, container:u8*, label:u8*, start:u64, finish:u64, line:u64,
                          role:i64, exact:i64, local:i64) -> LanguageKit:Analysis:Occurrence* {
    var entry = LanguageKit:Analysis:table_find(&file.by_position, "", start)
    while entry {
        let existing = cast(LanguageKit:Analysis:Occurrence*, entry.value)
        if existing.start == start && existing.finish == finish && LanguageKit:Analysis:equal(existing.target, target) {
            if local != 0 && role == 2 && !(existing.local != 0 && existing.role == 2) {
                LanguageKit:Analysis:table_add(&file.locals_by_name, existing.label, 0, cast(u8*, existing))
            }
            if role > existing.role { existing.role = role }
            if exact > existing.exact { existing.exact = exact }
            if local > existing.local { existing.local = local }
            if container && container[0] != 0 { free(existing.container); existing.container = LanguageKit:copy_text(container) }
            return existing
        }
        entry = LanguageKit:Analysis:table_next(entry)
    }
    let item = alloc(LanguageKit:Analysis:Occurrence)
    if !item { return cast(LanguageKit:Analysis:Occurrence*, 0) }
    item.target = LanguageKit:copy_text(target); item.container = LanguageKit:copy_text(container); item.label = LanguageKit:copy_text(label)
    if !item.target || !item.container || !item.label {
        free(item.target); free(item.container); free(item.label); free(cast(u8*, item))
        return cast(LanguageKit:Analysis:Occurrence*, 0)
    }
    item.start = start; item.finish = finish; item.line = line
    item.role = role; item.exact = exact; item.local = local
    item.depth = 0; item.scope_finish = 0
    item.declaration_next = cast(LanguageKit:Analysis:Occurrence*, 0)
    item.next = file.occurrences; file.occurrences = item
    LanguageKit:Analysis:table_add(&file.by_position, "", start, cast(u8*, item))
    LanguageKit:Analysis:table_add(&file.by_target, item.target, 0, cast(u8*, item))
    if local != 0 && role == 2 { LanguageKit:Analysis:table_add(&file.locals_by_name, item.label, 0, cast(u8*, item)) }
    return item
}

let LanguageKit:Analysis:parse_trace = fn (file:LanguageKit:Analysis:File*, response:u8*) -> void {
    if !response { file.diagnostic = LanguageKit:copy_text("source trace unavailable"); return }
    var at:i64 = 0
    var byte_at:u64 = 0
    var char_at:u64 = 0
    while response[at] != 0 {
        if context:process:interrupted() { return }
        let end = LanguageKit:Analysis:find_byte(response, at, 10)
        if response[at] == 80 && response[at + 1] == 9 {
            let f1 = LanguageKit:Analysis:find_byte(response, at + 2, 9)
            let f2 = LanguageKit:Analysis:find_byte(response, f1 + 1, 9)
            let f3 = LanguageKit:Analysis:find_byte(response, f2 + 1, 9)
            let f4 = LanguageKit:Analysis:find_byte(response, f3 + 1, 9)
            let f5 = LanguageKit:Analysis:find_byte(response, f4 + 1, 9)
            let f6 = LanguageKit:Analysis:find_byte(response, f5 + 1, 9)
            if f6 < end {
                let item = alloc(LanguageKit:Analysis:Symbol)
                if !item { return }
                item.id = cast(u64, LanguageKit:Analysis:parse_decimal(response, at + 2, f1))
                item.name = LanguageKit:Analysis:decode_hex(response, f1 + 1, f2)
                item.key = LanguageKit:Analysis:key(item.name, item.id)
                item.kind = LanguageKit:Analysis:decode_hex(response, f2 + 1, f3)
                item.docs = LanguageKit:Analysis:decode_hex(response, f3 + 1, f4)
                item.prototype = LanguageKit:Analysis:decode_hex(response, f4 + 1, f5)
                item.type = LanguageKit:Analysis:decode_hex(response, f5 + 1, f6)
                item.signature = LanguageKit:Analysis:decode_hex(response, f6 + 1, end)
                item.next = file.symbols; file.symbols = item
                LanguageKit:Analysis:table_add(&file.symbols_by_name, item.name, 0, cast(u8*, item))
                LanguageKit:Analysis:table_add(&file.symbols_by_name, item.key, 0, cast(u8*, item))
            }
        } else if response[at] == 82 && response[at + 1] == 9 {
            let f1 = LanguageKit:Analysis:find_byte(response, at + 2, 9)
            let f2 = LanguageKit:Analysis:find_byte(response, f1 + 1, 9)
            let f3 = LanguageKit:Analysis:find_byte(response, f2 + 1, 9)
            let f4 = LanguageKit:Analysis:find_byte(response, f3 + 1, 9)
            if f4 < end {
                let start = LanguageKit:Analysis:parse_decimal(response, at + 2, f1)
                let finish = LanguageKit:Analysis:parse_decimal(response, f1 + 1, f2)
                let source_line = LanguageKit:Analysis:parse_decimal(response, f2 + 1, f3)
                let version = cast(u64, LanguageKit:Analysis:parse_decimal(response, f3 + 1, f4))
                let name = LanguageKit:Analysis:decode_hex(response, f4 + 1, end)
                if name && start >= 0 && finish > start {
                    if cast(u64, start) < char_at { byte_at = 0; char_at = 0 }
                    while file.source[byte_at] != 0 && char_at < cast(u64, start) {
                        byte_at += 1; while file.source[byte_at] / 64 == 2 { byte_at += 1 }; char_at += 1
                    }
                    let begin_byte = byte_at
                    var end_byte = byte_at
                    var end_char = char_at
                    while file.source[end_byte] != 0 && end_char < cast(u64, finish) {
                        end_byte += 1; while file.source[end_byte] / 64 == 2 { end_byte += 1 }; end_char += 1
                    }
                    let label = LanguageKit:copy_bytes(&file.source[begin_byte], cast(i64, end_byte - begin_byte))
                    let key = LanguageKit:Analysis:key(name, version)
                    if label && key { LanguageKit:Analysis:add(file, key, "", label, cast(u64, start), cast(u64, finish), cast(u64, source_line), 1, 1, 0) }
                    if label { free(label) }; if key { free(key) }
                }
                if name { free(name) }
            }
        } else if response[at] == 69 && response[at + 1] == 9 {
            if file.diagnostic { free(file.diagnostic) }
            file.diagnostic = LanguageKit:Analysis:decode_hex(response, at + 2, end)
        }
        at = end
        if response[at] == 10 { at += 1 }
    }
}

let LanguageKit:Analysis:matching = fn (open:LanguageKit:Analysis:Token*, opening:u8*, closing:u8*) -> LanguageKit:Analysis:Token* {
    if open && LanguageKit:Analysis:equal(open.text, opening) && open.matching && LanguageKit:Analysis:equal(open.matching.text, closing) { return open.matching }
    return cast(LanguageKit:Analysis:Token*, 0)
}

let LanguageKit:Analysis:local_key = fn (file:LanguageKit:Analysis:File*, container:u8*, token:LanguageKit:Analysis:Token*, name:u8*) -> u8* {
    let text = LanguageKit:Text:new()
    if !text { return cast(u8*, 0) }
    text.append("@"); text.append(file.path); text.append("|"); text.append(container)
    text.append("|"); LanguageKit:Analysis:append_u64(text, token.start); text.append("|"); text.append(name)
    let result = text.take(); text.destroy(); return result
}


let LanguageKit:Analysis:container = fn (file:LanguageKit:Analysis:File*, position:u64) -> u8* {
    var container:u8* = ""
    var token = file.tokens
    while token && token.start <= position { container = token.container; token = token.next }
    return container
}

let LanguageKit:Analysis:declare_local = fn (file:LanguageKit:Analysis:File*, token:LanguageKit:Analysis:Token*, container:u8*, scope_finish:u64) -> void {
    let colon = LanguageKit:Analysis:find_byte(token.text, 0, 58)
    let size = strlen(token.text)
    let name = LanguageKit:copy_bytes(token.text, colon)
    if !name { return }
    defer free(name)
    let key = LanguageKit:Analysis:local_key(file, container, token, name)
    if !key { return }
    defer free(key)
    let item = LanguageKit:Analysis:add(file, key, container, name, token.start, token.start + cast(u64, colon), token.line, 2, 0, 1)
    if item { item.depth = token.depth; item.scope_finish = scope_finish }
    if cast(u64, colon) < size {
        let type = &token.text[colon + 1]
        let symbol = LanguageKit:Analysis:symbol(file, type)
        if symbol { LanguageKit:Analysis:add(file, symbol.key, key, type, token.start + cast(u64, colon) + 1, token.finish, token.line, 4, 0, 0) }
    }
}

let LanguageKit:Analysis:function = fn (file:LanguageKit:Analysis:File*, name:LanguageKit:Analysis:Token*, first:LanguageKit:Analysis:Token*) -> void {
    if !name || !first || !LanguageKit:Analysis:symbol(file, name.text) { return }
    let function_symbol = LanguageKit:Analysis:symbol(file, name.text)
    var open = first
    while open && !LanguageKit:Analysis:equal(open.text, "(") && !LanguageKit:Analysis:equal(open.text, "{") && open.text[0] != 59 { open = open.next }
    if !open || !LanguageKit:Analysis:equal(open.text, "(") { return }
    let parameters_end = LanguageKit:Analysis:matching(open, "(", ")")
    if !parameters_end { return }
    var body = parameters_end.next
    while body && !LanguageKit:Analysis:equal(body.text, "{") && body.text[0] != 59 { body = body.next }
    if !body || !LanguageKit:Analysis:equal(body.text, "{") { return }
    let finish = LanguageKit:Analysis:matching(body, "{", "}")
    if !finish { return }
    free(function_symbol.kind); function_symbol.kind = LanguageKit:copy_text("function")
    if function_symbol.signature && function_symbol.signature[0] == 0 {
        let signature = LanguageKit:Text:new()
        if signature {
            signature.append(name.text)
            let header = LanguageKit:copy_bytes(&file.source[open.byte_start], cast(i64, body.byte_start - open.byte_start))
            if header { signature.append(header); free(header) }
            free(function_symbol.signature); function_symbol.signature = signature.take(); signature.destroy()
        }
    }
    LanguageKit:Analysis:add(file, function_symbol.key, "", name.text, name.start, name.finish, name.line, 2, 0, 0)
    var parameter = open.next
    var expect:i64 = 1
    var nested:i64 = 0
    while parameter && parameter != parameters_end {
        if LanguageKit:Analysis:equal(parameter.text, "(") { nested += 1 }
        else if LanguageKit:Analysis:equal(parameter.text, ")") { nested -= 1 }
        else if nested == 0 {
            if LanguageKit:Analysis:equal(parameter.text, ",") { expect = 1 }
            else if expect != 0 && parameter.identifier != 0 {
                LanguageKit:Analysis:declare_local(file, parameter, function_symbol.key, finish.start); expect = 0
            }
        }
        parameter = parameter.next
    }
    var token = body.next
    while token && token != finish {
        if context:process:interrupted() { return }
        token.container = function_symbol.key
        if token.identifier != 0 && token.previous && LanguageKit:Analysis:local_word(token.previous.text) {
            let block = token.block
            var block_end = finish
            if block { let close = LanguageKit:Analysis:matching(block, "{", "}"); if close { block_end = close } }
            LanguageKit:Analysis:declare_local(file, token, function_symbol.key, block_end.start)
        }
        token = token.next
    }
    token = body.next
    while token && token != finish {
        if context:process:interrupted() { return }
        if token.identifier != 0 {
            var best = cast(LanguageKit:Analysis:Occurrence*, 0)
            var local_entry = LanguageKit:Analysis:table_find(&file.locals_by_name, token.text, 0)
            while local_entry {
                let occurrence = cast(LanguageKit:Analysis:Occurrence*, local_entry.value)
                if occurrence.local != 0 && occurrence.role == 2 && LanguageKit:Analysis:equal(occurrence.container, function_symbol.key) &&
                   LanguageKit:Analysis:equal(occurrence.label, token.text) && token.start >= occurrence.start &&
                   token.start < occurrence.scope_finish && token.depth >= occurrence.depth {
                    if !best { best = occurrence }
                    else if occurrence.depth > best.depth || (occurrence.depth == best.depth && occurrence.start > best.start) { best = occurrence }
                }
                local_entry = LanguageKit:Analysis:table_next(local_entry)
            }
            if best && best.start != token.start {
                var role:i64 = 1
                if token.next && LanguageKit:Analysis:equal(token.next.text, "(") { role = 3 }
                LanguageKit:Analysis:add(file, best.target, function_symbol.key, token.text, token.start, token.finish, token.line, role, 0, 1)
            }
        }
        token = token.next
    }
}

let LanguageKit:Analysis:classify = fn (file:LanguageKit:Analysis:File*) -> void {
    LanguageKit:Analysis:tokenize(file)
    var token = file.tokens
    while token {
        if context:process:interrupted() { return }
        if LanguageKit:Analysis:equal(token.text, "fn") {
            if token.next && token.next.identifier != 0 { LanguageKit:Analysis:function(file, token.next, token.next.next) }
            else if token.previous && token.previous.previous && LanguageKit:Analysis:equal(token.previous.text, "=") {
                let name = token.previous.previous
                if name.previous && LanguageKit:Analysis:equal(name.previous.text, "let") { LanguageKit:Analysis:function(file, name, token.next) }
            }
        }
        token = token.next
    }
    token = file.tokens
    while token {
        if context:process:interrupted() { return }
        if token.identifier != 0 {
            var definition:i64 = 0
            if token.previous && LanguageKit:Analysis:definition_word(token.previous.text) && token.depth == 0 { definition = 1 }
            var role:i64 = 1
            if token.previous && token.next && token.previous.text[0] == 60 && token.next.text[0] == 62 { role = 5 }
            if definition != 0 { role = 2 }
            else if token.next && LanguageKit:Analysis:equal(token.next.text, "(") { role = 3 }
            else if token.previous && token.previous.previous && token.previous.text[0] == 62 && token.previous.previous.text[0] == 45 { role = 4 }
            let symbol = LanguageKit:Analysis:symbol(file, token.text)
            var exact_entry = LanguageKit:Analysis:table_find(&file.by_position, "", token.start)
            while exact_entry {
                let occurrence = cast(LanguageKit:Analysis:Occurrence*, exact_entry.value)
                if symbol && occurrence.exact != 0 && occurrence.start == token.start && occurrence.finish == token.finish &&
                   LanguageKit:Analysis:equal(occurrence.target, symbol.key) {
                    if role > occurrence.role { occurrence.role = role }
                    free(occurrence.container); occurrence.container = LanguageKit:copy_text(token.container)
                }
                exact_entry = LanguageKit:Analysis:table_next(exact_entry)
            }
            // Typed fn identifiers are not phrase-dispatch tokens. Resolve calls
            // against the exported compiler catalog here, excluding member names
            // and lexically shadowed locals. This policy belongs to the example.
            var typed_call:i64 = 0
            if role == 3 && symbol && LanguageKit:Analysis:equal(symbol.kind, "function") {
                typed_call = 1
                if token.previous && token.previous.text[0] == 46 { typed_call = 0 }
                var local_entry = LanguageKit:Analysis:table_find(&file.by_position, "", token.start)
                while local_entry {
                    let local = cast(LanguageKit:Analysis:Occurrence*, local_entry.value)
                    if local.local != 0 && local.start == token.start && local.finish == token.finish { typed_call = 0 }
                    local_entry = LanguageKit:Analysis:table_next(local_entry)
                }
            }
            if (definition != 0 || role == 4 || role == 5 || typed_call != 0) && symbol {
                let added = LanguageKit:Analysis:add(file, symbol.key, "", token.text, token.start, token.finish, token.line, role, 0, 0)
                if added && typed_call != 0 {
                    free(added.container); added.container = LanguageKit:copy_text(token.container)
                }
            }
        }
        token = token.next
    }
}

let LanguageKit:Analysis:selected = fn (file:LanguageKit:Analysis:File*, position:u64) -> LanguageKit:Analysis:Occurrence* {
    var selected = cast(LanguageKit:Analysis:Occurrence*, 0)
    var low:u64 = 0
    var high = file.range_count
    while low < high {
        let middle = low + (high - low) / 2
        if file.ranges[middle].start <= position { low = middle + 1 } else { high = middle }
    }
    while low != 0 {
        low -= 1
        if file.range_ends[low] <= position { break }
        let item = file.ranges[low]
        if item.start <= position && position < item.finish {
            if !selected { selected = item }
            else if item.local > selected.local || (item.local == selected.local &&
                    (item.finish - item.start < selected.finish - selected.start ||
                     (item.finish - item.start == selected.finish - selected.start && item.role > selected.role))) { selected = item }
        }
    }
    return selected
}

let LanguageKit:Analysis:location = fn (out:LanguageKit:Text*, file:LanguageKit:Analysis:File*, item:LanguageKit:Analysis:Occurrence*) -> void {
    out.append("L\t"); LanguageKit:Analysis:append_hex(out, file.path); out.append("\t")
    LanguageKit:Analysis:append_u64(out, item.start); out.append("\t"); LanguageKit:Analysis:append_u64(out, item.finish); out.append("\t")
    LanguageKit:Analysis:append_u64(out, item.line); out.append("\t"); LanguageKit:Analysis:append_u64(out, cast(u64, item.role)); out.append("\t")
    LanguageKit:Analysis:append_hex(out, item.label); out.append("\n")
}

let LanguageKit:Analysis:sort_results = fn (head:LanguageKit:Analysis:Result*, descending:i64) -> LanguageKit:Analysis:Result* {
    if !head || !head.next || context:process:interrupted() { return head }
    var slow = head
    var fast = head.next
    while fast && fast.next { slow = slow.next; fast = fast.next.next }
    let second = slow.next; slow.next = cast(LanguageKit:Analysis:Result*, 0)
    var left = LanguageKit:Analysis:sort_results(head, descending)
    var right = LanguageKit:Analysis:sort_results(second, descending)
    var result = cast(LanguageKit:Analysis:Result*, 0)
    var tail = cast(LanguageKit:Analysis:Result*, 0)
    while left || right {
        var take_left:i64 = 0
        if !right { take_left = 1 }
        else if left {
            let order = strcmp(left.file.path, right.file.path)
            if order < 0 || (order == 0 && ((descending == 0 && (left.item.start < right.item.start || (left.item.start == right.item.start && left.item.finish <= right.item.finish))) ||
                                          (descending != 0 && (left.item.start > right.item.start || (left.item.start == right.item.start && left.item.finish >= right.item.finish))))) { take_left = 1 }
        }
        var item = right
        if take_left != 0 { item = left; left = left.next } else { right = right.next }
        if tail { tail.next = item } else { result = item }
        tail = item
    }
    tail.next = cast(LanguageKit:Analysis:Result*, 0)
    return result
}

let LanguageKit:Analysis:contains = fn (text:u8*, query:u8*) -> i64 {
    if !query || query[0] == 0 { return 1 }
    if !text { return 0 }
    var at:u64 = 0
    while text[at] != 0 {
        var i:u64 = 0
        while query[i] != 0 && text[at + i] != 0 && LanguageKit:Analysis:find_ascii_lower(text[at + i]) == LanguageKit:Analysis:find_ascii_lower(query[i]) { i += 1 }
        if query[i] == 0 { return 1 }
        at += 1
    }
    return 0
}

let LanguageKit:Analysis:prefix = fn (text:u8*, prefix:u8*) -> i64 {
    if !text || !prefix { return 0 }
    var i:u64 = 0
    while prefix[i] != 0 { if text[i] != prefix[i] { return 0 }; i += 1 }
    return 1
}

let LanguageKit:Analysis:completion = fn (out:LanguageKit:Text*, file:LanguageKit:Analysis:File*, position:u64) -> void {
    let end = LanguageKit:Analysis:byte_offset(file.source, position)
    var begin = end
    while begin > 0 && (LanguageKit:Analysis:identifier(file.source[begin - 1]) || file.source[begin - 1] == 58) { begin -= 1 }
    let prefix = LanguageKit:copy_bytes(&file.source[begin], cast(i64, end - begin))
    if !prefix { return }
    defer free(prefix)
    let start = cast(u64, LanguageKit:Analysis:find_byte_to_char(file.source, begin))
    var symbol = file.symbols
    while symbol {
        if LanguageKit:Analysis:prefix(symbol.name, prefix) {
            out.append("C\t"); LanguageKit:Analysis:append_u64(out, start); out.append("\t"); LanguageKit:Analysis:append_u64(out, position); out.append("\t")
            LanguageKit:Analysis:append_hex(out, symbol.name); out.append("\t"); LanguageKit:Analysis:append_hex(out, symbol.name); out.append("\t")
            LanguageKit:Analysis:append_hex(out, symbol.kind); out.append("\t"); LanguageKit:Analysis:append_hex(out, symbol.docs); out.append("\n")
        }
        symbol = symbol.next
    }
    var item = file.declarations
    let container = LanguageKit:Analysis:container(file, position)
    while item {
        var visible:i64 = item.local != 0 && item.role == 2 && item.start <= position && position < item.scope_finish &&
                          LanguageKit:Analysis:equal(container, item.container) && LanguageKit:Analysis:prefix(item.label, prefix)
        if visible != 0 {
            var entry = LanguageKit:Analysis:table_find(&file.locals_by_name, item.label, 0)
            while entry {
                let other = cast(LanguageKit:Analysis:Occurrence*, entry.value)
                if other.local != 0 && other.role == 2 && other.start <= position && position < other.scope_finish &&
                   LanguageKit:Analysis:equal(container, other.container) && LanguageKit:Analysis:equal(item.label, other.label) &&
                   (other.depth > item.depth || (other.depth == item.depth && other.start > item.start)) { visible = 0 }
                entry = LanguageKit:Analysis:table_next(entry)
            }
        }
        if visible != 0 {
            out.append("C\t"); LanguageKit:Analysis:append_u64(out, start); out.append("\t"); LanguageKit:Analysis:append_u64(out, position); out.append("\t")
            LanguageKit:Analysis:append_hex(out, item.label); out.append("\t"); LanguageKit:Analysis:append_hex(out, item.label); out.append("\t6c6f63616c\t\n")
        }
        item = item.declaration_next
    }
}

let LanguageKit:Analysis:signature = fn (out:LanguageKit:Text*, file:LanguageKit:Analysis:File*, position:u64) -> void {
    var token = file.tokens
    var open = cast(LanguageKit:Analysis:Token*, 0)
    var nested:i64 = 0
    while token && token.start < position { open = token; token = token.next }
    while open {
        if LanguageKit:Analysis:equal(open.text, ")") { nested += 1 }
        else if LanguageKit:Analysis:equal(open.text, "(") {
            if nested == 0 {
                if open.previous {
                    let symbol = LanguageKit:Analysis:symbol(file, open.previous.text)
                    if symbol && symbol.signature && symbol.signature[0] != 0 {
                        var at:i64 = 0
                        while symbol.signature[at] != 0 {
                            let end = LanguageKit:Analysis:find_byte(symbol.signature, at, 10)
                            let label = LanguageKit:copy_bytes(&symbol.signature[at], end - at)
                            if label { out.append("G\t"); LanguageKit:Analysis:append_hex(out, label); out.append("\t"); LanguageKit:Analysis:append_hex(out, symbol.docs); out.append("\n"); free(label) }
                            at = end; if symbol.signature[at] == 10 { at += 1 }
                        }
                    }
                }
                return
            }
            nested -= 1
        }
        open = open.previous
    }
}

let LanguageKit:Analysis:prototype_in = fn (file:LanguageKit:Analysis:File*, name:u8*, target:u8*) -> i64 {
    var symbol = LanguageKit:Analysis:symbol(file, name)
    var depth:u64 = 0
    while symbol && symbol.prototype && symbol.prototype[0] != 0 && depth < 128 {
        let prototype = LanguageKit:Analysis:symbol(file, symbol.prototype)
        if prototype && LanguageKit:Analysis:equal(prototype.key, target) { return 1 }
        symbol = LanguageKit:Analysis:symbol(file, symbol.prototype); depth += 1
    }
    return 0
}

let LanguageKit:Analysis:query_index = fn (index:LanguageKit:Analysis:Index*, current:LanguageKit:Analysis:File*, operation:u8*, position:u64, argument:u8*) -> u8* {
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    defer out.destroy()
    if current.diagnostic {
        // Partial traces still support completion and navigation. Rename needs
        // a completely successful analysis of every participating source.
        if LanguageKit:Analysis:equal(operation, "rename") { out.append("E\t"); LanguageKit:Analysis:append_hex(out, current.diagnostic); out.append("\n"); return out.take() }
    }
    if LanguageKit:Analysis:equal(operation, "completion") { LanguageKit:Analysis:completion(out, current, position); return out.take() }
    if LanguageKit:Analysis:equal(operation, "signature") { LanguageKit:Analysis:signature(out, current, position); return out.take() }
    let selected = LanguageKit:Analysis:selected(current, position)
    let document = LanguageKit:Analysis:equal(operation, "document-symbols")
    let workspace = LanguageKit:Analysis:equal(operation, "workspace-symbols")
    var effective_operation = operation
    if LanguageKit:Analysis:equal(operation, "scope") { effective_operation = argument }
    var file_only:i64 = document
    if selected && selected.local != 0 && !LanguageKit:Analysis:equal(effective_operation, "type-definition") { file_only = 1 }
    if selected && LanguageKit:Analysis:equal(effective_operation, "definition") {
        var own = LanguageKit:Analysis:table_find(&current.by_target, selected.target, 0)
        while own {
            let item = cast(LanguageKit:Analysis:Occurrence*, own.value)
            if item.role == 2 { file_only = 1 }
            own = LanguageKit:Analysis:table_next(own)
        }
    }
    if LanguageKit:Analysis:equal(operation, "scope") {
        if !selected { out.append("Q\tnone\n") }
        else if file_only != 0 { out.append("Q\tlocal\n") }
        else { out.append("Q\tproject\n") }
        return out.take()
    }
    if !selected && !document && !workspace { out.append("E\t"); LanguageKit:Analysis:append_hex(out, "no semantic symbol at cursor"); out.append("\n"); return out.take() }
    var requested = cast(u8*, 0)
    if selected { requested = selected.target }
    if LanguageKit:Analysis:equal(operation, "type-definition") {
        var entry = LanguageKit:Analysis:table_find(&current.by_container, selected.target, 0)
        while entry {
            let relation = cast(LanguageKit:Analysis:Occurrence*, entry.value)
            if relation.role == 4 { requested = relation.target }
            entry = LanguageKit:Analysis:table_next(entry)
        }
        if requested == selected.target {
            let symbol = LanguageKit:Analysis:symbol(current, selected.target)
            if symbol {
                if symbol.prototype && symbol.prototype[0] != 0 { let prototype = LanguageKit:Analysis:symbol(current, symbol.prototype); if prototype { requested = prototype.key } }
                else if symbol.type && symbol.type[0] != 0 { let type = LanguageKit:Analysis:symbol(current, symbol.type); if type { requested = type.key } }
            }
        }
    }
    if LanguageKit:Analysis:equal(operation, "rename") {
        var definitions:u64 = 0
        var file = index.files
        if file_only != 0 { file = current }
        while file {
            if file.diagnostic { out.append("E\t"); LanguageKit:Analysis:append_hex(out, file.diagnostic); out.append("\n"); return out.take() }
            var entry = LanguageKit:Analysis:table_find(&file.by_target, requested, 0)
            while entry {
                let item = cast(LanguageKit:Analysis:Occurrence*, entry.value)
                if item.role == 2 { definitions += 1 }
                entry = LanguageKit:Analysis:table_next(entry)
            }
            if file_only != 0 { file = cast(LanguageKit:Analysis:File*, 0) } else { file = file.next }
        }
        if definitions != 1 { out.append("E\t"); LanguageKit:Analysis:append_hex(out, "rename requires one unambiguous source definition"); out.append("\n"); return out.take() }
    }
    var parent = cast(u8*, 0)
    if LanguageKit:Analysis:equal(operation, "prototype-hierarchy") {
        let symbol = LanguageKit:Analysis:symbol(current, requested)
        if symbol { let prototype = LanguageKit:Analysis:symbol(current, symbol.prototype); if prototype { parent = prototype.key } }
    }
    var results = cast(LanguageKit:Analysis:Result*, 0)
    var file = index.files
    let declarations = document || workspace || LanguageKit:Analysis:equal(operation, "implementations") || LanguageKit:Analysis:equal(operation, "prototype-hierarchy")
    let outgoing = LanguageKit:Analysis:equal(operation, "outgoing-calls")
    let targeted = outgoing || LanguageKit:Analysis:equal(operation, "incoming-calls") || LanguageKit:Analysis:equal(operation, "definition") || LanguageKit:Analysis:equal(operation, "type-definition") ||
                   LanguageKit:Analysis:equal(operation, "references") || LanguageKit:Analysis:equal(operation, "rename")
    if file_only != 0 { file = current }
    while file {
        if context:process:interrupted() { break }
        var entry = cast(LanguageKit:Analysis:Entry*, 0)
        var item = file.occurrences
        if declarations { item = file.declarations }
        if targeted {
            if outgoing { entry = LanguageKit:Analysis:table_find(&file.by_container, requested, 0) }
            else { entry = LanguageKit:Analysis:table_find(&file.by_target, requested, 0) }
            item = cast(LanguageKit:Analysis:Occurrence*, 0)
            if entry { item = cast(LanguageKit:Analysis:Occurrence*, entry.value) }
        }
        while item {
            if context:process:interrupted() { break }
            var include:i64 = 0
            if document { include = file == current && item.role == 2 && item.local == 0 }
            else if workspace { include = item.role == 2 && item.local == 0 && LanguageKit:Analysis:contains(item.label, argument) }
            else if LanguageKit:Analysis:equal(operation, "definition") || LanguageKit:Analysis:equal(operation, "type-definition") {
                include = item.role == 2 && LanguageKit:Analysis:equal(item.target, requested)
            } else if LanguageKit:Analysis:equal(operation, "references") || LanguageKit:Analysis:equal(operation, "rename") {
                include = LanguageKit:Analysis:equal(item.target, requested)
                if include != 0 && item.local == 0 {
                    let resolved = LanguageKit:Analysis:symbol(file, item.label)
                    if !resolved || !LanguageKit:Analysis:equal(resolved.key, requested) { include = 0 }
                }
            } else if LanguageKit:Analysis:equal(operation, "incoming-calls") {
                include = item.role == 3 && LanguageKit:Analysis:equal(item.target, requested)
            } else if LanguageKit:Analysis:equal(operation, "outgoing-calls") {
                include = item.role == 3 && LanguageKit:Analysis:equal(item.container, requested)
            } else if LanguageKit:Analysis:equal(operation, "implementations") || LanguageKit:Analysis:equal(operation, "prototype-hierarchy") {
                include = item.role == 2 && item.local == 0 &&
                          (LanguageKit:Analysis:prototype_in(file, item.target, requested) || LanguageKit:Analysis:equal(item.target, parent))
            }
            if include != 0 {
                let result = alloc(LanguageKit:Analysis:Result)
                if result { result.file = file; result.item = item; result.next = results; results = result }
            }
            if targeted {
                entry = LanguageKit:Analysis:table_next(entry)
                item = cast(LanguageKit:Analysis:Occurrence*, 0)
                if entry { item = cast(LanguageKit:Analysis:Occurrence*, entry.value) }
            } else if declarations { item = item.declaration_next } else { item = item.next }
        }
        if file_only != 0 { file = cast(LanguageKit:Analysis:File*, 0) } else { file = file.next }
    }
    if !context:process:interrupted() { results = LanguageKit:Analysis:sort_results(results, LanguageKit:Analysis:equal(operation, "rename")) }
    var previous_file = cast(LanguageKit:Analysis:File*, 0)
    var previous_start:u64 = 0
    var previous_finish:u64 = 0
    while results {
        let next = results.next
        if !context:process:interrupted() && (results.file != previous_file || results.item.start != previous_start || results.item.finish != previous_finish) {
            LanguageKit:Analysis:location(out, results.file, results.item)
            previous_file = results.file; previous_start = results.item.start; previous_finish = results.item.finish
        }
        free(cast(u8*, results)); results = next
    }
    return out.take()
}

// Build one owned file fragment from real semantic traces. The same constructor
// serves the IDE and persistent editor session; no heap pointer is published.
let LanguageKit:Analysis:file = fn (index:LanguageKit:Analysis:Index*, path:u8*, source:u8*, trace:u8*) -> LanguageKit:Analysis:File* {
    let file = alloc(LanguageKit:Analysis:File)
    if !file { return cast(LanguageKit:Analysis:File*, 0) }
    file.path = LanguageKit:copy_text(path)
    file.source = LanguageKit:copy_text(source)
    file.diagnostic = cast(u8*, 0)
    file.symbols = cast(LanguageKit:Analysis:Symbol*, 0)
    file.tokens = cast(LanguageKit:Analysis:Token*, 0)
    file.occurrences = cast(LanguageKit:Analysis:Occurrence*, 0); file.declarations = cast(LanguageKit:Analysis:Occurrence*, 0)
    LanguageKit:Analysis:table_init(&file.symbols_by_name)
    LanguageKit:Analysis:table_init(&file.by_position)
    LanguageKit:Analysis:table_init(&file.by_target)
    LanguageKit:Analysis:table_init(&file.by_container)
    LanguageKit:Analysis:table_init(&file.locals_by_name)
    file.ranges = cast(LanguageKit:Analysis:Occurrence**, 0); file.range_ends = cast(u64*, 0); file.range_count = 0
    file.previous = cast(LanguageKit:Analysis:File*, 0); file.next = index.files
    if index.files { index.files.previous = file }
    index.files = file
    LanguageKit:Analysis:table_add(&index.by_path, file.path, 0, cast(u8*, file))
    LanguageKit:Analysis:parse_trace(file, trace)
    LanguageKit:Analysis:classify(file)
    if context:process:interrupted() { return file }
    var count:u64 = 0
    var occurrence = file.occurrences
    while occurrence { count += 1; occurrence = occurrence.next }
    file.ranges = cast(LanguageKit:Analysis:Occurrence**, malloc(count * 8))
    file.range_ends = cast(u64*, malloc(count * 8))
    var results = cast(LanguageKit:Analysis:Result*, 0)
    var item = file.occurrences
    while item {
        LanguageKit:Analysis:table_add(&file.by_container, item.container, 0, cast(u8*, item))
        if item.role == 2 { item.declaration_next = file.declarations; file.declarations = item }
        let result = alloc(LanguageKit:Analysis:Result)
        if result { result.file = file; result.item = item; result.next = results; results = result }
        item = item.next
    }
    results = LanguageKit:Analysis:sort_results(results, 0)
    var maximum:u64 = 0
    while results {
        let next = results.next
        if file.ranges && file.range_ends {
            file.ranges[file.range_count] = results.item
            if results.item.finish > maximum { maximum = results.item.finish }
            file.range_ends[file.range_count] = maximum; file.range_count += 1
        }
        free(cast(u8*, results)); results = next
    }
    return file
}

// A session owns the heap index through the existing native-payload lifecycle.
// It is never published; disconnecting or resetting the session destroys it.
let LanguageKit:Analysis:cleanup = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let slot = context:phrase:address(state, called)
        var raw:i64 = 0
        if context:phrase:read(state, slot, 0, cast(u8*, &raw), 8) && raw { LanguageKit:Analysis:destroy(cast(LanguageKit:Analysis:Index*, raw)) }
        raw = 0; context:phrase:write(state, slot, 0, cast(u8*, &raw), 8)
    }
}
let LanguageKit:Analysis:cached = fn (state:Context*) -> LanguageKit:Analysis:Index* {
    let raw = LanguageKit:state_get(state, "__analysis_index")
    if raw { return cast(LanguageKit:Analysis:Index*, raw) }
    let index = LanguageKit:Analysis:new()
    if !index { return cast(LanguageKit:Analysis:Index*, 0) }
    let kit = context:phrase:find(state, "LanguageKit")
    let analysis = context:phrase:find:exact(state, kit, "Analysis")
    let cleanup = context:phrase:find:exact(state, analysis, "cleanup")
    if !LanguageKit:state_pointer_set_owned(state, "__analysis_index", cast(i64, index), cleanup) {
        LanguageKit:Analysis:destroy(index); return cast(LanguageKit:Analysis:Index*, 0)
    }
    return index
}
let LanguageKit:Analysis:find_file = fn (index:LanguageKit:Analysis:Index*, path:u8*) -> LanguageKit:Analysis:File* {
    let entry = LanguageKit:Analysis:table_find(&index.by_path, path, 0)
    if entry { return cast(LanguageKit:Analysis:File*, entry.value) }
    return cast(LanguageKit:Analysis:File*, 0)
}
let LanguageKit:Analysis:remove_file = fn (index:LanguageKit:Analysis:Index*, path:u8*) -> void {
    let file = LanguageKit:Analysis:find_file(index, path)
    if !file { return }
    LanguageKit:Analysis:table_remove(&index.by_path, path, 0)
    if file.previous { file.previous.next = file.next } else { index.files = file.next }
    if file.next { file.next.previous = file.previous }
    LanguageKit:Analysis:file_clear(file); free(file.path); free(cast(u8*, file))
}
let LanguageKit:Analysis:update_file = fn (index:LanguageKit:Analysis:Index*, path:u8*, source:u8*, trace:u8*) -> LanguageKit:Analysis:File* {
    LanguageKit:Analysis:remove_file(index, path)
    return LanguageKit:Analysis:file(index, path, source, trace)
}

// Hex payloads are data consumed by one compiled phrase, not generated programs.
// update/remove/query share the same session-local index and lifecycle.
let LanguageKit:Analysis:request = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let bytes = context:source:bytes(state)
        let text = LanguageKit:copy_bytes(context:source:data(state), cast(i64, bytes))
        context:source:advance(state, bytes)
        if !text { return }
        defer free(text)
        var length = strlen(text)
        while length != 0 && (text[length - 1] == 10 || text[length - 1] == 13) { length -= 1; text[length] = 0 }
        var at:i64 = 0
        while text[at] == 9 || text[at] == 32 { at += 1 }
        let command_end = LanguageKit:Analysis:find_byte(text, at, 9)
        if command_end < 0 { return }
        let command = LanguageKit:copy_bytes(&text[at], command_end - at)
        if !command { return }
        defer free(command)
        let path_end = LanguageKit:Analysis:find_byte(text, command_end + 1, 9)
        var path_finish = path_end
        if path_finish < 0 { path_finish = cast(i64, strlen(text)) }
        let path = LanguageKit:Analysis:decode_hex(text, command_end + 1, path_finish)
        if !path { return }
        defer free(path)
        let index = LanguageKit:Analysis:cached(state)
        if !index { return }
        if LanguageKit:Analysis:equal(command, "remove") { LanguageKit:Analysis:remove_file(index, path); return }
        if path_end < 0 { return }
        let field_end = LanguageKit:Analysis:find_byte(text, path_end + 1, 9)
        if field_end < 0 { return }
        let field = LanguageKit:Analysis:decode_hex(text, path_end + 1, field_end)
        if !field { return }
        defer free(field)
        if LanguageKit:Analysis:equal(command, "update") {
            let trace = LanguageKit:Analysis:decode_hex(text, field_end + 1, cast(i64, strlen(text)))
            if trace { LanguageKit:Analysis:update_file(index, path, field, trace); free(trace) }
            return
        }
        let cursor_end = LanguageKit:Analysis:find_byte(text, field_end + 1, 9)
        if cursor_end < 0 { return }
        let cursor = LanguageKit:Analysis:parse_decimal(text, field_end + 1, cursor_end)
        let argument = LanguageKit:Analysis:decode_hex(text, cursor_end + 1, cast(i64, strlen(text)))
        if !argument { return }
        defer free(argument)
        let current = LanguageKit:Analysis:find_file(index, path)
        if !current { return }
        let response = LanguageKit:Analysis:query_index(index, current, field, cast(u64, cursor), argument)
        if response { context:io:write(state, response); free(response) }
    }
}
let languagekit_analysis_request = <LanguageKit:Analysis:request>
