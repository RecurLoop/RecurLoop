// =============================================================================
// RecurLoop Haskell compatibility experiment
//
// A small lazy functional runtime implemented entirely in RecurLoop source.
// The C++ host contains no Haskell parser, thunk, algebraic-data-type runtime,
// currying implementation, pattern matcher, or lazy evaluator.
//
// Supported subset:
//   - integer literals and arithmetic: +, -, *
//   - ordinary function application by whitespace
//   - curried functions and partial application
//   - multiple function equations
//   - integer, variable, wildcard, constructor and list-cons patterns
//   - algebraic data declarations: data Maybe a = Nothing | Just a
//   - [] / (:) lists and list literals
//   - higher-order functions
//   - call-by-need thunks with memoization
//   - recursive and infinite definitions when only a finite prefix is demanded
//   - builtins: print, div
//   - type-signature lines containing :: are accepted and ignored
//
// Deliberately not implemented yet:
//   modules/imports, classes, type inference/checking, strings/chars, tuples,
//   guards, where/let, lambdas, do notation, monads, records, deriving, case,
//   list comprehensions, exceptions, FFI, or the Haskell layout rule beyond
//   one top-level declaration per physical line.
// =============================================================================

link shared "c"

extern malloc(size:u64) -> u8* abi sysv-amd64
extern realloc(pointer:u8*, size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern memcpy(destination:u8*, source:u8*, bytes:u64) -> u8* abi sysv-amd64
extern strlen(text:u8*) -> u64 abi sysv-amd64
extern strcmp(left:u8*, right:u8*) -> i32 abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

let Haskell = phrase { dictionary = true permanent = true }
let Haskell:Internal = phrase { dictionary = true serializable = false }

// The RecurLoop lexicon is the canonical symbol table for the compatibility
// layer.  The lazy runtime still needs thunks and an AST, but names are interned
// as phrases and category dictionaries expose what each source declaration
// contributed to the active language.
let Haskell:Symbols = phrase { dictionary = true permanent = true }
let Haskell:Functions = phrase { dictionary = true permanent = true }
let Haskell:Values = phrase { dictionary = true permanent = true }
let Haskell:Constructors = phrase { dictionary = true permanent = true }
let Haskell:Types = phrase { dictionary = true permanent = true }
let Haskell:Variables = phrase { dictionary = true permanent = true }
let Haskell:Builtins = phrase { dictionary = true permanent = true }
let Haskell:Grammar = phrase { dictionary = true permanent = true }
let Haskell:Env = phrase { dictionary = true permanent = true }

// =============================================================================
// Text and state helpers.
// =============================================================================

let Haskell:copy_bytes = fn (source:u8*, bytes:i64) -> u8* {
    if bytes < 0 { return cast(u8*, 0) }
    let out = malloc(bytes + 1)
    if !out { return cast(u8*, 0) }
    if bytes > 0 { memcpy(out, source, bytes) }
    out[bytes] = 0
    return out
}

let Haskell:copy_text = fn (source:u8*) -> u8* {
    if !source { return cast(u8*, 0) }
    return Haskell:copy_bytes(source, cast(i64, strlen(source)))
}

let Haskell:concat = fn (left:u8*, right:u8*) -> u8* {
    let a = cast(i64, strlen(left))
    let b = cast(i64, strlen(right))
    let out = malloc(a + b + 1)
    if !out { return cast(u8*, 0) }
    memcpy(out, left, a)
    memcpy(&out[a], right, b)
    out[a + b] = 0
    return out
}

let Haskell:is_space = fn (ch:u8) -> i64 {
    return ch == 32 || ch == 9 || ch == 10 || ch == 13
}

let Haskell:is_alpha = fn (ch:u8) -> i64 {
    return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
}

let Haskell:is_upper = fn (ch:u8) -> i64 { return ch >= 65 && ch <= 90 }
let Haskell:is_digit = fn (ch:u8) -> i64 { return ch >= 48 && ch <= 57 }

let Haskell:is_ident_continue = fn (ch:u8) -> i64 {
    return Haskell:is_alpha(ch) || Haskell:is_digit(ch) || ch == 95 || ch == 39
}

let Haskell:text_number = fn (text:u8*) -> i64 {
    if !text { return 0 }
    var sign = 1
    var i = 0
    if text[0] == 45 { sign = -1; i = 1 }
    var value = 0
    while Haskell:is_digit(text[i]) {
        value = value * 10 + text[i] - 48
        i += 1
    }
    return value * sign
}

let Haskell:state_get = fn (state:Context*, name:u8*) -> i64 {
    if !context:value:contains(state, name) { return 0 }
    let text = context:value:format(state, name)
    if !text { return 0 }
    defer free(text)
    return Haskell:text_number(text)
}

let Haskell:state_set = fn (state:Context*, name:u8*, value:i64) -> i64 {
    if context:value:contains(state, name) {
        return context:value:assign:integer(state, name, value)
    }
    return context:value:define:integer(state, name, value)
}

// =============================================================================
// Phrase-backed symbol table.
// =============================================================================

let Haskell:category_owner = fn (state:Context*, category:u8*) -> i64 {
    let root = context:phrase:find(state, "Haskell")
    if !root { return 0 }
    return context:phrase:find:exact(state, root, category)
}

let Haskell:intern_symbol = fn (state:Context*, name:u8*) -> i64 {
    let owner = Haskell:category_owner(state, "Symbols")
    if !owner || !name { return 0 }
    let existing = context:phrase:find:exact(state, owner, name)
    if existing { return existing }
    let created = context:phrase:define:data(state, owner, name)
    return created
}

let Haskell:categorize_symbol = fn (state:Context*, category:u8*, name:u8*) -> i64 {
    let symbol = Haskell:intern_symbol(state, name)
    if !symbol { return 0 }
    let owner = Haskell:category_owner(state, category)
    if !owner { return symbol }
    if !context:phrase:find:exact(state, owner, name) {
        let alias = context:phrase:define:from(state, owner, name, symbol)
    }
    return symbol
}

let Haskell:symbol_in = fn (state:Context*, category:u8*, name:u8*) -> i64 {
    let owner = Haskell:category_owner(state, category)
    if !owner { return 0 }
    return context:phrase:find:exact(state, owner, name)
}

// =============================================================================
// AST, patterns and runtime objects.
// =============================================================================


record Haskell:Expr {
    kind:i64
    number:i64
    name:u8*
    symbol:i64
    left:Haskell:Expr*
    right:Haskell:Expr*
}


record Haskell:Pattern {
    kind:i64
    number:i64
    name:u8*
    symbol:i64
    arity:i64
    args:Haskell:Pattern**
}


record Haskell:Value {
    kind:i64
    number:i64
    name:u8*
    symbol:i64
    arity:i64
    applied:i64
    target_kind:i64
    args:u8*
    fields:u8*
}

record Haskell:Thunk {
    expr:Haskell:Expr*
    env:u8*
    value:Haskell:Value*
    forced:i64
    forcing:i64
}


record Haskell:EnvEntry {
    name:u8*
    symbol:i64
    thunk:u8*
    next:Haskell:EnvEntry*
}


record Haskell:Equation {
    name:u8*
    symbol:i64
    arity:i64
    patterns:Haskell:Pattern**
    body:Haskell:Expr*
    next:Haskell:Equation*
}


record Haskell:ConstructorDef {
    name:u8*
    symbol:i64
    arity:i64
    next:Haskell:ConstructorDef*
}

record Haskell:Database {
    equations:Haskell:Equation*
    equations_tail:Haskell:Equation*
    constructors:Haskell:ConstructorDef*
    main_ran:i64
}

let Haskell:Expr:new = fn (kind:i64) -> Haskell:Expr* {
    let self = cast(Haskell:Expr*, malloc(48))
    if !self { return cast(Haskell:Expr*, 0) }
    self.kind = kind
    self.number = 0
    self.name = cast(u8*, 0)
    self.symbol = 0
    self.left = cast(Haskell:Expr*, 0)
    self.right = cast(Haskell:Expr*, 0)
    return self
}

let Haskell:Expr:integer = fn (value:i64) -> Haskell:Expr* {
    let self = Haskell:Expr:new(1)
    if self { self.number = value }
    return self
}

let Haskell:Expr:name_owned = fn (state:Context*, name:u8*) -> Haskell:Expr* {
    let self = Haskell:Expr:new(2)
    if !self { if name { free(name) }; return cast(Haskell:Expr*, 0) }
    self.name = name
    self.symbol = Haskell:intern_symbol(state, name)
    return self
}

let Haskell:Expr:name = fn (state:Context*, name:u8*) -> Haskell:Expr* {
    return Haskell:Expr:name_owned(state, Haskell:copy_text(name))
}

let Haskell:Expr:app = fn (left:Haskell:Expr*, right:Haskell:Expr*) -> Haskell:Expr* {
    let self = Haskell:Expr:new(3)
    if self { self.left = left; self.right = right }
    return self
}

let Haskell:Expr:binary = fn (state:Context*, name:u8*, left:Haskell:Expr*, right:Haskell:Expr*) -> Haskell:Expr* {
    return Haskell:Expr:app(Haskell:Expr:app(Haskell:Expr:name(state, name), left), right)
}

let Haskell:Pattern:new = fn (kind:i64) -> Haskell:Pattern* {
    let self = cast(Haskell:Pattern*, malloc(48))
    if !self { return cast(Haskell:Pattern*, 0) }
    self.kind = kind
    self.number = 0
    self.name = cast(u8*, 0)
    self.symbol = 0
    self.arity = 0
    self.args = cast(Haskell:Pattern**, 0)
    return self
}

let Haskell:Pattern:variable_owned = fn (state:Context*, name:u8*) -> Haskell:Pattern* {
    let self = Haskell:Pattern:new(1)
    if !self { if name { free(name) }; return cast(Haskell:Pattern*, 0) }
    self.name = name
    self.symbol = Haskell:categorize_symbol(state, "Variables", name)
    return self
}

let Haskell:Pattern:wildcard = fn () -> Haskell:Pattern* { return Haskell:Pattern:new(2) }

let Haskell:Pattern:integer = fn (number:i64) -> Haskell:Pattern* {
    let self = Haskell:Pattern:new(3)
    if self { self.number = number }
    return self
}

let Haskell:Pattern:constructor_owned = fn (state:Context*, name:u8*, args:Haskell:Pattern**, arity:i64) -> Haskell:Pattern* {
    let self = Haskell:Pattern:new(4)
    if !self { if name { free(name) }; if args { free(cast(u8*, args)) }; return cast(Haskell:Pattern*, 0) }
    self.name = name
    self.symbol = Haskell:categorize_symbol(state, "Constructors", name)
    self.args = args
    self.arity = arity
    return self
}

let Haskell:Value:new = fn (kind:i64) -> Haskell:Value* {
    let self = cast(Haskell:Value*, malloc(72))
    if !self { return cast(Haskell:Value*, 0) }
    self.kind = kind
    self.number = 0
    self.name = cast(u8*, 0)
    self.symbol = 0
    self.arity = 0
    self.applied = 0
    self.target_kind = 0
    self.args = cast(u8*, 0)
    self.fields = cast(u8*, 0)
    return self
}

let Haskell:Value:integer = fn (number:i64) -> Haskell:Value* {
    let self = Haskell:Value:new(1)
    if self { self.number = number }
    return self
}

let Haskell:Value:constructor = fn (state:Context*, name:u8*, symbol:i64, arity:i64, fields:Haskell:Thunk**) -> Haskell:Value* {
    let self = Haskell:Value:new(2)
    if !self { return cast(Haskell:Value*, 0) }
    self.name = name
    self.symbol = symbol
    self.arity = arity
    self.fields = cast(u8*, fields)
    return self
}

let Haskell:Value:callable = fn (state:Context*, name:u8*, symbol:i64, arity:i64, target_kind:i64) -> Haskell:Value* {
    let self = Haskell:Value:new(3)
    if !self { return cast(Haskell:Value*, 0) }
    self.name = name
    self.symbol = symbol
    self.arity = arity
    self.applied = 0
    self.target_kind = target_kind
    self.args = cast(u8*, 0)
    return self
}

let Haskell:Thunk:expression = fn (expr:Haskell:Expr*, env:Haskell:EnvEntry*) -> Haskell:Thunk* {
    let self = cast(Haskell:Thunk*, malloc(40))
    if !self { return cast(Haskell:Thunk*, 0) }
    self.expr = expr
    self.env = cast(u8*, env)
    self.value = cast(Haskell:Value*, 0)
    self.forced = 0
    self.forcing = 0
    return self
}

let Haskell:Thunk:value_thunk = fn (value:Haskell:Value*) -> Haskell:Thunk* {
    let self = Haskell:Thunk:expression(cast(Haskell:Expr*, 0), cast(Haskell:EnvEntry*, 0))
    if self { self.value = value; self.forced = 1 }
    return self
}

let Haskell:Env:bind = fn (head:Haskell:EnvEntry*, name:u8*, symbol:i64, thunk:Haskell:Thunk*) -> Haskell:EnvEntry* {
    let item = cast(Haskell:EnvEntry*, malloc(32))
    if !item { return head }
    item.name = name
    item.symbol = symbol
    item.thunk = cast(u8*, thunk)
    item.next = head
    return item
}

let Haskell:Env:find = fn (head:Haskell:EnvEntry*, symbol:i64) -> Haskell:Thunk* {
    var item = head
    while item {
        if item.symbol == symbol { return cast(Haskell:Thunk*, item.thunk) }
        item = item.next
    }
    return cast(Haskell:Thunk*, 0)
}

let Haskell:Database:new = fn () -> Haskell:Database* {
    let self = cast(Haskell:Database*, malloc(32))
    if !self { return cast(Haskell:Database*, 0) }
    self.equations = cast(Haskell:Equation*, 0)
    self.equations_tail = cast(Haskell:Equation*, 0)
    self.constructors = cast(Haskell:ConstructorDef*, 0)
    self.main_ran = 0
    return self
}

let Haskell:database = fn (state:Context*) -> Haskell:Database* {
    let existing = cast(Haskell:Database*, Haskell:state_get(state, "__haskell_database"))
    if existing { return existing }
    let created = Haskell:Database:new()
    if !created { context:diagnostic:error(state, "Haskell: could not allocate language database"); return cast(Haskell:Database*, 0) }
    if !Haskell:state_set(state, "__haskell_database", cast(i64, created)) {
        free(cast(u8*, created))
        return cast(Haskell:Database*, 0)
    }
    // Lists are built-in algebraic constructors.
    let nil = cast(Haskell:ConstructorDef*, malloc(32))
    let cons = cast(Haskell:ConstructorDef*, malloc(32))
    if !nil || !cons { context:diagnostic:error(state, "Haskell: could not allocate list constructors"); return created }
    nil.name = Haskell:copy_text("__nil")
    nil.symbol = Haskell:categorize_symbol(state, "Constructors", "__nil")
    nil.arity = 0
    nil.next = cons
    cons.name = Haskell:copy_text("__cons")
    cons.symbol = Haskell:categorize_symbol(state, "Constructors", "__cons")
    cons.arity = 2
    cons.next = cast(Haskell:ConstructorDef*, 0)
    created.constructors = nil
    Haskell:categorize_symbol(state, "Builtins", "print")
    Haskell:categorize_symbol(state, "Builtins", "div")
    Haskell:categorize_symbol(state, "Builtins", "__add")
    Haskell:categorize_symbol(state, "Builtins", "__sub")
    Haskell:categorize_symbol(state, "Builtins", "__mul")
    return created
}

let Haskell:Database:add_constructor = fn (self:Haskell:Database*, state:Context*, name:u8*, arity:i64) -> i64 {
    let item = cast(Haskell:ConstructorDef*, malloc(32))
    if !item { return 0 }
    item.name = name
    item.symbol = Haskell:categorize_symbol(state, "Constructors", name)
    item.arity = arity
    item.next = self.constructors
    self.constructors = item
    return 1
}

let Haskell:Database:constructor = fn (self:Haskell:Database*, symbol:i64) -> Haskell:ConstructorDef* {
    var item = self.constructors
    while item {
        if item.symbol == symbol { return item }
        item = item.next
    }
    return cast(Haskell:ConstructorDef*, 0)
}

let Haskell:Database:function_arity = fn (self:Haskell:Database*, symbol:i64) -> i64 {
    var item = self.equations
    while item {
        if item.symbol == symbol { return item.arity }
        item = item.next
    }
    return -1
}

let Haskell:Database:add_equation = fn (self:Haskell:Database*, equation:Haskell:Equation*) -> void {
    equation.next = cast(Haskell:Equation*, 0)
    if self.equations_tail { self.equations_tail.next = equation }
    else { self.equations = equation }
    self.equations_tail = equation
}

// =============================================================================
// Parser.
// =============================================================================

record Haskell:Parser {
    state:Context*
    database:Haskell:Database*
    source:u8*
    length:i64
    position:i64
    error:i64
}

let Haskell:Parser:new = fn (state:Context*, database:Haskell:Database*, source:u8*) -> Haskell:Parser* {
    let self = cast(Haskell:Parser*, malloc(48))
    if !self { return cast(Haskell:Parser*, 0) }
    self.state = state
    self.database = database
    self.source = source
    self.length = cast(i64, strlen(source))
    self.position = 0
    self.error = 0
    return self
}

let Haskell:Parser:fail = fn (self:Haskell:Parser*, message:u8*) -> void {
    if !self.error { self.error = 1; context:diagnostic:error(self.state, message) }
}

let Haskell:Parser:skip = fn (self:Haskell:Parser*) -> void {
    while self.position < self.length && Haskell:is_space(self.source[self.position]) { self.position += 1 }
}

let Haskell:Parser:peek = fn (self:Haskell:Parser*) -> u8 {
    Haskell:Parser:skip(self)
    if self.position >= self.length { return cast(u8, 0) }
    return self.source[self.position]
}

let Haskell:Parser:match = fn (self:Haskell:Parser*, ch:u8) -> i64 {
    Haskell:Parser:skip(self)
    if self.position < self.length && self.source[self.position] == ch { self.position += 1; return 1 }
    return 0
}

let Haskell:Parser:match_pair = fn (self:Haskell:Parser*, a:u8, b:u8) -> i64 {
    Haskell:Parser:skip(self)
    if self.position + 1 < self.length && self.source[self.position] == a && self.source[self.position + 1] == b {
        self.position += 2
        return 1
    }
    return 0
}

let Haskell:Parser:identifier = fn (self:Haskell:Parser*) -> u8* {
    Haskell:Parser:skip(self)
    if self.position >= self.length { return cast(u8*, 0) }
    let first = self.source[self.position]
    if !(Haskell:is_alpha(first) || first == 95) { return cast(u8*, 0) }
    let start = self.position
    self.position += 1
    while self.position < self.length && Haskell:is_ident_continue(self.source[self.position]) { self.position += 1 }
    return Haskell:copy_bytes(&self.source[start], self.position - start)
}

let Haskell:Parser:number = fn (self:Haskell:Parser*) -> Haskell:Expr* {
    Haskell:Parser:skip(self)
    if self.position >= self.length || !Haskell:is_digit(self.source[self.position]) { return cast(Haskell:Expr*, 0) }
    var value = 0
    while self.position < self.length && Haskell:is_digit(self.source[self.position]) {
        value = value * 10 + self.source[self.position] - 48
        self.position += 1
    }
    return Haskell:Expr:integer(value)
}

let Haskell:Parser:starts_atom = fn (self:Haskell:Parser*) -> i64 {
    Haskell:Parser:skip(self)
    if self.position >= self.length { return 0 }
    let ch = self.source[self.position]
    return Haskell:is_alpha(ch) || Haskell:is_digit(ch) || ch == 95 || ch == 40 || ch == 91
}

let Haskell:Parser:parse_expr_mode = fn (self:Haskell:Parser*, mode:i64) -> Haskell:Expr* {
    // mode 0: cons, 1: add/sub, 2: multiply, 3: application, 4: atom
    if mode == 4 {
        Haskell:Parser:skip(self)
        let ch = Haskell:Parser:peek(self)
        if Haskell:is_digit(ch) { return Haskell:Parser:number(self) }
        if Haskell:is_alpha(ch) || ch == 95 {
            let name = Haskell:Parser:identifier(self)
            return Haskell:Expr:name_owned(self.state, name)
        }
        if Haskell:Parser:match(self, 40) {
            let expr = Haskell:Parser:parse_expr_mode(self, 0)
            if !Haskell:Parser:match(self, 41) { Haskell:Parser:fail(self, "Haskell: expected ')'") }
            return expr
        }
        if Haskell:Parser:match(self, 91) {
            if Haskell:Parser:match(self, 93) { return Haskell:Expr:name(self.state, "__nil") }
            let first = Haskell:Parser:parse_expr_mode(self, 0)
            if !first { return cast(Haskell:Expr*, 0) }
            var capacity = 4
            var count = 0
            var items = cast(Haskell:Expr**, malloc(capacity * 8))
            if !items { return cast(Haskell:Expr*, 0) }
            items[count] = first
            count += 1
            while Haskell:Parser:match(self, 44) {
                if count == capacity {
                    capacity *= 2
                    let replacement = realloc(cast(u8*, items), capacity * 8)
                    if !replacement { return cast(Haskell:Expr*, 0) }
                    items = cast(Haskell:Expr**, replacement)
                }
                let next = Haskell:Parser:parse_expr_mode(self, 0)
                if !next { return cast(Haskell:Expr*, 0) }
                items[count] = next
                count += 1
            }
            if !Haskell:Parser:match(self, 93) {
                Haskell:Parser:fail(self, "Haskell: expected ']' in list literal")
                return cast(Haskell:Expr*, 0)
            }
            var list = Haskell:Expr:name(self.state, "__nil")
            var index = count - 1
            while index >= 0 {
                list = Haskell:Expr:binary(self.state, "__cons", items[index], list)
                index -= 1
            }
            free(cast(u8*, items))
            return list
        }
        Haskell:Parser:fail(self, "Haskell: expected expression atom")
        return cast(Haskell:Expr*, 0)
    }

    if mode == 3 {
        var expr = Haskell:Parser:parse_expr_mode(self, 4)
        if !expr { return expr }
        var scanning = 1
        while scanning {
            let saved = self.position
            if Haskell:Parser:starts_atom(self) {
                let argument = Haskell:Parser:parse_expr_mode(self, 4)
                if argument { expr = Haskell:Expr:app(expr, argument) }
                else {
                    self.position = saved
                    scanning = 0
                }
            } else { scanning = 0 }
        }
        return expr
    }

    if mode == 2 {
        var left = Haskell:Parser:parse_expr_mode(self, 3)
        var scanning = 1
        while scanning {
            if Haskell:Parser:match(self, 42) {
                let right = Haskell:Parser:parse_expr_mode(self, 3)
                left = Haskell:Expr:binary(self.state, "__mul", left, right)
            } else { scanning = 0 }
        }
        return left
    }

    if mode == 1 {
        var left = Haskell:Parser:parse_expr_mode(self, 2)
        var scanning = 1
        while scanning {
            if Haskell:Parser:match(self, 43) {
                let right = Haskell:Parser:parse_expr_mode(self, 2)
                left = Haskell:Expr:binary(self.state, "__add", left, right)
            } else if Haskell:Parser:match(self, 45) {
                let right = Haskell:Parser:parse_expr_mode(self, 2)
                left = Haskell:Expr:binary(self.state, "__sub", left, right)
            } else { scanning = 0 }
        }
        return left
    }

    let left = Haskell:Parser:parse_expr_mode(self, 1)
    if Haskell:Parser:match(self, 58) {
        let right = Haskell:Parser:parse_expr_mode(self, 0)
        return Haskell:Expr:binary(self.state, "__cons", left, right)
    }
    return left
}

let Haskell:Parser:parse_pattern_mode = fn (self:Haskell:Parser*, mode:i64) -> Haskell:Pattern* {
    // mode 0: right-associative cons, mode 1: atomic pattern
    if mode == 1 {
        Haskell:Parser:skip(self)
        let ch = Haskell:Parser:peek(self)
        if Haskell:is_digit(ch) {
            var value = 0
            while self.position < self.length && Haskell:is_digit(self.source[self.position]) {
                value = value * 10 + self.source[self.position] - 48
                self.position += 1
            }
            return Haskell:Pattern:integer(value)
        }
        if ch == 95 {
            let name = Haskell:Parser:identifier(self)
            if name && strcmp(name, "_") == 0 {
                free(name)
                return Haskell:Pattern:wildcard()
            }
            return Haskell:Pattern:variable_owned(self.state, name)
        }
        if Haskell:is_alpha(ch) {
            let name = Haskell:Parser:identifier(self)
            if !name { return cast(Haskell:Pattern*, 0) }
            if Haskell:is_upper(name[0]) {
                let symbol = Haskell:intern_symbol(self.state, name)
                let constructor = Haskell:Database:constructor(self.database, symbol)
                var arity = 0
                if constructor { arity = constructor.arity }
                if arity == 0 {
                    return Haskell:Pattern:constructor_owned(self.state, name, cast(Haskell:Pattern**, 0), 0)
                }
                let args = cast(Haskell:Pattern**, malloc(arity * 8))
                if !args { free(name); return cast(Haskell:Pattern*, 0) }
                var i = 0
                while i < arity {
                    args[i] = Haskell:Parser:parse_pattern_mode(self, 1)
                    if !args[i] {
                        Haskell:Parser:fail(self, "Haskell: constructor pattern is missing an argument")
                        return cast(Haskell:Pattern*, 0)
                    }
                    i += 1
                }
                return Haskell:Pattern:constructor_owned(self.state, name, args, arity)
            }
            return Haskell:Pattern:variable_owned(self.state, name)
        }
        if Haskell:Parser:match(self, 91) {
            if !Haskell:Parser:match(self, 93) {
                Haskell:Parser:fail(self, "Haskell: only [] is supported directly in patterns")
                return cast(Haskell:Pattern*, 0)
            }
            return Haskell:Pattern:constructor_owned(self.state, Haskell:copy_text("__nil"), cast(Haskell:Pattern**, 0), 0)
        }
        if Haskell:Parser:match(self, 40) {
            let first = Haskell:Parser:parse_pattern_mode(self, 0)
            if !Haskell:Parser:match(self, 41) { Haskell:Parser:fail(self, "Haskell: expected ')' in pattern") }
            return first
        }
        Haskell:Parser:fail(self, "Haskell: expected pattern")
        return cast(Haskell:Pattern*, 0)
    }

    let left = Haskell:Parser:parse_pattern_mode(self, 1)
    if !left { return left }
    if Haskell:Parser:match(self, 58) {
        let right = Haskell:Parser:parse_pattern_mode(self, 0)
        let args = cast(Haskell:Pattern**, malloc(16))
        if !args { return cast(Haskell:Pattern*, 0) }
        args[0] = left
        args[1] = right
        return Haskell:Pattern:constructor_owned(self.state, Haskell:copy_text("__cons"), args, 2)
    }
    return left
}

// =============================================================================
// Top-level declaration parser.
// =============================================================================

let Haskell:contains_type_signature = fn (source:u8*) -> i64 {
    var i = 0
    let bytes = cast(i64, strlen(source))
    while i + 1 < bytes {
        if source[i] == 58 && source[i + 1] == 58 { return 1 }
        i += 1
    }
    return 0
}

let Haskell:parse_data = fn (state:Context*, database:Haskell:Database*, source:u8*) -> i64 {
    let parser = Haskell:Parser:new(state, database, source)
    if !parser { return 0 }
    defer free(cast(u8*, parser))
    let keyword = Haskell:Parser:identifier(parser)
    if !keyword || strcmp(keyword, "data") != 0 { if keyword { free(keyword) }; return 0 }
    free(keyword)
    let type_name = Haskell:Parser:identifier(parser)
    if !type_name { Haskell:Parser:fail(parser, "Haskell: data declaration expects a type name"); return 0 }
    Haskell:categorize_symbol(state, "Types", type_name)
    free(type_name)
    // Skip type variables up to '='.
    var found_equal = 0
    while parser.position < parser.length && !found_equal {
        if parser.source[parser.position] == 61 { parser.position += 1; found_equal = 1 }
        else { parser.position += 1 }
    }
    if !found_equal { Haskell:Parser:fail(parser, "Haskell: data declaration expects '='"); return 0 }
    var parsing = 1
    while parsing {
        let name = Haskell:Parser:identifier(parser)
        if !name || !Haskell:is_upper(name[0]) { if name { free(name) }; Haskell:Parser:fail(parser, "Haskell: expected constructor name"); return 0 }
        var arity = 0
        var scan = parser.position
        var depth = 0
        var in_token = 0
        while scan < parser.length {
            let ch = parser.source[scan]
            if ch == 40 || ch == 91 { depth += 1; in_token = 0; scan += 1 }
            else if ch == 41 || ch == 93 { depth -= 1; in_token = 0; scan += 1 }
            else if ch == 124 && depth == 0 { break }
            else if Haskell:is_space(ch) { in_token = 0; scan += 1 }
            else {
                if !in_token { arity += 1; in_token = 1 }
                scan += 1
            }
        }
        if !Haskell:Database:add_constructor(database, state, name, arity) { free(name); return 0 }
        parser.position = scan
        Haskell:Parser:skip(parser)
        if parser.position < parser.length && parser.source[parser.position] == 124 { parser.position += 1 }
        else { parsing = 0 }
    }
    return !parser.error
}

let Haskell:parse_equation = fn (state:Context*, database:Haskell:Database*, source:u8*) -> Haskell:Equation* {
    let parser = Haskell:Parser:new(state, database, source)
    if !parser { return cast(Haskell:Equation*, 0) }
    defer free(cast(u8*, parser))
    let name = Haskell:Parser:identifier(parser)
    if !name { Haskell:Parser:fail(parser, "Haskell: expected top-level binding name"); return cast(Haskell:Equation*, 0) }

    var capacity = 4
    var count = 0
    var patterns = cast(Haskell:Pattern**, malloc(capacity * 8))
    if !patterns { free(name); return cast(Haskell:Equation*, 0) }

    var scanning = 1
    while scanning {
        Haskell:Parser:skip(parser)
        if parser.position >= parser.length { Haskell:Parser:fail(parser, "Haskell: equation expects '='"); return cast(Haskell:Equation*, 0) }
        if parser.source[parser.position] == 61 { parser.position += 1; scanning = 0 }
        else {
            let pattern = Haskell:Parser:parse_pattern_mode(parser, 0)
            if !pattern { return cast(Haskell:Equation*, 0) }
            if count == capacity {
                capacity *= 2
                let replacement = realloc(cast(u8*, patterns), capacity * 8)
                if !replacement { return cast(Haskell:Equation*, 0) }
                patterns = cast(Haskell:Pattern**, replacement)
            }
            patterns[count] = pattern
            count += 1
        }
    }
    let body = Haskell:Parser:parse_expr_mode(parser, 0)
    if !body || parser.error { return cast(Haskell:Equation*, 0) }
    Haskell:Parser:skip(parser)
    if parser.position < parser.length && !(parser.position + 1 < parser.length && parser.source[parser.position] == 45 && parser.source[parser.position + 1] == 45) {
        Haskell:Parser:fail(parser, "Haskell: unexpected input after expression")
        return cast(Haskell:Equation*, 0)
    }
    let equation = cast(Haskell:Equation*, malloc(48))
    if !equation { return cast(Haskell:Equation*, 0) }
    equation.name = name
    equation.symbol = Haskell:categorize_symbol(state, "Functions", name)
    if count == 0 { Haskell:categorize_symbol(state, "Values", name) }
    equation.arity = count
    equation.patterns = patterns
    equation.body = body
    equation.next = cast(Haskell:Equation*, 0)
    return equation
}

// =============================================================================
// Lazy runtime.
//
// Helpers receive a typed callback to the recursive dispatcher. This avoids a
// special host facility for mutually recursive eval/force/apply/match logic.
// =============================================================================

let Haskell:RuntimeCallback = fn (state:Context*, mode:i64, a:i64, b:i64, c:i64) -> i64

let Haskell:builtin_arity = fn (state:Context*, symbol:i64) -> i64 {
    if symbol == Haskell:intern_symbol(state, "__add") { return 2 }
    if symbol == Haskell:intern_symbol(state, "__sub") { return 2 }
    if symbol == Haskell:intern_symbol(state, "__mul") { return 2 }
    if symbol == Haskell:intern_symbol(state, "div") { return 2 }
    if symbol == Haskell:intern_symbol(state, "print") { return 1 }
    return -1
}

let Haskell:copy_args_plus = fn (value:Haskell:Value*, argument:Haskell:Thunk*) -> Haskell:Thunk** {
    let count = value.applied + 1
    let args = cast(Haskell:Thunk**, malloc(count * 8))
    if !args { return cast(Haskell:Thunk**, 0) }
    var i = 0
    while i < value.applied { args[i] = cast(Haskell:Thunk**, value.args)[i]; i += 1 }
    args[value.applied] = argument
    return args
}

let Haskell:force_with = fn (dispatch:Haskell:RuntimeCallback, state:Context*, thunk:Haskell:Thunk*) -> Haskell:Value* {
    if !thunk { return cast(Haskell:Value*, 0) }
    if thunk.forced { return thunk.value }
    if thunk.forcing {
        context:diagnostic:error(state, "Haskell: black hole while forcing a recursive thunk")
        return cast(Haskell:Value*, 0)
    }
    thunk.forcing = 1
    let value = cast(Haskell:Value*, dispatch(state, 1, cast(i64, thunk.expr), cast(i64, cast(Haskell:EnvEntry*, thunk.env)), 0))
    thunk.value = value
    thunk.forced = 1
    thunk.forcing = 0
    return value
}

let Haskell:match_with = fn (
    dispatch:Haskell:RuntimeCallback, state:Context*, pattern:Haskell:Pattern*, thunk:Haskell:Thunk*, env:Haskell:EnvEntry*
) -> i64 {
    if !pattern || !thunk { return 0 }
    if pattern.kind == 2 { if env { return cast(i64, env) }; return 1 }
    if pattern.kind == 1 {
        return cast(i64, Haskell:Env:bind(env, pattern.name, pattern.symbol, thunk))
    }
    let value = Haskell:force_with(dispatch, state, thunk)
    if !value { return 0 }
    if pattern.kind == 3 {
        if value.kind == 1 && value.number == pattern.number { if env { return cast(i64, env) }; return 1 }
        return 0
    }
    if pattern.kind == 4 {
        if value.kind != 2 || value.arity != pattern.arity || value.symbol != pattern.symbol { return 0 }
        var current = env
        var i = 0
        while i < pattern.arity {
            let matched = Haskell:match_with(dispatch, state, pattern.args[i], cast(Haskell:Thunk**, value.fields)[i], current)
            if !matched { return 0 }
            if matched == 1 { current = cast(Haskell:EnvEntry*, 0) }
            else { current = cast(Haskell:EnvEntry*, matched) }
            i += 1
        }
        if current { return cast(i64, current) }
        return 1
    }
    return 0
}

let Haskell:print_value_with = fn (dispatch:Haskell:RuntimeCallback, state:Context*, value:Haskell:Value*) -> i64 {
    if !value { return 0 }
    if value.kind == 1 { printf("%lld", value.number); return 1 }
    if value.kind == 3 { printf("<function>"); return 1 }
    if value.kind != 2 { printf("<value>"); return 1 }
    if strcmp(value.name, "__nil") == 0 { printf("[]"); return 1 }
    if strcmp(value.name, "__cons") == 0 && value.arity == 2 {
        printf("[")
        var current = value
        var first = 1
        var running = 1
        while running {
            if !first { printf(",") }
            let head = Haskell:force_with(dispatch, state, cast(Haskell:Thunk**, current.fields)[0])
            Haskell:print_value_with(dispatch, state, head)
            first = 0
            let tail = Haskell:force_with(dispatch, state, cast(Haskell:Thunk**, current.fields)[1])
            if !tail { running = 0 }
            else if tail.kind == 2 && strcmp(tail.name, "__nil") == 0 { running = 0 }
            else if tail.kind == 2 && strcmp(tail.name, "__cons") == 0 && tail.arity == 2 { current = tail }
            else {
                printf("|")
                Haskell:print_value_with(dispatch, state, tail)
                running = 0
            }
        }
        printf("]")
        return 1
    }
    printf("%s", value.name)
    if value.arity > 0 {
        var i = 0
        while i < value.arity {
            printf(" ")
            let field = Haskell:force_with(dispatch, state, cast(Haskell:Thunk**, value.fields)[i])
            Haskell:print_value_with(dispatch, state, field)
            i += 1
        }
    }
    return 1
}

let Haskell:apply_builtin_with = fn (dispatch:Haskell:RuntimeCallback, state:Context*, value:Haskell:Value*, args:Haskell:Thunk**) -> Haskell:Value* {
    if value.symbol == Haskell:intern_symbol(state, "print") {
        let printed = Haskell:force_with(dispatch, state, args[0])
        Haskell:print_value_with(dispatch, state, printed)
        printf("\n")
        return Haskell:Value:constructor(state, Haskell:copy_text("()"), Haskell:intern_symbol(state, "()"), 0, cast(Haskell:Thunk**, 0))
    }
    let left = Haskell:force_with(dispatch, state, args[0])
    let right = Haskell:force_with(dispatch, state, args[1])
    if !left || !right || left.kind != 1 || right.kind != 1 {
        context:diagnostic:error(state, "Haskell: integer builtin received a non-integer")
        return cast(Haskell:Value*, 0)
    }
    if value.symbol == Haskell:intern_symbol(state, "__add") { return Haskell:Value:integer(left.number + right.number) }
    if value.symbol == Haskell:intern_symbol(state, "__sub") { return Haskell:Value:integer(left.number - right.number) }
    if value.symbol == Haskell:intern_symbol(state, "__mul") { return Haskell:Value:integer(left.number * right.number) }
    if value.symbol == Haskell:intern_symbol(state, "div") {
        if right.number == 0 { context:diagnostic:error(state, "Haskell: division by zero"); return cast(Haskell:Value*, 0) }
        return Haskell:Value:integer(left.number / right.number)
    }
    return cast(Haskell:Value*, 0)
}

let Haskell:apply_user_with = fn (
    dispatch:Haskell:RuntimeCallback, state:Context*, database:Haskell:Database*, value:Haskell:Value*, args:Haskell:Thunk**
) -> Haskell:Value* {
    var equation = database.equations
    while equation {
        if equation.arity == value.arity && equation.symbol == value.symbol {
            var env = cast(Haskell:EnvEntry*, 0)
            var matched = 1
            var i = 0
            while matched && i < equation.arity {
                let next_env = Haskell:match_with(dispatch, state, equation.patterns[i], args[i], env)
                if !next_env { matched = 0 }
                else if next_env == 1 { env = cast(Haskell:EnvEntry*, 0) }
                else { env = cast(Haskell:EnvEntry*, next_env) }
                i += 1
            }
            if matched {
                return cast(Haskell:Value*, dispatch(state, 1, cast(i64, equation.body), cast(i64, env), 0))
            }
        }
        equation = equation.next
    }
    context:diagnostic:error(state, "Haskell: non-exhaustive patterns")
    return cast(Haskell:Value*, 0)
}

let Haskell:apply_with = fn (
    dispatch:Haskell:RuntimeCallback, state:Context*, database:Haskell:Database*, function:Haskell:Value*, argument:Haskell:Thunk*
) -> Haskell:Value* {
    if !function || function.kind != 3 { context:diagnostic:error(state, "Haskell: attempted to apply a non-function"); return cast(Haskell:Value*, 0) }
    let args = Haskell:copy_args_plus(function, argument)
    if !args { return cast(Haskell:Value*, 0) }
    let applied = function.applied + 1
    if applied < function.arity {
        let partial = Haskell:Value:callable(state, function.name, function.symbol, function.arity, function.target_kind)
        partial.applied = applied
        partial.args = cast(u8*, args)
        return partial
    }
    if function.target_kind == 1 { return Haskell:apply_builtin_with(dispatch, state, function, args) }
    if function.target_kind == 2 { return Haskell:apply_user_with(dispatch, state, database, function, args) }
    if function.target_kind == 3 { return Haskell:Value:constructor(state, function.name, function.symbol, function.arity, args) }
    return cast(Haskell:Value*, 0)
}

let Haskell:dispatch = fn (state:Context*, mode:i64, a:i64, b:i64, c:i64) -> i64 {
    let database = Haskell:database(state)
    if !database { return 0 }
    if mode == 2 {
        return cast(i64, Haskell:force_with(Haskell:dispatch, state, cast(Haskell:Thunk*, a)))
    }
    if mode == 3 {
        return cast(i64, Haskell:apply_with(
            Haskell:dispatch, state, database, cast(Haskell:Value*, a), cast(Haskell:Thunk*, b)
        ))
    }
    if mode != 1 { return 0 }

    let expr = cast(Haskell:Expr*, a)
    let env = cast(Haskell:EnvEntry*, b)
    if !expr { return 0 }
    if expr.kind == 1 { return cast(i64, Haskell:Value:integer(expr.number)) }
    if expr.kind == 3 {
        let function = cast(Haskell:Value*, Haskell:dispatch(state, 1, cast(i64, expr.left), cast(i64, env), 0))
        let argument = Haskell:Thunk:expression(expr.right, env)
        return Haskell:dispatch(state, 3, cast(i64, function), cast(i64, argument), 0)
    }
    if expr.kind != 2 { return 0 }

    let local = Haskell:Env:find(env, expr.symbol)
    if local { return Haskell:dispatch(state, 2, cast(i64, local), 0, 0) }

    let constructor = Haskell:Database:constructor(database, expr.symbol)
    if constructor {
        if constructor.arity == 0 {
            return cast(i64, Haskell:Value:constructor(state, constructor.name, constructor.symbol, 0, cast(Haskell:Thunk**, 0)))
        }
        return cast(i64, Haskell:Value:callable(state, constructor.name, constructor.symbol, constructor.arity, 3))
    }

    let builtin = Haskell:builtin_arity(state, expr.symbol)
    if builtin >= 0 { return cast(i64, Haskell:Value:callable(state, expr.name, expr.symbol, builtin, 1)) }

    let arity = Haskell:Database:function_arity(database, expr.symbol)
    if arity >= 0 {
        if arity == 0 {
            var equation = database.equations
            while equation {
                if equation.arity == 0 && equation.symbol == expr.symbol {
                    let thunk = Haskell:Thunk:expression(equation.body, cast(Haskell:EnvEntry*, 0))
                    return Haskell:dispatch(state, 2, cast(i64, thunk), 0, 0)
                }
                equation = equation.next
            }
        }
        return cast(i64, Haskell:Value:callable(state, expr.name, expr.symbol, arity, 2))
    }

    context:diagnostic:error(state, "Haskell: unknown identifier")
    return 0
}

// =============================================================================
// Feed one top-level Haskell declaration into the runtime.
// =============================================================================

let Haskell:trim_comment = fn (source:u8*) -> u8* {
    let bytes = cast(i64, strlen(source))
    var i = 0
    while i + 1 < bytes {
        if source[i] == 45 && source[i + 1] == 45 { return Haskell:copy_bytes(source, i) }
        i += 1
    }
    return Haskell:copy_text(source)
}

let Haskell:line_is_data = fn (source:u8*) -> i64 {
    var i = 0
    while Haskell:is_space(source[i]) { i += 1 }
    return source[i] == 100 && source[i+1] == 97 && source[i+2] == 116 && source[i+3] == 97 && Haskell:is_space(source[i+4])
}

let Haskell:line_is_trivia = fn (source:u8*) -> i64 {
    var i = 0
    while Haskell:is_space(source[i]) { i += 1 }
    return source[i] == 0 || (source[i] == 45 && source[i + 1] == 45)
}

let Haskell:run_main = fn (state:Context*, equation:Haskell:Equation*) -> void {
    let database = Haskell:database(state)
    if !database || database.main_ran { return }
    database.main_ran = 1
    let result = cast(Haskell:Value*, Haskell:dispatch(state, 1, cast(i64, equation.body), 0, 0))
    if !result { context:diagnostic:error(state, "Haskell: main evaluation failed") }
}

let Haskell:consume_declaration = fn (state:Context*, source:u8*) -> void {
    if !source || Haskell:line_is_trivia(source) { return }
    let database = Haskell:database(state)
    if !database { return }
    let clean = Haskell:trim_comment(source)
    if !clean { return }
    defer free(clean)
    if Haskell:line_is_trivia(clean) { return }
    if Haskell:contains_type_signature(clean) {
        let signature_parser = Haskell:Parser:new(state, database, clean)
        if signature_parser {
            let signature_name = Haskell:Parser:identifier(signature_parser)
            if signature_name { Haskell:categorize_symbol(state, "Functions", signature_name); free(signature_name) }
            free(cast(u8*, signature_parser))
        }
        return
    }
    if Haskell:line_is_data(clean) {
        Haskell:parse_data(state, database, clean)
        return
    }
    let equation = Haskell:parse_equation(state, database, clean)
    if !equation { return }
    Haskell:Database:add_equation(database, equation)
    if equation.arity == 0 && equation.symbol == Haskell:intern_symbol(state, "main") { Haskell:run_main(state, equation) }
}

// =============================================================================
// Source-line capture and language fallback.
// =============================================================================

let Haskell:capture_line = fn (state:Context*) -> u8* {
    context:source:ensure(state, 1048576)
    let source = cast(u8*, context:source:data(state))
    let bytes = context:source:bytes(state)
    if bytes <= 0 { return cast(u8*, 0) }
    var i = 0
    while i < bytes && source[i] != 10 && source[i] != 13 { i += 1 }
    let text = Haskell:copy_bytes(source, i)
    if i < bytes && source[i] == 13 {
        i += 1
        if i < bytes && source[i] == 10 { i += 1 }
    } else if i < bytes && source[i] == 10 { i += 1 }
    context:source:advance(state, i)
    return text
}

// `data` is a real top-level RecurLoop phrase.  Arbitrary binding names still
// enter through the language fallback, but declarations are interned as phrases
// immediately and all subsequent semantic name resolution uses those phrase ids.
let Haskell:data_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let tail = Haskell:capture_line(state)
        if tail {
            let full = Haskell:concat("data ", tail)
            if full {
                let database = Haskell:database(state)
                if database { Haskell:parse_data(state, database, full) }
                free(full)
            }
            free(tail)
        }
        context:source:root(state)
    }
}

