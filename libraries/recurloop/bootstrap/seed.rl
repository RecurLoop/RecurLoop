// =============================================================================
// RecurLoop seed language
//
// This is NOT a vocabulary alias over the current RecurLoop language.
// It is a bootstrap experiment for the language that may eventually replace
// most of the current startup grammar.
//
// Irreducible public seed surface:
//
//   proc  name (typed-parameters) -> type { native body }
//   form  spelling = handler-proc
//
// `shape` is provided later in this file as the first self-hosted form built
// from proc + form; it is deliberately not a kernel root.
//
// These kernel forms are independently implemented through the Context API.
// They do not prototype/alias `let`, `var`, `fn`, `record`, or `phrase`.
//
// Current host contracts still used by the implementation:
//   - phrase/source/type Context API;
//   - context:function:compile for native function bodies;
// The seed requires no generated legacy declarations while extending syntax:
// `form` stores native handler symbols in a Phrase dictionary and one fallback
// dispatches them. The remaining high-level dependency is therefore isolated
// to the body language accepted by context:function:compile. That boundary can
// later be replaced by a tiny IR-builder ABI without changing this source model.
// =============================================================================

link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

// Bootstrap-only implementation namespace.  These declarations belong to the
// old host language because that is what is available today; programs importing
// the resulting image use only proc/shape/form.
let RecurLoopSeed = phrase { dictionary = true permanent = true }
let RecurLoopSeed:Forms = phrase { dictionary = true permanent = true }
let RecurLoopSeed:Action = fn (state:Context*, called:Phrase*) -> void
let RecurLoopSeed:I64Call0 = fn () -> i64
let RecurLoopSeed:I64Call1 = fn (a:i64) -> i64
let RecurLoopSeed:I64Call2 = fn (a:i64, b:i64) -> i64

let RecurLoopSeed:is_space = fn (ch:i64) -> i64 {
    return ch == 32 || ch == 9 || ch == 10 || ch == 13
}

let RecurLoopSeed:is_name = fn (ch:i64) -> i64 {
    return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) ||
           (ch >= 48 && ch <= 57) || ch == 95 || ch == 58 || ch == 45
}

let RecurLoopSeed:is_field_name = fn (ch:i64) -> i64 {
    return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) ||
           (ch >= 48 && ch <= 57) || ch == 95 || ch == 45
}

let RecurLoopSeed:copy_slice = fn (text:u8*, start:i64, finish:i64) -> u8* {
    if !text || start < 0 || finish < start { return cast(u8*, 0) }
    let bytes = finish - start
    let out = cast(u8*, malloc(bytes + 1))
    if !out { return cast(u8*, 0) }
    var i = 0
    while i < bytes { out[i] = text[start + i]; i += 1 }
    out[bytes] = 0
    return out
}

let RecurLoopSeed:skip_space = fn (text:u8*, index:i64) -> i64 {
    while text[index] != 0 && RecurLoopSeed:is_space(text[index]) { index += 1 }
    return index
}

let RecurLoopSeed:trim_finish = fn (text:u8*, start:i64, finish:i64) -> i64 {
    while finish > start && RecurLoopSeed:is_space(text[finish - 1]) { finish -= 1 }
    return finish
}

let RecurLoopSeed:text_length = fn (text:u8*) -> i64 {
    if !text { return 0 }
    var i = 0
    while text[i] != 0 { i += 1 }
    return i
}

let RecurLoopSeed:parse_name = fn (text:u8*, start:i64, finish_out:i64*) -> u8* {
    var i = RecurLoopSeed:skip_space(text, start)
    let begin = i
    while text[i] != 0 && RecurLoopSeed:is_name(text[i]) { i += 1 }
    if i == begin { return cast(u8*, 0) }
    finish_out[0] = i
    return RecurLoopSeed:copy_slice(text, begin, i)
}

