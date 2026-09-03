// =============================================================================
// RecurLoop Erlang compatibility experiment
//
// A small actor-oriented Erlang runtime implemented entirely in RecurLoop
// source. The C++ host contains no Erlang parser, process scheduler, mailbox,
// selective-receive implementation, tuple runtime, or Erlang pattern matcher.
//
// Supported subset:
//   - -module(...) and -export([...]) forms (accepted and ignored)
//   - integer, atom, string, tuple and list values
//   - variables and strict pattern matching with '='
//   - function clauses separated with ';'
//   - arithmetic +, -, *
//   - user function calls
//   - fun name/arity references
//   - self(), spawn(Fun), message send with '!'
//   - receive ... end with selective mailbox matching
//   - io:format/1 and io:format/2 (~p, ~n, ~~)
//   - cooperative actor scheduling sufficient for deterministic examples
//
// This is intentionally a compatibility experiment, not a complete Erlang VM.
// =============================================================================

link shared "c"

extern malloc(size:u64) -> u8* abi sysv-amd64
extern realloc(pointer:u8*, size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern memcpy(destination:u8*, source:u8*, bytes:u64) -> u8* abi sysv-amd64
extern strlen(text:u8*) -> u64 abi sysv-amd64
extern strcmp(left:u8*, right:u8*) -> i32 abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

let Erlang = phrase { dictionary = true permanent = true }
let Erlang:Internal = phrase { dictionary = true serializable = false }
let Erlang:Symbols = phrase { dictionary = true permanent = true }
let Erlang:Functions = phrase { dictionary = true permanent = true }
let Erlang:Variables = phrase { dictionary = true permanent = true }
let Erlang:Atoms = phrase { dictionary = true permanent = true }
let Erlang:Modules = phrase { dictionary = true permanent = true }
let Erlang:Processes = phrase { dictionary = true permanent = true }
let Erlang:Builtins = phrase { dictionary = true permanent = true }
let Erlang:Grammar = phrase { dictionary = true permanent = true }
let Erlang:Env = phrase { dictionary = true permanent = true }

let Erlang:copy_bytes = fn (source:u8*, bytes:i64) -> u8* {
    if bytes < 0 { return cast(u8*, 0) }
    let out = malloc(bytes + 1)
    if !out { return cast(u8*, 0) }
    if bytes > 0 { memcpy(out, source, bytes) }
    out[bytes] = 0
    return out
}

let Erlang:copy_text = fn (source:u8*) -> u8* {
    if !source { return cast(u8*, 0) }
    return Erlang:copy_bytes(source, cast(i64, strlen(source)))
}

let Erlang:is_space = fn (ch:u8) -> i64 { return ch == 32 || ch == 9 || ch == 10 || ch == 13 }
let Erlang:is_lower = fn (ch:u8) -> i64 { return ch >= 97 && ch <= 122 }
let Erlang:is_upper = fn (ch:u8) -> i64 { return ch >= 65 && ch <= 90 }
let Erlang:is_alpha = fn (ch:u8) -> i64 { return Erlang:is_lower(ch) || Erlang:is_upper(ch) }
let Erlang:is_digit = fn (ch:u8) -> i64 { return ch >= 48 && ch <= 57 }
let Erlang:is_ident_continue = fn (ch:u8) -> i64 {
    return Erlang:is_alpha(ch) || Erlang:is_digit(ch) || ch == 95 || ch == 64
}

let Erlang:text_number = fn (text:u8*) -> i64 {
    if !text { return 0 }
    var sign = 1
    var i = 0
    if text[0] == 45 { sign = -1; i = 1 }
    var value = 0
    while Erlang:is_digit(text[i]) { value = value * 10 + text[i] - 48; i += 1 }
    return value * sign
}

let Erlang:state_get = fn (state:Context*, name:u8*) -> i64 {
    if !context:value:contains(state, name) { return 0 }
    let text = context:value:format(state, name)
    if !text { return 0 }
    defer free(text)
    return Erlang:text_number(text)
}

let Erlang:state_set = fn (state:Context*, name:u8*, value:i64) -> i64 {
    if context:value:contains(state, name) { return context:value:assign:integer(state, name, value) }
    return context:value:define:integer(state, name, value)
}

let Erlang:category_owner = fn (state:Context*, category:u8*) -> i64 {
    let root = context:phrase:find(state, "Erlang")
    if !root { return 0 }
    return context:phrase:find:exact(state, root, category)
}

let Erlang:intern_symbol = fn (state:Context*, name:u8*) -> i64 {
    let owner = Erlang:category_owner(state, "Symbols")
    if !owner || !name { return 0 }
    let existing = context:phrase:find:exact(state, owner, name)
    if existing { return existing }
    let created = context:phrase:define:data(state, owner, name)
    return created
}

let Erlang:categorize_symbol = fn (state:Context*, category:u8*, name:u8*) -> i64 {
    let symbol = Erlang:intern_symbol(state, name)
    if !symbol { return 0 }
    let owner = Erlang:category_owner(state, category)
    if owner && !context:phrase:find:exact(state, owner, name) {
        let alias = context:phrase:define:from(state, owner, name, symbol)
    }
    return symbol
}

let Erlang:symbol_in = fn (state:Context*, category:u8*, name:u8*) -> i64 {
    let owner = Erlang:category_owner(state, category)
    if !owner { return 0 }
    return context:phrase:find:exact(state, owner, name)
}

// =============================================================================
// Syntax and runtime records.
// =============================================================================

record Erlang:Pattern {
    kind:i64
    number:i64
    name:u8*
    symbol:i64
    arity:i64
    items:u8*
}

record Erlang:ReceiveClause {
    pattern:Erlang:Pattern*
    body:u8*
    next:Erlang:ReceiveClause*
}

record Erlang:Expr {
    kind:i64
    number:i64
    name:u8*
    symbol:i64
    arity:i64
    items:u8*
    left:Erlang:Expr*
    right:Erlang:Expr*
    pattern:Erlang:Pattern*
}

record Erlang:Value {
    kind:i64
    number:i64
    name:u8*
    symbol:i64
    arity:i64
    items:u8*
}

record Erlang:EnvEntry {
    name:u8*
    symbol:i64
    value:Erlang:Value*
    next:Erlang:EnvEntry*
}

record Erlang:Frame {
    env:Erlang:EnvEntry*
}

record Erlang:Clause {
    name:u8*
    symbol:i64
    arity:i64
    patterns:u8*
    body:Erlang:Expr*
    next:Erlang:Clause*
}

record Erlang:Message {
    value:Erlang:Value*
    next:Erlang:Message*
}

record Erlang:Process {
    pid:i64
    status:i64
    function:u8*
    function_symbol:i64
    mailbox_head:Erlang:Message*
    mailbox_tail:Erlang:Message*
    next:Erlang:Process*
}

record Erlang:Database {
    clauses:Erlang:Clause*
    clauses_tail:Erlang:Clause*
    processes:Erlang:Process*
    next_pid:i64
    current_pid:i64
    main_ran:i64
}

// Expr kinds: 1 integer, 2 atom, 3 variable, 4 text, 5 tuple, 6 list,
// 7 call, 8 sequence, 9 match, 10 send, 11 receive, 12 binary, 13 funref.
let Erlang:Expr:new = fn (kind:i64) -> Erlang:Expr* {
    let self = cast(Erlang:Expr*, malloc(72))
    if !self { return cast(Erlang:Expr*, 0) }
    self.kind = kind; self.number = 0; self.name = cast(u8*, 0); self.symbol = 0; self.arity = 0
    self.items = cast(u8*, 0); self.left = cast(Erlang:Expr*, 0); self.right = cast(Erlang:Expr*, 0)
    self.pattern = cast(Erlang:Pattern*, 0)
    return self
}

let Erlang:Expr:integer = fn (value:i64) -> Erlang:Expr* { let e = Erlang:Expr:new(1); if e { e.number = value }; return e }
let Erlang:Expr:named = fn (state:Context*, kind:i64, name:u8*) -> Erlang:Expr* {
    let e = Erlang:Expr:new(kind)
    if e {
        e.name = name
        e.symbol = Erlang:intern_symbol(state, name)
        if kind == 2 { Erlang:categorize_symbol(state, "Atoms", name) }
        else if kind == 3 { Erlang:categorize_symbol(state, "Variables", name) }
        else if kind == 7 || kind == 13 { Erlang:categorize_symbol(state, "Functions", name) }
    }
    return e
}
let Erlang:Expr:pair = fn (kind:i64, left:Erlang:Expr*, right:Erlang:Expr*) -> Erlang:Expr* {
    let e = Erlang:Expr:new(kind); if e { e.left = left; e.right = right }; return e
}
let Erlang:Expr:make_binary = fn (state:Context*, name:u8*, left:Erlang:Expr*, right:Erlang:Expr*) -> Erlang:Expr* {
    let e = Erlang:Expr:pair(12, left, right)
    if e { e.name = Erlang:copy_text(name); e.symbol = Erlang:categorize_symbol(state, "Builtins", name) }
    return e
}

// Pattern kinds: 1 variable, 2 wildcard, 3 integer, 4 atom, 5 tuple, 6 list.
let Erlang:Pattern:new = fn (kind:i64) -> Erlang:Pattern* {
    let self = cast(Erlang:Pattern*, malloc(48))
    if !self { return cast(Erlang:Pattern*, 0) }
    self.kind = kind; self.number = 0; self.name = cast(u8*, 0); self.symbol = 0; self.arity = 0; self.items = cast(u8*, 0)
    return self
}

// Value kinds: 1 integer, 2 atom, 3 text, 4 tuple, 5 list, 6 pid, 7 funref.
let Erlang:Value:new = fn (kind:i64) -> Erlang:Value* {
    let self = cast(Erlang:Value*, malloc(48))
    if !self { return cast(Erlang:Value*, 0) }
    self.kind = kind; self.number = 0; self.name = cast(u8*, 0); self.symbol = 0; self.arity = 0; self.items = cast(u8*, 0)
    return self
}
let Erlang:Value:integer = fn (value:i64) -> Erlang:Value* { let v = Erlang:Value:new(1); if v { v.number = value }; return v }
let Erlang:Value:atom = fn (state:Context*, name:u8*) -> Erlang:Value* {
    let v = Erlang:Value:new(2)
    if v { v.name = Erlang:copy_text(name); v.symbol = Erlang:categorize_symbol(state, "Atoms", name) }
    return v
}
let Erlang:Value:text = fn (name:u8*) -> Erlang:Value* { let v = Erlang:Value:new(3); if v { v.name = Erlang:copy_text(name) }; return v }
let Erlang:Value:pid = fn (pid:i64) -> Erlang:Value* { let v = Erlang:Value:new(6); if v { v.number = pid }; return v }
let Erlang:Value:funref = fn (state:Context*, name:u8*, symbol:i64, arity:i64) -> Erlang:Value* {
    let v = Erlang:Value:new(7)
    if v { v.name = Erlang:copy_text(name); v.symbol = symbol; v.number = arity }
    return v
}

let Erlang:Env:find = fn (head:Erlang:EnvEntry*, symbol:i64) -> Erlang:Value* {
    var item = head
    while item { if item.symbol == symbol { return item.value }; item = item.next }
    return cast(Erlang:Value*, 0)
}
let Erlang:Env:bind = fn (head:Erlang:EnvEntry*, name:u8*, symbol:i64, value:Erlang:Value*) -> Erlang:EnvEntry* {
    let item = cast(Erlang:EnvEntry*, malloc(32))
    if !item { return head }
    item.name = Erlang:copy_text(name); item.symbol = symbol; item.value = value; item.next = head
    return item
}

let Erlang:Database:new = fn () -> Erlang:Database* {
    let self = cast(Erlang:Database*, malloc(48))
    if !self { return cast(Erlang:Database*, 0) }
    self.clauses = cast(Erlang:Clause*, 0); self.clauses_tail = cast(Erlang:Clause*, 0)
    self.processes = cast(Erlang:Process*, malloc(56))
    if !self.processes { return cast(Erlang:Database*, 0) }
    self.processes.pid = 1; self.processes.status = 1; self.processes.function = cast(u8*, 0); self.processes.function_symbol = 0
    self.processes.mailbox_head = cast(Erlang:Message*, 0); self.processes.mailbox_tail = cast(Erlang:Message*, 0)
    self.processes.next = cast(Erlang:Process*, 0)
    self.next_pid = 2; self.current_pid = 1; self.main_ran = 0
    return self
}

let Erlang:database = fn (state:Context*) -> Erlang:Database* {
    let existing = cast(Erlang:Database*, Erlang:state_get(state, "__erlang_database"))
    if existing { return existing }
    let created = Erlang:Database:new()
    if !created { context:diagnostic:error(state, "Erlang: could not allocate language database"); return cast(Erlang:Database*, 0) }
    if !Erlang:state_set(state, "__erlang_database", cast(i64, created)) { return cast(Erlang:Database*, 0) }
    Erlang:categorize_symbol(state, "Builtins", "self")
    Erlang:categorize_symbol(state, "Builtins", "spawn")
    Erlang:categorize_symbol(state, "Builtins", "io:format")
    Erlang:categorize_symbol(state, "Builtins", "__add")
    Erlang:categorize_symbol(state, "Builtins", "__sub")
    Erlang:categorize_symbol(state, "Builtins", "__mul")
    return created
}

let Erlang:Database:add_clause = fn (self:Erlang:Database*, clause:Erlang:Clause*) -> void {
    clause.next = cast(Erlang:Clause*, 0)
    if self.clauses_tail { self.clauses_tail.next = clause } else { self.clauses = clause }
    self.clauses_tail = clause
}

// =============================================================================
// Recursive-descent parser.
// =============================================================================

record Erlang:Parser {
    state:Context*
    database:Erlang:Database*
    source:u8*
    length:i64
    position:i64
    error:i64
}

let Erlang:Parser:new = fn (state:Context*, database:Erlang:Database*, source:u8*) -> Erlang:Parser* {
    let self = cast(Erlang:Parser*, malloc(48))
    if !self { return cast(Erlang:Parser*, 0) }
    self.state = state; self.database = database; self.source = source; self.length = cast(i64, strlen(source)); self.position = 0; self.error = 0
    return self
}

let Erlang:Parser:fail = fn (self:Erlang:Parser*, message:u8*) -> void {
    if !self.error { self.error = 1; context:diagnostic:error(self.state, message) }
}

let Erlang:Parser:skip = fn (self:Erlang:Parser*) -> void {
    var scanning = 1
    while scanning {
        while self.position < self.length && Erlang:is_space(self.source[self.position]) { self.position += 1 }
        if self.position < self.length && self.source[self.position] == 37 {
            while self.position < self.length && self.source[self.position] != 10 && self.source[self.position] != 13 { self.position += 1 }
        } else { scanning = 0 }
    }
}

let Erlang:Parser:peek = fn (self:Erlang:Parser*) -> u8 {
    Erlang:Parser:skip(self)
    if self.position >= self.length { return cast(u8, 0) }
    return self.source[self.position]
}

let Erlang:Parser:match = fn (self:Erlang:Parser*, ch:u8) -> i64 {
    Erlang:Parser:skip(self)
    if self.position < self.length && self.source[self.position] == ch { self.position += 1; return 1 }
    return 0
}

let Erlang:Parser:match_pair = fn (self:Erlang:Parser*, a:u8, b:u8) -> i64 {
    Erlang:Parser:skip(self)
    if self.position + 1 < self.length && self.source[self.position] == a && self.source[self.position + 1] == b {
        self.position += 2; return 1
    }
    return 0
}

let Erlang:Parser:identifier = fn (self:Erlang:Parser*) -> u8* {
    Erlang:Parser:skip(self)
    if self.position >= self.length { return cast(u8*, 0) }
    let ch = self.source[self.position]
    if !(Erlang:is_alpha(ch) || ch == 95) { return cast(u8*, 0) }
    let start = self.position
    self.position += 1
    while self.position < self.length && Erlang:is_ident_continue(self.source[self.position]) { self.position += 1 }
    return Erlang:copy_bytes(&self.source[start], self.position - start)
}

let Erlang:concat_names = fn (left:u8*, right:u8*) -> u8* {
    let a = cast(i64, strlen(left)); let b = cast(i64, strlen(right))
    let out = malloc(a + b + 2)
    if !out { return cast(u8*, 0) }
    memcpy(out, left, a); out[a] = 58; memcpy(&out[a + 1], right, b); out[a + b + 1] = 0
    return out
}

let Erlang:Parser:string = fn (self:Erlang:Parser*) -> u8* {
    Erlang:Parser:skip(self)
    if self.position >= self.length || self.source[self.position] != 34 { return cast(u8*, 0) }
    self.position += 1
    var capacity = 32; var count = 0
    var out = malloc(capacity)
    if !out { return cast(u8*, 0) }
    var done = 0
    while !done && self.position < self.length {
        let ch = self.source[self.position]
        self.position += 1
        if ch == 34 { done = 1 }
        else {
            var actual = ch
            if ch == 92 && self.position < self.length {
                let esc = self.source[self.position]; self.position += 1
                if esc == 110 { actual = 10 } else if esc == 114 { actual = 13 } else if esc == 116 { actual = 9 } else { actual = esc }
            }
            if count + 2 >= capacity { capacity *= 2; out = realloc(out, capacity) }
            out[count] = actual; count += 1
        }
    }
    if !done { free(out); Erlang:Parser:fail(self, "Erlang: unterminated string"); return cast(u8*, 0) }
    out[count] = 0
    return out
}

let Erlang:Parser:number_expr = fn (self:Erlang:Parser*) -> Erlang:Expr* {
    Erlang:Parser:skip(self)
    if self.position >= self.length || !Erlang:is_digit(self.source[self.position]) { return cast(Erlang:Expr*, 0) }
    var value = 0
    while self.position < self.length && Erlang:is_digit(self.source[self.position]) {
        value = value * 10 + self.source[self.position] - 48; self.position += 1
    }
    return Erlang:Expr:integer(value)
}

let Erlang:Parser:number_raw = fn (self:Erlang:Parser*) -> i64 {
    Erlang:Parser:skip(self); var value = 0
    while self.position < self.length && Erlang:is_digit(self.source[self.position]) {
        value = value * 10 + self.source[self.position] - 48; self.position += 1
    }
    return value
}

let Erlang:Parser:parse_pattern = fn (self:Erlang:Parser*) -> Erlang:Pattern* {
    Erlang:Parser:skip(self)
    let ch = Erlang:Parser:peek(self)
    if Erlang:is_digit(ch) {
        let p = Erlang:Pattern:new(3); if p { p.number = Erlang:Parser:number_raw(self) }; return p
    }
    if ch == 123 {
        self.position += 1
        var capacity = 4; var count = 0
        var items = cast(Erlang:Pattern**, malloc(capacity * 8))
        if !Erlang:Parser:match(self, 125) {
            var more = 1
            while more {
                if count == capacity { capacity *= 2; items = cast(Erlang:Pattern**, realloc(cast(u8*, items), capacity * 8)) }
                items[count] = Erlang:Parser:parse_pattern(self); if !items[count] { return cast(Erlang:Pattern*, 0) }; count += 1
                if Erlang:Parser:match(self, 44) { } else { more = 0 }
            }
            if !Erlang:Parser:match(self, 125) { Erlang:Parser:fail(self, "Erlang: expected '}' in tuple pattern"); return cast(Erlang:Pattern*, 0) }
        }
        let p = Erlang:Pattern:new(5); if p { p.arity = count; p.items = cast(u8*, items) }; return p
    }
    if ch == 91 {
        self.position += 1
        var capacity = 4; var count = 0
        var items = cast(Erlang:Pattern**, malloc(capacity * 8))
        if !Erlang:Parser:match(self, 93) {
            var more = 1
            while more {
                if count == capacity { capacity *= 2; items = cast(Erlang:Pattern**, realloc(cast(u8*, items), capacity * 8)) }
                items[count] = Erlang:Parser:parse_pattern(self); if !items[count] { return cast(Erlang:Pattern*, 0) }; count += 1
                if Erlang:Parser:match(self, 44) { } else { more = 0 }
            }
            if !Erlang:Parser:match(self, 93) { Erlang:Parser:fail(self, "Erlang: expected ']' in list pattern"); return cast(Erlang:Pattern*, 0) }
        }
        let p = Erlang:Pattern:new(6); if p { p.arity = count; p.items = cast(u8*, items) }; return p
    }
    if Erlang:is_alpha(ch) || ch == 95 {
        let name = Erlang:Parser:identifier(self)
        if !name { return cast(Erlang:Pattern*, 0) }
        if name[0] == 95 && name[1] == 0 { free(name); return Erlang:Pattern:new(2) }
        if Erlang:is_upper(name[0]) || name[0] == 95 { let p = Erlang:Pattern:new(1); if p { p.name = name; p.symbol = Erlang:categorize_symbol(self.state, "Variables", name) }; return p }
        let p = Erlang:Pattern:new(4); if p { p.name = name; p.symbol = Erlang:categorize_symbol(self.state, "Atoms", name) }; return p
    }
    Erlang:Parser:fail(self, "Erlang: expected pattern")
    return cast(Erlang:Pattern*, 0)
}

let Erlang:Expr:to_pattern = fn (state:Context*, expr:Erlang:Expr*) -> Erlang:Pattern* {
    if !expr { return cast(Erlang:Pattern*, 0) }
    if expr.kind == 1 { let p = Erlang:Pattern:new(3); if p { p.number = expr.number }; return p }
    if expr.kind == 2 { let p = Erlang:Pattern:new(4); if p { p.name = Erlang:copy_text(expr.name); p.symbol = expr.symbol }; return p }
    if expr.kind == 3 {
        if expr.name[0] == 95 && expr.name[1] == 0 { return Erlang:Pattern:new(2) }
        let p = Erlang:Pattern:new(1); if p { p.name = Erlang:copy_text(expr.name); p.symbol = expr.symbol }; return p
    }
    if expr.kind == 5 || expr.kind == 6 {
        var pattern_kind = 5
        if expr.kind == 6 { pattern_kind = 6 }
        let p = Erlang:Pattern:new(pattern_kind)
        if !p { return p }
        p.arity = expr.arity
        let items = cast(Erlang:Pattern**, malloc(expr.arity * 8))
        var i = 0
        while i < expr.arity { items[i] = Erlang:Expr:to_pattern(state, cast(Erlang:Expr**, expr.items)[i]); if !items[i] { return cast(Erlang:Pattern*, 0) }; i += 1 }
        p.items = cast(u8*, items)
        return p
    }
    return cast(Erlang:Pattern*, 0)
}

let Erlang:ParseCallback = fn (self:Erlang:Parser*, mode:i64) -> Erlang:Expr*

let Erlang:Parser:parse_sequence = fn (self:Erlang:Parser*, parse:Erlang:ParseCallback) -> Erlang:Expr* {
    var left = parse(self, 0)
    if !left { return left }
    while Erlang:Parser:match(self, 44) {
        let right = parse(self, 0)
        if !right { return cast(Erlang:Expr*, 0) }
        left = Erlang:Expr:pair(8, left, right)
    }
    return left
}

let Erlang:Parser:parse_receive = fn (self:Erlang:Parser*, parse:Erlang:ParseCallback) -> Erlang:Expr* {
    var head = cast(Erlang:ReceiveClause*, 0)
    var tail = cast(Erlang:ReceiveClause*, 0)
    var done = 0
    while !done {
        Erlang:Parser:skip(self)
        let saved = self.position
        let word = Erlang:Parser:identifier(self)
        if word && strcmp(word, "end") == 0 { free(word); done = 1 }
        else {
            if word { free(word) }
            self.position = saved
            let pattern = Erlang:Parser:parse_pattern(self)
            if !pattern { return cast(Erlang:Expr*, 0) }
            if !Erlang:Parser:match_pair(self, 45, 62) { Erlang:Parser:fail(self, "Erlang: receive clause expects '->'"); return cast(Erlang:Expr*, 0) }
            let body = Erlang:Parser:parse_sequence(self, parse)
            if !body { return cast(Erlang:Expr*, 0) }
            let clause = cast(Erlang:ReceiveClause*, malloc(24))
            if !clause { return cast(Erlang:Expr*, 0) }
            clause.pattern = pattern; clause.body = cast(u8*, body); clause.next = cast(Erlang:ReceiveClause*, 0)
            if tail { tail.next = clause } else { head = clause }; tail = clause
            Erlang:Parser:skip(self)
            if Erlang:Parser:match(self, 59) { } else {
                let endword = Erlang:Parser:identifier(self)
                if !endword || strcmp(endword, "end") != 0 { if endword { free(endword) }; Erlang:Parser:fail(self, "Erlang: receive expects ';' or end"); return cast(Erlang:Expr*, 0) }
                free(endword); done = 1
            }
        }
    }
    let expr = Erlang:Expr:new(11); if expr { expr.items = cast(u8*, head) }; return expr
}

let Erlang:Parser:parse_expr_mode = fn (self:Erlang:Parser*, mode:i64) -> Erlang:Expr* {
    // mode 0: match/send, 1: add/sub, 2: multiply, 3: primary
    if mode == 3 {
        Erlang:Parser:skip(self)
        let ch = Erlang:Parser:peek(self)
        if Erlang:is_digit(ch) { return Erlang:Parser:number_expr(self) }
        if ch == 34 { return Erlang:Expr:named(self.state, 4, Erlang:Parser:string(self)) }
        if ch == 40 {
            self.position += 1; let e = Erlang:Parser:parse_sequence(self, Erlang:Parser:parse_expr_mode)
            if !Erlang:Parser:match(self, 41) { Erlang:Parser:fail(self, "Erlang: expected ')'") }
            return e
        }
        if ch == 123 || ch == 91 {
            var close = 125
            var kind = 5
            if ch == 91 { close = 93; kind = 6 }
            self.position += 1
            var capacity = 4; var count = 0
            var items = cast(Erlang:Expr**, malloc(capacity * 8))
            if !Erlang:Parser:match(self, close) {
                var more = 1
                while more {
                    if count == capacity { capacity *= 2; items = cast(Erlang:Expr**, realloc(cast(u8*, items), capacity * 8)) }
                    items[count] = Erlang:Parser:parse_expr_mode(self, 0); if !items[count] { return cast(Erlang:Expr*, 0) }; count += 1
                    if Erlang:Parser:match(self, 44) { } else { more = 0 }
                }
                if !Erlang:Parser:match(self, close) { Erlang:Parser:fail(self, "Erlang: unterminated tuple/list"); return cast(Erlang:Expr*, 0) }
            }
            let e = Erlang:Expr:new(kind); if e { e.arity = count; e.items = cast(u8*, items) }; return e
        }
        if Erlang:is_alpha(ch) || ch == 95 {
            let first = Erlang:Parser:identifier(self)
            if !first { return cast(Erlang:Expr*, 0) }
            if strcmp(first, "receive") == 0 { free(first); return Erlang:Parser:parse_receive(self, Erlang:Parser:parse_expr_mode) }
            if strcmp(first, "fun") == 0 {
                free(first)
                let fname = Erlang:Parser:identifier(self)
                if !fname || !Erlang:Parser:match(self, 47) { Erlang:Parser:fail(self, "Erlang: fun expects name/arity"); return cast(Erlang:Expr*, 0) }
                let arity = Erlang:Parser:number_raw(self)
                let e = Erlang:Expr:named(self.state, 13, fname); if e { e.number = arity }; return e
            }
            var full = first
            let saved = self.position
            if Erlang:Parser:match(self, 58) {
                let second = Erlang:Parser:identifier(self)
                if second { let joined = Erlang:concat_names(first, second); free(first); free(second); full = joined }
                else { self.position = saved }
            }
            if Erlang:Parser:match(self, 40) {
                var capacity = 4; var count = 0
                var args = cast(Erlang:Expr**, malloc(capacity * 8))
                if !Erlang:Parser:match(self, 41) {
                    var more = 1
                    while more {
                        if count == capacity { capacity *= 2; args = cast(Erlang:Expr**, realloc(cast(u8*, args), capacity * 8)) }
                        args[count] = Erlang:Parser:parse_expr_mode(self, 0); if !args[count] { return cast(Erlang:Expr*, 0) }; count += 1
                        if Erlang:Parser:match(self, 44) { } else { more = 0 }
                    }
                    if !Erlang:Parser:match(self, 41) { Erlang:Parser:fail(self, "Erlang: expected ')' after call"); return cast(Erlang:Expr*, 0) }
                }
                let e = Erlang:Expr:named(self.state, 7, full); if e { e.arity = count; e.items = cast(u8*, args) }; return e
            }
            if Erlang:is_upper(full[0]) || full[0] == 95 { return Erlang:Expr:named(self.state, 3, full) }
            return Erlang:Expr:named(self.state, 2, full)
        }
        Erlang:Parser:fail(self, "Erlang: expected expression")
        return cast(Erlang:Expr*, 0)
    }
    if mode == 2 {
        var left = Erlang:Parser:parse_expr_mode(self, 3)
        while Erlang:Parser:match(self, 42) {
            let right = Erlang:Parser:parse_expr_mode(self, 3)
            left = Erlang:Expr:make_binary(self.state, "__mul", left, right)
        }
        return left
    }
    if mode == 1 {
        var left = Erlang:Parser:parse_expr_mode(self, 2)
        var scanning = 1
        while scanning {
            if Erlang:Parser:match(self, 43) {
                let right = Erlang:Parser:parse_expr_mode(self, 2)
                left = Erlang:Expr:make_binary(self.state, "__add", left, right)
            } else if Erlang:Parser:match(self, 45) {
                let right = Erlang:Parser:parse_expr_mode(self, 2)
                left = Erlang:Expr:make_binary(self.state, "__sub", left, right)
            }
            else { scanning = 0 }
        }
        return left
    }
    let left = Erlang:Parser:parse_expr_mode(self, 1)
    if Erlang:Parser:match(self, 61) {
        let pattern = Erlang:Expr:to_pattern(self.state, left)
        if !pattern { Erlang:Parser:fail(self, "Erlang: left side of '=' is not a pattern"); return cast(Erlang:Expr*, 0) }
        let e = Erlang:Expr:new(9); if e { e.pattern = pattern; e.right = Erlang:Parser:parse_expr_mode(self, 0) }; return e
    }
    if Erlang:Parser:match(self, 33) { return Erlang:Expr:pair(10, left, Erlang:Parser:parse_expr_mode(self, 0)) }
    return left
}

// =============================================================================
// Top-level function-form parser.
// =============================================================================

let Erlang:parse_clause = fn (state:Context*, database:Erlang:Database*, parser:Erlang:Parser*) -> Erlang:Clause* {
    let name = Erlang:Parser:identifier(parser)
    if !name { Erlang:Parser:fail(parser, "Erlang: expected function name"); return cast(Erlang:Clause*, 0) }
    if !Erlang:Parser:match(parser, 40) { free(name); Erlang:Parser:fail(parser, "Erlang: function expects '('"); return cast(Erlang:Clause*, 0) }
    var capacity = 4; var count = 0
    var patterns = cast(Erlang:Pattern**, malloc(capacity * 8))
    if !Erlang:Parser:match(parser, 41) {
        var more = 1
        while more {
            if count == capacity { capacity *= 2; patterns = cast(Erlang:Pattern**, realloc(cast(u8*, patterns), capacity * 8)) }
            patterns[count] = Erlang:Parser:parse_pattern(parser)
            if !patterns[count] { return cast(Erlang:Clause*, 0) }
            count += 1
            if Erlang:Parser:match(parser, 44) { } else { more = 0 }
        }
        if !Erlang:Parser:match(parser, 41) { Erlang:Parser:fail(parser, "Erlang: function parameter list expects ')'"); return cast(Erlang:Clause*, 0) }
    }
    if !Erlang:Parser:match_pair(parser, 45, 62) { Erlang:Parser:fail(parser, "Erlang: function clause expects '->'"); return cast(Erlang:Clause*, 0) }
    let body = Erlang:Parser:parse_sequence(parser, Erlang:Parser:parse_expr_mode)
    if !body { return cast(Erlang:Clause*, 0) }
    let clause = cast(Erlang:Clause*, malloc(48))
    if !clause { return cast(Erlang:Clause*, 0) }
    clause.name = name; clause.symbol = Erlang:categorize_symbol(state, "Functions", name); Erlang:categorize_symbol(state, "Grammar", name); clause.arity = count; clause.patterns = cast(u8*, patterns); clause.body = body; clause.next = cast(Erlang:Clause*, 0)
    return clause
}

let Erlang:parse_function_form = fn (state:Context*, database:Erlang:Database*, source:u8*) -> i64 {
    let parser = Erlang:Parser:new(state, database, source)
    if !parser { return 0 }
    defer free(cast(u8*, parser))
    var expected_name = cast(u8*, 0)
    var expected_symbol = 0
    var expected_arity = -1
    var more = 1
    while more {
        let clause = Erlang:parse_clause(state, database, parser)
        if !clause { return 0 }
        if !expected_name { expected_name = Erlang:copy_text(clause.name); expected_symbol = clause.symbol; expected_arity = clause.arity }
        else if expected_symbol != clause.symbol || expected_arity != clause.arity {
            context:diagnostic:error(state, "Erlang: clauses separated by ';' must have the same name and arity")
            return 0
        }
        Erlang:Database:add_clause(database, clause)
        Erlang:Parser:skip(parser)
        if parser.position < parser.length {
            if Erlang:Parser:match(parser, 59) { }
            else { Erlang:Parser:fail(parser, "Erlang: unexpected input after function clause"); return 0 }
        } else { more = 0 }
    }
    if expected_name { free(expected_name) }
    return !parser.error
}

// =============================================================================
// Strict values and pattern matching.
// =============================================================================

let Erlang:Value:composite = fn (kind:i64, items:Erlang:Value**, arity:i64) -> Erlang:Value* {
    let v = Erlang:Value:new(kind)
    if v { v.arity = arity; v.items = cast(u8*, items) }
    return v
}

let Erlang:Value:equal = fn (left:Erlang:Value*, right:Erlang:Value*) -> i64 {
    if !left || !right || left.kind != right.kind { return 0 }
    if left.kind == 1 || left.kind == 6 { return left.number == right.number }
    if left.kind == 2 { return left.symbol == right.symbol }
    if left.kind == 3 { return left.name && right.name && strcmp(left.name, right.name) == 0 }
    if left.kind == 7 { return left.symbol == right.symbol && left.number == right.number }
    if left.kind == 4 || left.kind == 5 {
        if left.arity != right.arity { return 0 }
        var i = 0
        while i < left.arity {
            if !Erlang:Value:equal(cast(Erlang:Value**, left.items)[i], cast(Erlang:Value**, right.items)[i]) { return 0 }
            i += 1
        }
        return 1
    }
    return 0
}

let Erlang:match_pattern = fn (pattern:Erlang:Pattern*, value:Erlang:Value*, env:Erlang:EnvEntry*) -> i64 {
    if !pattern || !value { return 0 }
    if pattern.kind == 2 { return 1 }
    if pattern.kind == 1 {
        let existing = Erlang:Env:find(env, pattern.symbol)
        if existing { if Erlang:Value:equal(existing, value) { return 1 }; return 0 }
        return cast(i64, Erlang:Env:bind(env, pattern.name, pattern.symbol, value))
    }
    if pattern.kind == 3 { if value.kind == 1 && value.number == pattern.number { return 1 }; return 0 }
    if pattern.kind == 4 { if value.kind == 2 && value.symbol == pattern.symbol { return 1 }; return 0 }
    if pattern.kind == 5 || pattern.kind == 6 {
        var expected_kind = 4
        if pattern.kind == 6 { expected_kind = 5 }
        if value.kind != expected_kind || value.arity != pattern.arity { return 0 }
        var current = env
        var i = 0
        while i < pattern.arity {
            let result = Erlang:match_pattern(cast(Erlang:Pattern**, pattern.items)[i], cast(Erlang:Value**, value.items)[i], current)
            if !result { return 0 }
            if result != 1 { current = cast(Erlang:EnvEntry*, result) }
            i += 1
        }
        if current == env { return 1 }
        return cast(i64, current)
    }
    return 0
}

// =============================================================================
// Actor runtime: process table, mailboxes, scheduler and evaluator.
// =============================================================================

let Erlang:Database:find_process = fn (self:Erlang:Database*, pid:i64) -> Erlang:Process* {
    var process = self.processes
    while process { if process.pid == pid { return process }; process = process.next }
    return cast(Erlang:Process*, 0)
}

let Erlang:Database:spawn = fn (state:Context*, self:Erlang:Database*, function:u8*, function_symbol:i64) -> Erlang:Process* {
    let process = cast(Erlang:Process*, malloc(56))
    if !process { return cast(Erlang:Process*, 0) }
    process.pid = self.next_pid; self.next_pid += 1
    process.status = 0; process.function = Erlang:copy_text(function); process.function_symbol = function_symbol
    process.mailbox_head = cast(Erlang:Message*, 0); process.mailbox_tail = cast(Erlang:Message*, 0)
    process.next = self.processes; self.processes = process

    // A spawned actor is also represented in the RecurLoop lexicon. The
    // runtime still owns scheduling/mailboxes; the phrase gives tooling and
    // other RecurLoop code an introspectable PID entry.
    return process
}

let Erlang:Process:enqueue = fn (self:Erlang:Process*, value:Erlang:Value*) -> i64 {
    let message = cast(Erlang:Message*, malloc(16))
    if !message { return 0 }
    message.value = value; message.next = cast(Erlang:Message*, 0)
    if self.mailbox_tail { self.mailbox_tail.next = message } else { self.mailbox_head = message }
    self.mailbox_tail = message
    return 1
}

let Erlang:print_value = fn (value:Erlang:Value*) -> void {
    if !value { printf("undefined"); return }
    if value.kind == 1 { printf("%lld", value.number); return }
    if value.kind == 2 { printf("%s", value.name); return }
    if value.kind == 3 { printf("%s", value.name); return }
    if value.kind == 6 { printf("<pid:%lld>", value.number); return }
    if value.kind == 7 { printf("fun %s/%lld", value.name, value.number); return }
    if value.kind == 4 {
        printf("{")
        var i = 0
        while i < value.arity { if i > 0 { printf(",") }; Erlang:print_value(cast(Erlang:Value**, value.items)[i]); i += 1 }
        printf("}")
        return
    }
    if value.kind == 5 {
        printf("[")
        var i = 0
        while i < value.arity { if i > 0 { printf(",") }; Erlang:print_value(cast(Erlang:Value**, value.items)[i]); i += 1 }
        printf("]")
    }
}

let Erlang:RuntimeCallback = fn (state:Context*, mode:i64, a:i64, b:i64, c:i64) -> i64

let Erlang:io_format = fn (state:Context*, format:u8*, args:Erlang:Value**, arity:i64) -> Erlang:Value* {
    var i = 0; var arg = 0
    while format[i] {
        if format[i] == 126 && format[i + 1] {
            let code = format[i + 1]
            if code == 110 { printf("\n"); i += 2 }
            else if code == 112 {
                if arg < arity { Erlang:print_value(args[arg]); arg += 1 }
                i += 2
            } else if code == 126 { printf("~"); i += 2 }
            else { printf("%c", format[i]); i += 1 }
        } else { printf("%c", format[i]); i += 1 }
    }
    return Erlang:Value:atom(state, "ok")
}

let Erlang:apply_function_with = fn (dispatch:Erlang:RuntimeCallback, state:Context*, symbol:i64, args:Erlang:Value**, arity:i64) -> Erlang:Value* {
    let database = Erlang:database(state)
    if !database { return cast(Erlang:Value*, 0) }

    if symbol == Erlang:intern_symbol(state, "self") && arity == 0 { return Erlang:Value:pid(database.current_pid) }
    if symbol == Erlang:intern_symbol(state, "spawn") && arity == 1 {
        if !args[0] || args[0].kind != 7 || args[0].number != 0 {
            context:diagnostic:error(state, "Erlang: spawn currently expects fun name/0")
            return cast(Erlang:Value*, 0)
        }
        let process = Erlang:Database:spawn(state, database, args[0].name, args[0].symbol)
        if !process { context:diagnostic:error(state, "Erlang: could not spawn process"); return cast(Erlang:Value*, 0) }
        return Erlang:Value:pid(process.pid)
    }
    if symbol == Erlang:intern_symbol(state, "io:format") {
        if arity == 1 && args[0] && args[0].kind == 3 { return Erlang:io_format(state, args[0].name, cast(Erlang:Value**, 0), 0) }
        if arity == 2 && args[0] && args[0].kind == 3 && args[1] && args[1].kind == 5 {
            return Erlang:io_format(state, args[0].name, cast(Erlang:Value**, args[1].items), args[1].arity)
        }
        context:diagnostic:error(state, "Erlang: io:format expects a format string and optional list")
        return cast(Erlang:Value*, 0)
    }

    var clause = database.clauses
    while clause {
        if clause.arity == arity && clause.symbol == symbol {
            var env = cast(Erlang:EnvEntry*, 0)
            var matched = 1
            var i = 0
            while matched && i < arity {
                let result = Erlang:match_pattern(cast(Erlang:Pattern**, clause.patterns)[i], args[i], env)
                if !result { matched = 0 }
                else if result != 1 { env = cast(Erlang:EnvEntry*, result) }
                i += 1
            }
            if matched {
                let frame = cast(Erlang:Frame*, malloc(8)); if !frame { return cast(Erlang:Value*, 0) }
                frame.env = env
                return cast(Erlang:Value*, dispatch(state, 1, cast(i64, clause.body), cast(i64, frame), 0))
            }
        }
        clause = clause.next
    }
    context:diagnostic:error(state, "Erlang: function_clause or undefined function")
    return cast(Erlang:Value*, 0)
}

let Erlang:scheduler_run_one_with = fn (dispatch:Erlang:RuntimeCallback, state:Context*) -> i64 {
    let database = Erlang:database(state)
    if !database { return 0 }
    var process = database.processes
    while process {
        if process.status == 0 {
            process.status = 1
            let saved = database.current_pid
            database.current_pid = process.pid
            let result = cast(Erlang:Value*, dispatch(state, 2, process.function_symbol, 0, 0))
            database.current_pid = saved
            process.status = 2
            if !result { return 0 }
            return 1
        }
        process = process.next
    }
    return 0
}

let Erlang:receive_message_with = fn (dispatch:Erlang:RuntimeCallback, state:Context*, clauses:Erlang:ReceiveClause*, frame:Erlang:Frame*) -> Erlang:Value* {
    let database = Erlang:database(state)
    if !database { return cast(Erlang:Value*, 0) }
    let process = Erlang:Database:find_process(database, database.current_pid)
    if !process { context:diagnostic:error(state, "Erlang: current process does not exist"); return cast(Erlang:Value*, 0) }
    var attempts = 0
    while attempts < 100000 {
        var previous = cast(Erlang:Message*, 0)
        var message = process.mailbox_head
        while message {
            var clause = clauses
            while clause {
                let result = Erlang:match_pattern(clause.pattern, message.value, frame.env)
                if result {
                    if previous { previous.next = message.next } else { process.mailbox_head = message.next }
                    if process.mailbox_tail == message { process.mailbox_tail = previous }
                    if result != 1 { frame.env = cast(Erlang:EnvEntry*, result) }
                    return cast(Erlang:Value*, dispatch(state, 1, cast(i64, clause.body), cast(i64, frame), 0))
                }
                clause = clause.next
            }
            previous = message; message = message.next
        }
        if !dispatch(state, 3, 0, 0, 0) {
            context:diagnostic:error(state, "Erlang: receive would block with no runnable process")
            return cast(Erlang:Value*, 0)
        }
        attempts += 1
    }
    context:diagnostic:error(state, "Erlang: scheduler step limit exceeded")
    return cast(Erlang:Value*, 0)
}

let Erlang:eval_with = fn (dispatch:Erlang:RuntimeCallback, state:Context*, expr:Erlang:Expr*, frame:Erlang:Frame*) -> Erlang:Value* {
    if !expr { return cast(Erlang:Value*, 0) }
    if expr.kind == 1 { return Erlang:Value:integer(expr.number) }
    if expr.kind == 2 { let v = Erlang:Value:atom(state, expr.name); if v { v.symbol = expr.symbol }; return v }
    if expr.kind == 3 {
        let value = Erlang:Env:find(frame.env, expr.symbol)
        if !value { context:diagnostic:error(state, "Erlang: unbound variable"); return cast(Erlang:Value*, 0) }
        return value
    }
    if expr.kind == 4 { return Erlang:Value:text(expr.name) }
    if expr.kind == 5 || expr.kind == 6 {
        let items = cast(Erlang:Value**, malloc(expr.arity * 8))
        var i = 0
        while i < expr.arity { items[i] = cast(Erlang:Value*, dispatch(state, 1, cast(i64, cast(Erlang:Expr**, expr.items)[i]), cast(i64, frame), 0)); if !items[i] { return cast(Erlang:Value*, 0) }; i += 1 }
        var kind = 4; if expr.kind == 6 { kind = 5 }
        return Erlang:Value:composite(kind, items, expr.arity)
    }
    if expr.kind == 7 {
        let args = cast(Erlang:Value**, malloc(expr.arity * 8))
        var i = 0
        while i < expr.arity { args[i] = cast(Erlang:Value*, dispatch(state, 1, cast(i64, cast(Erlang:Expr**, expr.items)[i]), cast(i64, frame), 0)); if !args[i] { return cast(Erlang:Value*, 0) }; i += 1 }
        return cast(Erlang:Value*, dispatch(state, 2, expr.symbol, cast(i64, args), expr.arity))
    }
    if expr.kind == 8 {
        let ignored = cast(Erlang:Value*, dispatch(state, 1, cast(i64, expr.left), cast(i64, frame), 0))
        if !ignored { return cast(Erlang:Value*, 0) }
        return cast(Erlang:Value*, dispatch(state, 1, cast(i64, expr.right), cast(i64, frame), 0))
    }
    if expr.kind == 9 {
        let value = cast(Erlang:Value*, dispatch(state, 1, cast(i64, expr.right), cast(i64, frame), 0))
        if !value { return value }
        let result = Erlang:match_pattern(expr.pattern, value, frame.env)
        if !result { context:diagnostic:error(state, "Erlang: badmatch"); return cast(Erlang:Value*, 0) }
        if result != 1 { frame.env = cast(Erlang:EnvEntry*, result) }
        return value
    }
    if expr.kind == 10 {
        let target = cast(Erlang:Value*, dispatch(state, 1, cast(i64, expr.left), cast(i64, frame), 0))
        let message = cast(Erlang:Value*, dispatch(state, 1, cast(i64, expr.right), cast(i64, frame), 0))
        if !target || target.kind != 6 || !message { context:diagnostic:error(state, "Erlang: send expects a pid"); return cast(Erlang:Value*, 0) }
        let database = Erlang:database(state)
        let process = Erlang:Database:find_process(database, target.number)
        if !process { context:diagnostic:error(state, "Erlang: send target does not exist"); return cast(Erlang:Value*, 0) }
        Erlang:Process:enqueue(process, message)
        return message
    }
    if expr.kind == 11 { return cast(Erlang:Value*, dispatch(state, 4, cast(i64, expr.items), cast(i64, frame), 0)) }
    if expr.kind == 12 {
        let left = cast(Erlang:Value*, dispatch(state, 1, cast(i64, expr.left), cast(i64, frame), 0)); let right = cast(Erlang:Value*, dispatch(state, 1, cast(i64, expr.right), cast(i64, frame), 0))
        if !left || !right || left.kind != 1 || right.kind != 1 { context:diagnostic:error(state, "Erlang: arithmetic expects integers"); return cast(Erlang:Value*, 0) }
        if expr.symbol == Erlang:intern_symbol(state, "__add") { return Erlang:Value:integer(left.number + right.number) }
        if expr.symbol == Erlang:intern_symbol(state, "__sub") { return Erlang:Value:integer(left.number - right.number) }
        return Erlang:Value:integer(left.number * right.number)
    }
    if expr.kind == 13 { return Erlang:Value:funref(state, expr.name, expr.symbol, expr.number) }
    return cast(Erlang:Value*, 0)
}

let Erlang:dispatch = fn (state:Context*, mode:i64, a:i64, b:i64, c:i64) -> i64 {
    if mode == 1 { return cast(i64, Erlang:eval_with(Erlang:dispatch, state, cast(Erlang:Expr*, a), cast(Erlang:Frame*, b))) }
    if mode == 2 { return cast(i64, Erlang:apply_function_with(Erlang:dispatch, state, a, cast(Erlang:Value**, b), c)) }
    if mode == 3 { return Erlang:scheduler_run_one_with(Erlang:dispatch, state) }
    if mode == 4 { return cast(i64, Erlang:receive_message_with(Erlang:dispatch, state, cast(Erlang:ReceiveClause*, a), cast(Erlang:Frame*, b))) }
    return 0
}

// =============================================================================
// Source forms, EOF detection and language-image export.
// =============================================================================

let Erlang:capture_form = fn (state:Context*) -> u8* {
    context:source:ensure(state, 1048576)
    let source = cast(u8*, context:source:data(state))
    let bytes = context:source:bytes(state)
    if bytes <= 0 { return cast(u8*, 0) }
    var i = 0; var quote = 0; var comment = 0
    while i < bytes {
        let ch = source[i]
        if comment {
            if ch == 10 || ch == 13 { comment = 0 }
            i += 1
        } else if quote {
            if ch == 92 { i += 2 }
            else { if ch == quote { quote = 0 }; i += 1 }
        } else if ch == 37 { comment = 1; i += 1 }
        else if ch == 34 || ch == 39 { quote = ch; i += 1 }
        else if ch == 46 {
            let text = Erlang:copy_bytes(source, i)
            context:source:advance(state, i + 1)
            return text
        } else { i += 1 }
    }
    context:diagnostic:error(state, "Erlang: top-level form is missing terminating '.'")
    return cast(u8*, 0)
}

let Erlang:source_has_more = fn (state:Context*) -> i64 {
    context:source:ensure(state, 1048576)
    let source = cast(u8*, context:source:data(state)); let bytes = context:source:bytes(state)
    var i = 0
    while i < bytes {
        if Erlang:is_space(source[i]) { i += 1 }
        else if source[i] == 37 { while i < bytes && source[i] != 10 && source[i] != 13 { i += 1 } }
        else { return 1 }
    }
    return 0
}

let Erlang:run_main = fn (state:Context*) -> void {
    let database = Erlang:database(state)
    if !database || database.main_ran { return }
    var found = 0; var clause = database.clauses
    let main_symbol = Erlang:intern_symbol(state, "main")
    while clause { if clause.arity == 0 && clause.symbol == main_symbol { found = 1 }; clause = clause.next }
    if !found { return }
    database.main_ran = 1
    let result = cast(Erlang:Value*, Erlang:dispatch(state, 2, main_symbol, 0, 0))
    if !result { context:diagnostic:error(state, "Erlang: main/0 failed") }
}

let Erlang:top_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = Erlang:capture_form(state)
        if source {
            let database = Erlang:database(state)
            Erlang:parse_function_form(state, database, source)
            free(source)
        }
        if !Erlang:source_has_more(state) { Erlang:run_main(state) }
        context:source:root(state)
    }
}

