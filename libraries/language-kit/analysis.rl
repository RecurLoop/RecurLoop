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
    next:LanguageKit:Analysis:Occurrence*
}

record LanguageKit:Analysis:Function {
    key:u8*
    start:u64
    finish:u64
    next:LanguageKit:Analysis:Function*
}

record LanguageKit:Analysis:File {
    path:u8*
    source:u8*
    diagnostic:u8*
    symbols:LanguageKit:Analysis:Symbol*
    tokens:LanguageKit:Analysis:Token*
    functions:LanguageKit:Analysis:Function*
    occurrences:LanguageKit:Analysis:Occurrence*
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
    var symbol = file.symbols
    while symbol {
        let next = symbol.next
        free(symbol.key); free(symbol.name); free(symbol.kind); free(symbol.docs)
        free(symbol.prototype); free(symbol.type); free(symbol.signature)
        free(cast(u8*, symbol)); symbol = next
    }
    var token = file.tokens
    while token { let next = token.next; free(token.text); free(cast(u8*, token)); token = next }
    var function = file.functions
    while function { let next = function.next; free(function.key); free(cast(u8*, function)); function = next }
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
    file.functions = cast(LanguageKit:Analysis:Function*, 0)
    file.occurrences = cast(LanguageKit:Analysis:Occurrence*, 0)
}

