// Source-defined scanner, translation helpers, and allocation utilities.
// =============================================================================
// RecurLoop language bootstrap layer 20: base language
//
// Public compatibility envelope while today's core still owns root spellings:
//
//   recur {
//       record Point { x:i64 y:i64 }
//       fn add(a:i64, b:i64) -> i64 { return a + b }
//       const answer = add(20, 22)
//       if answer == 42 { printf("ok\\n") }
//   }
//
// Everything INSIDE `recur` is parsed by this library. The envelope exists only
// because the current core already owns roots such as `fn`, `record`, `var`,
// `if`, etc. After those startup phrases are removed, the same parser can be
// installed as the root fallback and the envelope disappears.
//
// Current lowering boundary:
//   - record layout: direct context:type:* / context:phrase:* (no host record)
//   - fn declaration: parsed here, then context:function:compile
//   - if/while/bindings/return: parsed and normalized here, then body compiler
//   - defer: implemented HERE as lexical LIFO expansion; host defer is NOT used
//   - expressions: intentionally opaque and delegated to function compiler
// =============================================================================

shape RecurLoopLanguage:Translator {
    out:RecurLoopLanguage:Buffer
    defers:u8**
    defer_count:i64
    defer_capacity:i64
}


proc RecurLoopLanguage:allocate_type (state:Context*, name:u8*) -> u8* {
    let type = context:type:find(state, name)
    if !type { return cast(u8*, 0) }
    let bytes = context:type:size(state, type)
    if bytes <= 0 { return cast(u8*, 0) }
    return cast(u8*, malloc(bytes))
}

proc RecurLoopLanguage:Translator:init (self:RecurLoopLanguage:Translator*) -> i64 {
    if !RecurLoopLanguage:Buffer:init(&self.out, 256) { return 0 }
    self.defer_capacity = 16
    self.defer_count = 0
    self.defers = cast(u8**, malloc(self.defer_capacity * 8))
    if !self.defers { RecurLoopLanguage:Buffer:destroy(&self.out); return 0 }
    return 1
}

proc RecurLoopLanguage:Translator:destroy (self:RecurLoopLanguage:Translator*) -> void {
    var i = 0
    while i < self.defer_count {
        if self.defers[i] { free(self.defers[i]) }
        i += 1
    }
    if self.defers { free(cast(u8*, self.defers)) }
    self.defers = cast(u8**, 0)
    self.defer_count = 0
    self.defer_capacity = 0
    RecurLoopLanguage:Buffer:destroy(&self.out)
}

proc RecurLoopLanguage:Translator:grow_defers (self:RecurLoopLanguage:Translator*) -> i64 {
    if self.defer_count < self.defer_capacity { return 1 }
    let next_capacity = self.defer_capacity * 2
    let replacement = cast(u8**, malloc(next_capacity * 8))
    if !replacement { return 0 }
    var i = 0
    while i < self.defer_count { replacement[i] = self.defers[i]; i += 1 }
    free(cast(u8*, self.defers))
    self.defers = replacement
    self.defer_capacity = next_capacity
    return 1
}

proc RecurLoopLanguage:Translator:push_defer (self:RecurLoopLanguage:Translator*, text:u8*, start:i64, finish:i64) -> i64 {
    start = RecurLoopLanguage:trim_start(text, start, finish)
    finish = RecurLoopLanguage:trim_finish(text, start, finish)
    if finish <= start { return 0 }
    if !RecurLoopLanguage:Translator:grow_defers(self) { return 0 }
    let copy = RecurLoopLanguage:copy_slice(text, start, finish)
    if !copy { return 0 }
    self.defers[self.defer_count] = copy
    self.defer_count += 1
    return 1
}

proc RecurLoopLanguage:Translator:emit_defers_to (self:RecurLoopLanguage:Translator*, mark:i64, pop:i64) -> i64 {
    var i = self.defer_count - 1
    while i >= mark {
        if !RecurLoopLanguage:Buffer:append(&self.out, self.defers[i]) || !RecurLoopLanguage:Buffer:append(&self.out, "\n") { return 0 }
        i -= 1
    }
    if pop {
        i = self.defer_count - 1
        while i >= mark {
            free(self.defers[i])
            self.defers[i] = cast(u8*, 0)
            i -= 1
        }
        self.defer_count = mark
    }
    return 1
}

