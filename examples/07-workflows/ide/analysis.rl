// Project-local analysis policy. The host exports dictionary facts and actual
// source matches through :trace; all indexing and editor operations live here.
// Grammar extensions can replace the classifiers below without changing C++.

let IDE:Analysis = phrase { dictionary = true permanent = true }

record IDE:Analysis:Symbol {
    id:u64
    key:u8*
    name:u8*
    kind:u8*
    docs:u8*
    prototype:u8*
    type:u8*
    signature:u8*
    next:IDE:Analysis:Symbol*
}

record IDE:Analysis:Token {
    text:u8*
    start:u64
    finish:u64
    byte_start:u64
    byte_finish:u64
    line:u64
    depth:i64
    identifier:i64
    previous:IDE:Analysis:Token*
    next:IDE:Analysis:Token*
}

record IDE:Analysis:Occurrence {
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
    next:IDE:Analysis:Occurrence*
}

record IDE:Analysis:Function {
    key:u8*
    start:u64
    finish:u64
    next:IDE:Analysis:Function*
}

record IDE:Analysis:File {
    path:u8*
    source:u8*
    diagnostic:u8*
    symbols:IDE:Analysis:Symbol*
    tokens:IDE:Analysis:Token*
    functions:IDE:Analysis:Function*
    occurrences:IDE:Analysis:Occurrence*
    next:IDE:Analysis:File*
}

record IDE:Analysis:Result {
    file:IDE:Analysis:File*
    item:IDE:Analysis:Occurrence*
    next:IDE:Analysis:Result*
}

record IDE:Analysis:Index {
    revision:u64
    standalone:i64
    files:IDE:Analysis:File*
}

let IDE:Analysis:equal = fn (left:u8*, right:u8*) -> i64 {
    return left && right && strcmp(left, right) == 0
}

let IDE:Analysis:identifier = fn (ch:u8) -> i64 {
    return LanguageKit:is_alpha(ch) || LanguageKit:is_digit(ch) || ch == 95
}

let IDE:Analysis:byte_offset = fn (text:u8*, position:u64) -> u64 {
    var at:u64 = 0
    var count:u64 = 0
    while text[at] != 0 && count < position {
        at += 1
        while text[at] / 64 == 2 { at += 1 }
        count += 1
    }
    return at
}

let IDE:Analysis:definition_word = fn (word:u8*) -> i64 {
    return IDE:Analysis:equal(word, "let") || IDE:Analysis:equal(word, "record") ||
           IDE:Analysis:equal(word, "dictionary") || IDE:Analysis:equal(word, "type") || IDE:Analysis:equal(word, "fn")
}

let IDE:Analysis:local_word = fn (word:u8*) -> i64 {
    return IDE:Analysis:equal(word, "let") || IDE:Analysis:equal(word, "var") || IDE:Analysis:equal(word, "const")
}

let IDE:Analysis:file_clear = fn (file:IDE:Analysis:File*) -> void {
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
    file.symbols = cast(IDE:Analysis:Symbol*, 0)
    file.tokens = cast(IDE:Analysis:Token*, 0)
    file.functions = cast(IDE:Analysis:Function*, 0)
    file.occurrences = cast(IDE:Analysis:Occurrence*, 0)
}

let IDE:Analysis:destroy = fn (index:IDE:Analysis:Index*) -> void {
    if !index { return }
    var file = index.files
    while file {
        let next = file.next
        IDE:Analysis:file_clear(file); free(file.path); free(cast(u8*, file)); file = next
    }
    free(cast(u8*, index))
}

