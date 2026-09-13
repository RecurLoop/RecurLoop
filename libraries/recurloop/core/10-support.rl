// =============================================================================
// RecurLoop language bootstrap layer 10: allocation-free-ish scanner + buffers
//
// This file is intentionally written against the public seed surface:
//   proc + shape
// No top-level let/var/fn/record declarations are used here.
// Function bodies still pass through context:function:compile; that is the
// explicit temporary lowering bridge documented by the workflow.
// =============================================================================

shape RecurLoopLanguage:Buffer {
    data:u8*
    length:i64
    capacity:i64
}

proc RecurLoopLanguage:Buffer:init (self:RecurLoopLanguage:Buffer*, initial:i64) -> i64 {
    if initial < 64 { initial = 64 }
    self.data = cast(u8*, malloc(initial))
    if !self.data { self.length = 0; self.capacity = 0; return 0 }
    self.length = 0
    self.capacity = initial
    self.data[0] = 0
    return 1
}

proc RecurLoopLanguage:Buffer:destroy (self:RecurLoopLanguage:Buffer*) -> void {
    if self.data { free(self.data) }
    self.data = cast(u8*, 0)
    self.length = 0
    self.capacity = 0
}

proc RecurLoopLanguage:Buffer:reserve (self:RecurLoopLanguage:Buffer*, extra:i64) -> i64 {
    let needed = self.length + extra + 1
    if needed <= self.capacity { return 1 }
    var next = self.capacity
    if next < 64 { next = 64 }
    while next < needed { next *= 2 }
    let replacement = cast(u8*, malloc(next))
    if !replacement { return 0 }
    var i = 0
    while i < self.length { replacement[i] = self.data[i]; i += 1 }
    replacement[self.length] = 0
    if self.data { free(self.data) }
    self.data = replacement
    self.capacity = next
    return 1
}

proc RecurLoopLanguage:Buffer:append_slice (self:RecurLoopLanguage:Buffer*, text:u8*, start:i64, finish:i64) -> i64 {
    if !text || finish < start { return 0 }
    let count = finish - start
    if !self.reserve(count) { return 0 }
    var i = 0
    while i < count { self.data[self.length + i] = text[start + i]; i += 1 }
    self.length += count
    self.data[self.length] = 0
    return 1
}

proc RecurLoopLanguage:Buffer:append (self:RecurLoopLanguage:Buffer*, text:u8*) -> i64 {
    if !text { return 0 }
    var count = 0
    while text[count] != 0 { count += 1 }
    return self.append_slice(text, 0, count)
}

proc RecurLoopLanguage:Buffer:append_byte (self:RecurLoopLanguage:Buffer*, ch:i64) -> i64 {
    if !self.reserve(1) { return 0 }
    self.data[self.length] = ch
    self.length += 1
    self.data[self.length] = 0
    return 1
}

proc RecurLoopLanguage:is_space (ch:i64) -> i64 {
    return ch == 32 || ch == 9 || ch == 10 || ch == 13
}

proc RecurLoopLanguage:is_name_start (ch:i64) -> i64 {
    return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95
}

proc RecurLoopLanguage:is_name (ch:i64) -> i64 {
    return RecurLoopLanguage:is_name_start(ch) || (ch >= 48 && ch <= 57) || ch == 58 || ch == 45
}

proc RecurLoopLanguage:text_length (text:u8*) -> i64 {
    if !text { return 0 }
    var i = 0
    while text[i] != 0 { i += 1 }
    return i
}

proc RecurLoopLanguage:skip_trivia (text:u8*, position:i64, limit:i64) -> i64 {
    var i = position
    while i < limit {
        while i < limit && RecurLoopLanguage:is_space(text[i]) { i += 1 }
        if i + 1 < limit && text[i] == 47 && text[i + 1] == 47 {
            i += 2
            while i < limit && text[i] != 10 && text[i] != 13 { i += 1 }
            continue
        }
        if i + 1 < limit && text[i] == 47 && text[i + 1] == 42 {
            i += 2
            while i + 1 < limit && !(text[i] == 42 && text[i + 1] == 47) { i += 1 }
            if i + 1 < limit { i += 2 }
            continue
        }
        break
    }
    return i
}