let RecurLoopSeed:resolve_type = fn (state:Context*, text:u8*, start:i64, finish:i64) -> i64 {
    start = RecurLoopSeed:skip_space(text, start)
    finish = RecurLoopSeed:trim_finish(text, start, finish)
    if finish <= start { return 0 }

    // Parse a single optional [N] array suffix, then arbitrary pointer depth.
    var array_count = 0
    if finish > start && text[finish - 1] == 93 {
        var close = finish - 1
        var open = close - 1
        while open >= start && text[open] != 91 { open -= 1 }
        if open >= start {
            var count = 0
            var i = open + 1
            if i == close { return 0 }
            while i < close {
                if text[i] < 48 || text[i] > 57 { return 0 }
                count = count * 10 + text[i] - 48
                i += 1
            }
            if count <= 0 { return 0 }
            array_count = count
            finish = RecurLoopSeed:trim_finish(text, start, open)
        }
    }

    var pointers = 0
    while finish > start {
        finish = RecurLoopSeed:trim_finish(text, start, finish)
        if finish <= start || text[finish - 1] != 42 { break }
        pointers += 1
        finish -= 1
    }
    finish = RecurLoopSeed:trim_finish(text, start, finish)
    let base_name = RecurLoopSeed:copy_slice(text, start, finish)
    if !base_name { return 0 }
    let type = context:type:find(state, base_name)
    free(base_name)
    if !type { return 0 }

    var result = type
    var p = 0
    while p < pointers { result = context:type:pointer(state, result); p += 1 }
    if array_count > 0 { result = context:type:array(state, result, array_count) }
    return result
}

// -----------------------------------------------------------------------------
// proc
//
// Parses only the declaration shell.  The body is opaque to this phrase and is
// sent to context:function:compile.  This intentionally isolates the remaining
// host dependency to one API boundary.
// -----------------------------------------------------------------------------

let RecurLoopSeed:proc_action = fn (state:Context*, called:Phrase*) -> void {
    let block = context:source:block:capture(state)
    if !block { context:diagnostic:error(state, "proc expects a body block"); return }
    defer context:source:block:release(block)

    let header = context:source:block:header(block)
    let body = context:source:block:body(block)
    if !header || !body { context:diagnostic:error(state, "proc could not capture source"); return }

    var after_name = 0
    let name = RecurLoopSeed:parse_name(header, 0, &after_name)
    if !name { context:diagnostic:error(state, "proc expects a function name"); return }
    defer free(name)

    var sig_start = RecurLoopSeed:skip_space(header, after_name)
    let header_bytes = RecurLoopSeed:text_length(header)
    let sig_finish = RecurLoopSeed:trim_finish(header, sig_start, header_bytes)
    if sig_start >= sig_finish || header[sig_start] != 40 {
        context:diagnostic:error(state, "proc expects: proc name (args...) -> type { ... }")
        return
    }

    let signature = RecurLoopSeed:copy_slice(header, sig_start, sig_finish)
    if !signature { context:diagnostic:error(state, "proc: out of memory"); return }
    defer free(signature)

    if !context:function:compile(state, signature, body, name) {
        context:diagnostic:error(state, "proc could not compile native function")
    }
}

// -----------------------------------------------------------------------------
// shape
//
// Structure layout is created directly through context:type:* and phrase field
// metadata.  No `record` phrase is used or prototyped.
// -----------------------------------------------------------------------------