// End of a simple statement. Newlines terminate only when (), [] are closed.
proc RecurLoopLanguage:statement_end (text:u8*, start:i64, limit:i64) -> i64 {
    var paren = 0
    var bracket = 0
    var i = start
    while i < limit {
        if text[i] == 34 || text[i] == 39 { i = RecurLoopLanguage:skip_string(text, i, limit); continue }
        if i + 1 < limit && text[i] == 47 && text[i + 1] == 47 {
            if paren == 0 && bracket == 0 { return i }
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
        else if paren == 0 && bracket == 0 && (ch == 59 || ch == 10 || ch == 13) { return i }
        i += 1
    }
    return limit
}

proc RecurLoopLanguage:consume_terminator (text:u8*, position:i64, limit:i64) -> i64 {
    var i = position
    if i < limit && text[i] == 59 { i += 1 }
    if i < limit && text[i] == 13 { i += 1; if i < limit && text[i] == 10 { i += 1 }; return i }
    if i < limit && text[i] == 10 { return i + 1 }
    return i
}

proc RecurLoopLanguage:Translator:emit_simple (self:RecurLoopLanguage:Translator*, text:u8*, start:i64, finish:i64) -> i64 {
    start = RecurLoopLanguage:trim_start(text, start, finish)
    finish = RecurLoopLanguage:trim_finish(text, start, finish)
    if finish <= start { return 1 }
    if !RecurLoopLanguage:Buffer:append_slice(&self.out, text, start, finish) { return 0 }
    return RecurLoopLanguage:Buffer:append(&self.out, "\n")
}

proc RecurLoopLanguage:Translator:translate_block (self:RecurLoopLanguage:Translator*, text:u8*, start:i64, limit:i64) -> i64 {
    let mark = self.defer_count
    var i = start
    while 1 {
        i = RecurLoopLanguage:skip_trivia(text, i, limit)
        if i >= limit { break }

        if RecurLoopLanguage:word_at(text, i, limit, "defer", 5) {
            let statement_start = RecurLoopLanguage:skip_trivia(text, i + 5, limit)
            let statement_finish = RecurLoopLanguage:statement_end(text, statement_start, limit)
            if statement_finish <= statement_start || !RecurLoopLanguage:Translator:push_defer(self, text, statement_start, statement_finish) { return 0 }
            i = RecurLoopLanguage:consume_terminator(text, statement_finish, limit)
            continue
        }

        if RecurLoopLanguage:word_at(text, i, limit, "return", 6) {
            let statement_finish = RecurLoopLanguage:statement_end(text, i, limit)
            if !RecurLoopLanguage:Translator:emit_defers_to(self, 0, 0) { return 0 }
            if !RecurLoopLanguage:Translator:emit_simple(self, text, i, statement_finish) { return 0 }
            i = RecurLoopLanguage:consume_terminator(text, statement_finish, limit)
            continue
        }

        if RecurLoopLanguage:word_at(text, i, limit, "if", 2) {
            var cursor = RecurLoopLanguage:skip_trivia(text, i + 2, limit)
            var open = RecurLoopLanguage:find_top(text, cursor, limit, 123)
            if open < 0 { return 0 }
            var close = RecurLoopLanguage:matching(text, open, limit, 123, 125)
            if close < 0 { return 0 }
            var condition_start = RecurLoopLanguage:trim_start(text, cursor, open)
            var condition_finish = RecurLoopLanguage:trim_finish(text, condition_start, open)
            if condition_finish <= condition_start { return 0 }
            if !RecurLoopLanguage:Buffer:append(&self.out, "if ") ||
               !RecurLoopLanguage:Buffer:append_slice(&self.out, text, condition_start, condition_finish) ||
               !RecurLoopLanguage:Buffer:append(&self.out, " {\n") { return 0 }
            if !RecurLoopLanguage:Translator:translate_block(self, text, open + 1, close) { return 0 }
            if !RecurLoopLanguage:Buffer:append(&self.out, "}\n") { return 0 }
            cursor = RecurLoopLanguage:skip_trivia(text, close + 1, limit)

            while RecurLoopLanguage:word_at(text, cursor, limit, "else", 4) {
                cursor = RecurLoopLanguage:skip_trivia(text, cursor + 4, limit)
                if RecurLoopLanguage:word_at(text, cursor, limit, "if", 2) {
                    cursor = RecurLoopLanguage:skip_trivia(text, cursor + 2, limit)
                    open = RecurLoopLanguage:find_top(text, cursor, limit, 123)
                    if open < 0 { return 0 }
                    close = RecurLoopLanguage:matching(text, open, limit, 123, 125)
                    if close < 0 { return 0 }
                    condition_start = RecurLoopLanguage:trim_start(text, cursor, open)
                    condition_finish = RecurLoopLanguage:trim_finish(text, condition_start, open)
                    if condition_finish <= condition_start { return 0 }
                    if !RecurLoopLanguage:Buffer:append(&self.out, "else if ") ||
                       !RecurLoopLanguage:Buffer:append_slice(&self.out, text, condition_start, condition_finish) ||
                       !RecurLoopLanguage:Buffer:append(&self.out, " {\n") { return 0 }
                    if !RecurLoopLanguage:Translator:translate_block(self, text, open + 1, close) { return 0 }
                    if !RecurLoopLanguage:Buffer:append(&self.out, "}\n") { return 0 }
                    cursor = RecurLoopLanguage:skip_trivia(text, close + 1, limit)
                    continue
                }
                if cursor >= limit || text[cursor] != 123 { return 0 }
                close = RecurLoopLanguage:matching(text, cursor, limit, 123, 125)
                if close < 0 { return 0 }
                if !RecurLoopLanguage:Buffer:append(&self.out, "else {\n") { return 0 }
                if !RecurLoopLanguage:Translator:translate_block(self, text, cursor + 1, close) { return 0 }
                if !RecurLoopLanguage:Buffer:append(&self.out, "}\n") { return 0 }
                cursor = close + 1
                break
            }
            i = cursor
            continue
        }

        if RecurLoopLanguage:word_at(text, i, limit, "while", 5) {
            let cursor = RecurLoopLanguage:skip_trivia(text, i + 5, limit)
            let open = RecurLoopLanguage:find_top(text, cursor, limit, 123)
            if open < 0 { return 0 }
            let close = RecurLoopLanguage:matching(text, open, limit, 123, 125)
            if close < 0 { return 0 }
            let condition_start = RecurLoopLanguage:trim_start(text, cursor, open)
            let condition_finish = RecurLoopLanguage:trim_finish(text, condition_start, open)
            if condition_finish <= condition_start { return 0 }
            if !RecurLoopLanguage:Buffer:append(&self.out, "while ") ||
               !RecurLoopLanguage:Buffer:append_slice(&self.out, text, condition_start, condition_finish) ||
               !RecurLoopLanguage:Buffer:append(&self.out, " {\n") { return 0 }
            if !RecurLoopLanguage:Translator:translate_block(self, text, open + 1, close) { return 0 }
            if !RecurLoopLanguage:Buffer:append(&self.out, "}\n") { return 0 }
            i = close + 1
            continue
        }

        // let / const / var / assignments / calls / expressions are accepted as
        // simple statements. This parser owns their statement boundary; the
        // expression itself stays opaque until the future IR builder replaces
        // context:function:compile.
        let statement_finish = RecurLoopLanguage:statement_end(text, i, limit)
        if statement_finish <= i { return 0 }
        if !RecurLoopLanguage:Translator:emit_simple(self, text, i, statement_finish) { return 0 }
        i = RecurLoopLanguage:consume_terminator(text, statement_finish, limit)
    }

    // Lexical-scope defer: LIFO on normal fallthrough. Returns above inject all
    // currently active defers before the return itself.
    return RecurLoopLanguage:Translator:emit_defers_to(self, mark, 1)
}