proc RecurLoopLanguage:word_at (text:u8*, position:i64, limit:i64, word:u8*, bytes:i64) -> i64 {
    if position < 0 || position + bytes > limit { return 0 }
    if position > 0 && RecurLoopLanguage:is_name(text[position - 1]) { return 0 }
    var i = 0
    while i < bytes {
        if text[position + i] != word[i] { return 0 }
        i += 1
    }
    if position + bytes < limit && RecurLoopLanguage:is_name(text[position + bytes]) { return 0 }
    return 1
}

proc RecurLoopLanguage:trim_start (text:u8*, start:i64, finish:i64) -> i64 {
    var i = start
    while i < finish && RecurLoopLanguage:is_space(text[i]) { i += 1 }
    return i
}

proc RecurLoopLanguage:trim_finish (text:u8*, start:i64, finish:i64) -> i64 {
    var i = finish
    while i > start && RecurLoopLanguage:is_space(text[i - 1]) { i -= 1 }
    return i
}

proc RecurLoopLanguage:copy_slice (text:u8*, start:i64, finish:i64) -> u8* {
    if !text || finish < start { return cast(u8*, 0) }
    let count = finish - start
    let result = cast(u8*, malloc(count + 1))
    if !result { return cast(u8*, 0) }
    var i = 0
    while i < count { result[i] = text[start + i]; i += 1 }
    result[count] = 0
    return result
}

// Scan a quoted string. Returns the first byte after the closing quote.
proc RecurLoopLanguage:skip_string (text:u8*, position:i64, limit:i64) -> i64 {
    if position >= limit { return position }
    let quote = text[position]
    var i = position + 1
    var escaped = 0
    while i < limit {
        let ch = text[i]
        if escaped { escaped = 0; i += 1; continue }
        if ch == 92 { escaped = 1; i += 1; continue }
        if ch == quote { return i + 1 }
        i += 1
    }
    return limit
}

// Find matching close byte while ignoring strings and comments.
proc RecurLoopLanguage:matching (text:u8*, open:i64, limit:i64, open_ch:i64, close_ch:i64) -> i64 {
    var depth = 1
    var i = open + 1
    while i < limit {
        if text[i] == 34 || text[i] == 39 { i = RecurLoopLanguage:skip_string(text, i, limit); continue }
        if i + 1 < limit && text[i] == 47 && text[i + 1] == 47 {
            i += 2
            while i < limit && text[i] != 10 && text[i] != 13 { i += 1 }
            continue
        }
        if i + 1 < limit && text[i] == 47 && text[i + 1] == 42 {
            i += 2
            while i + 1 < limit && !(text[i] == 42 && text[i + 1] == 47) { i += 1 }
            if i + 1 < limit { i += 2 }
            continue
        }
        if text[i] == open_ch { depth += 1 }
        else if text[i] == close_ch {
            depth -= 1
            if depth == 0 { return i }
        }
        i += 1
    }
    return -1
}
// Find a top-level delimiter, respecting (), [], strings and comments.
proc RecurLoopLanguage:find_top (text:u8*, start:i64, limit:i64, needle:i64) -> i64 {
    var paren = 0
    var bracket = 0
    var i = start
    while i < limit {
        if text[i] == 34 || text[i] == 39 { i = RecurLoopLanguage:skip_string(text, i, limit); continue }
        if i + 1 < limit && text[i] == 47 && text[i + 1] == 47 {
            i += 2
            while i < limit && text[i] != 10 && text[i] != 13 { i += 1 }
            continue
        }
        if i + 1 < limit && text[i] == 47 && text[i + 1] == 42 {
            i += 2
            while i + 1 < limit && !(text[i] == 42 && text[i + 1] == 47) { i += 1 }
            if i + 1 < limit { i += 2 }
            continue
        }
        let ch = text[i]
        if ch == 40 { paren += 1 }
        else if ch == 41 && paren > 0 { paren -= 1 }
        else if ch == 91 { bracket += 1 }
        else if ch == 93 && bracket > 0 { bracket -= 1 }
        else if ch == needle && paren == 0 && bracket == 0 { return i }
        i += 1
    }
    return -1
}
