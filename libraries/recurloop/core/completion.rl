// Completion is a source-owned language service. The host transports a request
// and calls Completion:complete; libraries can replace that ordinary phrase.
// The default provider uses only the active lexicon and never enumerates files.
let Completion = []

let Completion:space = fn (byte:u8) -> i64 {
    return byte == 32 || (byte >= 9 && byte <= 13)
}

let Completion:separator = fn (byte:u8) -> i64 {
    return Completion:space(byte) || byte == 61 || byte == 40 || byte == 41 ||
           byte == 43 || byte == 45 || byte == 42 || byte == 47 || byte == 44 ||
           byte == 91 || byte == 93 || byte == 60 || byte == 62 || byte == 33 ||
           byte == 38 || byte == 124 || byte == 123 || byte == 125 || byte == 59
}

let Completion:length = fn (text:u8*) -> u64 {
    if !text { return 0 }
    var bytes:u64 = 0
    while text[bytes] { bytes += 1 }
    return bytes
}

let Completion:copy = fn (state:Context*, source:u8*, begin:u64, end:u64) -> u8* {
    if end < begin { return cast(u8*, 0) }
    let text = context:memory:allocate(state, end - begin + 1)
    if !text { return cast(u8*, 0) }
    context:memory:copy(state, text, &source[begin], end - begin)
    text[end - begin] = 0
    return text
}

let Completion:starts = fn (text:u8*, prefix:u8*) -> i64 {
    if !text || !prefix { return 0 }
    var index:u64 = 0
    while prefix[index] {
        if text[index] != prefix[index] { return 0 }
        index += 1
    }
    return 1
}

record Completion:LexiconInput {
    token:u8*
    qualified:u64
}

let Completion:phrase_candidate = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let input = cast(Completion:LexiconInput*, context:completion:data(state))
        if !input { return }
        let key = context:completion:candidate(state)
        var length = Completion:length(key)
        while length && Completion:space(key[length - 1]) { length -= 1 }
        if !length { return }
        var index:u64 = 0
        while index < length {
            if key[index] <= 32 || key[index] == 127 { return }
            index += 1
        }
        let candidate = context:memory:allocate(state, input.qualified + length + 1)
        if !candidate { return }
        defer context:memory:release(state, candidate)
        context:memory:copy(state, candidate, input.token, input.qualified)
        context:memory:copy(state, &candidate[input.qualified], key, length)
        candidate[input.qualified + length] = 0
        context:completion:add(state, candidate)
    }
}

// Enumerate qualified phrases in the current dictionary, enclosing dictionaries
// and root. All addresses remain phrase handles, including after image import.
let Completion:phrases = fn (state:Context*, start:u64) -> void {
    let source = context:completion:source(state)
    let cursor = context:completion:cursor(state)
    if start > cursor { return }
    let token = Completion:copy(state, source, start, cursor)
    if !token { return }
    defer context:memory:release(state, token)
    let bytes = cursor - start
    var qualified:u64 = 0
    var index:u64 = 0
    while index < bytes {
        if token[index] == 58 { qualified = index + 1 }
        index += 1
    }
    let input = cast(Completion:LexiconInput*, context:memory:allocate(state, sizeof(Completion:LexiconInput)))
    if !input { return }
    defer context:memory:release(state, cast(u8*, input))
    input.token = token
    input.qualified = qualified
    let previous = context:completion:data(state)
    context:completion:data(state, cast(u64, input))
    defer context:completion:data(state, previous)
    let service = context:phrase:find(state, "Completion")
    let consumer = context:phrase:find:exact(state, service, "phrase_candidate")
    let count = context:completion:dictionary:count(state)
    var scope:u64 = 0
    while scope < count {
        var owner = context:completion:dictionary(state, scope)
        scope += 1
        var position:u64 = 0
        while owner && position < qualified {
            var end = position
            while end < qualified && token[end] != 58 { end += 1 }
            let component = Completion:copy(state, token, position, end)
            if !component { return }
            owner = context:phrase:find:exact(state, owner, component)
            context:memory:release(state, component)
            position = end + 1
        }
        if owner && (context:phrase:flags(state, owner) & 1) {
            context:completion:children(state, owner, &token[qualified], consumer)
        }
    }
}

let Completion:lexicon = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = context:completion:source(state)
        let cursor = context:completion:cursor(state)
        var start:u64 = 0
        var index:u64 = 0
        var quote:u8 = 0
        var escaped = 0
        var comment = 0
        var string_token = 0
        while index < cursor {
            let byte = source[index]
            if comment == 1 {
                if byte == 10 { comment = 0; start = index + 1 }
            } else if comment == 2 {
                if byte == 42 && index + 1 < cursor && source[index + 1] == 47 {
                    comment = 0
                    index += 1
                    start = index + 1
                }
            } else if escaped {
                escaped = 0
            } else if byte == 92 {
                escaped = 1
            } else if quote {
                if byte == quote { quote = 0; start = index + 1 }
            } else if byte == 34 || byte == 39 {
                quote = byte
                string_token = 1
            } else if byte == 47 && index + 1 < cursor && source[index + 1] == 47 {
                comment = 1
                index += 1
            } else if byte == 47 && index + 1 < cursor && source[index + 1] == 42 {
                comment = 2
                index += 1
            } else if Completion:separator(byte) {
                start = index + 1
                string_token = 0
            }
            index += 1
        }
        if quote || comment || escaped || string_token { return }
        context:completion:start(state, start)
        Completion:phrases(state, start)
    }
}

// This slot is deliberately replaceable. Completion:lexicon remains available
// to providers that extend the service or want to restore the default.
let Completion:complete = <Completion:lexicon>
