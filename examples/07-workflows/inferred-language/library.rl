// =============================================================================
// RecurLoop inferred/lazy-specialization language experiment
//
// Functions omit parameter and result types. A call is keyed by the runtime
// LanguageKit value kinds of its arguments. The first call for a signature
// lowers the specialized AST to typed RecurLoop source, compiles it through
// RecurLoop's normal native function pipeline, JIT-links it, and caches the
// resulting entry pointer. Later calls jump directly to that native entry.
// =============================================================================

languagekit_native_begin
link shared "c"

let Inferred = phrase { dictionary = true permanent = true }
let Inferred:Internal = phrase { dictionary = true serializable = false }
let Inferred:Symbols = phrase { dictionary = true permanent = true }
let Inferred:Functions = phrase { dictionary = true permanent = true }
let Inferred:Variables = phrase { dictionary = true permanent = true }
let Inferred:Grammar = phrase { dictionary = true permanent = true }
let Inferred:Specializations = phrase { dictionary = true permanent = true }

let Inferred:is_space = fn (ch:u8) -> i64 { return LanguageKit:is_space(ch) }
let Inferred:is_alpha = fn (ch:u8) -> i64 { return LanguageKit:is_alpha(ch) }
let Inferred:is_digit = fn (ch:u8) -> i64 { return LanguageKit:is_digit(ch) }
let Inferred:is_ident = fn (ch:u8) -> i64 { return Inferred:is_alpha(ch) || Inferred:is_digit(ch) || ch == 95 }
let Inferred:copy_text = fn (text:u8*) -> u8* { return LanguageKit:copy_text(text) }
let Inferred:copy_bytes = fn (text:u8*, bytes:i64) -> u8* { return LanguageKit:copy_bytes(text, bytes) }

let Inferred:category = fn (state:Context*, owner_name:u8*, name:u8*) -> i64 {
    let root = context:phrase:find(state, "Inferred")
    if !root { return 0 }
    let owner = context:phrase:find:exact(state, root, owner_name)
    if !owner { return 0 }
    return LanguageKit:categorize(state, owner, name)
}

record Inferred:Expr {
    kind:i64
    op:i64
    number:i64
    text:u8*
    symbol:i64
    inferred_kind:i64
    left:Inferred:Expr*
    right:Inferred:Expr*
    argc:i64
    args:Inferred:Expr**
}

record Inferred:Stmt {
    kind:i64
    name:u8*
    symbol:i64
    expr:Inferred:Expr*
    body:Inferred:Stmt*
    else_body:Inferred:Stmt*
    next:Inferred:Stmt*
}

record Inferred:Specialization {
    arity:i64
    kinds:i64*
    result_kind:i64
    native_entry:i64
    compiled_symbol:u8*
    hits:i64
    state:i64
    next:Inferred:Specialization*
}

record Inferred:Function {
    name:u8*
    symbol:i64
    arity:i64
    params:u8**
    param_symbols:i64*
    body:Inferred:Stmt*
    specializations:Inferred:Specialization*
    specialization_tail:Inferred:Specialization*
    specialization_count:i64
    next:Inferred:Function*
}

record Inferred:Database {
    functions:Inferred:Function*
    tail:Inferred:Function*
}

record Inferred:Env {
    symbol:i64
    value:LanguageKit:Value*
    next:Inferred:Env*
}

record Inferred:TypeEnv {
    symbol:i64
    kind:i64
    next:Inferred:TypeEnv*
}

record Inferred:Parser {
    state:Context*
    source:u8*
    length:i64
    position:i64
    error:i64
}

let Inferred:Expr:new = fn (kind:i64) -> Inferred:Expr* {
    let self = cast(Inferred:Expr*, malloc(80))
    if !self { return cast(Inferred:Expr*, 0) }
    self.kind = kind; self.op = 0; self.number = 0; self.text = cast(u8*, 0)
    self.symbol = 0; self.inferred_kind = 0
    self.left = cast(Inferred:Expr*, 0); self.right = cast(Inferred:Expr*, 0)
    self.argc = 0; self.args = cast(Inferred:Expr**, 0)
    return self
}

let Inferred:Stmt:new = fn (kind:i64) -> Inferred:Stmt* {
    let self = cast(Inferred:Stmt*, malloc(56))
    if !self { return cast(Inferred:Stmt*, 0) }
    self.kind = kind; self.name = cast(u8*, 0); self.symbol = 0
    self.expr = cast(Inferred:Expr*, 0); self.body = cast(Inferred:Stmt*, 0)
    self.else_body = cast(Inferred:Stmt*, 0); self.next = cast(Inferred:Stmt*, 0)
    return self
}

let Inferred:database = fn (state:Context*) -> Inferred:Database* {
    let current = LanguageKit:state_get(state, "__inferred_database")
    if current { return cast(Inferred:Database*, current) }
    let db = cast(Inferred:Database*, malloc(16))
    if !db { return cast(Inferred:Database*, 0) }
    db.functions = cast(Inferred:Function*, 0); db.tail = cast(Inferred:Function*, 0)
    LanguageKit:state_set(state, "__inferred_database", cast(i64, db))
    return db
}

let Inferred:find_function = fn (db:Inferred:Database*, symbol:i64) -> Inferred:Function* {
    var f = db.functions
    while f { if f.symbol == symbol { return f }; f = f.next }
    return cast(Inferred:Function*, 0)
}

let Inferred:Parser:new = fn (state:Context*, source:u8*) -> Inferred:Parser* {
    let self = cast(Inferred:Parser*, malloc(40))
    if !self { return cast(Inferred:Parser*, 0) }
    self.state = state; self.source = source; self.length = cast(i64, strlen(source))
    self.position = 0; self.error = 0
    return self
}

let Inferred:Parser:fail = fn (self:Inferred:Parser*, message:u8*) -> void {
    if !self.error { self.error = 1; context:diagnostic:error(self.state, message) }
}

let Inferred:Parser:skip = fn (self:Inferred:Parser*) -> void {
    LanguageKit:Cursor:skip(self.source, self.length, &self.position, 8)
}

let Inferred:Parser:text_at = fn (self:Inferred:Parser*, text:u8*) -> i64 {
    return LanguageKit:Cursor:text_at(self.source, self.length, self.position, text)
}

let Inferred:Parser:starts = fn (self:Inferred:Parser*, text:u8*) -> i64 {
    return LanguageKit:Cursor:starts(self.source, self.length, &self.position, 8, text)
}

let Inferred:Parser:match_text = fn (self:Inferred:Parser*, text:u8*) -> i64 {
    return LanguageKit:Cursor:match_text(self.source, self.length, &self.position, 8, text)
}

let Inferred:Parser:match_ch = fn (self:Inferred:Parser*, value:u8) -> i64 {
    return LanguageKit:Cursor:match_byte(self.source, self.length, &self.position, 8, value)
}

let Inferred:Parser:match_pair = fn (self:Inferred:Parser*, first:u8, second:u8) -> i64 {
    return LanguageKit:Cursor:match_pair(self.source, self.length, &self.position, 8, first, second)
}

let Inferred:Parser:keyword = fn (self:Inferred:Parser*, text:u8*) -> i64 {
    return LanguageKit:Cursor:keyword(self.source, self.length, &self.position, 8, text)
}