let RecurLoopSeed:shape_action = fn (state:Context*, called:Phrase*) -> void {
    let block = context:source:block:capture(state)
    if !block { context:diagnostic:error(state, "shape expects a body block"); return }
    defer context:source:block:release(block)

    let header = context:source:block:header(block)
    let body = context:source:block:body(block)
    if !header || !body { context:diagnostic:error(state, "shape could not capture source"); return }

    var after_name = 0
    let name = RecurLoopSeed:parse_name(header, 0, &after_name)
    if !name { context:diagnostic:error(state, "shape expects a type name"); return }
    defer free(name)
    after_name = RecurLoopSeed:skip_space(header, after_name)
    if header[after_name] != 0 { context:diagnostic:error(state, "shape header accepts only a type name"); return }

    // Declare before parsing fields so self-referential pointer fields work.
    let structure = context:type:structure:declare(state, name)
    if !structure { context:diagnostic:error(state, "shape could not declare structure type"); return }

    let name_bytes = RecurLoopSeed:text_length(name)
    let prefix = "__recurloop_seed_fields_"
    let prefix_bytes = RecurLoopSeed:text_length(prefix)
    let owner_name = cast(u8*, malloc(prefix_bytes + name_bytes + 1))
    if !owner_name { context:diagnostic:error(state, "shape: out of memory"); return }
    defer free(owner_name)
    var copied = 0
    while copied < prefix_bytes { owner_name[copied] = prefix[copied]; copied += 1 }
    var ni = 0
    while ni < name_bytes { owner_name[prefix_bytes + ni] = name[ni]; ni += 1 }
    owner_name[prefix_bytes + name_bytes] = 0

    let owner = context:phrase:define:dictionary(state, owner_name)
    if !owner { context:diagnostic:error(state, "shape could not create field dictionary"); return }

    var i = 0
    var last_field = 0
    var fields = 0
    while 1 {
        while body[i] != 0 && (RecurLoopSeed:is_space(body[i]) || body[i] == 44 || body[i] == 59) { i += 1 }
        if body[i] == 0 { break }

        let field_start = i
        while body[i] != 0 && RecurLoopSeed:is_field_name(body[i]) { i += 1 }
        if i == field_start { context:diagnostic:error(state, "shape expected a field name"); return }
        let field_name = RecurLoopSeed:copy_slice(body, field_start, i)
        if !field_name { context:diagnostic:error(state, "shape: out of memory"); return }
        defer free(field_name)

        while RecurLoopSeed:is_space(body[i]) { i += 1 }
        if body[i] != 58 { context:diagnostic:error(state, "shape field expects ':' before type"); return }
        i += 1
        while RecurLoopSeed:is_space(body[i]) { i += 1 }
        let type_start = i

        // Type ends at comma, semicolon, newline, or whitespace followed by a
        // new field. Pointer stars and one [N] suffix are handled by resolver.
        var bracket = 0
        while body[i] != 0 {
            if body[i] == 91 { bracket += 1; i += 1; continue }
            if body[i] == 93 { if bracket > 0 { bracket -= 1 }; i += 1; continue }
            if bracket == 0 && (body[i] == 44 || body[i] == 59 || body[i] == 10 || body[i] == 13) { break }
            if bracket == 0 && (body[i] == 32 || body[i] == 9) {
                // Stop only if the following non-space token looks like the
                // next `name:` field; otherwise whitespace belongs to type.
                var probe = i
                while body[probe] == 32 || body[probe] == 9 { probe += 1 }
                var p = probe
                while RecurLoopSeed:is_field_name(body[p]) { p += 1 }
                var q = p
                while body[q] == 32 || body[q] == 9 { q += 1 }
                if p > probe && body[q] == 58 { break }
            }
            i += 1
        }
        let type_finish = RecurLoopSeed:trim_finish(body, type_start, i)
        let field_type = RecurLoopSeed:resolve_type(state, body, type_start, type_finish)
        if !field_type { context:diagnostic:error(state, "shape could not resolve field type"); return }

        var field = 0
        if last_field { field = context:phrase:define:successor(state, owner, field_name, last_field) }
        else { field = context:phrase:define:data(state, owner, field_name) }
        if !field { context:diagnostic:error(state, "shape could not define field metadata"); return }
        context:phrase:data(state, field, &field_type, 0, 8)
        last_field = field
        fields += 1
    }

    if fields == 0 { context:diagnostic:error(state, "shape requires at least one field"); return }
    if !context:type:structure:complete:natural(state, structure, last_field) {
        context:diagnostic:error(state, "shape could not complete structure layout")
    }
}

// -----------------------------------------------------------------------------
// form
//
// `form word = handler` stores a mapping in RecurLoopSeed:Forms. A single root
// fallback performs radix/lexicon longest-match against that dictionary and
// dispatches to the compiled native symbol. New language forms therefore do
// not create or clone host-language declarations at all.
// -----------------------------------------------------------------------------

let RecurLoopSeed:forms_owner = fn (state:Context*) -> i64 {
    let seed = context:phrase:find(state, "RecurLoopSeed")
    if !seed { return 0 }
    return context:phrase:find:exact(state, seed, "Forms")
}