let IDE:Analysis:tokenize = fn (file:IDE:Analysis:File*) -> void {
    let source = file.source
    var at:u64 = 0
    var chars:u64 = 0
    var line:u64 = 1
    var depth:i64 = 0
    var tail = cast(IDE:Analysis:Token*, 0)
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
                    if IDE:Analysis:identifier(source[at]) { at += 1; chars += 1 }
                    else if source[at] == 58 && source[at + 1] != 58 && (LanguageKit:is_alpha(source[at + 1]) || source[at + 1] == 95) { at += 1; chars += 1 }
                    else { scanning = 0 }
                }
            } else {
                at += 1
                if ch / 64 != 2 { chars += 1 }
                while source[at] / 64 == 2 { at += 1 }
            }
            if ch == 125 && depth > 0 { depth -= 1 }
            let token = alloc(IDE:Analysis:Token)
            if !token { return }
            token.text = LanguageKit:copy_bytes(&source[begin], cast(i64, at - begin))
            if !token.text { free(cast(u8*, token)); return }
            token.start = char_begin; token.finish = chars
            token.byte_start = begin; token.byte_finish = at
            token.line = source_line; token.depth = depth; token.identifier = is_id
            token.previous = tail; token.next = cast(IDE:Analysis:Token*, 0)
            if tail { tail.next = token } else { file.tokens = token }
            tail = token
            if ch == 123 { depth += 1 }
        }
    }
}

let IDE:Analysis:key = fn (name:u8*, version:u64) -> u8* {
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    out.append(name); out.append_byte(31); IDE:append_u64(out, version)
    let result = out.take(); out.destroy(); return result
}

let IDE:Analysis:symbol = fn (file:IDE:Analysis:File*, name:u8*) -> IDE:Analysis:Symbol* {
    var symbol = file.symbols
    while symbol { if (IDE:Analysis:equal(symbol.name, name) || IDE:Analysis:equal(symbol.key, name)) { return symbol }; symbol = symbol.next }
    return cast(IDE:Analysis:Symbol*, 0)
}

let IDE:Analysis:add = fn (file:IDE:Analysis:File*, target:u8*, container:u8*, label:u8*, start:u64, finish:u64, line:u64,
                          role:i64, exact:i64, local:i64) -> IDE:Analysis:Occurrence* {
    var existing = file.occurrences
    while existing {
        if existing.start == start && existing.finish == finish && IDE:Analysis:equal(existing.target, target) {
            if role > existing.role { existing.role = role }
            if exact > existing.exact { existing.exact = exact }
            if local > existing.local { existing.local = local }
            if container && container[0] != 0 { free(existing.container); existing.container = IDE:copy(container) }
            return existing
        }
        existing = existing.next
    }
    let item = alloc(IDE:Analysis:Occurrence)
    if !item { return cast(IDE:Analysis:Occurrence*, 0) }
    item.target = IDE:copy(target); item.container = IDE:copy(container); item.label = IDE:copy(label)
    if !item.target || !item.container || !item.label {
        free(item.target); free(item.container); free(item.label); free(cast(u8*, item))
        return cast(IDE:Analysis:Occurrence*, 0)
    }
    item.start = start; item.finish = finish; item.line = line
    item.role = role; item.exact = exact; item.local = local
    item.depth = 0; item.scope_finish = 0
    item.next = file.occurrences; file.occurrences = item
    return item
}

let IDE:Analysis:trace = fn (host:IDE:Host*, path:u8*, source:u8*) -> u8* {
    return IDE:intelligence_inspect(host, path, source, 1)
}