let Inferred:Parser:identifier = fn (self:Inferred:Parser*) -> u8* {
    return LanguageKit:Cursor:take_identifier(self.source, self.length, &self.position, 8)
}

let Inferred:Parser:string = fn (self:Inferred:Parser*) -> u8* {
    return LanguageKit:Cursor:take_string(self.state, self.source, self.length, &self.position, 8, "Inferred: unterminated string")
}

let Inferred:Parser:number = fn (self:Inferred:Parser*) -> Inferred:Expr* {
    var found = 0
    let value = LanguageKit:Cursor:take_integer(self.source, self.length, &self.position, 8, &found)
    if !found { return cast(Inferred:Expr*, 0) }
    let expr = Inferred:Expr:new(1)
    if expr { expr.number = value; expr.inferred_kind = 1 }
    return expr
}

let Inferred:op_expr = fn (op:i64, left:Inferred:Expr*, right:Inferred:Expr*) -> Inferred:Expr* {
    let e = Inferred:Expr:new(5); if e { e.op = op; e.left = left; e.right = right }; return e
}

let Inferred:Parser:parse_expr_mode = fn (self:Inferred:Parser*, mode:i64) -> Inferred:Expr* {
    // op: 1 +, 2 -, 3 *, 4 /, 5 %, 6 <, 7 >, 8 <=, 9 >=,
    // 10 ==, 11 !=, 12 &&, 13 ||, 14 specialized text concat.
    if mode == 6 {
        Inferred:Parser:skip(self)
        if Inferred:Parser:match_ch(self, cast(u8, 33)) {
            let e = Inferred:Expr:new(6); if e { e.op = 1; e.right = Inferred:Parser:parse_expr_mode(self, 6); e.inferred_kind = 1 }; return e
        }
        if Inferred:Parser:match_ch(self, cast(u8, 45)) {
            let e = Inferred:Expr:new(6); if e { e.op = 2; e.right = Inferred:Parser:parse_expr_mode(self, 6); e.inferred_kind = 1 }; return e
        }
        if Inferred:Parser:match_ch(self, cast(u8, 40)) {
            let e = Inferred:Parser:parse_expr_mode(self, 0)
            if !Inferred:Parser:match_ch(self, cast(u8, 41)) { Inferred:Parser:fail(self, "Inferred: expected ')'") }
            return e
        }
        let n = Inferred:Parser:number(self); if n { return n }
        let str = Inferred:Parser:string(self)
        if str { let e = Inferred:Expr:new(3); if e { e.text = str; e.inferred_kind = 2 }; return e }
        let name = Inferred:Parser:identifier(self)
        if !name { Inferred:Parser:fail(self, "Inferred: expected expression"); return cast(Inferred:Expr*, 0) }
        if Inferred:Parser:match_ch(self, cast(u8, 40)) {
            let e = Inferred:Expr:new(4); if !e { return e }
            e.text = name; e.symbol = LanguageKit:intern(self.state, name)
            var cap = 4; var count = 0; var args = cast(Inferred:Expr**, malloc(cap * 8))
            if !Inferred:Parser:match_ch(self, cast(u8, 41)) {
                var more = 1
                while more {
                    if count == cap { cap *= 2; args = cast(Inferred:Expr**, realloc(cast(u8*, args), cap * 8)) }
                    args[count] = Inferred:Parser:parse_expr_mode(self, 0); if !args[count] { return cast(Inferred:Expr*, 0) }; count += 1
                    if Inferred:Parser:match_ch(self, cast(u8, 44)) { } else { more = 0 }
                }
                if !Inferred:Parser:match_ch(self, cast(u8, 41)) { Inferred:Parser:fail(self, "Inferred: expected ')' after call"); return cast(Inferred:Expr*, 0) }
            }
            e.argc = count; e.args = args; return e
        }
        let e = Inferred:Expr:new(2); if e { e.text = name; e.symbol = LanguageKit:intern(self.state, name) }; return e
    }
    if mode == 5 {
        var left = Inferred:Parser:parse_expr_mode(self, 6); if !left { return left }
        var more = 1
        while more {
            if Inferred:Parser:match_ch(self, cast(u8, 42)) { left = Inferred:op_expr(3, left, Inferred:Parser:parse_expr_mode(self, 6)) }
            else if Inferred:Parser:match_ch(self, cast(u8, 47)) { left = Inferred:op_expr(4, left, Inferred:Parser:parse_expr_mode(self, 6)) }
            else if Inferred:Parser:match_ch(self, cast(u8, 37)) { left = Inferred:op_expr(5, left, Inferred:Parser:parse_expr_mode(self, 6)) }
            else { more = 0 }
        }
        return left
    }
    if mode == 4 {
        var left = Inferred:Parser:parse_expr_mode(self, 5); if !left { return left }
        var more = 1
        while more {
            if Inferred:Parser:match_ch(self, cast(u8, 43)) { left = Inferred:op_expr(1, left, Inferred:Parser:parse_expr_mode(self, 5)) }
            else if Inferred:Parser:match_ch(self, cast(u8, 45)) { left = Inferred:op_expr(2, left, Inferred:Parser:parse_expr_mode(self, 5)) }
            else { more = 0 }
        }
        return left
    }
    if mode == 3 {
        var left = Inferred:Parser:parse_expr_mode(self, 4); if !left { return left }
        if Inferred:Parser:match_pair(self, cast(u8, 60), cast(u8, 61)) { return Inferred:op_expr(8, left, Inferred:Parser:parse_expr_mode(self, 4)) }
        if Inferred:Parser:match_pair(self, cast(u8, 62), cast(u8, 61)) { return Inferred:op_expr(9, left, Inferred:Parser:parse_expr_mode(self, 4)) }
        if Inferred:Parser:match_ch(self, cast(u8, 60)) { return Inferred:op_expr(6, left, Inferred:Parser:parse_expr_mode(self, 4)) }
        if Inferred:Parser:match_ch(self, cast(u8, 62)) { return Inferred:op_expr(7, left, Inferred:Parser:parse_expr_mode(self, 4)) }
        return left
    }
    if mode == 2 {
        var left = Inferred:Parser:parse_expr_mode(self, 3); if !left { return left }
        if Inferred:Parser:match_pair(self, cast(u8, 61), cast(u8, 61)) { return Inferred:op_expr(10, left, Inferred:Parser:parse_expr_mode(self, 3)) }
        if Inferred:Parser:match_pair(self, cast(u8, 33), cast(u8, 61)) { return Inferred:op_expr(11, left, Inferred:Parser:parse_expr_mode(self, 3)) }
        return left
    }
    if mode == 1 {
        var left = Inferred:Parser:parse_expr_mode(self, 2); if !left { return left }
        while Inferred:Parser:match_pair(self, cast(u8, 38), cast(u8, 38)) { left = Inferred:op_expr(12, left, Inferred:Parser:parse_expr_mode(self, 2)) }
        return left
    }
    var left = Inferred:Parser:parse_expr_mode(self, 1); if !left { return left }
    while Inferred:Parser:match_pair(self, cast(u8, 124), cast(u8, 124)) { left = Inferred:op_expr(13, left, Inferred:Parser:parse_expr_mode(self, 1)) }
    return left
}