let RecurLoopSeed:form_action = fn (state:Context*, called:Phrase*) -> void {
    // Consume: <spaces> spelling <spaces> = <spaces> handler [;]
    while RecurLoopSeed:is_space(context:source:peek(state, 0)) { context:source:advance(state, 1) }

    var name_bytes = 0
    while RecurLoopSeed:is_name(context:source:peek(state, name_bytes)) { name_bytes += 1 }
    if name_bytes <= 0 { context:diagnostic:error(state, "form expects a source spelling"); return }
    let name = cast(u8*, malloc(name_bytes + 1))
    if !name { context:diagnostic:error(state, "form: out of memory"); return }
    defer free(name)
    var i = 0
    while i < name_bytes { name[i] = context:source:peek(state, i); i += 1 }
    name[name_bytes] = 0
    context:source:advance(state, name_bytes)

    while context:source:peek(state, 0) == 32 || context:source:peek(state, 0) == 9 { context:source:advance(state, 1) }
    if context:source:peek(state, 0) != 61 { context:diagnostic:error(state, "form expects '='"); return }
    context:source:advance(state, 1)
    while context:source:peek(state, 0) == 32 || context:source:peek(state, 0) == 9 { context:source:advance(state, 1) }

    var handler_bytes = 0
    while RecurLoopSeed:is_name(context:source:peek(state, handler_bytes)) { handler_bytes += 1 }
    if handler_bytes <= 0 { context:diagnostic:error(state, "form expects a handler proc name"); return }
    let handler = cast(u8*, malloc(handler_bytes + 1))
    if !handler { context:diagnostic:error(state, "form: out of memory"); return }
    defer free(handler)
    i = 0
    while i < handler_bytes { handler[i] = context:source:peek(state, i); i += 1 }
    handler[handler_bytes] = 0
    context:source:advance(state, handler_bytes)

    while context:source:peek(state, 0) == 32 || context:source:peek(state, 0) == 9 { context:source:advance(state, 1) }
    if context:source:peek(state, 0) == 59 { context:source:advance(state, 1) }

    if !context:function:address(state, handler) {
        context:diagnostic:error(state, "form handler is not a compiled proc symbol")
        return
    }

    let owner = RecurLoopSeed:forms_owner(state)
    if !owner { context:diagnostic:error(state, "seed form registry is unavailable"); return }
    if context:phrase:find:exact(state, owner, name) {
        context:diagnostic:error(state, "form spelling is already registered")
        return
    }
    let entry = context:phrase:define:data(state, owner, name)
    if !entry { context:diagnostic:error(state, "form could not register spelling"); return }
    context:phrase:data(state, entry, handler)
}

let RecurLoopSeed:dispatch_form_action = fn (state:Context*, called:Phrase*) -> void {
    let owner = RecurLoopSeed:forms_owner(state)
    if !owner { context:diagnostic:error(state, "seed form registry is unavailable"); return }

    let matched = context:source:match:longest(state, owner)
    if !matched {
        context:diagnostic:error(state, "unknown source form")
        return
    }

    let bytes = context:phrase:payload:bytes(state, matched)
    if bytes <= 0 { context:diagnostic:error(state, "seed form has no handler symbol"); return }
    let symbol = cast(u8*, malloc(bytes + 1))
    if !symbol { context:diagnostic:error(state, "seed dispatcher: out of memory"); return }
    defer free(symbol)
    if context:phrase:read(state, matched, 0, symbol, bytes) != bytes {
        context:diagnostic:error(state, "seed dispatcher could not read handler symbol")
        return
    }
    symbol[bytes] = 0

    let address = context:function:address(state, symbol)
    if !address { context:diagnostic:error(state, "seed form handler could not be linked"); return }
    let handler = cast(RecurLoopSeed:Action, address)
    handler(state, called)
    context:source:root(state)
}

// One fallback serves every source-defined form. The fallback itself is the
// only bootstrap Phrase needed for the open-ended language surface.
let RecurLoopSeed:dispatch_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        RecurLoopSeed:dispatch_form_action(state, called)
    }
}

let RecurLoopSeed:install_fallback = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let seed = context:phrase:find(state, "RecurLoopSeed")
        let dispatcher = context:phrase:find:exact(state, seed, "dispatch_form")
        if !dispatcher || !context:phrase:define:alias(state, "", dispatcher) {
            context:diagnostic:error(state, "could not install RecurLoop seed source fallback")
        }
    }
}

let recurloop_seed_install_fallback = <RecurLoopSeed:install_fallback>
recurloop_seed_install_fallback

// The two public bootstrap roots. They are fresh actions, not aliases or
// prototypes of current source constructs.
let proc = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        RecurLoopSeed:proc_action(state, called)
    }
}

let form = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        RecurLoopSeed:form_action(state, called)
    }
}

// First self-hosted language construct. `shape` is deliberately NOT a kernel
// root: it is ordinary syntax built from proc + form.
proc RecurLoopSeed:shape_handler (state:Context*, called:Phrase*) -> void {
    RecurLoopSeed:shape_action(state, called)
}
form shape = RecurLoopSeed:shape_handler