let IDE:Analysis:parse_trace = fn (file:IDE:Analysis:File*, response:u8*) -> void {
    if !response { file.diagnostic = IDE:copy("source trace unavailable"); return }
    var at:i64 = 0
    while response[at] != 0 {
        let end = IDE:App:find_byte(response, at, 10)
        if response[at] == 80 && response[at + 1] == 9 {
            let f1 = IDE:App:find_byte(response, at + 2, 9)
            let f2 = IDE:App:find_byte(response, f1 + 1, 9)
            let f3 = IDE:App:find_byte(response, f2 + 1, 9)
            let f4 = IDE:App:find_byte(response, f3 + 1, 9)
            let f5 = IDE:App:find_byte(response, f4 + 1, 9)
            let f6 = IDE:App:find_byte(response, f5 + 1, 9)
            if f6 < end {
                let item = alloc(IDE:Analysis:Symbol)
                if !item { return }
                item.id = cast(u64, IDE:App:parse_decimal(response, at + 2, f1))
                item.name = IDE:App:decode_hex(response, f1 + 1, f2)
                item.key = IDE:Analysis:key(item.name, item.id)
                item.kind = IDE:App:decode_hex(response, f2 + 1, f3)
                item.docs = IDE:App:decode_hex(response, f3 + 1, f4)
                item.prototype = IDE:App:decode_hex(response, f4 + 1, f5)
                item.type = IDE:App:decode_hex(response, f5 + 1, f6)
                item.signature = IDE:App:decode_hex(response, f6 + 1, end)
                item.next = file.symbols; file.symbols = item
            }
        } else if response[at] == 82 && response[at + 1] == 9 {
            let f1 = IDE:App:find_byte(response, at + 2, 9)
            let f2 = IDE:App:find_byte(response, f1 + 1, 9)
            let f3 = IDE:App:find_byte(response, f2 + 1, 9)
            let f4 = IDE:App:find_byte(response, f3 + 1, 9)
            if f4 < end {
                let start = IDE:App:parse_decimal(response, at + 2, f1)
                let finish = IDE:App:parse_decimal(response, f1 + 1, f2)
                let source_line = IDE:App:parse_decimal(response, f2 + 1, f3)
                let version = cast(u64, IDE:App:parse_decimal(response, f3 + 1, f4))
                let name = IDE:App:decode_hex(response, f4 + 1, end)
                if name && start >= 0 && finish > start {
                    let begin_byte = IDE:Analysis:byte_offset(file.source, cast(u64, start))
                    let end_byte = IDE:Analysis:byte_offset(file.source, cast(u64, finish))
                    let label = LanguageKit:copy_bytes(&file.source[begin_byte], cast(i64, end_byte - begin_byte))
                    let key = IDE:Analysis:key(name, version)
                    if label && key { IDE:Analysis:add(file, key, "", label, cast(u64, start), cast(u64, finish), cast(u64, source_line), 1, 1, 0) }
                    if label { free(label) }; if key { free(key) }
                }
                if name { free(name) }
            }
        } else if response[at] == 69 && response[at + 1] == 9 {
            if file.diagnostic { free(file.diagnostic) }
            file.diagnostic = IDE:App:decode_hex(response, at + 2, end)
        }
        at = end
        if response[at] == 10 { at += 1 }
    }
}

let IDE:Analysis:matching = fn (open:IDE:Analysis:Token*, opening:u8*, closing:u8*) -> IDE:Analysis:Token* {
    var token = open
    var depth:i64 = 0
    while token {
        if IDE:Analysis:equal(token.text, opening) { depth += 1 }
        else if IDE:Analysis:equal(token.text, closing) { depth -= 1; if depth == 0 { return token } }
        token = token.next
    }
    return cast(IDE:Analysis:Token*, 0)
}

let IDE:Analysis:local_key = fn (file:IDE:Analysis:File*, container:u8*, token:IDE:Analysis:Token*, name:u8*) -> u8* {
    let text = LanguageKit:Text:new()
    if !text { return cast(u8*, 0) }
    text.append("@"); text.append(file.path); text.append("|"); text.append(container)
    text.append("|"); IDE:append_u64(text, token.start); text.append("|"); text.append(name)
    let result = text.take(); text.destroy(); return result
}