let Inferred:Parser:parse_expr = fn (self:Inferred:Parser*) -> Inferred:Expr* { return Inferred:Parser:parse_expr_mode(self, 0) }
let Inferred:Parser:consume_semicolon = fn (self:Inferred:Parser*) -> void { let ignored = Inferred:Parser:match_ch(self, cast(u8, 59)) }

let Inferred:Parser:parse_statement_mode = fn (self:Inferred:Parser*, mode:i64) -> Inferred:Stmt* {
    if mode == 1 {
        if !Inferred:Parser:match_ch(self, cast(u8, 123)) { Inferred:Parser:fail(self, "Inferred: expected '{'"); return cast(Inferred:Stmt*, 0) }
        var head = cast(Inferred:Stmt*, 0); var tail = cast(Inferred:Stmt*, 0); var done = 0
        while !done {
            Inferred:Parser:skip(self)
            if Inferred:Parser:match_ch(self, cast(u8, 125)) { done = 1 }
            else if self.position >= self.length { Inferred:Parser:fail(self, "Inferred: unterminated block"); return cast(Inferred:Stmt*, 0) }
            else {
                let item = Inferred:Parser:parse_statement_mode(self, 0); if !item { return cast(Inferred:Stmt*, 0) }
                if tail { tail.next = item } else { head = item }; tail = item
            }
        }
        return head
    }

    Inferred:Parser:skip(self)
    if Inferred:Parser:keyword(self, "return") {
        let s = Inferred:Stmt:new(4); if !s { return s }
        s.expr = Inferred:Parser:parse_expr(self); Inferred:Parser:consume_semicolon(self); return s
    }
    if Inferred:Parser:keyword(self, "if") {
        let s = Inferred:Stmt:new(5); if !s { return s }
        s.expr = Inferred:Parser:parse_expr(self); s.body = Inferred:Parser:parse_statement_mode(self, 1)
        let saved = self.position
        if Inferred:Parser:keyword(self, "else") { s.else_body = Inferred:Parser:parse_statement_mode(self, 1) } else { self.position = saved }
        return s
    }
    if Inferred:Parser:keyword(self, "let") || Inferred:Parser:keyword(self, "var") {
        let name = Inferred:Parser:identifier(self)
        if !name { Inferred:Parser:fail(self, "Inferred: declaration expects a variable name"); return cast(Inferred:Stmt*, 0) }
        if !Inferred:Parser:match_text(self, "=") { Inferred:Parser:fail(self, "Inferred: declaration expects '='"); return cast(Inferred:Stmt*, 0) }
        let st = Inferred:Stmt:new(2); st.name = name; st.symbol = Inferred:category(self.state, "Variables", name)
        st.expr = Inferred:Parser:parse_expr(self); Inferred:Parser:consume_semicolon(self); return st
    }

    let saved = self.position
    let name = Inferred:Parser:identifier(self)
    if name {
        if Inferred:Parser:match_text(self, "=") {
            let st = Inferred:Stmt:new(6); st.name = name; st.symbol = Inferred:category(self.state, "Variables", name)
            st.expr = Inferred:Parser:parse_expr(self); Inferred:Parser:consume_semicolon(self); return st
        }
        free(name); self.position = saved
    }
    let st = Inferred:Stmt:new(3); st.expr = Inferred:Parser:parse_expr(self); Inferred:Parser:consume_semicolon(self); return st
}

let Inferred:Parser:parse_block = fn (self:Inferred:Parser*) -> Inferred:Stmt* { return Inferred:Parser:parse_statement_mode(self, 1) }

let Inferred:parse_function = fn (state:Context*, source:u8*) -> Inferred:Function* {
    let p = Inferred:Parser:new(state, source); if !p { return cast(Inferred:Function*, 0) }; defer free(cast(u8*, p))
    let had_poly = Inferred:Parser:keyword(p, "poly")
    if !Inferred:Parser:keyword(p, "fn") { Inferred:Parser:fail(p, "Inferred: function expects 'fn'"); return cast(Inferred:Function*, 0) }
    let name = Inferred:Parser:identifier(p); if !name { Inferred:Parser:fail(p, "Inferred: function expects a name"); return cast(Inferred:Function*, 0) }
    if !Inferred:Parser:match_ch(p, cast(u8, 40)) { Inferred:Parser:fail(p, "Inferred: function expects '('"); return cast(Inferred:Function*, 0) }
    var cap = 4; var count = 0; var params = cast(u8**, malloc(cap * 8)); var symbols = cast(i64*, malloc(cap * 8))
    if !Inferred:Parser:match_ch(p, cast(u8, 41)) {
        var more = 1
        while more {
            let param = Inferred:Parser:identifier(p); if !param { Inferred:Parser:fail(p, "Inferred: parameter expects a name"); return cast(Inferred:Function*, 0) }
            if count == cap { cap *= 2; params = cast(u8**, realloc(cast(u8*, params), cap * 8)); symbols = cast(i64*, realloc(cast(u8*, symbols), cap * 8)) }
            params[count] = param; symbols[count] = Inferred:category(state, "Variables", param); count += 1
            if Inferred:Parser:match_ch(p, cast(u8, 44)) { } else { more = 0 }
        }
        if !Inferred:Parser:match_ch(p, cast(u8, 41)) { Inferred:Parser:fail(p, "Inferred: expected ')' after parameters"); return cast(Inferred:Function*, 0) }
    }
    let body = Inferred:Parser:parse_block(p); if !body && p.error { return cast(Inferred:Function*, 0) }
    let f = cast(Inferred:Function*, malloc(80)); if !f { return cast(Inferred:Function*, 0) }
    f.name = name; f.symbol = Inferred:category(state, "Functions", name); Inferred:category(state, "Grammar", name)
    f.arity = count; f.params = params; f.param_symbols = symbols; f.body = body
    f.specializations = cast(Inferred:Specialization*, 0); f.specialization_tail = cast(Inferred:Specialization*, 0)
    f.specialization_count = 0; f.next = cast(Inferred:Function*, 0)
    return f
}

let Inferred:Env:find = fn (env:Inferred:Env*, symbol:i64) -> LanguageKit:Value* {
    var e = env; while e { if e.symbol == symbol { return e.value }; e = e.next }; return cast(LanguageKit:Value*, 0)
}

let Inferred:Env:set = fn (env:Inferred:Env*, symbol:i64, value:LanguageKit:Value*) -> Inferred:Env* {
    var e = env; while e { if e.symbol == symbol { e.value = value; return env }; e = e.next }
    let n = cast(Inferred:Env*, malloc(24)); if !n { return env }; n.symbol = symbol; n.value = value; n.next = env; return n
}

let Inferred:TypeEnv:find = fn (env:Inferred:TypeEnv*, symbol:i64) -> i64 {
    var e = env; while e { if e.symbol == symbol { return e.kind }; e = e.next }; return 0
}

let Inferred:TypeEnv:set = fn (env:Inferred:TypeEnv*, symbol:i64, kind:i64) -> Inferred:TypeEnv* {
    var e = env; while e { if e.symbol == symbol { e.kind = kind; return env }; e = e.next }
    let n = cast(Inferred:TypeEnv*, malloc(24)); if !n { return env }; n.symbol = symbol; n.kind = kind; n.next = env; return n
}

