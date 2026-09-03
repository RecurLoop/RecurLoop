// =============================================================================
// RecurLoop Prolog compatibility experiment
//
// A deliberately different language runtime implemented in RecurLoop source.
// The host has no Prolog parser, unifier, trail, choice point, or backtracking
// engine. This library installs a top-level clause fallback plus a `?-` query
// phrase and implements the logic runtime below in .rl.
//
// Supported subset:
//   - atoms and integers
//   - logical variables (Uppercase or _name; bare _ is anonymous)
//   - compound terms
//   - facts and rules (`:-`)
//   - conjunction (`,`) in rule bodies and queries
//   - unification (`=`) as a built-in goal
//   - `true` and `fail`
//   - lists: `[]`, `[a, b]`, `[Head | Tail]`
//   - depth-first search, clause-order choice points and trail-based rollback
//   - batch queries (`?- ... .`) that enumerate every solution
//
// Intentionally not implemented yet:
//   cut, disjunction, arithmetic/is, negation, modules, DCGs, dynamic clauses,
//   attributed variables, tabling, exceptions, streams, or ISO operator rules.
// =============================================================================

link shared "c"

extern malloc(size:u64) -> u8* abi sysv-amd64
extern realloc(pointer:u8*, size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern memcpy(destination:u8*, source:u8*, bytes:u64) -> u8* abi sysv-amd64
extern strlen(text:u8*) -> u64 abi sysv-amd64
extern strcmp(left:u8*, right:u8*) -> i32 abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

let Prolog = phrase { dictionary = true permanent = true }
let Prolog:Internal = phrase { dictionary = true serializable = false }
let Prolog:Symbols = phrase { dictionary = true permanent = true }
let Prolog:Predicates = phrase { dictionary = true permanent = true }
let Prolog:Atoms = phrase { dictionary = true permanent = true }
let Prolog:Variables = phrase { dictionary = true permanent = true }
let Prolog:Builtins = phrase { dictionary = true permanent = true }
let Prolog:Operators = phrase { dictionary = true permanent = true }
let Prolog:Grammar = phrase { dictionary = true permanent = true }

// =============================================================================
// Small allocation/string helpers.
// =============================================================================

let Prolog:copy_bytes = fn (source:u8*, bytes:i64) -> u8* {
    if bytes < 0 { return cast(u8*, 0) }
    let out = malloc(bytes + 1)
    if !out { return cast(u8*, 0) }
    if bytes > 0 { memcpy(out, source, bytes) }
    out[bytes] = 0
    return out
}

let Prolog:copy_text = fn (source:u8*) -> u8* {
    if !source { return cast(u8*, 0) }
    return Prolog:copy_bytes(source, cast(i64, strlen(source)))
}

let Prolog:is_space = fn (ch:u8) -> i64 {
    return ch == 32 || ch == 9 || ch == 10 || ch == 13
}

let Prolog:is_lower = fn (ch:u8) -> i64 {
    return ch >= 97 && ch <= 122
}

let Prolog:is_upper = fn (ch:u8) -> i64 {
    return ch >= 65 && ch <= 90
}

let Prolog:is_digit = fn (ch:u8) -> i64 {
    return ch >= 48 && ch <= 57
}

let Prolog:is_ident_continue = fn (ch:u8) -> i64 {
    return Prolog:is_lower(ch) || Prolog:is_upper(ch) || Prolog:is_digit(ch) || ch == 95
}

// State-local pointers are created only after an imported language image starts
// consuming Prolog source. No process address is written to the .rli image.
let Prolog:state_number = fn (text:u8*) -> i64 {
    if !text { return 0 }
    var sign = 1
    var i = 0
    if text[0] == 45 { sign = -1; i = 1 }
    var value = 0
    while Prolog:is_digit(text[i]) {
        value = value * 10 + text[i] - 48
        i += 1
    }
    return value * sign
}

let Prolog:state_get = fn (state:Context*, name:u8*) -> i64 {
    if !context:value:contains(state, name) { return 0 }
    let text = context:value:format(state, name)
    if !text { return 0 }
    defer free(text)
    return Prolog:state_number(text)
}

let Prolog:state_set = fn (state:Context*, name:u8*, value:i64) -> i64 {
    if context:value:contains(state, name) {
        return context:value:assign:integer(state, name, value)
    }
    return context:value:define:integer(state, name, value)
}

// =============================================================================
// Phrase-backed Prolog symbol table.
// =============================================================================

let Prolog:category_owner = fn (state:Context*, category:u8*) -> i64 {
    let root = context:phrase:find(state, "Prolog")
    if !root { return 0 }
    return context:phrase:find:exact(state, root, category)
}

let Prolog:intern_symbol = fn (state:Context*, name:u8*) -> i64 {
    let owner = Prolog:category_owner(state, "Symbols")
    if !owner || !name { return 0 }
    let existing = context:phrase:find:exact(state, owner, name)
    if existing { return existing }
    let created = context:phrase:define:data(state, owner, name)
    return created
}

let Prolog:categorize_symbol = fn (state:Context*, category:u8*, name:u8*) -> i64 {
    let symbol = Prolog:intern_symbol(state, name)
    if !symbol { return 0 }
    let owner = Prolog:category_owner(state, category)
    if owner && !context:phrase:find:exact(state, owner, name) {
        let alias = context:phrase:define:from(state, owner, name, symbol)
    }
    return symbol
}

let Prolog:symbol_in = fn (state:Context*, category:u8*, name:u8*) -> i64 {
    let owner = Prolog:category_owner(state, category)
    if !owner { return 0 }
    return context:phrase:find:exact(state, owner, name)
}

// =============================================================================
// Runtime terms.
// =============================================================================

record Prolog:Term {
    kind:i64
    number:i64
    name:u8*
    symbol:i64
    arity:i64
    args:Prolog:Term**
    binding:Prolog:Term*
}

let Prolog:Term:new = fn (kind:i64) -> Prolog:Term* {
    let self = cast(Prolog:Term*, malloc(56))
    if !self { return cast(Prolog:Term*, 0) }
    self.kind = kind
    self.number = 0
    self.name = cast(u8*, 0)
    self.symbol = 0
    self.arity = 0
    self.args = cast(Prolog:Term**, 0)
    self.binding = cast(Prolog:Term*, 0)
    return self
}

let Prolog:Term:atom_owned = fn (state:Context*, name:u8*) -> Prolog:Term* {
    let self = Prolog:Term:new(1)
    if !self { if name { free(name) }; return cast(Prolog:Term*, 0) }
    self.name = name
    self.symbol = Prolog:categorize_symbol(state, "Atoms", name)
    return self
}

let Prolog:Term:atom = fn (state:Context*, name:u8*) -> Prolog:Term* {
    return Prolog:Term:atom_owned(state, Prolog:copy_text(name))
}

let Prolog:Term:integer = fn (number:i64) -> Prolog:Term* {
    let self = Prolog:Term:new(2)
    if self { self.number = number }
    return self
}

let Prolog:Term:variable_owned = fn (state:Context*, name:u8*) -> Prolog:Term* {
    let self = Prolog:Term:new(3)
    if !self { if name { free(name) }; return cast(Prolog:Term*, 0) }
    self.name = name
    self.symbol = Prolog:categorize_symbol(state, "Variables", name)
    return self
}

let Prolog:Term:compound_owned = fn (state:Context*, name:u8*, args:Prolog:Term**, arity:i64) -> Prolog:Term* {
    let self = Prolog:Term:new(4)
    if !self {
        if name { free(name) }
        if args { free(cast(u8*, args)) }
        return cast(Prolog:Term*, 0)
    }
    self.name = name
    self.symbol = Prolog:categorize_symbol(state, "Atoms", name)
    self.args = args
    self.arity = arity
    return self
}

let Prolog:Term:deref = fn (term:Prolog:Term*) -> Prolog:Term* {
    var current = term
    while current && current.kind == 3 && current.binding {
        current = current.binding
    }
    return current
}

// Variables are shared by all occurrences with the same source name. Tree
// destruction therefore skips variable nodes; the parser's variable table owns
// and frees each variable exactly once.
let Prolog:Term:destroy_tree = fn (term:Prolog:Term*) -> void {
    if !term { return }
    if term.kind == 3 { return }
    if term.kind == 4 && term.args {
        var i = 0
        while i < term.arity {
            Prolog:Term:destroy_tree(term.args[i])
            i += 1
        }
        free(cast(u8*, term.args))
    }
    if term.name { free(term.name) }
    free(cast(u8*, term))
}

let Prolog:Term:callable = fn (term:Prolog:Term*) -> i64 {
    if !term { return 0 }
    return term.kind == 1 || term.kind == 4
}

let Prolog:Term:predicate_name = fn (term:Prolog:Term*) -> u8* {
    if !Prolog:Term:callable(term) { return cast(u8*, 0) }
    return term.name
}

let Prolog:Term:predicate_symbol = fn (term:Prolog:Term*) -> i64 {
    if !Prolog:Term:callable(term) { return 0 }
    return term.symbol
}

let Prolog:Term:predicate_arity = fn (term:Prolog:Term*) -> i64 {
    if !term { return -1 }
    if term.kind == 1 { return 0 }
    if term.kind == 4 { return term.arity }
    return -1
}

// =============================================================================
// Parser variable ownership and goal lists.
// =============================================================================

record Prolog:VarEntry {
    term:Prolog:Term*
    next:Prolog:VarEntry*
}

record Prolog:Goal {
    term:Prolog:Term*
    next:Prolog:Goal*
}

record Prolog:Parser {
    state:Context*
    source:u8*
    length:i64
    position:i64
    vars_head:Prolog:VarEntry*
    vars_tail:Prolog:VarEntry*
    error:i64
}

record Prolog:Clause {
    head:Prolog:Term*
    body:Prolog:Goal*
    vars_head:Prolog:VarEntry*
    vars_tail:Prolog:VarEntry*
}

record Prolog:Query {
    goals:Prolog:Goal*
    vars_head:Prolog:VarEntry*
    vars_tail:Prolog:VarEntry*
}

let Prolog:Parser:new = fn (state:Context*, source:u8*) -> Prolog:Parser* {
    let self = cast(Prolog:Parser*, malloc(56))
    if !self { return cast(Prolog:Parser*, 0) }
    self.state = state
    self.source = source
    self.length = cast(i64, strlen(source))
    self.position = 0
    self.vars_head = cast(Prolog:VarEntry*, 0)
    self.vars_tail = cast(Prolog:VarEntry*, 0)
    self.error = 0
    return self
}

let Prolog:Parser:fail = fn (self:Prolog:Parser*, message:u8*) -> void {
    if !self.error {
        self.error = 1
        context:diagnostic:error(self.state, message)
    }
}

let Prolog:Parser:skip = fn (self:Prolog:Parser*) -> void {
    var again = 1
    while again {
        again = 0
        while self.position < self.length && Prolog:is_space(self.source[self.position]) {
            self.position += 1
        }
        if self.position < self.length && self.source[self.position] == 37 {
            while self.position < self.length && self.source[self.position] != 10 {
                self.position += 1
            }
            again = 1
        }
    }
}

let Prolog:Parser:peek = fn (self:Prolog:Parser*) -> u8 {
    self.skip()
    if self.position >= self.length { return cast(u8, 0) }
    return self.source[self.position]
}

let Prolog:Parser:match_byte = fn (self:Prolog:Parser*, expected:u8) -> i64 {
    self.skip()
    if self.position < self.length && self.source[self.position] == expected {
        self.position += 1
        return 1
    }
    return 0
}

let Prolog:Parser:match_pair = fn (self:Prolog:Parser*, first:u8, second:u8) -> i64 {
    self.skip()
    if self.position + 1 < self.length && self.source[self.position] == first && self.source[self.position + 1] == second {
        self.position += 2
        return 1
    }
    return 0
}

let Prolog:Parser:identifier = fn (self:Prolog:Parser*) -> u8* {
    self.skip()
    if self.position >= self.length { return cast(u8*, 0) }
    let first = self.source[self.position]
    if !(Prolog:is_lower(first) || Prolog:is_upper(first) || first == 95) {
        return cast(u8*, 0)
    }
    let start = self.position
    self.position += 1
    while self.position < self.length && Prolog:is_ident_continue(self.source[self.position]) {
        self.position += 1
    }
    return Prolog:copy_bytes(&self.source[start], self.position - start)
}

let Prolog:Parser:quoted_atom = fn (self:Prolog:Parser*) -> u8* {
    self.skip()
    if self.position >= self.length || self.source[self.position] != 39 {
        return cast(u8*, 0)
    }
    self.position += 1
    let capacity = self.length - self.position + 1
    let out = malloc(capacity)
    if !out { self.fail("Prolog: out of memory while parsing quoted atom"); return cast(u8*, 0) }
    var length = 0
    var closed = 0
    while self.position < self.length && !closed {
        let ch = self.source[self.position]
        if ch == 92 && self.position + 1 < self.length {
            out[length] = self.source[self.position + 1]
            length += 1
            self.position += 2
        } else if ch == 39 {
            self.position += 1
            closed = 1
        } else {
            out[length] = ch
            length += 1
            self.position += 1
        }
    }
    if !closed {
        free(out)
        self.fail("Prolog: unterminated quoted atom")
        return cast(u8*, 0)
    }
    out[length] = 0
    return out
}

let Prolog:Parser:add_variable = fn (self:Prolog:Parser*, term:Prolog:Term*) -> i64 {
    let entry = cast(Prolog:VarEntry*, malloc(16))
    if !entry { self.fail("Prolog: out of memory while recording variable"); return 0 }
    entry.term = term
    entry.next = cast(Prolog:VarEntry*, 0)
    if self.vars_tail { self.vars_tail.next = entry }
    else { self.vars_head = entry }
    self.vars_tail = entry
    return 1
}

let Prolog:Parser:variable_owned = fn (self:Prolog:Parser*, name:u8*) -> Prolog:Term* {
    // Bare `_` is anonymous and is fresh on every occurrence.  The phrase
    // symbol represents the lexical spelling; the Term object remains the
    // clause-local logical variable identity.
    let symbol = Prolog:categorize_symbol(self.state, "Variables", name)
    if strcmp(name, "_") != 0 {
        var entry = self.vars_head
        while entry {
            if entry.term.symbol == symbol {
                free(name)
                return entry.term
            }
            entry = entry.next
        }
    }
    let term = Prolog:Term:variable_owned(self.state, name)
    if !term { self.fail("Prolog: out of memory while creating variable"); return cast(Prolog:Term*, 0) }
    if !self.add_variable(term) {
        if term.name { free(term.name) }
        free(cast(u8*, term))
        return cast(Prolog:Term*, 0)
    }
    return term
}

let Prolog:VarEntry:destroy_all = fn (entry:Prolog:VarEntry*) -> void {
    var current = entry
    while current {
        let next = current.next
        if current.term {
            if current.term.name { free(current.term.name) }
            free(cast(u8*, current.term))
        }
        free(cast(u8*, current))
        current = next
    }
}

let Prolog:Goal:destroy_all = fn (goal:Prolog:Goal*) -> void {
    var current = goal
    while current {
        let next = current.next
        Prolog:Term:destroy_tree(current.term)
        free(cast(u8*, current))
        current = next
    }
}

let Prolog:Parser:append_term = fn (items:Prolog:Term***, count:i64*, capacity:i64*, value:Prolog:Term*) -> i64 {
    if count[0] == capacity[0] {
        var next_capacity = capacity[0] * 2
        if next_capacity < 4 { next_capacity = 4 }
        let replacement = realloc(cast(u8*, items[0]), next_capacity * 8)
        if !replacement { return 0 }
        items[0] = cast(Prolog:Term**, replacement)
        capacity[0] = next_capacity
    }
    items[0][count[0]] = value
    count[0] += 1
    return 1
}

let Prolog:Parser:parse_term = fn (self:Prolog:Parser*) -> Prolog:Term* {
    self.skip()
    if self.position >= self.length {
        self.fail("Prolog: expected term")
        return cast(Prolog:Term*, 0)
    }

    let ch = self.source[self.position]

    // Lists are encoded as the ordinary Prolog '.'/2 functor and [] atom.
    if ch == 91 {
        self.position += 1
        self.skip()
        if self.match_byte(cast(u8, 93)) {
            return Prolog:Term:atom(self.state, "[]")
        }

        var items = cast(Prolog:Term**, 0)
        var count = 0
        var capacity = 0
        var tail = cast(Prolog:Term*, 0)
        var done = 0
        while !done && !self.error {
            let item = self.parse_term()
            if !item { done = 1 }
            else if !Prolog:Parser:append_term(&items, &count, &capacity, item) {
                self.fail("Prolog: out of memory while parsing list")
                done = 1
            } else {
                self.skip()
                if self.match_byte(cast(u8, 44)) {
                    // another element
                } else if self.match_byte(cast(u8, 124)) {
                    tail = self.parse_term()
                    if !self.match_byte(cast(u8, 93)) {
                        self.fail("Prolog: expected ']' after list tail")
                    }
                    done = 1
                } else if self.match_byte(cast(u8, 93)) {
                    tail = Prolog:Term:atom(self.state, "[]")
                    done = 1
                } else {
                    self.fail("Prolog: expected ',', '|' or ']' in list")
                    done = 1
                }
            }
        }

        if self.error || !tail {
            var cleanup = 0
            while cleanup < count { Prolog:Term:destroy_tree(items[cleanup]); cleanup += 1 }
            if items { free(cast(u8*, items)) }
            Prolog:Term:destroy_tree(tail)
            return cast(Prolog:Term*, 0)
        }

        var index = count
        while index > 0 {
            index -= 1
            let args = cast(Prolog:Term**, malloc(16))
            if !args {
                self.fail("Prolog: out of memory while building list")
                Prolog:Term:destroy_tree(tail)
                var cleanup = 0
                while cleanup <= index { Prolog:Term:destroy_tree(items[cleanup]); cleanup += 1 }
                free(cast(u8*, items))
                return cast(Prolog:Term*, 0)
            }
            args[0] = items[index]
            args[1] = tail
            tail = Prolog:Term:compound_owned(self.state, Prolog:copy_text("."), args, 2)
            if !tail {
                self.fail("Prolog: out of memory while building list cell")
                free(cast(u8*, items))
                return cast(Prolog:Term*, 0)
            }
        }
        if items { free(cast(u8*, items)) }
        return tail
    }

    // Signed decimal integers.
    if Prolog:is_digit(ch) || (ch == 45 && self.position + 1 < self.length && Prolog:is_digit(self.source[self.position + 1])) {
        var sign = 1
        if ch == 45 { sign = -1; self.position += 1 }
        var number = 0
        while self.position < self.length && Prolog:is_digit(self.source[self.position]) {
            number = number * 10 + self.source[self.position] - 48
            self.position += 1
        }
        return Prolog:Term:integer(number * sign)
    }

    var name = cast(u8*, 0)
    if ch == 39 { name = self.quoted_atom() }
    else { name = self.identifier() }
    if !name {
        self.fail("Prolog: expected atom, variable, integer, compound term or list")
        return cast(Prolog:Term*, 0)
    }

    let variable = Prolog:is_upper(name[0]) || name[0] == 95
    if variable {
        return self.variable_owned(name)
    }

    self.skip()
    if !self.match_byte(cast(u8, 40)) {
        return Prolog:Term:atom_owned(self.state, name)
    }

    var args = cast(Prolog:Term**, 0)
    var count = 0
    var capacity = 0
    self.skip()
    if !self.match_byte(cast(u8, 41)) {
        var done = 0
        while !done && !self.error {
            let arg = self.parse_term()
            if !arg {
                done = 1
            } else if !Prolog:Parser:append_term(&args, &count, &capacity, arg) {
                self.fail("Prolog: out of memory while parsing compound term")
                done = 1
            } else if self.match_byte(cast(u8, 44)) {
                // another argument
            } else if self.match_byte(cast(u8, 41)) {
                done = 1
            } else {
                self.fail("Prolog: expected ',' or ')' in compound term")
                done = 1
            }
        }
    }

    if self.error {
        var cleanup = 0
        while cleanup < count { Prolog:Term:destroy_tree(args[cleanup]); cleanup += 1 }
        if args { free(cast(u8*, args)) }
        free(name)
        return cast(Prolog:Term*, 0)
    }
    return Prolog:Term:compound_owned(self.state, name, args, count)
}

let Prolog:Parser:parse_goal = fn (self:Prolog:Parser*) -> Prolog:Term* {
    let left = self.parse_term()
    if !left { return cast(Prolog:Term*, 0) }
    self.skip()
    if self.match_byte(cast(u8, 61)) {
        let right = self.parse_term()
        if !right { Prolog:Term:destroy_tree(left); return cast(Prolog:Term*, 0) }
        let args = cast(Prolog:Term**, malloc(16))
        if !args {
            self.fail("Prolog: out of memory while parsing unification")
            Prolog:Term:destroy_tree(left)
            Prolog:Term:destroy_tree(right)
            return cast(Prolog:Term*, 0)
        }
        args[0] = left
        args[1] = right
        return Prolog:Term:compound_owned(self.state, Prolog:copy_text("="), args, 2)
    }
    return left
}

let Prolog:Parser:parse_goals_until_dot = fn (self:Prolog:Parser*) -> Prolog:Goal* {
    var head = cast(Prolog:Goal*, 0)
    var tail = cast(Prolog:Goal*, 0)
    var done = 0
    while !done && !self.error {
        let term = self.parse_goal()
        if !term { done = 1 }
        else {
            let goal = cast(Prolog:Goal*, malloc(16))
            if !goal {
                self.fail("Prolog: out of memory while parsing goal list")
                Prolog:Term:destroy_tree(term)
                done = 1
            } else {
                goal.term = term
                goal.next = cast(Prolog:Goal*, 0)
                if tail { tail.next = goal }
                else { head = goal }
                tail = goal
                self.skip()
                if self.match_byte(cast(u8, 44)) {
                    // another conjunct
                } else if self.match_byte(cast(u8, 46)) {
                    done = 1
                } else {
                    self.fail("Prolog: expected ',' or '.' after goal")
                    done = 1
                }
            }
        }
    }
    if self.error {
        Prolog:Goal:destroy_all(head)
        return cast(Prolog:Goal*, 0)
    }
    return head
}

let Prolog:Parser:parse_clause = fn (self:Prolog:Parser*) -> Prolog:Clause* {
    let head = self.parse_term()
    if !head { return cast(Prolog:Clause*, 0) }
    if !Prolog:Term:callable(head) {
        self.fail("Prolog: clause head must be an atom or compound term")
        Prolog:Term:destroy_tree(head)
        return cast(Prolog:Clause*, 0)
    }

    var body = cast(Prolog:Goal*, 0)
    self.skip()
    if self.match_pair(cast(u8, 58), cast(u8, 45)) {
        body = self.parse_goals_until_dot()
        if self.error {
            Prolog:Term:destroy_tree(head)
            return cast(Prolog:Clause*, 0)
        }
    } else if !self.match_byte(cast(u8, 46)) {
        self.fail("Prolog: expected ':-' or '.' after clause head")
        Prolog:Term:destroy_tree(head)
        return cast(Prolog:Clause*, 0)
    }

    self.skip()
    if self.position != self.length {
        self.fail("Prolog: unexpected text after clause terminator")
        Prolog:Term:destroy_tree(head)
        Prolog:Goal:destroy_all(body)
        return cast(Prolog:Clause*, 0)
    }

    let clause = cast(Prolog:Clause*, malloc(32))
    if !clause {
        self.fail("Prolog: out of memory while creating clause")
        Prolog:Term:destroy_tree(head)
        Prolog:Goal:destroy_all(body)
        return cast(Prolog:Clause*, 0)
    }
    clause.head = head
    clause.body = body
    clause.vars_head = self.vars_head
    clause.vars_tail = self.vars_tail
    self.vars_head = cast(Prolog:VarEntry*, 0)
    self.vars_tail = cast(Prolog:VarEntry*, 0)
    return clause
}

let Prolog:Parser:parse_query = fn (self:Prolog:Parser*) -> Prolog:Query* {
    let goals = self.parse_goals_until_dot()
    if self.error { return cast(Prolog:Query*, 0) }
    self.skip()
    if self.position != self.length {
        self.fail("Prolog: unexpected text after query terminator")
        Prolog:Goal:destroy_all(goals)
        return cast(Prolog:Query*, 0)
    }
    let query = cast(Prolog:Query*, malloc(24))
    if !query {
        self.fail("Prolog: out of memory while creating query")
        Prolog:Goal:destroy_all(goals)
        return cast(Prolog:Query*, 0)
    }
    query.goals = goals
    query.vars_head = self.vars_head
    query.vars_tail = self.vars_tail
    self.vars_head = cast(Prolog:VarEntry*, 0)
    self.vars_tail = cast(Prolog:VarEntry*, 0)
    return query
}

let Prolog:Parser:destroy = fn (self:Prolog:Parser*) -> void {
    if !self { return }
    if self.vars_head { Prolog:VarEntry:destroy_all(self.vars_head) }
    free(cast(u8*, self))
}

let Prolog:Clause:destroy = fn (self:Prolog:Clause*) -> void {
    if !self { return }
    Prolog:Term:destroy_tree(self.head)
    Prolog:Goal:destroy_all(self.body)
    Prolog:VarEntry:destroy_all(self.vars_head)
    free(cast(u8*, self))
}

let Prolog:Query:destroy = fn (self:Prolog:Query*) -> void {
    if !self { return }
    Prolog:Goal:destroy_all(self.goals)
    Prolog:VarEntry:destroy_all(self.vars_head)
    free(cast(u8*, self))
}

let Prolog:parse_clause = fn (state:Context*, source:u8*) -> Prolog:Clause* {
    let parser = Prolog:Parser:new(state, source)
    if !parser { context:diagnostic:error(state, "Prolog: could not allocate parser"); return cast(Prolog:Clause*, 0) }
    defer parser.destroy()
    return parser.parse_clause()
}

let Prolog:parse_query = fn (state:Context*, source:u8*) -> Prolog:Query* {
    let parser = Prolog:Parser:new(state, source)
    if !parser { context:diagnostic:error(state, "Prolog: could not allocate parser"); return cast(Prolog:Query*, 0) }
    defer parser.destroy()
    return parser.parse_query()
}

// =============================================================================
// Clause database. Source is deliberately retained as Prolog text; every
// predicate invocation reparses a matching clause, giving each invocation a
// fresh set of logical variables without any host-language special case.
// =============================================================================

record Prolog:ClauseSource {
    text:u8*
    name:u8*
    symbol:i64
    arity:i64
    next:Prolog:ClauseSource*
}

record Prolog:Database {
    head:Prolog:ClauseSource*
    tail:Prolog:ClauseSource*
}

let Prolog:Database:new = fn () -> Prolog:Database* {
    let self = cast(Prolog:Database*, malloc(16))
    if !self { return cast(Prolog:Database*, 0) }
    self.head = cast(Prolog:ClauseSource*, 0)
    self.tail = cast(Prolog:ClauseSource*, 0)
    return self
}

let Prolog:database = fn (state:Context*) -> Prolog:Database* {
    let existing = cast(Prolog:Database*, Prolog:state_get(state, "__prolog_database"))
    if existing { return existing }
    let created = Prolog:Database:new()
    if !created {
        context:diagnostic:error(state, "Prolog: could not allocate clause database")
        return cast(Prolog:Database*, 0)
    }
    if !Prolog:state_set(state, "__prolog_database", cast(i64, created)) {
        free(cast(u8*, created))
        context:diagnostic:error(state, "Prolog: could not store clause database")
        return cast(Prolog:Database*, 0)
    }
    Prolog:categorize_symbol(state, "Builtins", "true")
    Prolog:categorize_symbol(state, "Builtins", "fail")
    Prolog:categorize_symbol(state, "Builtins", "=")
    Prolog:categorize_symbol(state, "Operators", ":-")
    Prolog:categorize_symbol(state, "Operators", ",")
    Prolog:categorize_symbol(state, "Operators", ".")
    Prolog:categorize_symbol(state, "Operators", "|")
    return created
}

let Prolog:Database:add = fn (self:Prolog:Database*, state:Context*, text:u8*) -> i64 {
    let parsed = Prolog:parse_clause(state, text)
    if !parsed { return 0 }
    let name = Prolog:copy_text(Prolog:Term:predicate_name(parsed.head))
    let arity = Prolog:Term:predicate_arity(parsed.head)
    parsed.destroy()
    if !name { context:diagnostic:error(state, "Prolog: out of memory while indexing clause"); return 0 }

    let item = cast(Prolog:ClauseSource*, malloc(40))
    if !item {
        free(name)
        context:diagnostic:error(state, "Prolog: out of memory while storing clause")
        return 0
    }
    item.text = text
    item.name = name
    item.symbol = Prolog:categorize_symbol(state, "Predicates", name)
    Prolog:categorize_symbol(state, "Grammar", name)
    item.arity = arity
    item.next = cast(Prolog:ClauseSource*, 0)
    if self.tail { self.tail.next = item }
    else { self.head = item }
    self.tail = item
    return 1
}

// =============================================================================
// Trail and unification.
// =============================================================================

record Prolog:Trail {
    items:Prolog:Term**
    length:i64
    capacity:i64
}

let Prolog:Trail:new = fn () -> Prolog:Trail* {
    let self = cast(Prolog:Trail*, malloc(24))
    if !self { return cast(Prolog:Trail*, 0) }
    self.items = cast(Prolog:Term**, 0)
    self.length = 0
    self.capacity = 0
    return self
}

let Prolog:Trail:destroy = fn (self:Prolog:Trail*) -> void {
    if !self { return }
    if self.items { free(cast(u8*, self.items)) }
    free(cast(u8*, self))
}

let Prolog:Trail:push = fn (self:Prolog:Trail*, variable:Prolog:Term*) -> i64 {
    if self.length == self.capacity {
        var capacity = self.capacity * 2
        if capacity < 16 { capacity = 16 }
        let replacement = realloc(cast(u8*, self.items), capacity * 8)
        if !replacement { return 0 }
        self.items = cast(Prolog:Term**, replacement)
        self.capacity = capacity
    }
    self.items[self.length] = variable
    self.length += 1
    return 1
}

let Prolog:Trail:undo = fn (self:Prolog:Trail*, mark:i64) -> void {
    while self.length > mark {
        self.length -= 1
        self.items[self.length].binding = cast(Prolog:Term*, 0)
    }
}

let Prolog:unify = fn (left:Prolog:Term*, right:Prolog:Term*, trail:Prolog:Trail*) -> i64 {
    let a = Prolog:Term:deref(left)
    let b = Prolog:Term:deref(right)
    if !a || !b { return 0 }
    if a == b { return 1 }

    if a.kind == 3 {
        if !trail.push(a) { return 0 }
        a.binding = b
        return 1
    }
    if b.kind == 3 {
        if !trail.push(b) { return 0 }
        b.binding = a
        return 1
    }

    if a.kind != b.kind { return 0 }
    if a.kind == 2 { return a.number == b.number }
    if a.kind == 1 { return a.symbol == b.symbol }
    if a.kind != 4 { return 0 }
    if a.arity != b.arity || a.symbol != b.symbol { return 0 }

    var i = 0
    while i < a.arity {
        if !Prolog:unify(a.args[i], b.args[i], trail) { return 0 }
        i += 1
    }
    return 1
}

// =============================================================================
// Solution rendering.
// =============================================================================

let Prolog:Term:is_list_cell = fn (term:Prolog:Term*) -> i64 {
    let value = Prolog:Term:deref(term)
    return value && value.kind == 4 && value.arity == 2 && strcmp(value.name, ".") == 0
}

let Prolog:Term:is_nil = fn (term:Prolog:Term*) -> i64 {
    let value = Prolog:Term:deref(term)
    return value && value.kind == 1 && strcmp(value.name, "[]") == 0
}

let Prolog:Term:print = fn (term:Prolog:Term*) -> void {
    let value = Prolog:Term:deref(term)
    if !value { printf("%s", "<null>"); return }
    if value.kind == 2 { printf("%lld", value.number); return }
    if value.kind == 3 { printf("%s", value.name); return }
    if value.kind == 1 { printf("%s", value.name); return }

    if Prolog:Term:is_list_cell(value) {
        printf("%s", "[")
        var current = value
        var first = 1
        var done = 0
        while !done {
            let cell = Prolog:Term:deref(current)
            if Prolog:Term:is_list_cell(cell) {
                if !first { printf("%s", ", ") }
                Prolog:Term:print(cell.args[0])
                first = 0
                current = cell.args[1]
            } else if Prolog:Term:is_nil(cell) {
                done = 1
            } else {
                printf("%s", " | ")
                Prolog:Term:print(cell)
                done = 1
            }
        }
        printf("%s", "]")
        return
    }

    printf("%s(", value.name)
    var i = 0
    while i < value.arity {
        if i > 0 { printf("%s", ", ") }
        Prolog:Term:print(value.args[i])
        i += 1
    }
    printf("%s", ")")
}

record Prolog:Solver {
    state:Context*
    database:Prolog:Database*
    query_vars:Prolog:VarEntry*
    solutions:i64
}

let Prolog:Solver:emit_solution = fn (self:Prolog:Solver*) -> void {
    self.solutions += 1
    var entry = self.query_vars
    var shown = 0
    while entry {
        if strcmp(entry.term.name, "_") != 0 {
            if shown { printf("%s", ", ") }
            printf("%s = ", entry.term.name)
            Prolog:Term:print(entry.term)
            shown = 1
        }
        entry = entry.next
    }
    if !shown { printf("%s", "true") }
    printf("%s", ".\n")
}

// =============================================================================
// Depth-first resolution with explicit trail rollback.
// =============================================================================

let Prolog:Goal:tail = fn (goal:Prolog:Goal*) -> Prolog:Goal* {
    var current = goal
    if !current { return cast(Prolog:Goal*, 0) }
    while current.next { current = current.next }
    return current
}

let Prolog:solve_goals = fn (
    solver:Prolog:Solver*, goals:Prolog:Goal*, trail:Prolog:Trail*, depth:i64
) -> i64 {
    if !goals {
        solver.emit_solution()
        return 1
    }
    if depth > 256 {
        context:diagnostic:error(solver.state, "Prolog: resolution depth exceeded 256")
        return 0
    }

    let goal_term = Prolog:Term:deref(goals.term)
    if !goal_term { return 0 }

    // Built-in unification.
    if goal_term.kind == 4 && goal_term.arity == 2 && goal_term.symbol == Prolog:intern_symbol(solver.state, "=") {
        let mark = trail.length
        var total = 0
        if Prolog:unify(goal_term.args[0], goal_term.args[1], trail) {
            total = Prolog:solve_goals(solver, goals.next, trail, depth + 1)
        }
        trail.undo(mark)
        return total
    }

    // Tiny pure built-in set used by the compatibility tests.
    if goal_term.kind == 1 && goal_term.symbol == Prolog:intern_symbol(solver.state, "true") {
        return Prolog:solve_goals(solver, goals.next, trail, depth + 1)
    }
    if goal_term.kind == 1 && goal_term.symbol == Prolog:intern_symbol(solver.state, "fail") {
        return 0
    }
    if !Prolog:Term:callable(goal_term) { return 0 }

    let wanted_name = Prolog:Term:predicate_name(goal_term)
    let wanted_symbol = Prolog:Term:predicate_symbol(goal_term)
    let wanted_arity = Prolog:Term:predicate_arity(goal_term)
    var candidate = solver.database.head
    var total = 0

    while candidate {
        if candidate.arity == wanted_arity && candidate.symbol == wanted_symbol {
            // Reparse for every choice-point entry: clause-local variables are
            // therefore fresh even during recursion through the same clause.
            let clause = Prolog:parse_clause(solver.state, candidate.text)
            if !clause { return total }
            let mark = trail.length
            if Prolog:unify(goal_term, clause.head, trail) {
                if clause.body {
                    let tail = Prolog:Goal:tail(clause.body)
                    tail.next = goals.next
                    total += Prolog:solve_goals(solver, clause.body, trail, depth + 1)
                    tail.next = cast(Prolog:Goal*, 0)
                } else {
                    total += Prolog:solve_goals(solver, goals.next, trail, depth + 1)
                }
            }
            trail.undo(mark)
            clause.destroy()
        }
        candidate = candidate.next
    }
    return total
}

let Prolog:run_query = fn (state:Context*, source:u8*) -> i64 {
    let query = Prolog:parse_query(state, source)
    if !query { return 0 }
    defer query.destroy()
    let database = Prolog:database(state)
    if !database { return 0 }
    let trail = Prolog:Trail:new()
    if !trail { context:diagnostic:error(state, "Prolog: could not allocate trail"); return 0 }
    defer trail.destroy()
    let solver = cast(Prolog:Solver*, malloc(32))
    if !solver { context:diagnostic:error(state, "Prolog: could not allocate solver"); return 0 }
    defer free(cast(u8*, solver))
    solver.state = state
    solver.database = database
    solver.query_vars = query.vars_head
    solver.solutions = 0
    Prolog:solve_goals(solver, query.goals, trail, 0)
    if solver.solutions == 0 { printf("%s", "false.\n") }
    return solver.solutions
}

// =============================================================================
// Source statement capture.
// =============================================================================

// Find the first statement-ending '.' outside comments, quoted atoms,
// parentheses and lists. Returns the byte count including '.', or -1.
let Prolog:statement_end = fn (source:u8*, bytes:i64) -> i64 {
    var i = 0
    var parens = 0
    var brackets = 0
    var quoted = 0
    var comment = 0
    while i < bytes {
        let ch = source[i]
        if comment {
            if ch == 10 { comment = 0 }
            i += 1
        } else if quoted {
            if ch == 92 && i + 1 < bytes { i += 2 }
            else {
                if ch == 39 { quoted = 0 }
                i += 1
            }
        } else if ch == 37 {
            comment = 1
            i += 1
        } else if ch == 39 {
            quoted = 1
            i += 1
        } else {
            if ch == 40 { parens += 1 }
            else if ch == 41 { parens -= 1 }
            else if ch == 91 { brackets += 1 }
            else if ch == 93 { brackets -= 1 }
            else if ch == 46 && parens == 0 && brackets == 0 { return i + 1 }
            i += 1
        }
    }
    return -1
}

let Prolog:only_trivia = fn (source:u8*, bytes:i64) -> i64 {
    var i = 0
    while i < bytes {
        if Prolog:is_space(source[i]) { i += 1 }
        else if source[i] == 37 {
            while i < bytes && source[i] != 10 { i += 1 }
        } else { return 0 }
    }
    return 1
}

let Prolog:current_line_is_comment = fn (state:Context*) -> i64 {
    let source = cast(u8*, context:source:data(state))
    let bytes = context:source:bytes(state)
    var i = 0
    while i < bytes && (source[i] == 32 || source[i] == 9 || source[i] == 13) { i += 1 }
    return i < bytes && source[i] == 37
}

let Prolog:consume_current_line = fn (state:Context*) -> void {
    let source = cast(u8*, context:source:data(state))
    let bytes = context:source:bytes(state)
    var i = 0
    while i < bytes && source[i] != 10 && source[i] != 13 { i += 1 }
    if i < bytes && source[i] == 13 {
        i += 1
        if i < bytes && source[i] == 10 { i += 1 }
    } else if i < bytes && source[i] == 10 { i += 1 }
    context:source:advance(state, i)
}

let Prolog:capture_statement = fn (state:Context*) -> u8* {
    // Files used as language inputs are intentionally bounded to 1 MiB per
    // top-level statement for this experiment. `ensure` streams additional
    // lines into the current source window before we scan for the final '.'.
    context:source:ensure(state, 1048576)
    let source = cast(u8*, context:source:data(state))
    let bytes = context:source:bytes(state)
    if bytes <= 0 { return cast(u8*, 0) }
    let finish = Prolog:statement_end(source, bytes)
    if finish < 0 {
        if Prolog:only_trivia(source, bytes) {
            context:source:advance(state, bytes)
            return cast(u8*, 0)
        }
        context:diagnostic:error(state, "Prolog: expected '.' to terminate statement")
        return cast(u8*, 0)
    }
    let text = Prolog:copy_bytes(source, finish)
    if !text {
        context:diagnostic:error(state, "Prolog: out of memory while capturing statement")
        return cast(u8*, 0)
    }
    context:source:advance(state, finish)
    return text
}

// =============================================================================
// Language phrases.
// =============================================================================

// Explicit query marker wins longest-prefix lookup over the empty-key fallback.
let "?-" = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = Prolog:capture_statement(state)
        if source {
            Prolog:run_query(state, source)
            free(source)
        }
        context:source:root(state)
    }
}