let LanguageKit:Analysis:destroy = fn (index:LanguageKit:Analysis:Index*) -> void {
    if !index { return }
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
    while source[at] != 0 {
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
    var symbol = file.symbols
    while symbol { if (LanguageKit:Analysis:equal(symbol.name, name) || LanguageKit:Analysis:equal(symbol.key, name)) { return symbol }; symbol = symbol.next }
    return cast(LanguageKit:Analysis:Symbol*, 0)
}

let LanguageKit:Analysis:add = fn (file:LanguageKit:Analysis:File*, target:u8*, container:u8*, label:u8*, start:u64, finish:u64, line:u64,
                          role:i64, exact:i64, local:i64) -> LanguageKit:Analysis:Occurrence* {
    var existing = file.occurrences
    while existing {
        if existing.start == start && existing.finish == finish && LanguageKit:Analysis:equal(existing.target, target) {
            if role > existing.role { existing.role = role }
            if exact > existing.exact { existing.exact = exact }
            if local > existing.local { existing.local = local }
            if container && container[0] != 0 { free(existing.container); existing.container = LanguageKit:copy_text(container) }
            return existing
        }
        existing = existing.next
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
    item.next = file.occurrences; file.occurrences = item
    return item
}

let LanguageKit:Analysis:parse_trace = fn (file:LanguageKit:Analysis:File*, response:u8*) -> void {
    if !response { file.diagnostic = LanguageKit:copy_text("source trace unavailable"); return }
    var at:i64 = 0
    while response[at] != 0 {
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
                    let begin_byte = LanguageKit:Analysis:byte_offset(file.source, cast(u64, start))
                    let end_byte = LanguageKit:Analysis:byte_offset(file.source, cast(u64, finish))
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
    var token = open
    var depth:i64 = 0
    while token {
        if LanguageKit:Analysis:equal(token.text, opening) { depth += 1 }
        else if LanguageKit:Analysis:equal(token.text, closing) { depth -= 1; if depth == 0 { return token } }
        token = token.next
    }
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
    var result:u8* = ""
    var width:u64 = strlen(file.source) + 1
    var function = file.functions
    while function {
        if function.start <= position && position < function.finish && function.finish - function.start < width {
            result = function.key; width = function.finish - function.start
        }
        function = function.next
    }
    return result
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
    let range = alloc(LanguageKit:Analysis:Function)
    if range {
        range.key = LanguageKit:copy_text(function_symbol.key); range.start = body.finish; range.finish = finish.start
        range.next = file.functions; file.functions = range
    }
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
    var occurrence = file.occurrences
    while occurrence {
        if occurrence.start >= body.finish && occurrence.finish <= finish.start {
            free(occurrence.container); occurrence.container = LanguageKit:copy_text(function_symbol.key)
        }
        occurrence = occurrence.next
    }
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
        if token.identifier != 0 && token.previous && LanguageKit:Analysis:local_word(token.previous.text) {
            var block = token.previous
            while block && !(LanguageKit:Analysis:equal(block.text, "{") && block.depth + 1 == token.depth) { block = block.previous }
            var block_end = finish
            if block { let close = LanguageKit:Analysis:matching(block, "{", "}"); if close { block_end = close } }
            LanguageKit:Analysis:declare_local(file, token, function_symbol.key, block_end.start)
        }
        token = token.next
    }
    token = body.next
    while token && token != finish {
        if token.identifier != 0 {
            var best = cast(LanguageKit:Analysis:Occurrence*, 0)
            occurrence = file.occurrences
            while occurrence {
                if occurrence.local != 0 && occurrence.role == 2 && LanguageKit:Analysis:equal(occurrence.container, function_symbol.key) &&
                   LanguageKit:Analysis:equal(occurrence.label, token.text) && token.start >= occurrence.start &&
                   token.start < occurrence.scope_finish && token.depth >= occurrence.depth {
                    if !best { best = occurrence }
                    else if occurrence.depth > best.depth || (occurrence.depth == best.depth && occurrence.start > best.start) { best = occurrence }
                }
                occurrence = occurrence.next
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
        if token.identifier != 0 {
            var definition:i64 = 0
            if token.previous && LanguageKit:Analysis:definition_word(token.previous.text) && token.depth == 0 { definition = 1 }
            var role:i64 = 1
            if token.previous && token.next && token.previous.text[0] == 60 && token.next.text[0] == 62 { role = 5 }
            if definition != 0 { role = 2 }
            else if token.next && LanguageKit:Analysis:equal(token.next.text, "(") { role = 3 }
            else if token.previous && token.previous.previous && token.previous.text[0] == 62 && token.previous.previous.text[0] == 45 { role = 4 }
            let symbol = LanguageKit:Analysis:symbol(file, token.text)
            var occurrence = file.occurrences
            while occurrence {
                if symbol && occurrence.exact != 0 && occurrence.start == token.start && occurrence.finish == token.finish &&
                   LanguageKit:Analysis:equal(occurrence.target, symbol.key) {
                    if role > occurrence.role { occurrence.role = role }
                }
                occurrence = occurrence.next
            }
            // Typed fn identifiers are not phrase-dispatch tokens. Resolve calls
            // against the exported compiler catalog here, excluding member names
            // and lexically shadowed locals. This policy belongs to the example.
            var typed_call:i64 = 0
            if role == 3 && symbol && LanguageKit:Analysis:equal(symbol.kind, "function") {
                typed_call = 1
                if token.previous && token.previous.text[0] == 46 { typed_call = 0 }
                var local = file.occurrences
                while local {
                    if local.local != 0 && local.start == token.start && local.finish == token.finish { typed_call = 0 }
                    local = local.next
                }
            }
            if (definition != 0 || role == 4 || role == 5 || typed_call != 0) && symbol {
                let added = LanguageKit:Analysis:add(file, symbol.key, "", token.text, token.start, token.finish, token.line, role, 0, 0)
                if added && typed_call != 0 {
                    free(added.container); added.container = LanguageKit:copy_text(LanguageKit:Analysis:container(file, token.start))
                }
            }
        }
        token = token.next
    }
}

let LanguageKit:Analysis:selected = fn (file:LanguageKit:Analysis:File*, position:u64) -> LanguageKit:Analysis:Occurrence* {
    var selected = cast(LanguageKit:Analysis:Occurrence*, 0)
    var item = file.occurrences
    while item {
        if item.start <= position && position < item.finish {
            if !selected { selected = item }
            else if item.local > selected.local || (item.local == selected.local &&
                    (item.finish - item.start < selected.finish - selected.start ||
                     (item.finish - item.start == selected.finish - selected.start && item.role > selected.role))) { selected = item }
        }
        item = item.next
    }
    return selected
}

let LanguageKit:Analysis:location = fn (out:LanguageKit:Text*, file:LanguageKit:Analysis:File*, item:LanguageKit:Analysis:Occurrence*) -> void {
    out.append("L\t"); LanguageKit:Analysis:append_hex(out, file.path); out.append("\t")
    LanguageKit:Analysis:append_u64(out, item.start); out.append("\t"); LanguageKit:Analysis:append_u64(out, item.finish); out.append("\t")
    LanguageKit:Analysis:append_u64(out, item.line); out.append("\t"); LanguageKit:Analysis:append_u64(out, cast(u64, item.role)); out.append("\t")
    LanguageKit:Analysis:append_hex(out, item.label); out.append("\n")
}

let LanguageKit:Analysis:insert_result = fn (head:LanguageKit:Analysis:Result*, file:LanguageKit:Analysis:File*, item:LanguageKit:Analysis:Occurrence*,
                                    descending:i64) -> LanguageKit:Analysis:Result* {
    var previous = cast(LanguageKit:Analysis:Result*, 0)
    var current = head
    var searching:i64 = 1
    while current && searching != 0 {
        let order = strcmp(current.file.path, file.path)
        if order > 0 { searching = 0 }
        else if order == 0 && ((descending != 0 && current.item.start < item.start) ||
                              (descending == 0 && current.item.start > item.start)) { searching = 0 }
        else {
            if order == 0 && current.item.start == item.start && current.item.finish == item.finish { return head }
            previous = current; current = current.next
        }
    }
    let result = alloc(LanguageKit:Analysis:Result)
    if !result { return head }
    result.file = file; result.item = item; result.next = current
    if previous { previous.next = result; return head }
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
    var item = file.occurrences
    let container = LanguageKit:Analysis:container(file, position)
    while item {
        var visible:i64 = item.local != 0 && item.role == 2 && item.start <= position && position < item.scope_finish &&
                          LanguageKit:Analysis:equal(container, item.container) && LanguageKit:Analysis:prefix(item.label, prefix)
        if visible != 0 {
            var other = file.occurrences
            while other {
                if other.local != 0 && other.role == 2 && other.start <= position && position < other.scope_finish &&
                   LanguageKit:Analysis:equal(container, other.container) && LanguageKit:Analysis:equal(item.label, other.label) &&
                   (other.depth > item.depth || (other.depth == item.depth && other.start > item.start)) { visible = 0 }
                other = other.next
            }
        }
        if visible != 0 {
            out.append("C\t"); LanguageKit:Analysis:append_u64(out, start); out.append("\t"); LanguageKit:Analysis:append_u64(out, position); out.append("\t")
            LanguageKit:Analysis:append_hex(out, item.label); out.append("\t"); LanguageKit:Analysis:append_hex(out, item.label); out.append("\t6c6f63616c\t\n")
        }
        item = item.next
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
    if !selected && !document && !workspace { out.append("E\t"); LanguageKit:Analysis:append_hex(out, "no semantic symbol at cursor"); out.append("\n"); return out.take() }
    var requested = cast(u8*, 0)
    if selected { requested = selected.target }
    if LanguageKit:Analysis:equal(operation, "type-definition") {
        var relation = current.occurrences
        while relation {
            if relation.role == 4 && LanguageKit:Analysis:equal(relation.container, selected.target) { requested = relation.target }
            relation = relation.next
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
        while file {
            if file.diagnostic { out.append("E\t"); LanguageKit:Analysis:append_hex(out, file.diagnostic); out.append("\n"); return out.take() }
            var item = file.occurrences
            while item {
                if item.role == 2 && LanguageKit:Analysis:equal(item.target, requested) { definitions += 1 }
                item = item.next
            }
            file = file.next
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
    while file {
        var item = file.occurrences
        while item {
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
            if include != 0 { results = LanguageKit:Analysis:insert_result(results, file, item, LanguageKit:Analysis:equal(operation, "rename")) }
            item = item.next
        }
        file = file.next
    }
    while results {
        let next = results.next
        LanguageKit:Analysis:location(out, results.file, results.item)
        free(cast(u8*, results)); results = next
    }
    return out.take()
}

// Build a transient request index from real semantic traces. No heap pointers are
// published or written to engine images; the caller destroys the index.
let LanguageKit:Analysis:file = fn (index:LanguageKit:Analysis:Index*, path:u8*, source:u8*, trace:u8*) -> LanguageKit:Analysis:File* {
    let file = alloc(LanguageKit:Analysis:File)
    if !file { return cast(LanguageKit:Analysis:File*, 0) }
    file.path = LanguageKit:copy_text(path)
    file.source = LanguageKit:copy_text(source)
    file.diagnostic = cast(u8*, 0)
    file.symbols = cast(LanguageKit:Analysis:Symbol*, 0)
    file.tokens = cast(LanguageKit:Analysis:Token*, 0)
    file.functions = cast(LanguageKit:Analysis:Function*, 0)
    file.occurrences = cast(LanguageKit:Analysis:Occurrence*, 0)
    file.next = index.files
    index.files = file
    LanguageKit:Analysis:parse_trace(file, trace)
    LanguageKit:Analysis:classify(file)
    return file
}