let Inferred:clone_expr = fn (state:Context*, expr:Inferred:Expr*, types:Inferred:TypeEnv*) -> Inferred:Expr* {
    if !expr { return cast(Inferred:Expr*, 0) }
    let out = Inferred:Expr:new(expr.kind); if !out { return out }
    out.op = expr.op; out.number = expr.number; out.text = expr.text; out.symbol = expr.symbol; out.argc = expr.argc
    if expr.kind == 1 { out.inferred_kind = 1; return out }
    if expr.kind == 3 { out.inferred_kind = 2; return out }
    if expr.kind == 2 { out.inferred_kind = Inferred:TypeEnv:find(types, expr.symbol); return out }
    if expr.kind == 4 {
        if expr.argc > 0 {
            out.args = cast(Inferred:Expr**, malloc(expr.argc * 8)); var i = 0
            while i < expr.argc { out.args[i] = Inferred:clone_expr(state, expr.args[i], types); i += 1 }
        }
        out.inferred_kind = 0; return out
    }
    if expr.kind == 6 {
        out.right = Inferred:clone_expr(state, expr.right, types); out.inferred_kind = 1; return out
    }
    if expr.kind == 5 {
        out.left = Inferred:clone_expr(state, expr.left, types); out.right = Inferred:clone_expr(state, expr.right, types)
        let lk = out.left.inferred_kind; let rk = out.right.inferred_kind
        if out.op == 1 && lk == 2 && rk == 2 { out.op = 14; out.inferred_kind = 2; return out }
        if out.op >= 6 { out.inferred_kind = 1; return out }
        if lk == 1 && rk == 1 { out.inferred_kind = 1 }
        return out
    }
    return out
}

let Inferred:clone_block = fn (state:Context*, stmt:Inferred:Stmt*, types:Inferred:TypeEnv*) -> Inferred:Stmt* {
    var source = stmt; var head = cast(Inferred:Stmt*, 0); var tail = cast(Inferred:Stmt*, 0); var local_types = types
    while source {
        let out = Inferred:Stmt:new(source.kind); if !out { return head }
        out.name = source.name; out.symbol = source.symbol
        if source.expr { out.expr = Inferred:clone_expr(state, source.expr, local_types) }
        if (source.kind == 2 || source.kind == 6) && out.expr && out.expr.inferred_kind != 0 { local_types = Inferred:TypeEnv:set(local_types, out.symbol, out.expr.inferred_kind) }
        if source.body { out.body = Inferred:clone_block(state, source.body, local_types) }
        if source.else_body { out.else_body = Inferred:clone_block(state, source.else_body, local_types) }
        if tail { tail.next = out } else { head = out }; tail = out
        source = source.next
    }
    return head
}

let Inferred:signature_equal = fn (spec:Inferred:Specialization*, args:LanguageKit:Value**, argc:i64) -> i64 {
    if !spec || spec.arity != argc { return 0 }
    var i = 0
    while i < argc { if !args[i] || spec.kinds[i] != args[i].kind { return 0 }; i += 1 }
    return 1
}

let Inferred:find_specialization = fn (f:Inferred:Function*, args:LanguageKit:Value**, argc:i64) -> Inferred:Specialization* {
    var spec = f.specializations
    while spec { if Inferred:signature_equal(spec, args, argc) { return spec }; spec = spec.next }
    return cast(Inferred:Specialization*, 0)
}

let Inferred:concat_values = fn (state:Context*, left:u8*, right:u8*) -> LanguageKit:Value* {
    let a = cast(i64, strlen(left)); let b = cast(i64, strlen(right)); let out = cast(u8*, malloc(a + b + 1))
    if !out { return cast(LanguageKit:Value*, 0) }
    memcpy(out, left, a); memcpy(&out[a], right, b); out[a + b] = 0
    let value = LanguageKit:Value:text_value(state, out); free(out); return value
}

// Native runtime helpers used by generated specializations. These helpers are
// ordinary compiled RecurLoop functions; the generated specialization contains
// control flow and direct helper calls, never an AST interpreter loop.
let Inferred:native_truth = fn (value:LanguageKit:Value*) -> i64 {
    return value && ((value.kind == 1 && value.number != 0) || (value.kind == 2 && value.text && value.text[0] != 0))
}

let Inferred:native_not = fn (state:Context*, value:LanguageKit:Value*) -> LanguageKit:Value* {
    if !value || value.kind != 1 { return cast(LanguageKit:Value*, 0) }
    return LanguageKit:Value:integer(state, value.number == 0)
}

let Inferred:native_negate = fn (state:Context*, value:LanguageKit:Value*) -> LanguageKit:Value* {
    if !value || value.kind != 1 { return cast(LanguageKit:Value*, 0) }
    return LanguageKit:Value:integer(state, -value.number)
}

let Inferred:native_integer_binary = fn (state:Context*, op:i64, left:LanguageKit:Value*, right:LanguageKit:Value*) -> LanguageKit:Value* {
    if !left || !right || left.kind != 1 || right.kind != 1 { return cast(LanguageKit:Value*, 0) }
    if op == 1 { return LanguageKit:Value:integer(state, left.number + right.number) }
    if op == 2 { return LanguageKit:Value:integer(state, left.number - right.number) }
    if op == 3 { return LanguageKit:Value:integer(state, left.number * right.number) }
    if op == 4 { if right.number == 0 { return cast(LanguageKit:Value*, 0) }; return LanguageKit:Value:integer(state, left.number / right.number) }
    if op == 5 { if right.number == 0 { return cast(LanguageKit:Value*, 0) }; return LanguageKit:Value:integer(state, left.number % right.number) }
    if op == 6 { return LanguageKit:Value:integer(state, left.number < right.number) }
    if op == 7 { return LanguageKit:Value:integer(state, left.number > right.number) }
    if op == 8 { return LanguageKit:Value:integer(state, left.number <= right.number) }
    if op == 9 { return LanguageKit:Value:integer(state, left.number >= right.number) }
    if op == 10 { return LanguageKit:Value:integer(state, left.number == right.number) }
    if op == 11 { return LanguageKit:Value:integer(state, left.number != right.number) }
    if op == 12 { return LanguageKit:Value:integer(state, left.number != 0 && right.number != 0) }
    if op == 13 { return LanguageKit:Value:integer(state, left.number != 0 || right.number != 0) }
    return cast(LanguageKit:Value*, 0)
}

let Inferred:native_binary = fn (state:Context*, op:i64, left:LanguageKit:Value*, right:LanguageKit:Value*) -> LanguageKit:Value* {
    if !left || !right { return cast(LanguageKit:Value*, 0) }
    if op == 1 && left.kind == 2 && right.kind == 2 { return Inferred:concat_values(state, left.text, right.text) }
    if op == 10 {
        if left.kind == 1 && right.kind == 1 { return LanguageKit:Value:integer(state, left.number == right.number) }
        if left.kind == 2 && right.kind == 2 { return LanguageKit:Value:integer(state, strcmp(left.text, right.text) == 0) }
        return LanguageKit:Value:integer(state, 0)
    }
    if op == 11 {
        if left.kind == 1 && right.kind == 1 { return LanguageKit:Value:integer(state, left.number != right.number) }
        if left.kind == 2 && right.kind == 2 { return LanguageKit:Value:integer(state, strcmp(left.text, right.text) != 0) }
        return LanguageKit:Value:integer(state, 1)
    }
    return Inferred:native_integer_binary(state, op, left, right)
}