let IDE:Analysis:container = fn (file:IDE:Analysis:File*, position:u64) -> u8* {
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

let IDE:Analysis:declare_local = fn (file:IDE:Analysis:File*, token:IDE:Analysis:Token*, container:u8*, scope_finish:u64) -> void {
    let colon = IDE:App:find_byte(token.text, 0, 58)
    let size = strlen(token.text)
    let name = LanguageKit:copy_bytes(token.text, colon)
    if !name { return }
    defer free(name)
    let key = IDE:Analysis:local_key(file, container, token, name)
    if !key { return }
    defer free(key)
    let item = IDE:Analysis:add(file, key, container, name, token.start, token.start + cast(u64, colon), token.line, 2, 0, 1)
    if item { item.depth = token.depth; item.scope_finish = scope_finish }
    if cast(u64, colon) < size {
        let type = &token.text[colon + 1]
        let symbol = IDE:Analysis:symbol(file, type)
        if symbol { IDE:Analysis:add(file, symbol.key, key, type, token.start + cast(u64, colon) + 1, token.finish, token.line, 4, 0, 0) }
    }
}

let IDE:Analysis:function = fn (file:IDE:Analysis:File*, name:IDE:Analysis:Token*, first:IDE:Analysis:Token*) -> void {
    if !name || !first || !IDE:Analysis:symbol(file, name.text) { return }
    let function_symbol = IDE:Analysis:symbol(file, name.text)
    var open = first
    while open && !IDE:Analysis:equal(open.text, "(") && !IDE:Analysis:equal(open.text, "{") && open.text[0] != 59 { open = open.next }
    if !open || !IDE:Analysis:equal(open.text, "(") { return }
    let parameters_end = IDE:Analysis:matching(open, "(", ")")
    if !parameters_end { return }
    var body = parameters_end.next
    while body && !IDE:Analysis:equal(body.text, "{") && body.text[0] != 59 { body = body.next }
    if !body || !IDE:Analysis:equal(body.text, "{") { return }
    let finish = IDE:Analysis:matching(body, "{", "}")
    if !finish { return }
    let range = alloc(IDE:Analysis:Function)
    if range {
        range.key = IDE:copy(function_symbol.key); range.start = body.finish; range.finish = finish.start
        range.next = file.functions; file.functions = range
    }
    free(function_symbol.kind); function_symbol.kind = IDE:copy("function")
    if function_symbol.signature && function_symbol.signature[0] == 0 {
        let signature = LanguageKit:Text:new()
        if signature {
            signature.append(name.text)
            let header = LanguageKit:copy_bytes(&file.source[open.byte_start], cast(i64, body.byte_start - open.byte_start))
            if header { signature.append(header); free(header) }
            free(function_symbol.signature); function_symbol.signature = signature.take(); signature.destroy()
        }
    }
    IDE:Analysis:add(file, function_symbol.key, "", name.text, name.start, name.finish, name.line, 2, 0, 0)
    var occurrence = file.occurrences
    while occurrence {
        if occurrence.start >= body.finish && occurrence.finish <= finish.start {
            free(occurrence.container); occurrence.container = IDE:copy(function_symbol.key)
        }
        occurrence = occurrence.next
    }
    var parameter = open.next
    var expect:i64 = 1
    var nested:i64 = 0
    while parameter && parameter != parameters_end {
        if IDE:Analysis:equal(parameter.text, "(") { nested += 1 }
        else if IDE:Analysis:equal(parameter.text, ")") { nested -= 1 }
        else if nested == 0 {
            if IDE:Analysis:equal(parameter.text, ",") { expect = 1 }
            else if expect != 0 && parameter.identifier != 0 {
                IDE:Analysis:declare_local(file, parameter, function_symbol.key, finish.start); expect = 0
            }
        }
        parameter = parameter.next
    }
    var token = body.next
    while token && token != finish {
        if token.identifier != 0 && token.previous && IDE:Analysis:local_word(token.previous.text) {
            var block = token.previous
            while block && !(IDE:Analysis:equal(block.text, "{") && block.depth + 1 == token.depth) { block = block.previous }
            var block_end = finish
            if block { let close = IDE:Analysis:matching(block, "{", "}"); if close { block_end = close } }
            IDE:Analysis:declare_local(file, token, function_symbol.key, block_end.start)
        }
        token = token.next
    }
    token = body.next
    while token && token != finish {
        if token.identifier != 0 {
            var best = cast(IDE:Analysis:Occurrence*, 0)
            occurrence = file.occurrences
            while occurrence {
                if occurrence.local != 0 && occurrence.role == 2 && IDE:Analysis:equal(occurrence.container, function_symbol.key) &&
                   IDE:Analysis:equal(occurrence.label, token.text) && token.start >= occurrence.start &&
                   token.start < occurrence.scope_finish && token.depth >= occurrence.depth {
                    if !best { best = occurrence }
                    else if occurrence.depth > best.depth || (occurrence.depth == best.depth && occurrence.start > best.start) { best = occurrence }
                }
                occurrence = occurrence.next
            }
            if best && best.start != token.start {
                var role:i64 = 1
                if token.next && IDE:Analysis:equal(token.next.text, "(") { role = 3 }
                IDE:Analysis:add(file, best.target, function_symbol.key, token.text, token.start, token.finish, token.line, role, 0, 1)
            }
        }
        token = token.next
    }
}

let IDE:Analysis:classify = fn (file:IDE:Analysis:File*) -> void {
    IDE:Analysis:tokenize(file)
    var token = file.tokens
    while token {
        if IDE:Analysis:equal(token.text, "fn") {
            if token.next && token.next.identifier != 0 { IDE:Analysis:function(file, token.next, token.next.next) }
            else if token.previous && token.previous.previous && IDE:Analysis:equal(token.previous.text, "=") {
                let name = token.previous.previous
                if name.previous && IDE:Analysis:equal(name.previous.text, "let") { IDE:Analysis:function(file, name, token.next) }
            }
        }
        token = token.next
    }
    token = file.tokens
    while token {
        if token.identifier != 0 {
            var definition:i64 = 0
            if token.previous && IDE:Analysis:definition_word(token.previous.text) && token.depth == 0 { definition = 1 }
            var role:i64 = 1
            if token.previous && token.next && token.previous.text[0] == 60 && token.next.text[0] == 62 { role = 5 }
            if definition != 0 { role = 2 }
            else if token.next && IDE:Analysis:equal(token.next.text, "(") { role = 3 }
            else if token.previous && token.previous.previous && token.previous.text[0] == 62 && token.previous.previous.text[0] == 45 { role = 4 }
            let symbol = IDE:Analysis:symbol(file, token.text)
            var occurrence = file.occurrences
            while occurrence {
                if symbol && occurrence.exact != 0 && occurrence.start == token.start && occurrence.finish == token.finish &&
                   IDE:Analysis:equal(occurrence.target, symbol.key) {
                    if role > occurrence.role { occurrence.role = role }
                }
                occurrence = occurrence.next
            }
            // Typed fn identifiers are not phrase-dispatch tokens. Resolve calls
            // against the exported compiler catalog here, excluding member names
            // and lexically shadowed locals. This policy belongs to the example.
            var typed_call:i64 = 0
            if role == 3 && symbol && IDE:Analysis:equal(symbol.kind, "function") {
                typed_call = 1
                if token.previous && token.previous.text[0] == 46 { typed_call = 0 }
                var local = file.occurrences
                while local {
                    if local.local != 0 && local.start == token.start && local.finish == token.finish { typed_call = 0 }
                    local = local.next
                }
            }
            if (definition != 0 || role == 4 || role == 5 || typed_call != 0) && symbol {
                let added = IDE:Analysis:add(file, symbol.key, "", token.text, token.start, token.finish, token.line, role, 0, 0)
                if added && typed_call != 0 {
                    free(added.container); added.container = IDE:copy(IDE:Analysis:container(file, token.start))
                }
            }
        }
        token = token.next
    }
}

let IDE:Analysis:update_file = fn (index:IDE:Analysis:Index*, host:IDE:Host*, path:u8*, source:u8*) -> IDE:Analysis:File* {
    var file = index.files
    while file && !IDE:Analysis:equal(file.path, path) { file = file.next }
    if file && IDE:Analysis:equal(file.source, source) { return file }
    if !file {
        file = alloc(IDE:Analysis:File)
        if !file { return cast(IDE:Analysis:File*, 0) }
        file.path = IDE:copy(path); file.source = cast(u8*, 0); file.diagnostic = cast(u8*, 0)
        file.symbols = cast(IDE:Analysis:Symbol*, 0); file.tokens = cast(IDE:Analysis:Token*, 0)
        file.functions = cast(IDE:Analysis:Function*, 0)
        file.occurrences = cast(IDE:Analysis:Occurrence*, 0)
        file.next = index.files; index.files = file
    }
    IDE:Analysis:file_clear(file)
    file.source = IDE:copy(source)
    if !file.source { return cast(IDE:Analysis:File*, 0) }
    let trace = IDE:Analysis:trace(host, path, source)
    IDE:Analysis:parse_trace(file, trace)
    if trace { free(trace) }
    IDE:Analysis:classify(file)
    return file
}

let IDE:Analysis:index = fn (state:IDE:App:State*, path:u8*, source:u8*) -> IDE:Analysis:File* {
    if !state || !state.host || !state.host.runner { return cast(IDE:Analysis:File*, 0) }
    var index = cast(IDE:Analysis:Index*, state.intelligence_index)
    let application_root = IDE:App:application_root(state)
    defer free(application_root)
    let standalone = application_root && IDE:path_is_inside(path, application_root)
    if index && (index.revision != state.host.runner.revision || index.standalone != standalone) {
        IDE:Analysis:destroy(index); index = cast(IDE:Analysis:Index*, 0); state.intelligence_index = cast(u8*, 0)
    }
    if !index {
        index = alloc(IDE:Analysis:Index)
        if !index { return cast(IDE:Analysis:File*, 0) }
        index.revision = state.host.runner.revision; index.standalone = standalone
        index.files = cast(IDE:Analysis:File*, 0)
        state.intelligence_index = cast(u8*, index)
    }
    let paths = state.host.watch_sources
    if paths {
        var at:i64 = 0
        while paths[at] != 0 {
            let end = IDE:App:find_byte(paths, at, 10)
            let file_path = LanguageKit:copy_bytes(&paths[at], end - at)
            if file_path {
                let application_file = application_root && IDE:path_is_inside(file_path, application_root)
                if application_file == standalone && !IDE:Analysis:equal(file_path, path) {
                    let disk = IDE:read_file(file_path)
                    if disk { IDE:Analysis:update_file(index, state.host, file_path, disk); free(disk) }
                }
                free(file_path)
            }
            at = end; if paths[at] == 10 { at += 1 }
        }
    }
    return IDE:Analysis:update_file(index, state.host, path, source)
}

let IDE:Analysis:selected = fn (file:IDE:Analysis:File*, position:u64) -> IDE:Analysis:Occurrence* {
    var selected = cast(IDE:Analysis:Occurrence*, 0)
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

let IDE:Analysis:location = fn (out:LanguageKit:Text*, file:IDE:Analysis:File*, item:IDE:Analysis:Occurrence*) -> void {
    out.append("L\t"); IDE:append_hex(out, file.path); out.append("\t")
    IDE:append_u64(out, item.start); out.append("\t"); IDE:append_u64(out, item.finish); out.append("\t")
    IDE:append_u64(out, item.line); out.append("\t"); IDE:append_u64(out, cast(u64, item.role)); out.append("\t")
    IDE:append_hex(out, item.label); out.append("\n")
}

let IDE:Analysis:insert_result = fn (head:IDE:Analysis:Result*, file:IDE:Analysis:File*, item:IDE:Analysis:Occurrence*,
                                    descending:i64) -> IDE:Analysis:Result* {
    var previous = cast(IDE:Analysis:Result*, 0)
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
    let result = alloc(IDE:Analysis:Result)
    if !result { return head }
    result.file = file; result.item = item; result.next = current
    if previous { previous.next = result; return head }
    return result
}

let IDE:Analysis:contains = fn (text:u8*, query:u8*) -> i64 {
    if !query || query[0] == 0 { return 1 }
    if !text { return 0 }
    var at:u64 = 0
    while text[at] != 0 {
        var i:u64 = 0
        while query[i] != 0 && text[at + i] != 0 && IDE:App:find_ascii_lower(text[at + i]) == IDE:App:find_ascii_lower(query[i]) { i += 1 }
        if query[i] == 0 { return 1 }
        at += 1
    }
    return 0
}

let IDE:Analysis:prefix = fn (text:u8*, prefix:u8*) -> i64 {
    if !text || !prefix { return 0 }
    var i:u64 = 0
    while prefix[i] != 0 { if text[i] != prefix[i] { return 0 }; i += 1 }
    return 1
}

let IDE:Analysis:completion = fn (out:LanguageKit:Text*, file:IDE:Analysis:File*, position:u64) -> void {
    let end = IDE:Analysis:byte_offset(file.source, position)
    var begin = end
    while begin > 0 && (IDE:Analysis:identifier(file.source[begin - 1]) || file.source[begin - 1] == 58) { begin -= 1 }
    let prefix = LanguageKit:copy_bytes(&file.source[begin], cast(i64, end - begin))
    if !prefix { return }
    defer free(prefix)
    let start = cast(u64, IDE:App:find_byte_to_char(file.source, begin))
    var symbol = file.symbols
    while symbol {
        if IDE:Analysis:prefix(symbol.name, prefix) {
            out.append("C\t"); IDE:append_u64(out, start); out.append("\t"); IDE:append_u64(out, position); out.append("\t")
            IDE:append_hex(out, symbol.name); out.append("\t"); IDE:append_hex(out, symbol.name); out.append("\t")
            IDE:append_hex(out, symbol.kind); out.append("\t"); IDE:append_hex(out, symbol.docs); out.append("\n")
        }
        symbol = symbol.next
    }
    var item = file.occurrences
    let container = IDE:Analysis:container(file, position)
    while item {
        var visible:i64 = item.local != 0 && item.role == 2 && item.start <= position && position < item.scope_finish &&
                          IDE:Analysis:equal(container, item.container) && IDE:Analysis:prefix(item.label, prefix)
        if visible != 0 {
            var other = file.occurrences
            while other {
                if other.local != 0 && other.role == 2 && other.start <= position && position < other.scope_finish &&
                   IDE:Analysis:equal(container, other.container) && IDE:Analysis:equal(item.label, other.label) &&
                   (other.depth > item.depth || (other.depth == item.depth && other.start > item.start)) { visible = 0 }
                other = other.next
            }
        }
        if visible != 0 {
            out.append("C\t"); IDE:append_u64(out, start); out.append("\t"); IDE:append_u64(out, position); out.append("\t")
            IDE:append_hex(out, item.label); out.append("\t"); IDE:append_hex(out, item.label); out.append("\t6c6f63616c\t\n")
        }
        item = item.next
    }
}

let IDE:Analysis:signature = fn (out:LanguageKit:Text*, file:IDE:Analysis:File*, position:u64) -> void {
    var token = file.tokens
    var open = cast(IDE:Analysis:Token*, 0)
    var nested:i64 = 0
    while token && token.start < position { open = token; token = token.next }
    while open {
        if IDE:Analysis:equal(open.text, ")") { nested += 1 }
        else if IDE:Analysis:equal(open.text, "(") {
            if nested == 0 {
                if open.previous {
                    let symbol = IDE:Analysis:symbol(file, open.previous.text)
                    if symbol && symbol.signature && symbol.signature[0] != 0 {
                        var at:i64 = 0
                        while symbol.signature[at] != 0 {
                            let end = IDE:App:find_byte(symbol.signature, at, 10)
                            let label = LanguageKit:copy_bytes(&symbol.signature[at], end - at)
                            if label { out.append("G\t"); IDE:append_hex(out, label); out.append("\t"); IDE:append_hex(out, symbol.docs); out.append("\n"); free(label) }
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

let IDE:Analysis:prototype_in = fn (file:IDE:Analysis:File*, name:u8*, target:u8*) -> i64 {
    var symbol = IDE:Analysis:symbol(file, name)
    var depth:u64 = 0
    while symbol && symbol.prototype && symbol.prototype[0] != 0 && depth < 128 {
        let prototype = IDE:Analysis:symbol(file, symbol.prototype)
        if prototype && IDE:Analysis:equal(prototype.key, target) { return 1 }
        symbol = IDE:Analysis:symbol(file, symbol.prototype); depth += 1
    }
    return 0
}

let IDE:Analysis:query = fn (state:IDE:App:State*, operation:u8*, path:u8*, source:u8*, position:u64, argument:u8*) -> u8* {
    let current = IDE:Analysis:index(state, path, source)
    if !current { return cast(u8*, 0) }
    let index = cast(IDE:Analysis:Index*, state.intelligence_index)
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    defer out.destroy()
    if current.diagnostic {
        // Partial traces still support completion and navigation. Rename needs
        // a completely successful analysis of every participating source.
        if IDE:Analysis:equal(operation, "rename") { out.append("E\t"); IDE:append_hex(out, current.diagnostic); out.append("\n"); return out.take() }
    }
    if IDE:Analysis:equal(operation, "completion") { IDE:Analysis:completion(out, current, position); return out.take() }
    if IDE:Analysis:equal(operation, "signature") { IDE:Analysis:signature(out, current, position); return out.take() }
    let selected = IDE:Analysis:selected(current, position)
    let document = IDE:Analysis:equal(operation, "document-symbols")
    let workspace = IDE:Analysis:equal(operation, "workspace-symbols")
    if !selected && !document && !workspace { out.append("E\t"); IDE:append_hex(out, "no semantic symbol at cursor"); out.append("\n"); return out.take() }
    var requested = cast(u8*, 0)
    if selected { requested = selected.target }
    if IDE:Analysis:equal(operation, "type-definition") {
        var relation = current.occurrences
        while relation {
            if relation.role == 4 && IDE:Analysis:equal(relation.container, selected.target) { requested = relation.target }
            relation = relation.next
        }
        if requested == selected.target {
            let symbol = IDE:Analysis:symbol(current, selected.target)
            if symbol {
                if symbol.prototype && symbol.prototype[0] != 0 { let prototype = IDE:Analysis:symbol(current, symbol.prototype); if prototype { requested = prototype.key } }
                else if symbol.type && symbol.type[0] != 0 { let type = IDE:Analysis:symbol(current, symbol.type); if type { requested = type.key } }
            }
        }
    }
    if IDE:Analysis:equal(operation, "rename") {
        var definitions:u64 = 0
        var file = index.files
        while file {
            if file.diagnostic { out.append("E\t"); IDE:append_hex(out, file.diagnostic); out.append("\n"); return out.take() }
            var item = file.occurrences
            while item {
                if item.role == 2 && IDE:Analysis:equal(item.target, requested) { definitions += 1 }
                item = item.next
            }
            file = file.next
        }
        if definitions != 1 { out.append("E\t"); IDE:append_hex(out, "rename requires one unambiguous source definition"); out.append("\n"); return out.take() }
    }
    var parent = cast(u8*, 0)
    if IDE:Analysis:equal(operation, "prototype-hierarchy") {
        let symbol = IDE:Analysis:symbol(current, requested)
        if symbol { let prototype = IDE:Analysis:symbol(current, symbol.prototype); if prototype { parent = prototype.key } }
    }
    var results = cast(IDE:Analysis:Result*, 0)
    var file = index.files
    while file {
        var item = file.occurrences
        while item {
            var include:i64 = 0
            if document { include = file == current && item.role == 2 && item.local == 0 }
            else if workspace { include = item.role == 2 && item.local == 0 && IDE:Analysis:contains(item.label, argument) }
            else if IDE:Analysis:equal(operation, "definition") || IDE:Analysis:equal(operation, "type-definition") {
                include = item.role == 2 && IDE:Analysis:equal(item.target, requested)
            } else if IDE:Analysis:equal(operation, "references") || IDE:Analysis:equal(operation, "rename") {
                include = IDE:Analysis:equal(item.target, requested)
                if include != 0 && item.local == 0 {
                    let resolved = IDE:Analysis:symbol(file, item.label)
                    if !resolved || !IDE:Analysis:equal(resolved.key, requested) { include = 0 }
                }
            } else if IDE:Analysis:equal(operation, "incoming-calls") {
                include = item.role == 3 && IDE:Analysis:equal(item.target, requested)
            } else if IDE:Analysis:equal(operation, "outgoing-calls") {
                include = item.role == 3 && IDE:Analysis:equal(item.container, requested)
            } else if IDE:Analysis:equal(operation, "implementations") || IDE:Analysis:equal(operation, "prototype-hierarchy") {
                include = item.role == 2 && item.local == 0 &&
                          (IDE:Analysis:prototype_in(file, item.target, requested) || IDE:Analysis:equal(item.target, parent))
            }
            if include != 0 { results = IDE:Analysis:insert_result(results, file, item, IDE:Analysis:equal(operation, "rename")) }
            item = item.next
        }
        file = file.next
    }
    while results {
        let next = results.next
        IDE:Analysis:location(out, results.file, results.item)
        free(cast(u8*, results)); results = next
    }
    return out.take()
}