let Erlang:ignore_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = Erlang:capture_form(state)
        if source { free(source) }
        if !Erlang:source_has_more(state) { Erlang:run_main(state) }
        context:source:root(state)
    }
}

// Fixed Erlang forms are real RecurLoop phrases. Only their small payload is
// parsed here; arbitrary function bodies continue through the function-form
// parser because Erlang expression/pattern semantics require their own AST.
let Erlang:module_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = Erlang:capture_form(state)
        if source {
            let database = Erlang:database(state)
            let parser = Erlang:Parser:new(state, database, source)
            if parser {
                if Erlang:Parser:match(parser, 40) {
                    let name = Erlang:Parser:identifier(parser)
                    if name {
                        Erlang:categorize_symbol(state, "Modules", name)
                        free(name)
                    }
                    if !Erlang:Parser:match(parser, 41) { context:diagnostic:error(state, "Erlang: -module expects ')' ") }
                } else { context:diagnostic:error(state, "Erlang: -module expects '(name)'") }
                free(cast(u8*, parser))
            }
            free(source)
        }
        if !Erlang:source_has_more(state) { Erlang:run_main(state) }
        context:source:root(state)
    }
}

let Erlang:export_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = Erlang:capture_form(state)
        if source {
            let database = Erlang:database(state)
            let parser = Erlang:Parser:new(state, database, source)
            if parser {
                if Erlang:Parser:match(parser, 40) && Erlang:Parser:match(parser, 91) {
                    var more = !Erlang:Parser:match(parser, 93)
                    while more {
                        let name = Erlang:Parser:identifier(parser)
                        if !name { context:diagnostic:error(state, "Erlang: -export expects function/arity entries"); more = 0 }
                        else {
                            if Erlang:Parser:match(parser, 47) {
                                let arity = Erlang:Parser:number_raw(parser)
                                Erlang:categorize_symbol(state, "Functions", name)
                                Erlang:categorize_symbol(state, "Grammar", name)
                            } else { context:diagnostic:error(state, "Erlang: -export expects '/arity'"); more = 0 }
                            free(name)
                            if more {
                                if Erlang:Parser:match(parser, 44) { }
                                else { more = 0 }
                            }
                        }
                    }
                    if !Erlang:Parser:match(parser, 93) { context:diagnostic:error(state, "Erlang: -export expects ']'") }
                    if !Erlang:Parser:match(parser, 41) { context:diagnostic:error(state, "Erlang: -export expects ')'") }
                } else { context:diagnostic:error(state, "Erlang: -export expects '([...])'") }
                free(cast(u8*, parser))
            }
            free(source)
        }
        if !Erlang:source_has_more(state) { Erlang:run_main(state) }
        context:source:root(state)
    }
}