let Inferred:native_invoke0 = fn (state:Context*, name:u8*) -> LanguageKit:Value* {
    return LanguageKit:invoke(state, name, cast(LanguageKit:Value**, 0), 0)
}
let Inferred:native_invoke1 = fn (state:Context*, name:u8*, a0:LanguageKit:Value*) -> LanguageKit:Value* {
    let args = cast(LanguageKit:Value**, malloc(8)); if !args { return cast(LanguageKit:Value*, 0) }
    args[0] = a0; let result = LanguageKit:invoke(state, name, args, 1); free(cast(u8*, args)); return result
}
let Inferred:native_invoke2 = fn (state:Context*, name:u8*, a0:LanguageKit:Value*, a1:LanguageKit:Value*) -> LanguageKit:Value* {
    let args = cast(LanguageKit:Value**, malloc(16)); if !args { return cast(LanguageKit:Value*, 0) }
    args[0] = a0; args[1] = a1; let result = LanguageKit:invoke(state, name, args, 2); free(cast(u8*, args)); return result
}
let Inferred:native_invoke3 = fn (state:Context*, name:u8*, a0:LanguageKit:Value*, a1:LanguageKit:Value*, a2:LanguageKit:Value*) -> LanguageKit:Value* {
    let args = cast(LanguageKit:Value**, malloc(24)); if !args { return cast(LanguageKit:Value*, 0) }
    args[0] = a0; args[1] = a1; args[2] = a2; let result = LanguageKit:invoke(state, name, args, 3); free(cast(u8*, args)); return result
}
let Inferred:native_invoke4 = fn (state:Context*, name:u8*, a0:LanguageKit:Value*, a1:LanguageKit:Value*, a2:LanguageKit:Value*, a3:LanguageKit:Value*) -> LanguageKit:Value* {
    let args = cast(LanguageKit:Value**, malloc(32)); if !args { return cast(LanguageKit:Value*, 0) }
    args[0] = a0; args[1] = a1; args[2] = a2; args[3] = a3; let result = LanguageKit:invoke(state, name, args, 4); free(cast(u8*, args)); return result
}
let Inferred:native_invoke5 = fn (state:Context*, name:u8*, a0:LanguageKit:Value*, a1:LanguageKit:Value*, a2:LanguageKit:Value*, a3:LanguageKit:Value*, a4:LanguageKit:Value*) -> LanguageKit:Value* {
    let args = cast(LanguageKit:Value**, malloc(40)); if !args { return cast(LanguageKit:Value*, 0) }
    args[0] = a0; args[1] = a1; args[2] = a2; args[3] = a3; args[4] = a4; let result = LanguageKit:invoke(state, name, args, 5); free(cast(u8*, args)); return result
}
let Inferred:native_invoke6 = fn (state:Context*, name:u8*, a0:LanguageKit:Value*, a1:LanguageKit:Value*, a2:LanguageKit:Value*, a3:LanguageKit:Value*, a4:LanguageKit:Value*, a5:LanguageKit:Value*) -> LanguageKit:Value* {
    let args = cast(LanguageKit:Value**, malloc(48)); if !args { return cast(LanguageKit:Value*, 0) }
    args[0] = a0; args[1] = a1; args[2] = a2; args[3] = a3; args[4] = a4; args[5] = a5
    let result = LanguageKit:invoke(state, name, args, 6); free(cast(u8*, args)); return result
}

let Inferred:append_integer = fn (out:LanguageKit:Text*, value:i64) -> i64 {
    if value == 0 { return out.append_byte(cast(u8, 48)) }
    var n = value
    if n < 0 { if !out.append_byte(cast(u8, 45)) { return 0 }; n = -n }
    let digits = cast(u8*, malloc(32)); if !digits { return 0 }
    var count = 0
    while n > 0 { digits[count] = cast(u8, 48 + (n % 10)); count += 1; n /= 10 }
    var i = count
    while i > 0 { i -= 1; if !out.append_byte(digits[i]) { free(digits); return 0 } }
    free(digits); return 1
}

let Inferred:append_quoted = fn (out:LanguageKit:Text*, text:u8*) -> i64 {
    if !out.append_byte(cast(u8, 34)) { return 0 }
    var i = 0
    while text && text[i] != 0 {
        let ch = text[i]
        if ch == 34 || ch == 92 { if !out.append_byte(cast(u8, 92)) || !out.append_byte(ch) { return 0 } }
        else if ch == 10 { if !out.append("\\n") { return 0 } }
        else if ch == 9 { if !out.append("\\t") { return 0 } }
        else if ch == 13 { if !out.append("\\r") { return 0 } }
        else if !out.append_byte(ch) { return 0 }
        i += 1
    }
    return out.append_byte(cast(u8, 34))
}

let Inferred:codegen_expr = fn (state:Context*, out:LanguageKit:Text*, expr:Inferred:Expr*) -> i64 {
    if !expr { context:diagnostic:error(state, "Inferred: native codegen received an empty expression"); return 0 }
    if expr.kind == 1 {
        if !out.append("LanguageKit:Value:integer(__state, ") { return 0 }
        if !Inferred:append_integer(out, expr.number) { return 0 }
        return out.append_byte(cast(u8, 41))
    }
    if expr.kind == 3 {
        if !out.append("LanguageKit:Value:text_value(__state, ") { return 0 }
        if !Inferred:append_quoted(out, expr.text) { return 0 }
        return out.append_byte(cast(u8, 41))
    }
    if expr.kind == 2 {
        if expr.inferred_kind != 0 { return out.append(expr.text) }
        if !out.append("LanguageKit:value(__state, ") { return 0 }
        if !Inferred:append_quoted(out, expr.text) { return 0 }
        return out.append_byte(cast(u8, 41))
    }
    if expr.kind == 4 {
        if expr.argc < 0 || expr.argc > 6 { context:diagnostic:error(state, "Inferred: native calls currently support at most six arguments"); return 0 }
        if !out.append("Inferred:native_invoke") { return 0 }
        if !Inferred:append_integer(out, expr.argc) { return 0 }
        if !out.append("(__state, ") { return 0 }
        if !Inferred:append_quoted(out, expr.text) { return 0 }
        var i = 0
        while i < expr.argc {
            if !out.append(", ") { return 0 }
            if !Inferred:codegen_expr(state, out, expr.args[i]) { return 0 }
            i += 1
        }
        return out.append_byte(cast(u8, 41))
    }
    if expr.kind == 6 {
        if expr.op == 1 {
            if !out.append("Inferred:native_not(__state, ") { return 0 }
        } else {
            if !out.append("Inferred:native_negate(__state, ") { return 0 }
        }
        if !Inferred:codegen_expr(state, out, expr.right) { return 0 }
        return out.append_byte(cast(u8, 41))
    }
    if expr.kind == 5 {
        if expr.op == 14 {
            if !out.append("Inferred:concat_values(__state, (") { return 0 }
            if !Inferred:codegen_expr(state, out, expr.left) { return 0 }
            if !out.append(").text, (") { return 0 }
            if !Inferred:codegen_expr(state, out, expr.right) { return 0 }
            if !out.append(").text)") { return 0 }
            return 1
        }
        if expr.left && expr.right && expr.left.inferred_kind == 1 && expr.right.inferred_kind == 1 {
            if !out.append("Inferred:native_integer_binary(__state, ") { return 0 }
            if !Inferred:append_integer(out, expr.op) { return 0 }
            if !out.append(", ") { return 0 }
            if !Inferred:codegen_expr(state, out, expr.left) { return 0 }
            if !out.append(", ") { return 0 }
            if !Inferred:codegen_expr(state, out, expr.right) { return 0 }
            out.append_byte(cast(u8, 41))
            return 1
        }
        if !out.append("Inferred:native_binary(__state, ") { return 0 }
        if !Inferred:append_integer(out, expr.op) { return 0 }
        if !out.append(", ") { return 0 }
        if !Inferred:codegen_expr(state, out, expr.left) { return 0 }
        if !out.append(", ") { return 0 }
        if !Inferred:codegen_expr(state, out, expr.right) { return 0 }
        out.append_byte(cast(u8, 41))
        return 1
    }
    context:diagnostic:error(state, "Inferred: native codegen encountered an unsupported expression")
    return 0
}