let data = <Haskell:data_form>

let Haskell:top_line = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let line = Haskell:capture_line(state)
        if line { Haskell:consume_declaration(state, line); free(line) }
        context:source:root(state)
    }
}

let Haskell:assert_symbol_phrase = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        context:source:ensure(state, 4096)
        let source = cast(u8*, context:source:data(state))
        let bytes = context:source:bytes(state)
        var i = 0
        while i < bytes && Haskell:is_space(source[i]) { i += 1 }
        let category_start = i
        while i < bytes && Haskell:is_ident_continue(source[i]) { i += 1 }
        let category = Haskell:copy_bytes(&source[category_start], i - category_start)
        while i < bytes && Haskell:is_space(source[i]) { i += 1 }
        let name_start = i
        while i < bytes && !Haskell:is_space(source[i]) { i += 1 }
        let name = Haskell:copy_bytes(&source[name_start], i - name_start)
        if !category || !name { context:diagnostic:error(state, "Haskell: assert-symbol expects CATEGORY NAME") }
        else {
            var owner_name = cast(u8*, 0)
            if strcmp(category, "function") == 0 { owner_name = "Functions" }
            else if strcmp(category, "value") == 0 { owner_name = "Values" }
            else if strcmp(category, "constructor") == 0 { owner_name = "Constructors" }
            else if strcmp(category, "type") == 0 { owner_name = "Types" }
            else if strcmp(category, "variable") == 0 { owner_name = "Variables" }
            else if strcmp(category, "builtin") == 0 { owner_name = "Builtins" }
            else if strcmp(category, "symbol") == 0 { owner_name = "Symbols" }
            if !owner_name || !Haskell:symbol_in(state, owner_name, name) {
                context:diagnostic:error(state, "Haskell: expected phrase-backed symbol is missing")
            }
        }
        if category { free(category) }
        if name { free(name) }
        while i < bytes && source[i] != 10 && source[i] != 13 { i += 1 }
        if i < bytes { i += 1 }
        context:source:advance(state, i)
        context:source:root(state)
    }
}

let Haskell:assert = <Haskell:assert_symbol_phrase>
let haskell_assert = <Haskell:assert_symbol_phrase>

let install_haskell_fallback = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let haskell = context:phrase:find(state, "Haskell")
        let top_line = context:phrase:find:exact(state, haskell, "top_line")
        let fallback = context:phrase:define:alias(state, "", top_line)
        if !fallback { context:diagnostic:error(state, "Haskell: could not install top-level fallback") }
    }
}

install_haskell_fallback

set malloc.serializable = false
set realloc.serializable = false
set free.serializable = false
set memcpy.serializable = false
set strlen.serializable = false
set strcmp.serializable = false
set printf.serializable = false
set install_haskell_fallback.serializable = false

engine export "/tmp/recurloop-haskell-library.rli"