// Unknown top-level source is a Prolog clause. The fallback is installed only
// in the language image; ordinary longer RecurLoop phrases still win lookup.
let Prolog:top_clause = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        // A standalone `% ...` line is consumed as trivia and then control is
        // returned to the root dictionary. This matters when the following
        // line begins with the explicit `?-` query phrase.
        if Prolog:current_line_is_comment(state) {
            Prolog:consume_current_line(state)
            context:source:root(state)
            return
        }
        let source = Prolog:capture_statement(state)
        if source {
            let database = Prolog:database(state)
            if database {
                if !database.add(state, source) { free(source) }
            } else { free(source) }
        }
        context:source:root(state)
    }
}

// RecurLoop-side introspection hook.  Example after loading Prolog source:
//   prolog_assert predicate ancestor
// This intentionally uses ordinary phrase lookup rather than consulting the
// Prolog clause database.
let Prolog:assert_symbol_phrase = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        context:source:ensure(state, 4096)
        let source = cast(u8*, context:source:data(state))
        let bytes = context:source:bytes(state)
        var i = 0
        while i < bytes && Prolog:is_space(source[i]) { i += 1 }
        let cs = i
        while i < bytes && Prolog:is_ident_continue(source[i]) { i += 1 }
        let category = Prolog:copy_bytes(&source[cs], i - cs)
        while i < bytes && Prolog:is_space(source[i]) { i += 1 }
        let ns = i
        while i < bytes && !Prolog:is_space(source[i]) { i += 1 }
        let name = Prolog:copy_bytes(&source[ns], i - ns)
        var owner = cast(u8*, 0)
        if category {
            if strcmp(category, "predicate") == 0 { owner = "Predicates" }
            else if strcmp(category, "atom") == 0 { owner = "Atoms" }
            else if strcmp(category, "variable") == 0 { owner = "Variables" }
            else if strcmp(category, "builtin") == 0 { owner = "Builtins" }
            else if strcmp(category, "operator") == 0 { owner = "Operators" }
            else if strcmp(category, "grammar") == 0 { owner = "Grammar" }
            else if strcmp(category, "symbol") == 0 { owner = "Symbols" }
        }
        if !owner || !name || !Prolog:symbol_in(state, owner, name) {
            context:diagnostic:error(state, "Prolog: expected phrase-backed symbol is missing")
        }
        if category { free(category) }
        if name { free(name) }
        while i < bytes && source[i] != 10 && source[i] != 13 { i += 1 }
        if i < bytes { i += 1 }
        context:source:advance(state, i)
        context:source:root(state)
    }
}

let prolog_assert = <Prolog:assert_symbol_phrase>

let install_prolog_fallback = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let prolog = context:phrase:find(state, "Prolog")
        let top_clause = context:phrase:find:exact(state, prolog, "top_clause")
        let fallback = context:phrase:define:alias(state, "", top_clause)
        if !fallback { context:diagnostic:error(state, "Prolog: could not install top-level clause fallback") }
    }
}

install_prolog_fallback

// Never serialize process-local libc bindings or the one-shot installer.
set malloc.serializable = false
set realloc.serializable = false
set free.serializable = false
set memcpy.serializable = false
set strlen.serializable = false
set strcmp.serializable = false
set printf.serializable = false
set install_prolog_fallback.serializable = false

engine export "/tmp/recurloop-prolog-library.rli"