let Inferred:codegen_block = fn (state:Context*, out:LanguageKit:Text*, stmt:Inferred:Stmt*) -> i64 {
    var current = stmt
    while current {
        if current.kind == 2 {
            if !out.append("var ") { return 0 }
            if !out.append(current.name) { return 0 }
            if !out.append(":LanguageKit:Value* = ") { return 0 }
            if !Inferred:codegen_expr(state, out, current.expr) { return 0 }
            if !out.append("\n") { return 0 }
        } else if current.kind == 6 {
            if !out.append(current.name) { return 0 }
            if !out.append(" = ") { return 0 }
            if !Inferred:codegen_expr(state, out, current.expr) { return 0 }
            if !out.append("\n") { return 0 }
        } else if current.kind == 3 {
            if !Inferred:codegen_expr(state, out, current.expr) { return 0 }
            if !out.append("\n") { return 0 }
        } else if current.kind == 4 {
            if !out.append("return ") { return 0 }
            if !Inferred:codegen_expr(state, out, current.expr) { return 0 }
            if !out.append("\n") { return 0 }
        } else if current.kind == 5 {
            if !out.append("if Inferred:native_truth(") { return 0 }
            if !Inferred:codegen_expr(state, out, current.expr) { return 0 }
            if !out.append(") {\n") { return 0 }
            if !Inferred:codegen_block(state, out, current.body) { return 0 }
            if !out.append("}\n") { return 0 }
            if current.else_body {
                if !out.append("else {\n") { return 0 }
                if !Inferred:codegen_block(state, out, current.else_body) { return 0 }
                if !out.append("}\n") { return 0 }
            }
        } else {
            context:diagnostic:error(state, "Inferred: native codegen encountered an unsupported statement")
            return 0
        }
        current = current.next
    }
    return 1
}

let Inferred:native_symbol = fn (f:Inferred:Function*, args:LanguageKit:Value**, argc:i64) -> u8* {
    let out = LanguageKit:Text:new(); if !out { return cast(u8*, 0) }
    out.append("__inferred_native_"); Inferred:append_integer(out, f.symbol)
    var i = 0
    while i < argc { out.append("_"); Inferred:append_integer(out, args[i].kind); i += 1 }
    let text = out.take(); out.destroy(); return text
}

let Inferred:compile_specialization = fn (state:Context*, f:Inferred:Function*, spec:Inferred:Specialization*, typed_body:Inferred:Stmt*) -> i64 {
    let body = LanguageKit:Text:new(); if !body { return 0 }
    body.append("if __argc != "); Inferred:append_integer(body, f.arity); body.append(" { return cast(LanguageKit:Value*, 0) }\n")
    var i = 0
    while i < f.arity {
        body.append("if !__args["); Inferred:append_integer(body, i); body.append("] || __args["); Inferred:append_integer(body, i); body.append("].kind != "); Inferred:append_integer(body, spec.kinds[i]); body.append(" { return cast(LanguageKit:Value*, 0) }\n")
        body.append("var "); body.append(f.params[i]); body.append(":LanguageKit:Value* = __args["); Inferred:append_integer(body, i); body.append("]\n")
        i += 1
    }
    if !Inferred:codegen_block(state, body, typed_body) { body.destroy(); return 0 }
    body.append("return LanguageKit:Value:integer(__state, 0)\n")
    let source = body.take(); body.destroy(); if !source { return 0 }
    let signature = "(__state:Context*, __userdata:i64, __args:LanguageKit:Value**, __argc:i64) -> LanguageKit:Value*"
    let entry = context:function:compile(state, signature, source, spec.compiled_symbol)
    free(source)
    if entry == 0 { context:diagnostic:error(state, "Inferred: native specialization compilation failed"); return 0 }
    spec.native_entry = entry
    return 1
}

let Inferred:create_specialization = fn (state:Context*, f:Inferred:Function*, args:LanguageKit:Value**, argc:i64) -> Inferred:Specialization* {
    let spec = cast(Inferred:Specialization*, malloc(64)); if !spec { return cast(Inferred:Specialization*, 0) }
    spec.arity = argc; spec.kinds = cast(i64*, malloc(argc * 8)); spec.result_kind = 0
    spec.native_entry = 0; spec.compiled_symbol = Inferred:native_symbol(f, args, argc)
    spec.hits = 0; spec.state = 1; spec.next = cast(Inferred:Specialization*, 0)
    var types = cast(Inferred:TypeEnv*, 0); var i = 0
    while i < argc { spec.kinds[i] = args[i].kind; types = Inferred:TypeEnv:set(types, f.param_symbols[i], args[i].kind); i += 1 }
    if f.specialization_tail { f.specialization_tail.next = spec } else { f.specializations = spec }
    f.specialization_tail = spec; f.specialization_count += 1
    let typed_body = Inferred:clone_block(state, f.body, types)
    if !typed_body || !spec.compiled_symbol || !Inferred:compile_specialization(state, f, spec, typed_body) { return cast(Inferred:Specialization*, 0) }
    spec.state = 2
    return spec
}

let Inferred:interop_call = fn (state:Context*, userdata:i64, args:LanguageKit:Value**, argc:i64) -> LanguageKit:Value* {
    let f = Inferred:find_function(Inferred:database(state), userdata)
    if !f || argc != f.arity { context:diagnostic:error(state, "Inferred: function arity mismatch"); return cast(LanguageKit:Value*, 0) }
    var spec = Inferred:find_specialization(f, args, argc)
    if !spec { spec = Inferred:create_specialization(state, f, args, argc) }
    if !spec || spec.state != 2 || spec.native_entry == 0 { context:diagnostic:error(state, "Inferred: native specialization could not be materialized"); return cast(LanguageKit:Value*, 0) }
    spec.hits += 1
    let call = cast(LanguageKit:Call, spec.native_entry)
    let result = call(state, userdata, args, argc)
    if !result { context:diagnostic:error(state, "Inferred: native specialization returned no value"); return cast(LanguageKit:Value*, 0) }
    if spec.result_kind == 0 { spec.result_kind = result.kind }
    else if spec.result_kind != result.kind { context:diagnostic:error(state, "Inferred: specialization changed result kind"); return cast(LanguageKit:Value*, 0) }
    return result
}