// RecurLoop-side introspection helper. It deliberately consults only phrase
// dictionaries, so passing this check proves the foreign entity is visible in
// the RecurLoop lexicon rather than merely present in the Erlang database.
let Erlang:assert_symbol_phrase = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        context:source:ensure(state, 4096)
        let source = cast(u8*, context:source:data(state))
        let bytes = context:source:bytes(state)
        var i = 0
        while i < bytes && Erlang:is_space(source[i]) { i += 1 }
        let category_start = i
        while i < bytes && Erlang:is_ident_continue(source[i]) { i += 1 }
        let category_end = i
        while i < bytes && Erlang:is_space(source[i]) { i += 1 }
        let name_start = i
        while i < bytes && !Erlang:is_space(source[i]) { i += 1 }
        let name_end = i
        let category = Erlang:copy_bytes(&source[category_start], category_end - category_start)
        let name = Erlang:copy_bytes(&source[name_start], name_end - name_start)
        if !category || !name { context:diagnostic:error(state, "erlang_assert expects CATEGORY NAME") }
        else {
            var owner_name = cast(u8*, 0)
            if strcmp(category, "function") == 0 { owner_name = "Functions" }
            else if strcmp(category, "variable") == 0 { owner_name = "Variables" }
            else if strcmp(category, "atom") == 0 { owner_name = "Atoms" }
            else if strcmp(category, "module") == 0 { owner_name = "Modules" }
            else if strcmp(category, "process") == 0 { owner_name = "Processes" }
            else if strcmp(category, "builtin") == 0 { owner_name = "Builtins" }
            else if strcmp(category, "grammar") == 0 { owner_name = "Grammar" }
            else if strcmp(category, "symbol") == 0 { owner_name = "Symbols" }
            if !owner_name || !Erlang:symbol_in(state, owner_name, name) {
                context:diagnostic:error(state, "Erlang: expected phrase-backed symbol is missing")
            }
        }
        if category { free(category) }
        if name { free(name) }
        context:source:advance(state, name_end)
        context:source:root(state)
    }
}

let install_erlang_fallback = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let erlang = context:phrase:find(state, "Erlang")
        let top = context:phrase:find:exact(state, erlang, "top_form")
        let fallback = context:phrase:define:alias(state, "", top)
        if !fallback { context:diagnostic:error(state, "Erlang: could not install top-level fallback") }
    }
}

let "-module" = <Erlang:module_form>
let "-export" = <Erlang:export_form>
let erlang_assert = <Erlang:assert_symbol_phrase>

install_erlang_fallback

set malloc.serializable = false
set realloc.serializable = false
set free.serializable = false
set memcpy.serializable = false
set strlen.serializable = false
set strcmp.serializable = false
set printf.serializable = false
set install_erlang_fallback.serializable = false

engine export "/tmp/recurloop-erlang-library.rli"