let Inferred:compile_top_expression = fn (state:Context*, expr:Inferred:Expr*) -> LanguageKit:Value* {
    let typed = Inferred:clone_expr(state, expr, cast(Inferred:TypeEnv*, 0)); if !typed { return cast(LanguageKit:Value*, 0) }
    let body = LanguageKit:Text:new(); if !body { return cast(LanguageKit:Value*, 0) }
    body.append("return "); if !Inferred:codegen_expr(state, body, typed) { body.destroy(); return cast(LanguageKit:Value*, 0) }; body.append("\n")
    let source = body.take(); body.destroy(); if !source { return cast(LanguageKit:Value*, 0) }
    let id = LanguageKit:state_get(state, "__inferred_native_expression_id") + 1; LanguageKit:state_set(state, "__inferred_native_expression_id", id)
    let symbol_builder = LanguageKit:Text:new(); if !symbol_builder { free(source); return cast(LanguageKit:Value*, 0) }
    symbol_builder.append("__inferred_expression_"); Inferred:append_integer(symbol_builder, id)
    let symbol = symbol_builder.take(); symbol_builder.destroy()
    let signature = "(__state:Context*, __userdata:i64, __args:LanguageKit:Value**, __argc:i64) -> LanguageKit:Value*"
    let entry = context:function:compile(state, signature, source, symbol)
    free(source); free(symbol)
    if entry == 0 { return cast(LanguageKit:Value*, 0) }
    let call = cast(LanguageKit:Call, entry)
    return call(state, 0, cast(LanguageKit:Value**, 0), 0)
}

let Inferred:native_scalar_append_integer = fn (out:LanguageKit:Text*, value:i64) -> i64 {
    if value == 0 { return out.append_byte(cast(u8, 48)) }
    var n = value
    if n < 0 { if !out.append_byte(cast(u8, 45)) { return 0 }; n = -n }
    let digits = cast(u8*, malloc(32)); if !digits { return 0 }
    var count = 0
    while n > 0 { digits[count] = cast(u8, 48 + (n % 10)); count += 1; n /= 10 }
    var i = count
    while i > 0 { i -= 1; if !out.append_byte(digits[i]) { free(digits); return 0 } }
    free(digits); return 1
}

let Inferred:native_scalar_expr = fn (state:Context*, out:LanguageKit:Text*, expr:Inferred:Expr*) -> i64 {
    if !expr { return 0 }
    if expr.kind == 1 { return Inferred:native_scalar_append_integer(out, expr.number) }
    if expr.kind == 2 { return out.append(expr.text) }
    if expr.kind == 4 {
        if !out.append(expr.text) || !out.append_byte(cast(u8, 40)) { return 0 }
        var i = 0
        while i < expr.argc {
            if i > 0 && !out.append(", ") { return 0 }
            if !Inferred:native_scalar_expr(state, out, expr.args[i]) { return 0 }
            i += 1
        }
        let closed = out.append_byte(cast(u8, 41))
        if !closed { return 0 }
        return 1
    }
    if expr.kind == 6 {
        if expr.op == 1 { if !out.append("(!") { return 0 } } else { if !out.append("(-") { return 0 } }
        if !Inferred:native_scalar_expr(state, out, expr.right) { return 0 }
        let closed = out.append_byte(cast(u8, 41))
        if !closed { return 0 }
        return 1
    }
    if expr.kind == 5 {
        if !out.append_byte(cast(u8, 40)) || !Inferred:native_scalar_expr(state, out, expr.left) { return 0 }
        if expr.op == 1 { if !out.append(" + ") { return 0 } }
        else if expr.op == 2 { if !out.append(" - ") { return 0 } }
        else if expr.op == 3 { if !out.append(" * ") { return 0 } }
        else if expr.op == 4 { if !out.append(" / ") { return 0 } }
        else if expr.op == 5 { if !out.append(" % ") { return 0 } }
        else if expr.op == 6 { if !out.append(" < ") { return 0 } }
        else if expr.op == 7 { if !out.append(" > ") { return 0 } }
        else if expr.op == 8 { if !out.append(" <= ") { return 0 } }
        else if expr.op == 9 { if !out.append(" >= ") { return 0 } }
        else if expr.op == 10 { if !out.append(" == ") { return 0 } }
        else if expr.op == 11 { if !out.append(" != ") { return 0 } }
        else if expr.op == 12 { if !out.append(" && ") { return 0 } }
        else if expr.op == 13 { if !out.append(" || ") { return 0 } }
        else { return 0 }
        if !Inferred:native_scalar_expr(state, out, expr.right) { return 0 }
        let closed = out.append_byte(cast(u8, 41))
        if !closed { return 0 }
        return 1
    }
    return 0
}

let Inferred:compile_native_scalar = fn (state:Context*, f:Inferred:Function*) -> i64 {
    if !f || !f.body || f.body.next || f.body.kind != 4 || !f.body.expr { return 0 }
    let signature = LanguageKit:Text:new(); let body = LanguageKit:Text:new()
    if !signature || !body { return 0 }
    if !signature.append_byte(cast(u8, 40)) { return 0 }
    var i = 0
    while i < f.arity {
        if i > 0 && !signature.append(", ") { return 0 }
        if !signature.append(f.params[i]) || !signature.append(":i64") { return 0 }
        i += 1
    }
    if !signature.append(") -> i64") || !body.append("return ") { return 0 }
    if !Inferred:native_scalar_expr(state, body, f.body.expr) || !body.append("\n") { return 0 }
    let sig_text = signature.take(); let body_text = body.take(); signature.destroy(); body.destroy()
    if !sig_text || !body_text { return 0 }
    let entry = context:function:compile(state, sig_text, body_text, f.name)
    free(sig_text); free(body_text)
    return entry != 0
}

let Inferred:add_function = fn (state:Context*, f:Inferred:Function*) -> i64 {
    let db = Inferred:database(state)
    if db.tail { db.tail.next = f } else { db.functions = f }; db.tail = f
    let native_scalar = Inferred:compile_native_scalar(state, f)
    LanguageKit:publish_callable(state, f.name, f.arity, Inferred:interop_call, f.symbol)
    return 1
}

let Inferred:kind_name = fn (kind:i64) -> u8* {
    if kind == 1 { return "integer" }
    if kind == 2 { return "text" }
    if kind == 3 { return "symbol" }
    if kind == 4 { return "list" }
    if kind == 5 { return "tuple" }
    if kind == 6 { return "opaque" }
    return "dynamic"
}

let Inferred:print_value = fn (value:LanguageKit:Value*) -> void {
    if !value { printf("<nil>"); return }
    if value.kind == 1 { printf("%lld", value.number); return }
    if value.kind == 2 && value.text { printf("%s", value.text); return }
    if value.kind == 3 && value.text { printf("%s", value.text); return }
    printf("<value>")
}

let Inferred:print_specializations = fn (state:Context*, name:u8*) -> void {
    let symbol = LanguageKit:intern(state, name); let f = Inferred:find_function(Inferred:database(state), symbol)
    if !f { context:diagnostic:error(state, "Inferred: unknown function for specialization report"); return }
    printf("%s specializations=%lld\n", f.name, f.specialization_count)
    var spec = f.specializations
    while spec {
        printf("  (")
        var i = 0
        while i < spec.arity { if i > 0 { printf(",") }; printf("%s", Inferred:kind_name(spec.kinds[i])); i += 1 }
        printf(") -> %s hits=%lld compiled=%lld\n", Inferred:kind_name(spec.result_kind), spec.hits, spec.native_entry != 0)
        spec = spec.next
    }
}

let Inferred:balanced_extent = fn (state:Context*, open_at:i64) -> i64 {
    var i = open_at; var depth = 0; var quote:u8 = 0; var escaped = 0; var line_comment = 0
    while 1 {
        let ch = LanguageKit:Source:peek(state, i); if ch == 0 { return 0 }
        let next = LanguageKit:Source:peek(state, i + 1)
        if line_comment { if ch == 10 || ch == 13 { line_comment = 0 }; i += 1 }
        else if quote {
            if escaped { escaped = 0; i += 1 } else if ch == 92 { escaped = 1; i += 1 } else if ch == quote { quote = 0; i += 1 } else { i += 1 }
        } else if ch == 34 || ch == 39 { quote = ch; i += 1 }
        else if ch == 47 && next == 47 { line_comment = 1; i += 2 }
        else if ch == 123 { depth += 1; i += 1 }
        else if ch == 125 { depth -= 1; i += 1; if depth == 0 { return i } }
        else { i += 1 }
    }
    return 0
}

let Inferred:starts_word_at = fn (state:Context*, offset:i64, text:u8*) -> i64 {
    if !LanguageKit:Source:starts_with_at(state, offset, text) { return 0 }
    let n = cast(i64, strlen(text)); let ch = LanguageKit:Source:peek(state, offset + n)
    return !Inferred:is_ident(ch)
}

let Inferred:accepts_form = fn (state:Context*) -> i64 {
    var i = 0; while Inferred:is_space(LanguageKit:Source:peek(state, i)) { i += 1 }
    if Inferred:starts_word_at(state, i, "poly") {
        i += 4; while Inferred:is_space(LanguageKit:Source:peek(state, i)) { i += 1 }
    }
    if Inferred:starts_word_at(state, i, "fn") {
        var open = i
        while LanguageKit:Source:peek(state, open) != 0 && LanguageKit:Source:peek(state, open) != 123 && LanguageKit:Source:peek(state, open) != 10 && LanguageKit:Source:peek(state, open) != 13 { open += 1 }
        if LanguageKit:Source:peek(state, open) != 123 { return 0 }
        return Inferred:balanced_extent(state, open)
    }
    if Inferred:starts_word_at(state, i, "print") || Inferred:starts_word_at(state, i, "specializations") {
        return LanguageKit:Source:line_extent(state)
    }
    return 0
}

let Inferred:capture_extent = fn (state:Context*, extent:i64) -> u8* {
    let out = cast(u8*, malloc(extent + 1)); if !out { return cast(u8*, 0) }
    var i = 0; while i < extent { out[i] = LanguageKit:Source:peek(state, i); i += 1 }; out[extent] = 0
    LanguageKit:Source:advance(state, extent); return out
}

let Inferred:execute_source = fn (state:Context*, source:u8*) -> void {
    let p = Inferred:Parser:new(state, source); if !p { return }; defer free(cast(u8*, p))
    let had_poly = Inferred:Parser:keyword(p, "poly")
    if Inferred:Parser:keyword(p, "fn") {
        let f = Inferred:parse_function(state, source); if f { Inferred:add_function(state, f) }
        return
    }
    if Inferred:Parser:keyword(p, "print") {
        let expr = Inferred:Parser:parse_expr(p); if !expr || p.error { return }
        let scope = LanguageKit:Lifetime:enter(state); if !scope { return }
        defer LanguageKit:Lifetime:leave(state, scope)
        let value = Inferred:compile_top_expression(state, expr); if value { Inferred:print_value(value); printf("\n") }
        return
    }
    if Inferred:Parser:keyword(p, "specializations") {
        let name = Inferred:Parser:identifier(p); if !name { Inferred:Parser:fail(p, "Inferred: specializations expects a function name"); return }
        Inferred:print_specializations(state, name); return
    }
    Inferred:Parser:fail(p, "Inferred: unsupported top-level form")
}

let Inferred:top_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let extent = Inferred:accepts_form(state)
        if extent <= 0 { context:diagnostic:error(state, "Inferred: unsupported top-level form"); LanguageKit:Source:skip_line(state); context:source:root(state); return }
        let source = Inferred:capture_extent(state, extent)
        if source { Inferred:execute_source(state, source); free(source) }
        context:source:root(state)
    }
}

let LanguageKit:Forms:Inferred = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let extent = Inferred:accepts_form(state)
        if extent > 0 {
            let root = context:phrase:find(state, "Inferred"); let form = context:phrase:find:exact(state, root, "top_form")
            var specificity = 6
            if LanguageKit:Source:starts_with(state, "poly ") { specificity = 10 }
            else if LanguageKit:Source:starts_with(state, "specializations ") { specificity = 8 }
            LanguageKit:offer_form(state, form, LanguageKit:registry_entry(state, "Forms", "Inferred"), extent, specificity)
        }
    }
}

let Inferred:assert_phrase = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let reader = LanguageKit:Reader:new(state, 8); if !reader { return }; defer LanguageKit:Reader:destroy(reader)
        let category = LanguageKit:Reader:take_identifier(reader); let name = LanguageKit:Reader:take_text(reader)
        if !category || !name { context:diagnostic:error(state, "inferred_assert expects CATEGORY NAME") }
        else {
            var owner_name = cast(u8*, 0)
            if strcmp(category, "function") == 0 { owner_name = "Functions" }
            else if strcmp(category, "variable") == 0 { owner_name = "Variables" }
            else if strcmp(category, "grammar") == 0 { owner_name = "Grammar" }
            else if strcmp(category, "symbol") == 0 { owner_name = "Symbols" }
            if !owner_name { context:diagnostic:error(state, "Inferred: unknown assertion category") }
            else {
                let root = context:phrase:find(state, "Inferred"); let owner = context:phrase:find:exact(state, root, owner_name)
                if !owner || !context:phrase:find:exact(state, owner, name) { context:diagnostic:error(state, "Inferred: expected phrase-backed symbol is missing") }
            }
        }
        if category { free(category) }; if name { free(name) }
        LanguageKit:Source:skip_line(state); context:source:root(state)
    }
}
let inferred_assert = <Inferred:assert_phrase>

let Inferred:explicit_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if LanguageKit:selector_block_present(state) { LanguageKit:execute_preferred_block(state, LanguageKit:registry_entry(state, "Forms", "Inferred"), 0); return }
        context:phrase:dispatch(state, context:phrase:find:exact(state, context:phrase:find(state, "Inferred"), "top_form"))
    }
}
let "infer " = <Inferred:explicit_form>
let LanguageKit:Selectors:"infer " = <Inferred:explicit_form>
let LanguageKit:Overrides:Inferred = <LanguageKit:Forms:Inferred>

languagekit_native_end
engine export "/tmp/recurloop-inferred-library.rli"
