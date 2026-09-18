// =============================================================================
// RecurLoop LanguageKit
//
// Shared building blocks for composable source-defined languages.
//
// Design goals:
//   - one shared symbol universe across every loaded language;
//   - streaming, left-to-right source consumption with bounded buffering;
//   - a reusable reader/cursor layer instead of one whole-language scanner per extension;
//   - one merged top-level fallback whose handlers are contributed by libraries;
//   - a small dynamic value/call ABI for cross-language values and functions;
//   - no language-specific parser or runtime in the C++ host.
//
// The only host primitive added for this library is context:source:refill. It is
// equivalent to context:source:ensure, except that when more bytes are required
// it slides away the already-consumed prefix before appending input. A parser
// which consumes left-to-right therefore keeps source memory bounded by its
// active lookahead/form instead of retaining the whole translation unit.
// =============================================================================

link shared "c"

extern malloc(size:u64) -> u8* abi sysv-amd64
extern realloc(pointer:u8*, size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern memcpy(destination:u8*, source:u8*, bytes:u64) -> u8* abi sysv-amd64
extern strlen(text:u8*) -> u64 abi sysv-amd64
extern strcmp(left:u8*, right:u8*) -> i32 abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64
extern perror(prefix:u8*) -> void abi sysv-amd64
extern close(fd:i32) -> i32 abi sysv-amd64

let LanguageKit = phrase { dictionary = true permanent = true }
let LanguageKit:Internal = phrase { dictionary = true serializable = false }
let LanguageKit:Symbols = phrase { dictionary = true permanent = true }
let LanguageKit:Forms = phrase { dictionary = true permanent = true }
let LanguageKit:Overrides = phrase { dictionary = true permanent = true }
let LanguageKit:Fallbacks = phrase { dictionary = true permanent = true }
let LanguageKit:Selectors = phrase { dictionary = true permanent = true }
let LanguageKit:Grammar = phrase { dictionary = true permanent = true }
let LanguageKit:Bindings = phrase { dictionary = true permanent = true }
let LanguageKit:Source = phrase { dictionary = true permanent = true }
let LanguageKit:Cursor = phrase { dictionary = true permanent = true }
let LanguageKit:Lifetime = phrase { dictionary = true permanent = true }
let LanguageKit:Guard = phrase { dictionary = true permanent = true }

// =============================================================================
// Small text utilities.
// =============================================================================

let LanguageKit:is_space = fn (ch:u8) -> i64 {
    return ch == 32 || ch == 9 || ch == 10 || ch == 13
}

let LanguageKit:is_hspace = fn (ch:u8) -> i64 {
    return ch == 32 || ch == 9
}

let LanguageKit:is_alpha = fn (ch:u8) -> i64 {
    return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
}

let LanguageKit:is_lower = fn (ch:u8) -> i64 { return ch >= 97 && ch <= 122 }
let LanguageKit:is_upper = fn (ch:u8) -> i64 { return ch >= 65 && ch <= 90 }
let LanguageKit:is_digit = fn (ch:u8) -> i64 { return ch >= 48 && ch <= 57 }

let LanguageKit:copy_bytes = fn (source:u8*, bytes:i64) -> u8* {
    if bytes < 0 { return cast(u8*, 0) }
    let out = cast(u8*, malloc(bytes + 1))
    if !out { return cast(u8*, 0) }
    if bytes > 0 { memcpy(out, source, bytes) }
    out[bytes] = 0
    return out
}

let LanguageKit:copy_text = fn (source:u8*) -> u8* {
    if !source { return cast(u8*, 0) }
    return LanguageKit:copy_bytes(source, cast(i64, strlen(source)))
}

let LanguageKit:text_equal = fn (left:u8*, right:u8*) -> i64 {
    if !left || !right { return 0 }
    return strcmp(left, right) == 0
}

let LanguageKit:text_number = fn (text:u8*) -> i64 {
    if !text { return 0 }
    var sign = 1
    var i = 0
    if text[0] == 45 { sign = -1; i = 1 }
    var value = 0
    while LanguageKit:is_digit(text[i]) {
        value = value * 10 + text[i] - 48
        i += 1
    }
    return value * sign
}

let LanguageKit:has_flag = fn (flags:i64, flag:i64) -> i64 {
    if flag <= 0 { return 0 }
    return ((flags / flag) % 2) != 0
}

record LanguageKit:Text {
    data:u8*
    length:i64
    capacity:i64
}

let LanguageKit:Text:new = fn () -> LanguageKit:Text* {
    let self = cast(LanguageKit:Text*, malloc(24))
    if !self { return cast(LanguageKit:Text*, 0) }
    self.capacity = 32
    self.length = 0
    self.data = cast(u8*, malloc(self.capacity))
    if !self.data { free(cast(u8*, self)); return cast(LanguageKit:Text*, 0) }
    self.data[0] = 0
    return self
}

let LanguageKit:Text:reserve = fn (self:LanguageKit:Text*, needed:i64) -> i64 {
    if !self { return 0 }
    if needed <= self.capacity { return 1 }
    var capacity = self.capacity
    while capacity < needed { capacity *= 2 }
    let replacement = realloc(self.data, capacity)
    if !replacement { return 0 }
    self.data = replacement
    self.capacity = capacity
    return 1
}

let LanguageKit:Text:append_byte = fn (self:LanguageKit:Text*, value:u8) -> i64 {
    if !self || !self.reserve(self.length + 2) { return 0 }
    self.data[self.length] = value
    self.length += 1
    self.data[self.length] = 0
    return 1
}

let LanguageKit:Text:append = fn (self:LanguageKit:Text*, value:u8*) -> i64 {
    if !self || !value { return 0 }
    let bytes = cast(i64, strlen(value))
    if !self.reserve(self.length + bytes + 1) { return 0 }
    if bytes > 0 { memcpy(&self.data[self.length], value, bytes) }
    self.length += bytes
    self.data[self.length] = 0
    return 1
}

let LanguageKit:Text:take = fn (self:LanguageKit:Text*) -> u8* {
    if !self { return cast(u8*, 0) }
    let out = self.data
    self.data = cast(u8*, 0)
    self.length = 0
    self.capacity = 0
    return out
}

let LanguageKit:Text:destroy = fn (self:LanguageKit:Text*) -> void {
    if !self { return }
    if self.data { free(self.data) }
    free(cast(u8*, self))
}

// =============================================================================
// Shared symbol universe.
//
// Every language interns identifiers here first. Its own Functions/Variables/
// Atoms/etc dictionaries contain aliases to the canonical LanguageKit symbol,
// so the same spelling has one phrase identity even when several languages use
// it with different semantics.
// =============================================================================

let LanguageKit:symbol_owner = fn (state:Context*) -> i64 {
    let root = context:phrase:find(state, "LanguageKit")
    if !root { return 0 }
    return context:phrase:find:exact(state, root, "Symbols")
}

let LanguageKit:intern = fn (state:Context*, name:u8*) -> i64 {
    if !state || !name { return 0 }
    let owner = LanguageKit:symbol_owner(state)
    if !owner { return 0 }
    let existing = context:phrase:find:exact(state, owner, name)
    if existing { return existing }
    return context:phrase:define:data(state, owner, name)
}

let LanguageKit:categorize = fn (state:Context*, owner:i64, name:u8*) -> i64 {
    let symbol = LanguageKit:intern(state, name)
    if !symbol || !owner { return symbol }
    if !context:phrase:find:exact(state, owner, name) {
        let alias = context:phrase:define:from(state, owner, name, symbol)
    }
    return symbol
}

let LanguageKit:categorized = fn (state:Context*, owner:i64, name:u8*) -> i64 {
    if !owner || !name { return 0 }
    return context:phrase:find:exact(state, owner, name)
}

let LanguageKit:state_get = fn (state:Context*, name:u8*) -> i64 {
    if !context:value:contains(state, name) { return 0 }
    let text = context:value:format(state, name)
    if !text { return 0 }
    defer free(text)
    return LanguageKit:text_number(text)
}

let LanguageKit:state_set = fn (state:Context*, name:u8*, value:i64) -> i64 {
    if context:value:contains(state, name) { return context:value:assign:integer(state, name, value) }
    return context:value:define:integer(state, name, value)
}

// =============================================================================
// Generic runtime safety guards.
//
// Foreign runtimes may recurse internally without crossing LanguageKit:invoke.
// These counters provide one shared, configurable mechanism for protecting the
// native stack without adding a host-side special case for each language.
// =============================================================================

let LanguageKit:Guard:limit = fn (state:Context*, key:u8*, fallback:i64) -> i64 {
    let configured = LanguageKit:state_get(state, key)
    if configured > 0 { return configured }
    return fallback
}

let LanguageKit:Guard:enter = fn (state:Context*, counter:u8*, limit_key:u8*, fallback:i64, message:u8*) -> i64 {
    let depth = LanguageKit:state_get(state, counter)
    let limit = LanguageKit:Guard:limit(state, limit_key, fallback)
    if depth >= limit {
        context:diagnostic:error(state, message)
        return 0
    }
    LanguageKit:state_set(state, counter, depth + 1)
    return 1
}

let LanguageKit:Guard:leave = fn (state:Context*, counter:u8*) -> void {
    let depth = LanguageKit:state_get(state, counter)
    if depth > 0 { LanguageKit:state_set(state, counter, depth - 1) }
}

// =============================================================================
// Deterministic lifetime / ownership runtime.
//
// This is intentionally not a tracing garbage collector. Managed allocations
// belong to lexical/runtime scopes and are destroyed in reverse registration
// order when the scope leaves. A value can be moved to the parent/root scope,
// retained as an explicit shared reference, or observed through a weak handle.
// Language implementations use this substrate internally; source programs do
// not need GC annotations or manual frees for LanguageKit values.
// =============================================================================

let LanguageKit:Drop = fn (state:Context*, pointer:u8*, userdata:i64) -> void

record LanguageKit:LifetimeControl {
    pointer:u8*
    bytes:i64
    strong:i64
    weak:i64
    alive:i64
    drop:LanguageKit:Drop
    userdata:i64
    next:LanguageKit:LifetimeControl*
}

record LanguageKit:LifetimeRef {
    control:LanguageKit:LifetimeControl*
    active:i64
    next:LanguageKit:LifetimeRef*
}

record LanguageKit:LifetimeScope {
    parent:LanguageKit:LifetimeScope*
    refs:LanguageKit:LifetimeRef*
    depth:i64
}

record LanguageKit:Weak {
    control:LanguageKit:LifetimeControl*
}

// Raw region objects may point at one another arbitrarily. Those edges are not
// ownership edges; the surrounding scope owns the whole region and therefore
// frees cyclic graphs deterministically without tracing them.
record LanguageKit:LifetimeProbe {
    other:LanguageKit:LifetimeProbe*
}

let LanguageKit:Lifetime:control_head = fn (state:Context*) -> LanguageKit:LifetimeControl* {
    return cast(LanguageKit:LifetimeControl*, LanguageKit:state_get(state, "__languagekit_lifetime_controls"))
}

let LanguageKit:Lifetime:set_control_head = fn (state:Context*, head:LanguageKit:LifetimeControl*) -> i64 {
    return LanguageKit:state_set(state, "__languagekit_lifetime_controls", cast(i64, head))
}

let LanguageKit:Lifetime:root = fn (state:Context*) -> LanguageKit:LifetimeScope* {
    let existing = cast(LanguageKit:LifetimeScope*, LanguageKit:state_get(state, "__languagekit_lifetime_root"))
    if existing { return existing }
    let scope = cast(LanguageKit:LifetimeScope*, malloc(24))
    if !scope { context:diagnostic:error(state, "LanguageKit: could not allocate lifetime root"); return cast(LanguageKit:LifetimeScope*, 0) }
    scope.parent = cast(LanguageKit:LifetimeScope*, 0)
    scope.refs = cast(LanguageKit:LifetimeRef*, 0)
    scope.depth = 0
    LanguageKit:state_set(state, "__languagekit_lifetime_root", cast(i64, scope))
    LanguageKit:state_set(state, "__languagekit_lifetime_current", cast(i64, scope))
    return scope
}

let LanguageKit:Lifetime:current = fn (state:Context*) -> LanguageKit:LifetimeScope* {
    let current = cast(LanguageKit:LifetimeScope*, LanguageKit:state_get(state, "__languagekit_lifetime_current"))
    if current { return current }
    return LanguageKit:Lifetime:root(state)
}

let LanguageKit:Lifetime:limit_bytes = fn (state:Context*) -> i64 {
    let configured = LanguageKit:state_get(state, "__languagekit_lifetime_limit_bytes")
    if configured > 0 { return configured }
    return 268435456
}

let LanguageKit:Lifetime:limit_objects = fn (state:Context*) -> i64 {
    let configured = LanguageKit:state_get(state, "__languagekit_lifetime_limit_objects")
    if configured > 0 { return configured }
    return 1048576
}

let LanguageKit:Lifetime:live_bytes = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_lifetime_live_bytes")
}

let LanguageKit:Lifetime:live_objects = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_lifetime_live_objects")
}

let LanguageKit:Lifetime:limit_refs = fn (state:Context*) -> i64 {
    let configured = LanguageKit:state_get(state, "__languagekit_lifetime_limit_refs")
    if configured > 0 { return configured }
    return 4194304
}

let LanguageKit:Lifetime:live_refs = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_lifetime_live_refs")
}

let LanguageKit:Lifetime:set_reference_limit = fn (state:Context*, refs:i64) -> i64 {
    if refs <= 0 { return 0 }
    LanguageKit:state_set(state, "__languagekit_lifetime_limit_refs", refs)
    return 1
}

let LanguageKit:Lifetime:ref_slot_available = fn (state:Context*) -> i64 {
    if LanguageKit:Lifetime:live_refs(state) >= LanguageKit:Lifetime:limit_refs(state) {
        context:diagnostic:error(state, "LanguageKit: ownership/weak reference limit exceeded")
        return 0
    }
    return 1
}

let LanguageKit:Lifetime:ref_slot_added = fn (state:Context*) -> void {
    LanguageKit:state_set(state, "__languagekit_lifetime_live_refs", LanguageKit:Lifetime:live_refs(state) + 1)
}

let LanguageKit:Lifetime:ref_slot_removed = fn (state:Context*) -> void {
    let refs = LanguageKit:Lifetime:live_refs(state)
    if refs > 0 { LanguageKit:state_set(state, "__languagekit_lifetime_live_refs", refs - 1) }
}

let LanguageKit:Lifetime:set_limits = fn (state:Context*, bytes:i64, objects:i64) -> i64 {
    if bytes <= 0 || objects <= 0 { return 0 }
    LanguageKit:state_set(state, "__languagekit_lifetime_limit_bytes", bytes)
    LanguageKit:state_set(state, "__languagekit_lifetime_limit_objects", objects)
    return 1
}

let LanguageKit:Lifetime:control = fn (state:Context*, pointer:u8*) -> LanguageKit:LifetimeControl* {
    if !pointer { return cast(LanguageKit:LifetimeControl*, 0) }
    var current = LanguageKit:Lifetime:control_head(state)
    while current {
        if current.pointer == pointer && current.alive { return current }
        current = current.next
    }
    return cast(LanguageKit:LifetimeControl*, 0)
}

let LanguageKit:Lifetime:add_ref_to = fn (
    state:Context*, scope:LanguageKit:LifetimeScope*, control:LanguageKit:LifetimeControl*
) -> i64 {
    if !scope || !control { return 0 }
    if !LanguageKit:Lifetime:ref_slot_available(state) { return 0 }
    let ref = cast(LanguageKit:LifetimeRef*, malloc(24))
    if !ref { context:diagnostic:error(state, "LanguageKit: could not allocate ownership reference"); return 0 }
    LanguageKit:Lifetime:ref_slot_added(state)
    ref.control = control
    ref.active = 1
    ref.next = scope.refs
    scope.refs = ref
    return 1
}

let LanguageKit:Lifetime:find_ref = fn (
    scope:LanguageKit:LifetimeScope*, control:LanguageKit:LifetimeControl*
) -> LanguageKit:LifetimeRef* {
    if !scope || !control { return cast(LanguageKit:LifetimeRef*, 0) }
    var ref = scope.refs
    while ref {
        if ref.active && ref.control == control { return ref }
        ref = ref.next
    }
    return cast(LanguageKit:LifetimeRef*, 0)
}

let LanguageKit:Lifetime:remove_control = fn (state:Context*, target:LanguageKit:LifetimeControl*) -> void {
    if !target { return }
    var previous = cast(LanguageKit:LifetimeControl*, 0)
    var current = LanguageKit:Lifetime:control_head(state)
    while current && current != target { previous = current; current = current.next }
    if !current { return }
    if previous { previous.next = current.next } else { LanguageKit:Lifetime:set_control_head(state, current.next) }
    free(cast(u8*, current))
}

let LanguageKit:Lifetime:destroy_payload = fn (state:Context*, control:LanguageKit:LifetimeControl*) -> void {
    if !control || !control.alive { return }
    let pointer = control.pointer
    let bytes = control.bytes
    control.alive = 0
    control.pointer = cast(u8*, 0)
    if control.drop {
        let callback = control.drop
        callback(state, pointer, control.userdata)
    } else if pointer { free(pointer) }
    let live_bytes = LanguageKit:Lifetime:live_bytes(state)
    let live_objects = LanguageKit:Lifetime:live_objects(state)
    LanguageKit:state_set(state, "__languagekit_lifetime_live_bytes", live_bytes - bytes)
    LanguageKit:state_set(state, "__languagekit_lifetime_live_objects", live_objects - 1)
}

let LanguageKit:Lifetime:release_control = fn (state:Context*, control:LanguageKit:LifetimeControl*) -> i64 {
    if !control || control.strong <= 0 { return 0 }
    control.strong -= 1
    if control.strong == 0 {
        LanguageKit:Lifetime:destroy_payload(state, control)
        if control.weak == 0 { LanguageKit:Lifetime:remove_control(state, control) }
    }
    return 1
}

let LanguageKit:Lifetime:enter = fn (state:Context*) -> LanguageKit:LifetimeScope* {
    let parent = LanguageKit:Lifetime:current(state)
    if !parent { return cast(LanguageKit:LifetimeScope*, 0) }
    if parent.depth >= 1024 {
        context:diagnostic:error(state, "LanguageKit: lifetime/call scope depth exceeded 1024")
        return cast(LanguageKit:LifetimeScope*, 0)
    }
    let scope = cast(LanguageKit:LifetimeScope*, malloc(24))
    if !scope { context:diagnostic:error(state, "LanguageKit: could not allocate lifetime scope"); return cast(LanguageKit:LifetimeScope*, 0) }
    scope.parent = parent
    scope.refs = cast(LanguageKit:LifetimeRef*, 0)
    scope.depth = parent.depth + 1
    LanguageKit:state_set(state, "__languagekit_lifetime_current", cast(i64, scope))
    return scope
}

let LanguageKit:Lifetime:leave = fn (state:Context*, scope:LanguageKit:LifetimeScope*) -> void {
    if !scope { return }
    let current = LanguageKit:Lifetime:current(state)
    if current != scope {
        context:diagnostic:error(state, "LanguageKit: lifetime scopes must leave in LIFO order")
        return
    }
    var ref = scope.refs
    while ref {
        let next = ref.next
        if ref.active && ref.control {
            ref.active = 0
            LanguageKit:Lifetime:release_control(state, ref.control)
        }
        free(cast(u8*, ref))
        LanguageKit:Lifetime:ref_slot_removed(state)
        ref = next
    }
    LanguageKit:state_set(state, "__languagekit_lifetime_current", cast(i64, scope.parent))
    free(cast(u8*, scope))
}

let LanguageKit:Lifetime:adopt = fn (
    state:Context*, pointer:u8*, bytes:i64, drop:LanguageKit:Drop, userdata:i64
) -> u8* {
    if !pointer || bytes < 0 { return cast(u8*, 0) }
    let live_bytes = LanguageKit:Lifetime:live_bytes(state)
    let live_objects = LanguageKit:Lifetime:live_objects(state)
    if bytes > 67108864 || live_bytes + bytes > LanguageKit:Lifetime:limit_bytes(state) ||
       live_objects + 1 > LanguageKit:Lifetime:limit_objects(state) {
        context:diagnostic:error(state, "LanguageKit: managed allocation limit exceeded")
        if pointer {
            if drop { let cleanup = drop; cleanup(state, pointer, userdata) }
            else { free(pointer) }
        }
        return cast(u8*, 0)
    }
    let control = cast(LanguageKit:LifetimeControl*, malloc(64))
    if !control {
        if drop { let cleanup = drop; cleanup(state, pointer, userdata) }
        else { free(pointer) }
        context:diagnostic:error(state, "LanguageKit: could not allocate lifetime metadata")
        return cast(u8*, 0)
    }
    control.pointer = pointer
    control.bytes = bytes
    control.strong = 1
    control.weak = 0
    control.alive = 1
    control.drop = drop
    control.userdata = userdata
    control.next = LanguageKit:Lifetime:control_head(state)
    LanguageKit:Lifetime:set_control_head(state, control)
    LanguageKit:state_set(state, "__languagekit_lifetime_live_bytes", live_bytes + bytes)
    LanguageKit:state_set(state, "__languagekit_lifetime_live_objects", live_objects + 1)
    let scope = LanguageKit:Lifetime:current(state)
    if !scope || !LanguageKit:Lifetime:add_ref_to(state, scope, control) {
        LanguageKit:Lifetime:destroy_payload(state, control)
        LanguageKit:Lifetime:remove_control(state, control)
        return cast(u8*, 0)
    }
    return pointer
}

let LanguageKit:Lifetime:alloc = fn (
    state:Context*, bytes:i64, drop:LanguageKit:Drop, userdata:i64
) -> u8* {
    if bytes <= 0 || bytes > 67108864 {
        context:diagnostic:error(state, "LanguageKit: invalid managed allocation size")
        return cast(u8*, 0)
    }
    let pointer = cast(u8*, malloc(bytes))
    if !pointer { context:diagnostic:error(state, "LanguageKit: managed allocation failed"); return cast(u8*, 0) }
    return LanguageKit:Lifetime:adopt(state, pointer, bytes, drop, userdata)
}

let LanguageKit:Lifetime:raw_drop = fn (state:Context*, pointer:u8*, userdata:i64) -> void {
    if pointer { free(pointer) }
}

let LanguageKit:Lifetime:alloc_raw = fn (state:Context*, bytes:i64) -> u8* {
    return LanguageKit:Lifetime:alloc(state, bytes, LanguageKit:Lifetime:raw_drop, 0)
}

let LanguageKit:Lifetime:retain_in = fn (
    state:Context*, pointer:u8*, scope:LanguageKit:LifetimeScope*
) -> i64 {
    let control = LanguageKit:Lifetime:control(state, pointer)
    if !control || !scope { return 0 }
    if control.strong >= 1152921504606846976 {
        context:diagnostic:error(state, "LanguageKit: strong ownership count overflow")
        return 0
    }
    control.strong += 1
    if !LanguageKit:Lifetime:add_ref_to(state, scope, control) {
        control.strong -= 1
        return 0
    }
    return 1
}

let LanguageKit:Lifetime:retain = fn (state:Context*, pointer:u8*) -> i64 {
    return LanguageKit:Lifetime:retain_in(state, pointer, LanguageKit:Lifetime:current(state))
}

let LanguageKit:Lifetime:release_from = fn (
    state:Context*, pointer:u8*, scope:LanguageKit:LifetimeScope*
) -> i64 {
    let control = LanguageKit:Lifetime:control(state, pointer)
    if !control || !scope { return 0 }
    var previous = cast(LanguageKit:LifetimeRef*, 0)
    var ref = scope.refs
    while ref && (!ref.active || ref.control != control) { previous = ref; ref = ref.next }
    if !ref { return 0 }
    if previous { previous.next = ref.next } else { scope.refs = ref.next }
    ref.active = 0
    free(cast(u8*, ref))
    LanguageKit:Lifetime:ref_slot_removed(state)
    return LanguageKit:Lifetime:release_control(state, control)
}

let LanguageKit:Lifetime:release = fn (state:Context*, pointer:u8*) -> i64 {
    return LanguageKit:Lifetime:release_from(state, pointer, LanguageKit:Lifetime:current(state))
}

let LanguageKit:Lifetime:retain_detached = fn (state:Context*, pointer:u8*) -> i64 {
    let control = LanguageKit:Lifetime:control(state, pointer)
    if !control { return 0 }
    if control.strong >= 1152921504606846976 {
        context:diagnostic:error(state, "LanguageKit: strong ownership count overflow")
        return 0
    }
    control.strong += 1
    return 1
}

let LanguageKit:Lifetime:release_detached = fn (state:Context*, pointer:u8*) -> i64 {
    let control = LanguageKit:Lifetime:control(state, pointer)
    if !control { return 0 }
    return LanguageKit:Lifetime:release_control(state, control)
}

let LanguageKit:Lifetime:move_to = fn (
    state:Context*, pointer:u8*, destination:LanguageKit:LifetimeScope*
) -> i64 {
    let control = LanguageKit:Lifetime:control(state, pointer)
    let current = LanguageKit:Lifetime:current(state)
    if !control || !current || !destination { return 0 }
    if current == destination { return 1 }
    var previous = cast(LanguageKit:LifetimeRef*, 0)
    var ref = current.refs
    while ref && (!ref.active || ref.control != control) { previous = ref; ref = ref.next }
    if !ref { return 0 }
    if previous { previous.next = ref.next } else { current.refs = ref.next }
    if !LanguageKit:Lifetime:add_ref_to(state, destination, control) {
        ref.next = current.refs; current.refs = ref
        return 0
    }
    ref.active = 0
    free(cast(u8*, ref))
    LanguageKit:Lifetime:ref_slot_removed(state)
    return 1
}

let LanguageKit:Lifetime:move_to_parent = fn (state:Context*, pointer:u8*) -> i64 {
    let current = LanguageKit:Lifetime:current(state)
    if !current || !current.parent { return 0 }
    return LanguageKit:Lifetime:move_to(state, pointer, current.parent)
}

let LanguageKit:Lifetime:promote_root = fn (state:Context*, pointer:u8*) -> i64 {
    let control = LanguageKit:Lifetime:control(state, pointer)
    if !control { return 0 }
    let root = LanguageKit:Lifetime:root(state)
    let current = LanguageKit:Lifetime:current(state)
    if current == root {
        if LanguageKit:Lifetime:find_ref(root, control) { return 1 }
        return LanguageKit:Lifetime:retain_in(state, pointer, root)
    }
    if current && LanguageKit:Lifetime:find_ref(current, control) {
        return LanguageKit:Lifetime:move_to(state, pointer, root)
    }
    if LanguageKit:Lifetime:find_ref(root, control) { return 1 }
    return LanguageKit:Lifetime:retain_in(state, pointer, root)
}

let LanguageKit:Lifetime:attach_detached = fn (state:Context*, pointer:u8*) -> i64 {
    let control = LanguageKit:Lifetime:control(state, pointer)
    if !control { return 0 }
    if !LanguageKit:Lifetime:retain(state, pointer) { return 0 }
    return LanguageKit:Lifetime:release_detached(state, pointer)
}

let LanguageKit:Lifetime:weak = fn (state:Context*, pointer:u8*) -> LanguageKit:Weak* {
    let control = LanguageKit:Lifetime:control(state, pointer)
    if !control { return cast(LanguageKit:Weak*, 0) }
    if !LanguageKit:Lifetime:ref_slot_available(state) { return cast(LanguageKit:Weak*, 0) }
    let weak = cast(LanguageKit:Weak*, malloc(8))
    if !weak { context:diagnostic:error(state, "LanguageKit: could not allocate weak ownership handle"); return cast(LanguageKit:Weak*, 0) }
    LanguageKit:Lifetime:ref_slot_added(state)
    weak.control = control
    control.weak += 1
    return weak
}

let LanguageKit:Lifetime:weak_lock = fn (state:Context*, weak:LanguageKit:Weak*) -> u8* {
    if !weak || !weak.control || !weak.control.alive || weak.control.strong <= 0 { return cast(u8*, 0) }
    let pointer = weak.control.pointer
    if !LanguageKit:Lifetime:retain(state, pointer) { return cast(u8*, 0) }
    return pointer
}

let LanguageKit:Lifetime:weak_destroy = fn (state:Context*, weak:LanguageKit:Weak*) -> void {
    if !weak { return }
    let control = weak.control
    if control {
        if control.weak > 0 { control.weak -= 1 }
        if control.weak == 0 && control.strong == 0 { LanguageKit:Lifetime:remove_control(state, control) }
    }
    free(cast(u8*, weak))
    LanguageKit:Lifetime:ref_slot_removed(state)
}

let LanguageKit:Lifetime:managed = fn (state:Context*, pointer:u8*) -> i64 {
    return LanguageKit:Lifetime:control(state, pointer) != cast(LanguageKit:LifetimeControl*, 0)
}

let LanguageKit:Lifetime:test_drop = fn (state:Context*, pointer:u8*, userdata:i64) -> void {
    let drops = LanguageKit:state_get(state, "__languagekit_lifetime_test_drops")
    LanguageKit:state_set(state, "__languagekit_lifetime_test_drops", drops + 1)
    if pointer { free(pointer) }
}

let LanguageKit:Lifetime:selftest = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let before = LanguageKit:Lifetime:live_objects(state)
        let before_bytes = LanguageKit:Lifetime:live_bytes(state)
        let before_refs = LanguageKit:Lifetime:live_refs(state)
        LanguageKit:state_set(state, "__languagekit_lifetime_test_drops", 0)

        var scope_ok = 0
        var shared_ok = 0
        var weak_ok = 0
        var move_ok = 0
        var region_ok = 0

        let scope = LanguageKit:Lifetime:enter(state)
        if scope {
            let pointer = LanguageKit:Lifetime:alloc(state, 16, LanguageKit:Lifetime:test_drop, 0)
            let weak = LanguageKit:Lifetime:weak(state, pointer)
            let cycle_a = cast(LanguageKit:LifetimeProbe*, LanguageKit:Lifetime:alloc_raw(state, 8))
            let cycle_b = cast(LanguageKit:LifetimeProbe*, LanguageKit:Lifetime:alloc_raw(state, 8))
            if cycle_a && cycle_b { cycle_a.other = cycle_b; cycle_b.other = cycle_a; region_ok = 1 }
            if pointer && weak && LanguageKit:Lifetime:retain_detached(state, pointer) { scope_ok = 1 }
            LanguageKit:Lifetime:leave(state, scope)
            if weak {
                let locked = LanguageKit:Lifetime:weak_lock(state, weak)
                if locked { shared_ok = 1; LanguageKit:Lifetime:release(state, locked) }
                if pointer { LanguageKit:Lifetime:release_detached(state, pointer) }
                if !LanguageKit:Lifetime:weak_lock(state, weak) { weak_ok = 1 }
                LanguageKit:Lifetime:weak_destroy(state, weak)
            }
        }

        let move_scope = LanguageKit:Lifetime:enter(state)
        if move_scope {
            let moved = LanguageKit:Lifetime:alloc(state, 8, LanguageKit:Lifetime:test_drop, 0)
            if moved && LanguageKit:Lifetime:move_to_parent(state, moved) { move_ok = 1 }
            LanguageKit:Lifetime:leave(state, move_scope)
            if moved { LanguageKit:Lifetime:release(state, moved) }
        }

        let drops = LanguageKit:state_get(state, "__languagekit_lifetime_test_drops")
        let balanced = LanguageKit:Lifetime:live_objects(state) == before &&
                       LanguageKit:Lifetime:live_bytes(state) == before_bytes &&
                       LanguageKit:Lifetime:live_refs(state) == before_refs
        printf("ownership scope=%lld shared=%lld weak=%lld move=%lld region=%lld drops=%lld balanced=%lld\n",
               scope_ok, shared_ok, weak_ok, move_ok, region_ok, drops, balanced)
        context:source:root(state)
    }
}

let LanguageKit:Lifetime:stats = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let scope = LanguageKit:Lifetime:current(state)
        var depth = 0
        if scope { depth = scope.depth }
        printf("managed objects=%lld bytes=%lld refs=%lld scope-depth=%lld\n",
               LanguageKit:Lifetime:live_objects(state), LanguageKit:Lifetime:live_bytes(state),
               LanguageKit:Lifetime:live_refs(state), depth)
        context:source:root(state)
    }
}

let "languagekit lifetime selftest" = <LanguageKit:Lifetime:selftest>
let "languagekit lifetime stats" = <LanguageKit:Lifetime:stats>

// =============================================================================
// Sliding source stream.
//
// No function below keeps context:source:data() across a refill. That rule is
// important because a refill may compact the underlying Source buffer.
// =============================================================================

let LanguageKit:Source:available = fn (state:Context*, bytes:i64) -> i64 {
    if bytes <= 0 { return context:source:bytes(state) }
    return context:source:refill(state, bytes)
}

let LanguageKit:Source:eof = fn (state:Context*) -> i64 {
    return LanguageKit:Source:available(state, 1) <= 0
}

let LanguageKit:Source:peek = fn (state:Context*, relative:i64) -> u8 {
    if relative < 0 { return cast(u8, 0) }
    if LanguageKit:Source:available(state, relative + 1) <= relative { return cast(u8, 0) }
    return cast(u8, context:source:peek(state, relative))
}

let LanguageKit:Source:advance = fn (state:Context*, bytes:i64) -> i64 {
    if bytes <= 0 { return 0 }
    return context:source:advance(state, bytes)
}

let LanguageKit:Source:match_byte = fn (state:Context*, value:u8) -> i64 {
    if LanguageKit:Source:peek(state, 0) != value { return 0 }
    LanguageKit:Source:advance(state, 1)
    return 1
}

let LanguageKit:Source:match_pair = fn (state:Context*, first:u8, second:u8) -> i64 {
    if LanguageKit:Source:peek(state, 0) != first || LanguageKit:Source:peek(state, 1) != second { return 0 }
    LanguageKit:Source:advance(state, 2)
    return 1
}

let LanguageKit:Source:starts_with = fn (state:Context*, text:u8*) -> i64 {
    if !text { return 0 }
    var i = 0
    while text[i] != 0 {
        if LanguageKit:Source:peek(state, i) != text[i] { return 0 }
        i += 1
    }
    return 1
}

let LanguageKit:Source:match_text = fn (state:Context*, text:u8*) -> i64 {
    if !LanguageKit:Source:starts_with(state, text) { return 0 }
    LanguageKit:Source:advance(state, cast(i64, strlen(text)))
    return 1
}

let LanguageKit:Source:skip_hspace = fn (state:Context*) -> i64 {
    var count = 0
    var scanning = 1
    while scanning {
        let ch = LanguageKit:Source:peek(state, 0)
        if LanguageKit:is_hspace(ch) { LanguageKit:Source:advance(state, 1); count += 1 }
        else { scanning = 0 }
    }
    return count
}

let LanguageKit:Source:skip_space = fn (state:Context*) -> i64 {
    var count = 0
    var scanning = 1
    while scanning {
        let ch = LanguageKit:Source:peek(state, 0)
        if LanguageKit:is_space(ch) { LanguageKit:Source:advance(state, 1); count += 1 }
        else { scanning = 0 }
    }
    return count
}

let LanguageKit:Source:skip_line = fn (state:Context*) -> i64 {
    var count = 0
    var running = 1
    while running && !LanguageKit:Source:eof(state) {
        let ch = LanguageKit:Source:peek(state, 0)
        LanguageKit:Source:advance(state, 1)
        count += 1
        if ch == 10 { running = 0 }
        else if ch == 13 {
            if LanguageKit:Source:peek(state, 0) == 10 { LanguageKit:Source:advance(state, 1); count += 1 }
            running = 0
        }
    }
    return count
}

let LanguageKit:Source:skip_to_newline = fn (state:Context*) -> i64 {
    var count = 0
    var running = 1
    while running && !LanguageKit:Source:eof(state) {
        let ch = LanguageKit:Source:peek(state, 0)
        if ch == 10 || ch == 13 { running = 0 }
        else { LanguageKit:Source:advance(state, 1); count += 1 }
    }
    return count
}

let LanguageKit:Source:starts_with_at = fn (state:Context*, relative:i64, text:u8*) -> i64 {
    if !text { return 0 }
    var i = 0
    while text[i] != 0 {
        if LanguageKit:Source:peek(state, relative + i) != text[i] { return 0 }
        i += 1
    }
    return 1
}

// Length of the current logical line without consuming it. This is used as a
// conservative full-form extent by line-oriented language probes.
let LanguageKit:Source:line_extent = fn (state:Context*) -> i64 {
    var i = 0
    var scanning = 1
    while scanning {
        let ch = LanguageKit:Source:peek(state, i)
        if ch == 0 || ch == 10 || ch == 13 { return i }
        i += 1
    }
    return i
}

// Non-consuming separator probe used by the merged top-level dispatcher.
// It ignores quoted strings and nested (), [] and {}. The return value is the
// byte offset of the first top-level separator or -1.
let LanguageKit:Source:find_top = fn (
    state:Context*, first:u8*, second:u8*, third:u8*, stop_at_newline:i64, stop_at_dot:i64
) -> i64 {
    var i = 0
    var paren = 0
    var bracket = 0
    var brace = 0
    var quote = 0
    var escaped = 0
    var running = 1
    while running {
        let ch = LanguageKit:Source:peek(state, i)
        if ch == 0 { return -1 }
        if quote {
            if escaped { escaped = 0; i += 1 }
            else if ch == 92 { escaped = 1; i += 1 }
            else if ch == quote { quote = 0; i += 1 }
            else { i += 1 }
        } else if ch == 34 || ch == 39 {
            quote = ch
            i += 1
        } else {
            if ch == 40 { paren += 1 }
            else if ch == 41 && paren > 0 { paren -= 1 }
            else if ch == 91 { bracket += 1 }
            else if ch == 93 && bracket > 0 { bracket -= 1 }
            else if ch == 123 { brace += 1 }
            else if ch == 125 && brace > 0 { brace -= 1 }
            if paren == 0 && bracket == 0 && brace == 0 {
                if first && LanguageKit:Source:starts_with_at(state, i, first) { return i }
                if second && LanguageKit:Source:starts_with_at(state, i, second) { return i }
                if third && LanguageKit:Source:starts_with_at(state, i, third) { return i }
                if stop_at_newline && (ch == 10 || ch == 13) { return -1 }
                if stop_at_dot && ch == 46 { return -1 }
            }
            i += 1
        }
    }
    return -1
}

// =============================================================================
// Direct slice cursor.
//
// This is intentionally not a token stream. Language parsers keep their own
// recursive grammar/AST logic and ask the shared cursor only for bounded
// character-level operations (trivia, exact literals, identifiers, strings and
// integers). That removes the duplicated mini-readers from newer workflows while
// keeping phrase dictionaries / longest-match responsible for top-level form
// arbitration.
//
// flags:
//   8   // line comments
//   256 /* block comments */
// =============================================================================

let LanguageKit:Cursor:peek = fn (source:u8*, length:i64, position:i64, relative:i64) -> u8 {
    let at = position + relative
    if at < 0 || at >= length { return cast(u8, 0) }
    return source[at]
}

let LanguageKit:Cursor:text_at = fn (source:u8*, length:i64, position:i64, text:u8*) -> i64 {
    if !source || !text { return 0 }
    let n = cast(i64, strlen(text))
    if position < 0 || position + n > length { return 0 }
    var i = 0
    while i < n {
        if source[position + i] != text[i] { return 0 }
        i += 1
    }
    return 1
}

let LanguageKit:Cursor:skip = fn (source:u8*, length:i64, position:i64*, flags:i64) -> void {
    if !position { return }
    var scanning = 1
    while scanning {
        scanning = 0
        while *position < length && LanguageKit:is_space(source[*position]) { *position += 1 }

        if LanguageKit:has_flag(flags, 8) && *position + 1 < length && source[*position] == 47 && source[*position + 1] == 47 {
            *position += 2
            while *position < length && source[*position] != 10 && source[*position] != 13 { *position += 1 }
            scanning = 1
        } else if LanguageKit:has_flag(flags, 256) && *position + 1 < length && source[*position] == 47 && source[*position + 1] == 42 {
            *position += 2
            var closed = 0
            while !closed && *position + 1 < length {
                if source[*position] == 42 && source[*position + 1] == 47 { *position += 2; closed = 1 }
                else { *position += 1 }
            }
            // An unterminated block comment is left at EOF; the surrounding
            // parser will report the structural error at its normal boundary.
            if !closed { *position = length }
            scanning = 1
        }
    }
}

let LanguageKit:Cursor:starts = fn (source:u8*, length:i64, position:i64*, flags:i64, text:u8*) -> i64 {
    LanguageKit:Cursor:skip(source, length, position, flags)
    return LanguageKit:Cursor:text_at(source, length, *position, text)
}

let LanguageKit:Cursor:match_text = fn (source:u8*, length:i64, position:i64*, flags:i64, text:u8*) -> i64 {
    if !LanguageKit:Cursor:starts(source, length, position, flags, text) { return 0 }
    *position += cast(i64, strlen(text))
    return 1
}

let LanguageKit:Cursor:match_byte = fn (source:u8*, length:i64, position:i64*, flags:i64, value:u8) -> i64 {
    LanguageKit:Cursor:skip(source, length, position, flags)
    if *position < length && source[*position] == value { *position += 1; return 1 }
    return 0
}

let LanguageKit:Cursor:match_pair = fn (source:u8*, length:i64, position:i64*, flags:i64, first:u8, second:u8) -> i64 {
    LanguageKit:Cursor:skip(source, length, position, flags)
    if *position + 1 < length && source[*position] == first && source[*position + 1] == second {
        *position += 2
        return 1
    }
    return 0
}

let LanguageKit:Cursor:keyword = fn (source:u8*, length:i64, position:i64*, flags:i64, text:u8*) -> i64 {
    LanguageKit:Cursor:skip(source, length, position, flags)
    let n = cast(i64, strlen(text))
    if !LanguageKit:Cursor:text_at(source, length, *position, text) { return 0 }
    if *position + n < length {
        let next = source[*position + n]
        if LanguageKit:is_alpha(next) || LanguageKit:is_digit(next) || next == 95 { return 0 }
    }
    *position += n
    return 1
}

let LanguageKit:Cursor:take_identifier = fn (source:u8*, length:i64, position:i64*, flags:i64) -> u8* {
    LanguageKit:Cursor:skip(source, length, position, flags)
    if *position >= length { return cast(u8*, 0) }
    let ch = source[*position]
    if !(LanguageKit:is_alpha(ch) || ch == 95) { return cast(u8*, 0) }
    let start = *position
    *position += 1
    while *position < length {
        let current = source[*position]
        if LanguageKit:is_alpha(current) || LanguageKit:is_digit(current) || current == 95 { *position += 1 }
        else { return LanguageKit:copy_bytes(&source[start], *position - start) }
    }
    return LanguageKit:copy_bytes(&source[start], *position - start)
}

let LanguageKit:Cursor:take_string = fn (
    state:Context*, source:u8*, length:i64, position:i64*, flags:i64, unterminated:u8*
) -> u8* {
    LanguageKit:Cursor:skip(source, length, position, flags)
    if *position >= length || source[*position] != 34 { return cast(u8*, 0) }
    *position += 1
    let out = LanguageKit:Text:new()
    if !out { context:diagnostic:error(state, "LanguageKit: out of memory while reading string"); return cast(u8*, 0) }
    var closed = 0
    while !closed && *position < length {
        let ch = source[*position]
        *position += 1
        if ch == 34 { closed = 1 }
        else if ch == 92 && *position < length {
            let escaped = source[*position]
            *position += 1
            if escaped == 110 { out.append_byte(10) }
            else if escaped == 116 { out.append_byte(9) }
            else if escaped == 114 { out.append_byte(13) }
            else { out.append_byte(escaped) }
        } else { out.append_byte(ch) }
    }
    if !closed {
        out.destroy()
        context:diagnostic:error(state, unterminated)
        return cast(u8*, 0)
    }
    let result = out.take()
    out.destroy()
    return result
}

let LanguageKit:Cursor:take_integer = fn (
    source:u8*, length:i64, position:i64*, flags:i64, found:i64*
) -> i64 {
    if found { *found = 0 }
    LanguageKit:Cursor:skip(source, length, position, flags)
    if *position >= length || !LanguageKit:is_digit(source[*position]) { return 0 }
    var value = 0
    while *position < length && LanguageKit:is_digit(source[*position]) {
        value = value * 10 + source[*position] - 48
        *position += 1
    }
    if found { *found = 1 }
    return value
}

// =============================================================================
// Streaming reader.
//
// Token kinds:
//   0 EOF
//   1 identifier
//   2 integer
//   3 quoted text/atom
//   4 symbolic operator
//   5 punctuation: ()[]{},.;
//   6 newline
//
// Flags:
//   1   preserve newline as token 6
//   2   -- line comments
//   4   % line comments
//   8   // line comments
//   16  apostrophe is allowed inside identifiers
//   32  @ is allowed inside identifiers
//   64  single-quoted text is enabled
//   128 double-quoted text is enabled
// =============================================================================

record LanguageKit:Reader {
    state:Context*
    flags:i64
    error:i64
    cached:i64
    kind:i64
    number:i64
    text:u8*
    symbol:i64
}

let LanguageKit:Reader:new = fn (state:Context*, flags:i64) -> LanguageKit:Reader* {
    let self = cast(LanguageKit:Reader*, malloc(64))
    if !self { return cast(LanguageKit:Reader*, 0) }
    self.state = state
    self.flags = flags
    self.error = 0
    self.cached = 0
    self.kind = 0
    self.number = 0
    self.text = cast(u8*, 0)
    self.symbol = 0
    return self
}

let LanguageKit:Reader:clear = fn (self:LanguageKit:Reader*) -> void {
    if !self { return }
    if self.text { free(self.text) }
    self.text = cast(u8*, 0)
    self.number = 0
    self.symbol = 0
    self.kind = 0
    self.cached = 0
}

let LanguageKit:Reader:destroy = fn (self:LanguageKit:Reader*) -> void {
    if !self { return }
    self.clear()
    free(cast(u8*, self))
}

let LanguageKit:Reader:fail = fn (self:LanguageKit:Reader*, message:u8*) -> void {
    if !self.error {
        self.error = 1
        context:diagnostic:error(self.state, message)
    }
}

let LanguageKit:Reader:identifier_continue = fn (self:LanguageKit:Reader*, ch:u8) -> i64 {
    if LanguageKit:is_alpha(ch) || LanguageKit:is_digit(ch) || ch == 95 { return 1 }
    if LanguageKit:has_flag(self.flags, 16) && ch == 39 { return 1 }
    if LanguageKit:has_flag(self.flags, 32) && ch == 64 { return 1 }
    return 0
}

let LanguageKit:Reader:is_punctuation = fn (ch:u8) -> i64 {
    return ch == 40 || ch == 41 || ch == 91 || ch == 93 || ch == 123 || ch == 125 ||
           ch == 44 || ch == 46 || ch == 59
}

let LanguageKit:Reader:is_operator = fn (ch:u8) -> i64 {
    if ch == 0 || LanguageKit:is_space(ch) || LanguageKit:is_alpha(ch) || LanguageKit:is_digit(ch) || ch == 95 { return 0 }
    if ch == 34 || ch == 39 || LanguageKit:Reader:is_punctuation(ch) { return 0 }
    return 1
}

let LanguageKit:Reader:skip_trivia = fn (self:LanguageKit:Reader*) -> void {
    var scanning = 1
    while scanning {
        let ch = LanguageKit:Source:peek(self.state, 0)
        if ch == 32 || ch == 9 { LanguageKit:Source:advance(self.state, 1) }
        else if ch == 10 || ch == 13 {
            if LanguageKit:has_flag(self.flags, 1) { scanning = 0 }
            else { LanguageKit:Source:skip_line(self.state) }
        } else if LanguageKit:has_flag(self.flags, 2) && ch == 45 && LanguageKit:Source:peek(self.state, 1) == 45 {
            if LanguageKit:has_flag(self.flags, 1) { LanguageKit:Source:skip_to_newline(self.state) }
            else { LanguageKit:Source:skip_line(self.state) }
        } else if LanguageKit:has_flag(self.flags, 4) && ch == 37 {
            if LanguageKit:has_flag(self.flags, 1) { LanguageKit:Source:skip_to_newline(self.state) }
            else { LanguageKit:Source:skip_line(self.state) }
        } else if LanguageKit:has_flag(self.flags, 8) && ch == 47 && LanguageKit:Source:peek(self.state, 1) == 47 {
            if LanguageKit:has_flag(self.flags, 1) { LanguageKit:Source:skip_to_newline(self.state) }
            else { LanguageKit:Source:skip_line(self.state) }
        } else { scanning = 0 }
    }
}

let LanguageKit:Reader:read_quoted = fn (self:LanguageKit:Reader*, quote:u8) -> u8* {
    if LanguageKit:Source:peek(self.state, 0) != quote { return cast(u8*, 0) }
    LanguageKit:Source:advance(self.state, 1)
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    var running = 1
    while running {
        if LanguageKit:Source:eof(self.state) {
            out.destroy()
            self.fail("LanguageKit: unterminated quoted token")
            return cast(u8*, 0)
        }
        let ch = LanguageKit:Source:peek(self.state, 0)
        LanguageKit:Source:advance(self.state, 1)
        if ch == quote { running = 0 }
        else if ch == 92 {
            if LanguageKit:Source:eof(self.state) {
                out.destroy()
                self.fail("LanguageKit: unterminated escape")
                return cast(u8*, 0)
            }
            let escaped = LanguageKit:Source:peek(self.state, 0)
            LanguageKit:Source:advance(self.state, 1)
            if escaped == 110 { out.append_byte(10) }
            else if escaped == 114 { out.append_byte(13) }
            else if escaped == 116 { out.append_byte(9) }
            else { out.append_byte(escaped) }
        } else { out.append_byte(ch) }
    }
    let text = out.take()
    out.destroy()
    return text
}

let LanguageKit:Reader:scan = fn (self:LanguageKit:Reader*) -> void {
    if self.cached { return }
    self.skip_trivia()
    self.kind = 0
    self.number = 0
    self.symbol = 0
    if self.text { free(self.text); self.text = cast(u8*, 0) }

    if LanguageKit:Source:eof(self.state) { self.cached = 1; return }
    let ch = LanguageKit:Source:peek(self.state, 0)

    if (ch == 10 || ch == 13) && LanguageKit:has_flag(self.flags, 1) {
        LanguageKit:Source:skip_line(self.state)
        self.kind = 6
        self.text = LanguageKit:copy_text("\n")
        self.cached = 1
        return
    }

    if LanguageKit:is_alpha(ch) || ch == 95 {
        let out = LanguageKit:Text:new()
        if !out { self.fail("LanguageKit: out of memory while reading identifier"); self.cached = 1; return }
        var reading = 1
        while reading {
            let current = LanguageKit:Source:peek(self.state, 0)
            if self.identifier_continue(current) {
                out.append_byte(current)
                LanguageKit:Source:advance(self.state, 1)
            } else { reading = 0 }
        }
        self.text = out.take()
        out.destroy()
        self.kind = 1
        self.symbol = LanguageKit:intern(self.state, self.text)
        self.cached = 1
        return
    }

    if LanguageKit:is_digit(ch) {
        var value = 0
        let out = LanguageKit:Text:new()
        if !out { self.fail("LanguageKit: out of memory while reading integer"); self.cached = 1; return }
        var reading = 1
        while reading {
            let current = LanguageKit:Source:peek(self.state, 0)
            if LanguageKit:is_digit(current) {
                out.append_byte(current)
                value = value * 10 + current - 48
                LanguageKit:Source:advance(self.state, 1)
            } else { reading = 0 }
        }
        self.text = out.take()
        out.destroy()
        self.kind = 2
        self.number = value
        self.cached = 1
        return
    }

    if ch == 39 && LanguageKit:has_flag(self.flags, 64) {
        self.text = self.read_quoted(39)
        self.kind = 3
        self.symbol = LanguageKit:intern(self.state, self.text)
        self.cached = 1
        return
    }

    if ch == 34 && LanguageKit:has_flag(self.flags, 128) {
        self.text = self.read_quoted(34)
        self.kind = 3
        self.cached = 1
        return
    }

    if LanguageKit:Reader:is_punctuation(ch) {
        let out = cast(u8*, malloc(2))
        if !out { self.fail("LanguageKit: out of memory while reading punctuation"); self.cached = 1; return }
        out[0] = ch
        out[1] = 0
        LanguageKit:Source:advance(self.state, 1)
        self.kind = 5
        self.text = out
        self.cached = 1
        return
    }

    if LanguageKit:Reader:is_operator(ch) {
        let out = LanguageKit:Text:new()
        if !out { self.fail("LanguageKit: out of memory while reading operator"); self.cached = 1; return }
        var reading = 1
        while reading {
            let current = LanguageKit:Source:peek(self.state, 0)
            if LanguageKit:Reader:is_operator(current) {
                out.append_byte(current)
                LanguageKit:Source:advance(self.state, 1)
            } else { reading = 0 }
        }
        self.text = out.take()
        out.destroy()
        self.kind = 4
        self.symbol = LanguageKit:intern(self.state, self.text)
        self.cached = 1
        return
    }

    self.fail("LanguageKit: unsupported source byte")
    LanguageKit:Source:advance(self.state, 1)
    self.cached = 1
}

let LanguageKit:Reader:kind_of = fn (self:LanguageKit:Reader*) -> i64 { self.scan(); return self.kind }
let LanguageKit:Reader:number_of = fn (self:LanguageKit:Reader*) -> i64 { self.scan(); return self.number }
let LanguageKit:Reader:text_of = fn (self:LanguageKit:Reader*) -> u8* { self.scan(); return self.text }
let LanguageKit:Reader:symbol_of = fn (self:LanguageKit:Reader*) -> i64 { self.scan(); return self.symbol }

let LanguageKit:Reader:is = fn (self:LanguageKit:Reader*, text:u8*) -> i64 {
    self.scan()
    return self.text && LanguageKit:text_equal(self.text, text)
}

let LanguageKit:Reader:consume = fn (self:LanguageKit:Reader*) -> void {
    self.scan()
    self.clear()
}

let LanguageKit:Reader:match = fn (self:LanguageKit:Reader*, text:u8*) -> i64 {
    if !self.is(text) { return 0 }
    self.consume()
    return 1
}

let LanguageKit:Reader:match_kind = fn (self:LanguageKit:Reader*, kind:i64) -> i64 {
    if self.kind_of() != kind { return 0 }
    self.consume()
    return 1
}

let LanguageKit:Reader:take_text = fn (self:LanguageKit:Reader*) -> u8* {
    self.scan()
    let out = self.text
    self.text = cast(u8*, 0)
    self.cached = 0
    self.kind = 0
    self.number = 0
    self.symbol = 0
    return out
}

let LanguageKit:Reader:take_identifier = fn (self:LanguageKit:Reader*) -> u8* {
    if self.kind_of() != 1 { return cast(u8*, 0) }
    return self.take_text()
}

let LanguageKit:Reader:expect = fn (self:LanguageKit:Reader*, text:u8*, message:u8*) -> i64 {
    if self.match(text) { return 1 }
    self.fail(message)
    return 0
}

// =============================================================================
// In-memory slice reader.
//
// Phrase rewrites inside compiled functions receive an already captured
// context:syntax buffer rather than the live Source stream. SliceReader exposes
// a shared bounded reader for that case, so DSLs do not grow a second ad-hoc
// scanner. It does not claim streaming: the host has already materialized the
// syntax slice before the phrase action runs.
// =============================================================================

record LanguageKit:SliceReader {
    state:Context*
    source:u8*
    length:i64
    position:i64
    flags:i64
    error:i64
    cached:i64
    kind:i64
    number:i64
    text:u8*
    symbol:i64
}

let LanguageKit:SliceReader:new = fn (
    state:Context*, source:u8*, length:i64, flags:i64
) -> LanguageKit:SliceReader* {
    let self = cast(LanguageKit:SliceReader*, malloc(80))
    if !self { return cast(LanguageKit:SliceReader*, 0) }
    self.state = state
    self.source = source
    self.length = length
    self.position = 0
    self.flags = flags
    self.error = 0
    self.cached = 0
    self.kind = 0
    self.number = 0
    self.text = cast(u8*, 0)
    self.symbol = 0
    return self
}

let LanguageKit:SliceReader:clear = fn (self:LanguageKit:SliceReader*) -> void {
    if !self { return }
    if self.text { free(self.text) }
    self.text = cast(u8*, 0)
    self.cached = 0
    self.kind = 0
    self.number = 0
    self.symbol = 0
}

let LanguageKit:SliceReader:destroy = fn (self:LanguageKit:SliceReader*) -> void {
    if !self { return }
    self.clear()
    free(cast(u8*, self))
}

let LanguageKit:SliceReader:fail = fn (self:LanguageKit:SliceReader*, message:u8*) -> void {
    if !self.error {
        self.error = 1
        context:diagnostic:error(self.state, message)
    }
}

let LanguageKit:SliceReader:peek = fn (self:LanguageKit:SliceReader*, relative:i64) -> u8 {
    let at = self.position + relative
    if at < 0 || at >= self.length { return cast(u8, 0) }
    return self.source[at]
}

let LanguageKit:SliceReader:advance = fn (self:LanguageKit:SliceReader*, bytes:i64) -> void {
    self.position += bytes
    if self.position > self.length { self.position = self.length }
}

let LanguageKit:SliceReader:identifier_continue = fn (self:LanguageKit:SliceReader*, ch:u8) -> i64 {
    if LanguageKit:is_alpha(ch) || LanguageKit:is_digit(ch) || ch == 95 { return 1 }
    if LanguageKit:has_flag(self.flags, 16) && ch == 39 { return 1 }
    if LanguageKit:has_flag(self.flags, 32) && ch == 64 { return 1 }
    return 0
}

let LanguageKit:SliceReader:skip_line = fn (self:LanguageKit:SliceReader*) -> void {
    var running = 1
    while running && self.position < self.length {
        let ch = self.peek(0)
        self.advance(1)
        if ch == 10 { running = 0 }
        else if ch == 13 {
            if self.peek(0) == 10 { self.advance(1) }
            running = 0
        }
    }
}

let LanguageKit:SliceReader:skip_to_newline = fn (self:LanguageKit:SliceReader*) -> void {
    var running = 1
    while running && self.position < self.length {
        let ch = self.peek(0)
        if ch == 10 || ch == 13 { running = 0 }
        else { self.advance(1) }
    }
}

let LanguageKit:SliceReader:skip_trivia = fn (self:LanguageKit:SliceReader*) -> void {
    var scanning = 1
    while scanning {
        let ch = self.peek(0)
        if ch == 32 || ch == 9 { self.advance(1) }
        else if ch == 10 || ch == 13 {
            if LanguageKit:has_flag(self.flags, 1) { scanning = 0 }
            else { self.skip_line() }
        } else if LanguageKit:has_flag(self.flags, 2) && ch == 45 && self.peek(1) == 45 {
            if LanguageKit:has_flag(self.flags, 1) { self.skip_to_newline() } else { self.skip_line() }
        } else if LanguageKit:has_flag(self.flags, 4) && ch == 37 {
            if LanguageKit:has_flag(self.flags, 1) { self.skip_to_newline() } else { self.skip_line() }
        } else if LanguageKit:has_flag(self.flags, 8) && ch == 47 && self.peek(1) == 47 {
            if LanguageKit:has_flag(self.flags, 1) { self.skip_to_newline() } else { self.skip_line() }
        } else { scanning = 0 }
    }
}

let LanguageKit:SliceReader:read_quoted = fn (self:LanguageKit:SliceReader*, quote:u8) -> u8* {
    if self.peek(0) != quote { return cast(u8*, 0) }
    self.advance(1)
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    var running = 1
    while running {
        if self.position >= self.length {
            out.destroy()
            self.fail("LanguageKit: unterminated quoted slice token")
            return cast(u8*, 0)
        }
        let ch = self.peek(0)
        self.advance(1)
        if ch == quote { running = 0 }
        else if ch == 92 {
            if self.position >= self.length {
                out.destroy()
                self.fail("LanguageKit: unterminated slice escape")
                return cast(u8*, 0)
            }
            let escaped = self.peek(0)
            self.advance(1)
            if escaped == 110 { out.append_byte(10) }
            else if escaped == 114 { out.append_byte(13) }
            else if escaped == 116 { out.append_byte(9) }
            else { out.append_byte(escaped) }
        } else { out.append_byte(ch) }
    }
    let text = out.take()
    out.destroy()
    return text
}

let LanguageKit:SliceReader:scan = fn (self:LanguageKit:SliceReader*) -> void {
    if self.cached { return }
    self.skip_trivia()
    self.kind = 0
    self.number = 0
    self.symbol = 0
    if self.text { free(self.text); self.text = cast(u8*, 0) }
    if self.position >= self.length { self.cached = 1; return }
    let ch = self.peek(0)

    if (ch == 10 || ch == 13) && LanguageKit:has_flag(self.flags, 1) {
        self.skip_line()
        self.kind = 6
        self.text = LanguageKit:copy_text("\n")
        self.cached = 1
        return
    }

    if LanguageKit:is_alpha(ch) || ch == 95 {
        let out = LanguageKit:Text:new()
        if !out { self.fail("LanguageKit: out of memory while reading slice identifier"); self.cached = 1; return }
        var reading = 1
        while reading {
            let current = self.peek(0)
            if self.identifier_continue(current) {
                out.append_byte(current)
                self.advance(1)
            } else { reading = 0 }
        }
        self.text = out.take()
        out.destroy()
        self.kind = 1
        self.symbol = LanguageKit:intern(self.state, self.text)
        self.cached = 1
        return
    }

    if LanguageKit:is_digit(ch) {
        let out = LanguageKit:Text:new()
        if !out { self.fail("LanguageKit: out of memory while reading slice integer"); self.cached = 1; return }
        var value = 0
        var reading = 1
        while reading {
            let current = self.peek(0)
            if LanguageKit:is_digit(current) {
                out.append_byte(current)
                value = value * 10 + current - 48
                self.advance(1)
            } else { reading = 0 }
        }
        self.text = out.take()
        out.destroy()
        self.kind = 2
        self.number = value
        self.cached = 1
        return
    }

    if ch == 39 && LanguageKit:has_flag(self.flags, 64) {
        self.text = self.read_quoted(39)
        self.kind = 3
        self.symbol = LanguageKit:intern(self.state, self.text)
        self.cached = 1
        return
    }

    if ch == 34 && LanguageKit:has_flag(self.flags, 128) {
        self.text = self.read_quoted(34)
        self.kind = 3
        self.cached = 1
        return
    }

    if LanguageKit:Reader:is_punctuation(ch) {
        let out = cast(u8*, malloc(2))
        if !out { self.fail("LanguageKit: out of memory while reading slice punctuation"); self.cached = 1; return }
        out[0] = ch
        out[1] = 0
        self.advance(1)
        self.kind = 5
        self.text = out
        self.cached = 1
        return
    }

    if LanguageKit:Reader:is_operator(ch) {
        let out = LanguageKit:Text:new()
        if !out { self.fail("LanguageKit: out of memory while reading slice operator"); self.cached = 1; return }
        var reading = 1
        while reading {
            let current = self.peek(0)
            if LanguageKit:Reader:is_operator(current) {
                out.append_byte(current)
                self.advance(1)
            } else { reading = 0 }
        }
        self.text = out.take()
        out.destroy()
        self.kind = 4
        self.symbol = LanguageKit:intern(self.state, self.text)
        self.cached = 1
        return
    }

    self.fail("LanguageKit: unsupported syntax-slice byte")
    self.advance(1)
    self.cached = 1
}

let LanguageKit:SliceReader:kind_of = fn (self:LanguageKit:SliceReader*) -> i64 { self.scan(); return self.kind }
let LanguageKit:SliceReader:number_of = fn (self:LanguageKit:SliceReader*) -> i64 { self.scan(); return self.number }
let LanguageKit:SliceReader:text_of = fn (self:LanguageKit:SliceReader*) -> u8* { self.scan(); return self.text }
let LanguageKit:SliceReader:symbol_of = fn (self:LanguageKit:SliceReader*) -> i64 { self.scan(); return self.symbol }
let LanguageKit:SliceReader:is = fn (self:LanguageKit:SliceReader*, text:u8*) -> i64 { self.scan(); return self.text && LanguageKit:text_equal(self.text, text) }
let LanguageKit:SliceReader:consume = fn (self:LanguageKit:SliceReader*) -> void { self.scan(); self.clear() }
let LanguageKit:SliceReader:match = fn (self:LanguageKit:SliceReader*, text:u8*) -> i64 { if !self.is(text) { return 0 }; self.consume(); return 1 }
let LanguageKit:SliceReader:take_text = fn (self:LanguageKit:SliceReader*) -> u8* {
    self.scan()
    let out = self.text
    self.text = cast(u8*, 0)
    self.cached = 0
    self.kind = 0
    self.number = 0
    self.symbol = 0
    return out
}
let LanguageKit:SliceReader:take_identifier = fn (self:LanguageKit:SliceReader*) -> u8* {
    if self.kind_of() != 1 { return cast(u8*, 0) }
    return self.take_text()
}
let LanguageKit:SliceReader:expect = fn (self:LanguageKit:SliceReader*, text:u8*, message:u8*) -> i64 {
    if self.match(text) { return 1 }
    self.fail(message)
    return 0
}

// =============================================================================
// Generic syntax nodes and patterns.
//
// Language extensions may use these directly or keep a specialized evaluator
// while still sharing the streaming reader. The node deliberately carries the
// canonical phrase id beside optional text, so semantic layers do not need to
// compare identifier strings.
// =============================================================================

record LanguageKit:Node {
    kind:i64
    number:i64
    text:u8*
    symbol:i64
    arity:i64
    items:LanguageKit:Node**
    left:LanguageKit:Node*
    right:LanguageKit:Node*
}

let LanguageKit:Node:new = fn (kind:i64) -> LanguageKit:Node* {
    let self = cast(LanguageKit:Node*, malloc(64))
    if !self { return cast(LanguageKit:Node*, 0) }
    self.kind = kind
    self.number = 0
    self.text = cast(u8*, 0)
    self.symbol = 0
    self.arity = 0
    self.items = cast(LanguageKit:Node**, 0)
    self.left = cast(LanguageKit:Node*, 0)
    self.right = cast(LanguageKit:Node*, 0)
    return self
}

let LanguageKit:Node:integer = fn (value:i64) -> LanguageKit:Node* {
    let self = LanguageKit:Node:new(1)
    if self { self.number = value }
    return self
}

let LanguageKit:Node:named = fn (state:Context*, kind:i64, name:u8*) -> LanguageKit:Node* {
    let self = LanguageKit:Node:new(kind)
    if self {
        self.text = name
        self.symbol = LanguageKit:intern(state, name)
    }
    return self
}

let LanguageKit:Node:pair = fn (kind:i64, left:LanguageKit:Node*, right:LanguageKit:Node*) -> LanguageKit:Node* {
    let self = LanguageKit:Node:new(kind)
    if self { self.left = left; self.right = right }
    return self
}

// Pattern kinds suggested by LanguageKit:
//   1 binder, 2 wildcard, 3 integer, 4 symbol/atom/constructor,
//   5 tuple, 6 list, 7 cons, 8 literal text.
// The matcher itself is language-specific because Erlang binding, Haskell lazy
// constructor matching and Prolog unification deliberately have different
// rollback/evaluation semantics. The representation, however, can be shared.
record LanguageKit:Pattern {
    kind:i64
    number:i64
    text:u8*
    symbol:i64
    arity:i64
    items:LanguageKit:Pattern**
}

let LanguageKit:Pattern:new = fn (kind:i64) -> LanguageKit:Pattern* {
    let self = cast(LanguageKit:Pattern*, malloc(48))
    if !self { return cast(LanguageKit:Pattern*, 0) }
    self.kind = kind
    self.number = 0
    self.text = cast(u8*, 0)
    self.symbol = 0
    self.arity = 0
    self.items = cast(LanguageKit:Pattern**, 0)
    return self
}

let LanguageKit:Pattern:integer = fn (value:i64) -> LanguageKit:Pattern* {
    let self = LanguageKit:Pattern:new(3)
    if self { self.number = value }
    return self
}

let LanguageKit:Pattern:named = fn (state:Context*, kind:i64, name:u8*) -> LanguageKit:Pattern* {
    let self = LanguageKit:Pattern:new(kind)
    if self {
        self.text = name
        self.symbol = LanguageKit:intern(state, name)
    }
    return self
}

// =============================================================================
// Cross-language value and callable ABI.
//
// Value kinds:
//   0 null, 1 integer, 2 text, 3 symbol/atom, 4 list, 5 tuple, 6 opaque.
//
// A language runtime can publish a value under a canonical symbol and another
// runtime can consume it without knowing the producer's AST. Integer/text
// publications are mirrored into RecurLoop Context values, which also makes
// them directly visible to ordinary RecurLoop expressions.
// =============================================================================

record LanguageKit:Value {
    kind:i64
    number:i64
    text:u8*
    symbol:i64
    arity:i64
    items:LanguageKit:Value**
    opaque:i64
    opaque_drop:LanguageKit:Drop
    opaque_userdata:i64
}

let LanguageKit:Value:drop = fn (state:Context*, pointer:u8*, userdata:i64) -> void {
    let self = cast(LanguageKit:Value*, pointer)
    if !self { return }
    if self.text { free(self.text); self.text = cast(u8*, 0) }
    if self.items {
        var i = 0
        while i < self.arity {
            let child = self.items[i]
            if child { LanguageKit:Lifetime:release_detached(state, cast(u8*, child)) }
            i += 1
        }
        free(cast(u8*, self.items))
        self.items = cast(LanguageKit:Value**, 0)
    }
    if self.opaque && self.opaque_drop {
        let callback = self.opaque_drop
        callback(state, cast(u8*, self.opaque), self.opaque_userdata)
        self.opaque = 0
    }
    free(pointer)
}

let LanguageKit:Value:new = fn (state:Context*, kind:i64) -> LanguageKit:Value* {
    let self = cast(LanguageKit:Value*, LanguageKit:Lifetime:alloc(state, 72, LanguageKit:Value:drop, 0))
    if !self { return cast(LanguageKit:Value*, 0) }
    self.kind = kind
    self.number = 0
    self.text = cast(u8*, 0)
    self.symbol = 0
    self.arity = 0
    self.items = cast(LanguageKit:Value**, 0)
    self.opaque = 0
    self.opaque_drop = cast(LanguageKit:Drop, 0)
    self.opaque_userdata = 0
    return self
}

let LanguageKit:Value:integer = fn (state:Context*, value:i64) -> LanguageKit:Value* {
    let self = LanguageKit:Value:new(state, 1)
    if self { self.number = value }
    return self
}

let LanguageKit:Value:text_value = fn (state:Context*, text:u8*) -> LanguageKit:Value* {
    let self = LanguageKit:Value:new(state, 2)
    if self { self.text = LanguageKit:copy_text(text) }
    return self
}

let LanguageKit:Value:symbol_value = fn (state:Context*, name:u8*) -> LanguageKit:Value* {
    let self = LanguageKit:Value:new(state, 3)
    if self { self.text = LanguageKit:copy_text(name); self.symbol = LanguageKit:intern(state, name) }
    return self
}

// Returns 1 if root strongly owns target through Value.items, 0 if not,
// and -1 if the graph is deeper than the bounded safety limit. This is not a
// tracing collector: it only prevents creating reference-count cycles in the
// generic cross-language Value ownership graph.
let LanguageKit:Value:owns_bounded = fn (
    root:LanguageKit:Value*, target:LanguageKit:Value*, depth:i64
) -> i64 {
    if !root || !target { return 0 }
    if root == target { return 1 }
    if depth >= 256 { return -1 }
    if !root.items || root.arity <= 0 { return 0 }
    var i = 0
    while i < root.arity {
        let child = root.items[i]
        if child {
            let nested = LanguageKit:Value:owns_bounded(child, target, depth + 1)
            if nested != 0 { return nested }
        }
        i += 1
    }
    return 0
}

let LanguageKit:Value:set_item = fn (state:Context*, self:LanguageKit:Value*, index:i64, value:LanguageKit:Value*) -> i64 {
    if !self || !self.items || index < 0 || index >= self.arity { return 0 }
    let old = self.items[index]
    if cast(u8*, self) == cast(u8*, value) {
        context:diagnostic:error(state, "LanguageKit: strong Value ownership cannot contain a self-cycle; use Weak or a scoped region")
        return 0
    }
    if value {
        let cycle = LanguageKit:Value:owns_bounded(value, self, 0)
        if cycle == 1 {
            context:diagnostic:error(state, "LanguageKit: strong Value ownership cycle detected; use Weak for back-edges or allocate the graph in one lifetime region")
            return 0
        }
        if cycle < 0 {
            context:diagnostic:error(state, "LanguageKit: Value ownership graph exceeds safe cycle-check depth 256")
            return 0
        }
    }
    if old == value { return 1 }
    // Acquire the new child before releasing the old one. Besides giving the
    // operation strong exception/failure safety, this also handles replacing a
    // slot with another reference to an otherwise-last-owned object.
    if value && !LanguageKit:Lifetime:retain_detached(state, cast(u8*, value)) { return 0 }
    self.items[index] = value
    if old { LanguageKit:Lifetime:release_detached(state, cast(u8*, old)) }
    return 1
}

let LanguageKit:Value:set_opaque_owned = fn (
    state:Context*, self:LanguageKit:Value*, pointer:u8*, drop:LanguageKit:Drop, userdata:i64
) -> i64 {
    if !self || !pointer { return 0 }
    if self.opaque && self.opaque_drop {
        let cleanup = self.opaque_drop
        cleanup(state, cast(u8*, self.opaque), self.opaque_userdata)
    }
    self.opaque = cast(i64, pointer)
    self.opaque_drop = drop
    self.opaque_userdata = userdata
    return 1
}

let LanguageKit:Value:release = fn (state:Context*, self:LanguageKit:Value*) -> i64 {
    if !self { return 0 }
    return LanguageKit:Lifetime:release(state, cast(u8*, self))
}

let LanguageKit:Call = fn (state:Context*, userdata:i64, args:LanguageKit:Value**, argc:i64) -> LanguageKit:Value*

record LanguageKit:Binding {
    symbol:i64
    name:u8*
    kind:i64
    value:LanguageKit:Value*
    call:LanguageKit:Call
    arity:i64
    userdata:i64
    next:LanguageKit:Binding*
}

let LanguageKit:binding_head = fn (state:Context*) -> LanguageKit:Binding* {
    return cast(LanguageKit:Binding*, LanguageKit:state_get(state, "__languagekit_binding_head"))
}

let LanguageKit:set_binding_head = fn (state:Context*, head:LanguageKit:Binding*) -> i64 {
    return LanguageKit:state_set(state, "__languagekit_binding_head", cast(i64, head))
}

let LanguageKit:binding = fn (state:Context*, symbol:i64) -> LanguageKit:Binding* {
    var current = LanguageKit:binding_head(state)
    while current {
        if current.symbol == symbol { return current }
        current = current.next
    }
    return cast(LanguageKit:Binding*, 0)
}

let LanguageKit:binding_named = fn (state:Context*, name:u8*) -> LanguageKit:Binding* {
    return LanguageKit:binding(state, LanguageKit:intern(state, name))
}

let LanguageKit:ensure_binding = fn (state:Context*, name:u8*) -> LanguageKit:Binding* {
    let symbol = LanguageKit:intern(state, name)
    let existing = LanguageKit:binding(state, symbol)
    if existing { return existing }
    let self = cast(LanguageKit:Binding*, malloc(64))
    if !self { return cast(LanguageKit:Binding*, 0) }
    self.symbol = symbol
    self.name = LanguageKit:copy_text(name)
    self.kind = 0
    self.value = cast(LanguageKit:Value*, 0)
    self.call = cast(LanguageKit:Call, 0)
    self.arity = -1
    self.userdata = 0
    self.next = LanguageKit:binding_head(state)
    LanguageKit:set_binding_head(state, self)
    return self
}

let LanguageKit:publish = fn (state:Context*, name:u8*, value:LanguageKit:Value*) -> i64 {
    let binding = LanguageKit:ensure_binding(state, name)
    if !binding { return 0 }
    if binding.kind == 1 && binding.value && binding.value != value {
        LanguageKit:Lifetime:release_from(state, cast(u8*, binding.value), LanguageKit:Lifetime:root(state))
    }
    if value && LanguageKit:Lifetime:managed(state, cast(u8*, value)) {
        LanguageKit:Lifetime:promote_root(state, cast(u8*, value))
    }
    binding.kind = 1
    binding.value = value
    binding.call = cast(LanguageKit:Call, 0)
    binding.arity = -1
    binding.userdata = 0
    if value {
        if value.kind == 1 {
            if context:value:contains(state, name) { context:value:assign:integer(state, name, value.number) }
            else { context:value:define:integer(state, name, value.number) }
        } else if value.kind == 2 && value.text {
            if context:value:contains(state, name) { context:value:assign:text(state, name, value.text) }
            else { context:value:define:text(state, name, value.text) }
        }
    }
    return binding.symbol
}

let LanguageKit:publish_integer = fn (state:Context*, name:u8*, value:i64) -> i64 {
    return LanguageKit:publish(state, name, LanguageKit:Value:integer(state, value))
}

let LanguageKit:publish_text = fn (state:Context*, name:u8*, value:u8*) -> i64 {
    return LanguageKit:publish(state, name, LanguageKit:Value:text_value(state, value))
}

let LanguageKit:publish_callable = fn (
    state:Context*, name:u8*, arity:i64, call:LanguageKit:Call, userdata:i64
) -> i64 {
    let binding = LanguageKit:ensure_binding(state, name)
    if !binding { return 0 }
    if binding.kind == 1 && binding.value {
        LanguageKit:Lifetime:release_from(state, cast(u8*, binding.value), LanguageKit:Lifetime:root(state))
    }
    binding.kind = 2
    binding.value = cast(LanguageKit:Value*, 0)
    binding.call = call
    binding.arity = arity
    binding.userdata = userdata
    return binding.symbol
}

let LanguageKit:value = fn (state:Context*, name:u8*) -> LanguageKit:Value* {
    let binding = LanguageKit:binding_named(state, name)
    if binding && binding.kind == 1 { return binding.value }
    if binding && binding.kind == 2 && binding.arity == 0 && binding.call {
        let callback = binding.call
        let evaluated = callback(state, binding.userdata, cast(LanguageKit:Value**, 0), 0)
        if evaluated { LanguageKit:publish(state, name, evaluated) }
        return evaluated
    }
    // Ordinary RecurLoop values participate without an explicit export step.
    if context:value:contains(state, name) {
        let formatted = context:value:format(state, name)
        if formatted {
            // The generic fallback is intentionally integer-first. Languages
            // with richer type information can publish an explicit Value.
            let value = LanguageKit:Value:integer(state, LanguageKit:text_number(formatted))
            free(formatted)
            return value
        }
    }
    return cast(LanguageKit:Value*, 0)
}

let LanguageKit:invoke = fn (
    state:Context*, name:u8*, args:LanguageKit:Value**, argc:i64
) -> LanguageKit:Value* {
    let binding = LanguageKit:binding_named(state, name)
    if !binding || binding.kind != 2 || !binding.call { return cast(LanguageKit:Value*, 0) }
    if binding.arity >= 0 && binding.arity != argc {
        context:diagnostic:error(state, "LanguageKit: callable arity mismatch")
        return cast(LanguageKit:Value*, 0)
    }
    let depth = LanguageKit:state_get(state, "__languagekit_call_depth")
    let depth_limit = LanguageKit:Guard:limit(state, "__languagekit_call_depth_limit", 512)
    if depth >= depth_limit { context:diagnostic:error(state, "LanguageKit: cross-language call depth limit exceeded"); return cast(LanguageKit:Value*, 0) }
    let scope = LanguageKit:Lifetime:enter(state)
    if !scope { return cast(LanguageKit:Value*, 0) }
    defer LanguageKit:Lifetime:leave(state, scope)
    LanguageKit:state_set(state, "__languagekit_call_depth", depth + 1)
    defer LanguageKit:state_set(state, "__languagekit_call_depth", depth)
    let callback = binding.call
    let result = callback(state, binding.userdata, args, argc)
    if result && LanguageKit:Lifetime:managed(state, cast(u8*, result)) {
        LanguageKit:Lifetime:move_to_parent(state, cast(u8*, result))
    }
    return result
}


// =============================================================================
// Native semantic capabilities.
//
// A capability is a source-defined native runtime component.  Language
// extensions lower semantic operations to these stable symbols instead of
// asking the C++ host to understand laziness, backtracking, mailboxes, channels,
// or any other language-specific execution model. Source-defined compilers
// store every component as an ordinary native Module; composeModule therefore
// closes the dependency graph automatically when an executable is emitted.
// =============================================================================

let LanguageKit:Native = phrase { dictionary = true permanent = true }
let LanguageKit:Native:Capabilities = phrase { dictionary = true permanent = true }

let LanguageKit:Native:capability_owner = fn (state:Context*) -> i64 {
    let kit = context:phrase:find(state, "LanguageKit")
    if !kit { return 0 }
    let native = context:phrase:find:exact(state, kit, "Native")
    if !native { return 0 }
    return context:phrase:find:exact(state, native, "Capabilities")
}

// Capability metadata is stored in phrase payloads, not in malloc-backed
// Context values.  That makes the registry survive engine export/import just
// like the compiler's own typed-function and native-module registries.
// Payload layout: [version:i64][flags:i64][root symbol bytes...].
let LanguageKit:Native:find = fn (state:Context*, name:u8*) -> i64 {
    let owner = LanguageKit:Native:capability_owner(state)
    if !owner || !name { return 0 }
    return context:phrase:find:exact(state, owner, name)
}

let LanguageKit:Native:register = fn (
    state:Context*, name:u8*, version:i64, root_symbol:u8*, flags:i64
) -> i64 {
    if !state || !name || !root_symbol || version <= 0 { return 0 }
    let owner = LanguageKit:Native:capability_owner(state)
    if !owner { return 0 }
    let existing = context:phrase:find:exact(state, owner, name)
    if existing {
        let bytes = context:phrase:payload:bytes(state, existing)
        if bytes < 16 { context:diagnostic:error(state, "LanguageKit Native: malformed capability metadata"); return 0 }
        var stored_version:i64 = 0
        var stored_flags:i64 = 0
        context:phrase:read(state, existing, 0, cast(u8*, &stored_version), 8)
        context:phrase:read(state, existing, 8, cast(u8*, &stored_flags), 8)
        if stored_version != version || stored_flags != flags {
            context:diagnostic:error(state, "LanguageKit Native: incompatible capability redefinition")
            return 0
        }
        let symbol_bytes = bytes - 16
        let stored = cast(u8*, malloc(symbol_bytes + 1))
        if !stored { return 0 }
        defer free(stored)
        if symbol_bytes > 0 { context:phrase:read(state, existing, 16, stored, symbol_bytes) }
        stored[symbol_bytes] = 0
        if strcmp(stored, root_symbol) != 0 {
            context:diagnostic:error(state, "LanguageKit Native: capability root symbol changed")
            return 0
        }
        return 1
    }
    let entry = context:phrase:define:data(state, owner, name)
    if !entry { return 0 }
    if context:phrase:data(state, entry, cast(u8*, &version), 0, 8) != entry { return 0 }
    if context:phrase:data(state, entry, cast(u8*, &flags), 0, 8) != entry { return 0 }
    let symbol_bytes = cast(i64, strlen(root_symbol))
    if symbol_bytes > 0 && context:phrase:data(state, entry, root_symbol, 0, symbol_bytes) != entry { return 0 }
    return 1
}

let LanguageKit:Native:version = fn (state:Context*, name:u8*) -> i64 {
    let entry = LanguageKit:Native:find(state, name)
    if !entry || context:phrase:payload:bytes(state, entry) < 16 { return 0 }
    var version:i64 = 0
    context:phrase:read(state, entry, 0, cast(u8*, &version), 8)
    return version
}

let LanguageKit:Native:flags = fn (state:Context*, name:u8*) -> i64 {
    let entry = LanguageKit:Native:find(state, name)
    if !entry || context:phrase:payload:bytes(state, entry) < 16 { return 0 }
    var flags:i64 = 0
    context:phrase:read(state, entry, 8, cast(u8*, &flags), 8)
    return flags
}

let LanguageKit:Native:require = fn (state:Context*, name:u8*, minimum_version:i64) -> u8* {
    let entry = LanguageKit:Native:find(state, name)
    if !entry {
        context:diagnostic:error(state, "LanguageKit Native: required semantic capability is not installed")
        return cast(u8*, 0)
    }
    let bytes = context:phrase:payload:bytes(state, entry)
    if bytes < 16 { context:diagnostic:error(state, "LanguageKit Native: malformed capability metadata"); return cast(u8*, 0) }
    var version:i64 = 0
    context:phrase:read(state, entry, 0, cast(u8*, &version), 8)
    if version < minimum_version {
        context:diagnostic:error(state, "LanguageKit Native: semantic capability version is too old")
        return cast(u8*, 0)
    }
    let symbol_bytes = bytes - 16
    let root = cast(u8*, malloc(symbol_bytes + 1))
    if !root { return cast(u8*, 0) }
    if symbol_bytes > 0 { context:phrase:read(state, entry, 16, root, symbol_bytes) }
    root[symbol_bytes] = 0
    return root
}

// Generic live-engine adapters for capability-backed scalar native functions.
// Language libraries may publish the same semantic primitive both as a
// LanguageKit callable and as a typed native module without duplicating ABI
// conversion code here or teaching the host about the language.
let LanguageKit:Native:I64Call0 = fn () -> i64
let LanguageKit:Native:I64Call1 = fn (a:i64) -> i64
let LanguageKit:Native:I64Call4 = fn (a:i64, b:i64, c:i64, d:i64) -> i64

let LanguageKit:Native:call_i64_0 = fn (
    state:Context*, userdata:i64, args:LanguageKit:Value**, argc:i64
) -> LanguageKit:Value* {
    if argc != 0 { return cast(LanguageKit:Value*, 0) }
    let target = cast(LanguageKit:Native:I64Call0, userdata)
    if !target { return cast(LanguageKit:Value*, 0) }
    return LanguageKit:Value:integer(state, target())
}

let LanguageKit:Native:call_i64_1 = fn (
    state:Context*, userdata:i64, args:LanguageKit:Value**, argc:i64
) -> LanguageKit:Value* {
    if argc != 1 || !args || !args[0] || args[0].kind != 1 { return cast(LanguageKit:Value*, 0) }
    let target = cast(LanguageKit:Native:I64Call1, userdata)
    if !target { return cast(LanguageKit:Value*, 0) }
    return LanguageKit:Value:integer(state, target(args[0].number))
}

let LanguageKit:Native:call_i64_4 = fn (
    state:Context*, userdata:i64, args:LanguageKit:Value**, argc:i64
) -> LanguageKit:Value* {
    if argc != 4 || !args { return cast(LanguageKit:Value*, 0) }
    var i = 0
    while i < 4 { if !args[i] || args[i].kind != 1 { return cast(LanguageKit:Value*, 0) }; i += 1 }
    let target = cast(LanguageKit:Native:I64Call4, userdata)
    if !target { return cast(LanguageKit:Value*, 0) }
    return LanguageKit:Value:integer(state, target(args[0].number, args[1].number, args[2].number, args[3].number))
}

let LanguageKit:Native:invoke_i64_1 = fn (state:Context*, capability:u8*, argument:i64) -> i64 {
    let root = LanguageKit:Native:require(state, capability, 1)
    if !root { return 0 }
    let address = context:function:address(state, root)
    free(root)
    if !address { return 0 }
    let target = cast(LanguageKit:Native:I64Call1, address)
    return target(argument)
}

let LanguageKit:Native:invoke_i64_4 = fn (
    state:Context*, capability:u8*, a:i64, b:i64, c:i64, d:i64
) -> i64 {
    let root = LanguageKit:Native:require(state, capability, 1)
    if !root { return 0 }
    let address = context:function:address(state, root)
    free(root)
    if !address { return 0 }
    let target = cast(LanguageKit:Native:I64Call4, address)
    return target(a, b, c, d)
}

// =============================================================================
// Shared ambiguity-aware top-level dispatcher.
//
// Structural language probes never consume source. Each probe offers a parser
// together with the byte extent it can validate and a small specificity score.
// All probes are evaluated; import/child iteration order therefore cannot pick
// a winner. Among foreign structural forms, longest validated extent wins,
// then specificity. An exact tie is an ambiguity error.
//
// The ordinary RecurLoop root dictionary is probed independently through the
// non-consuming context:source:probe:longest host primitive. If a root phrase
// and a longer foreign form both match, LanguageKit deliberately reports an
// ambiguity instead of guessing whether the root phrase's action would consume
// the remaining bytes. A user can resolve that case with an explicit selector
// such as `haskell `, `prolog `, `erlang `, `go `, `cpp `, `shell `, `amber ` or `recurloop `.
//
// Generic catch-alls (currently Shell) are kept in LanguageKit:Fallbacks and
// are considered only when neither an ordinary root phrase nor a structural
// language form has matched.
// =============================================================================

// A block selector is a soft, dynamically scoped preference rather than a
// language mode. Longest validated extent still wins. For equal extents the
// preferred language wins before specificity is considered; if the preferred
// language does not match, all other shared grammars remain available.
let LanguageKit:preferred_probe = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_preferred_probe")
}

let LanguageKit:prefer_root = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_prefer_root")
}

let LanguageKit:selector_block_present = fn (state:Context*) -> i64 {
    var offset = 0
    while LanguageKit:is_space(LanguageKit:Source:peek(state, offset)) { offset += 1 }
    return LanguageKit:Source:peek(state, offset) == 123
}

let LanguageKit:execute_preferred_block = fn (
    state:Context*, preferred_probe:i64, prefer_root:i64
) -> i64 {
    let block = context:source:block:capture(state)
    if !block { return 0 }
    defer context:source:block:release(block)

    // Selectors accept only an optional-whitespace header before `{`.
    let header = context:source:block:header(block)
    var index = 0
    while header && header[index] != 0 {
        if !LanguageKit:is_space(header[index]) {
            context:diagnostic:error(state, "LanguageKit: language preference block expects '{' immediately after the selector")
            return 0
        }
        index += 1
    }

    let old_probe = LanguageKit:preferred_probe(state)
    let old_root = LanguageKit:prefer_root(state)
    LanguageKit:state_set(state, "__languagekit_preferred_probe", preferred_probe)
    LanguageKit:state_set(state, "__languagekit_prefer_root", prefer_root)
    defer LanguageKit:state_set(state, "__languagekit_preferred_probe", old_probe)
    defer LanguageKit:state_set(state, "__languagekit_prefer_root", old_root)

    // This is syntax grouping, not a value scope: declarations made inside the
    // block remain in the same shared RecurLoop/Haskell/Prolog/Erlang/Go/C++/Shell/
    // Amber space. Nested preference blocks work because the old preference is
    // restored synchronously after the captured body finishes.
    context:source:block:execute:current(state, block)
    context:source:root(state)
    return 1
}

let LanguageKit:candidate_reset = fn (state:Context*) -> i64 {
    LanguageKit:state_set(state, "__languagekit_candidate_present", 0)
    LanguageKit:state_set(state, "__languagekit_selected_form", 0)
    LanguageKit:state_set(state, "__languagekit_selected_probe", 0)
    LanguageKit:state_set(state, "__languagekit_selected_extent", 0)
    LanguageKit:state_set(state, "__languagekit_selected_specificity", 0)
    LanguageKit:state_set(state, "__languagekit_ambiguous", 0)
    LanguageKit:state_set(state, "__languagekit_ambiguous_probe", 0)
    return 1
}

let LanguageKit:candidate_present = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_candidate_present")
}

let LanguageKit:selected_form = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_selected_form")
}

let LanguageKit:selected_probe = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_selected_probe")
}

let LanguageKit:selected_extent = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_selected_extent")
}

let LanguageKit:selected_specificity = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_selected_specificity")
}

let LanguageKit:candidate_ambiguous = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_ambiguous")
}

let LanguageKit:ambiguous_probe = fn (state:Context*) -> i64 {
    return LanguageKit:state_get(state, "__languagekit_ambiguous_probe")
}

// Offer one fully validated language form. Longer validated source wins; if
// extents tie, the probe with more literal/structural evidence wins. A perfect
// tie between different parsers remains ambiguous by design.
let LanguageKit:offer_form = fn (
    state:Context*, form:i64, probe:i64, extent:i64, specificity:i64
) -> i64 {
    if !form || extent <= 0 { return 0 }
    if !LanguageKit:candidate_present(state) {
        LanguageKit:state_set(state, "__languagekit_candidate_present", 1)
        LanguageKit:state_set(state, "__languagekit_selected_form", form)
        LanguageKit:state_set(state, "__languagekit_selected_probe", probe)
        LanguageKit:state_set(state, "__languagekit_selected_extent", extent)
        LanguageKit:state_set(state, "__languagekit_selected_specificity", specificity)
        return 1
    }

    let selected = LanguageKit:selected_form(state)
    let selected_probe = LanguageKit:selected_probe(state)
    let selected_extent = LanguageKit:selected_extent(state)
    let selected_specificity = LanguageKit:selected_specificity(state)
    let preferred = LanguageKit:preferred_probe(state)
    let offered_preferred = preferred && probe == preferred
    let selected_preferred = preferred && selected_probe == preferred
    var better = 0
    if extent > selected_extent {
        better = 1
    } else if extent == selected_extent {
        // A block preference is deliberately below longest-match but above the
        // heuristic specificity score. This makes it a predictable tie-breaker
        // without turning the block into an isolated language mode.
        if offered_preferred && !selected_preferred { better = 1 }
        else if offered_preferred == selected_preferred && specificity > selected_specificity { better = 1 }
    }

    if better {
        LanguageKit:state_set(state, "__languagekit_selected_form", form)
        LanguageKit:state_set(state, "__languagekit_selected_probe", probe)
        LanguageKit:state_set(state, "__languagekit_selected_extent", extent)
        LanguageKit:state_set(state, "__languagekit_selected_specificity", specificity)
        LanguageKit:state_set(state, "__languagekit_ambiguous", 0)
        LanguageKit:state_set(state, "__languagekit_ambiguous_probe", 0)
        return 1
    }

    if extent == selected_extent && specificity == selected_specificity && form != selected {
        // If exactly one candidate carries the current block preference, the
        // preference resolved this tie. Two non-preferred (or two preferred)
        // equal candidates are genuinely ambiguous.
        if offered_preferred == selected_preferred {
            LanguageKit:state_set(state, "__languagekit_ambiguous", 1)
            LanguageKit:state_set(state, "__languagekit_ambiguous_probe", probe)
        }
    }
    return 1
}

// Backwards-compatible convenience for very small extensions. New language
// probes should call offer_form with a real extent and specificity.
let LanguageKit:select_form = fn (state:Context*, phrase:i64) -> i64 {
    if !phrase { LanguageKit:candidate_reset(state); return 0 }
    return LanguageKit:offer_form(state, phrase, 0, 1, 0)
}

let LanguageKit:probe_owner = fn (state:Context*, owner:i64) -> i64 {
    var child = context:phrase:child:first(state, owner)
    while child {
        // Probe actions may intern symbols, so fetch the next stable registry
        // cursor before dispatching the current probe.
        let next = context:phrase:child:next(state, owner, child)
        context:phrase:dispatch(state, child)
        child = next
    }
    return LanguageKit:candidate_present(state)
}

let LanguageKit:registry_entry = fn (state:Context*, registry:u8*, name:u8*) -> i64 {
    let kit = context:phrase:find(state, "LanguageKit")
    if !kit { return 0 }
    let owner = context:phrase:find:exact(state, kit, registry)
    if !owner { return 0 }
    return context:phrase:find:exact(state, owner, name)
}

let LanguageKit:phrase_key_text = fn (state:Context*, phrase:i64) -> u8* {
    if !phrase { return LanguageKit:copy_text("?") }
    let bytes = context:phrase:key(state, phrase, cast(u8*, 0), 0)
    if bytes <= 0 { return LanguageKit:copy_text("?") }
    let out = cast(u8*, malloc(bytes + 1))
    if !out { return cast(u8*, 0) }
    context:phrase:key(state, phrase, out, bytes)
    out[bytes] = 0
    return out
}

let LanguageKit:report_ambiguity = fn (
    state:Context*, root_phrase:i64, first_probe:i64, second_probe:i64, extent:i64
) -> i64 {
    let text = LanguageKit:Text:new()
    if text {
        text.append("LanguageKit: ambiguous top-level form: ")
        if root_phrase {
            let root_key = LanguageKit:phrase_key_text(state, root_phrase)
            text.append("RecurLoop phrase '")
            if root_key { text.append(root_key); free(root_key) }
            text.append("' and ")
        }
        if first_probe {
            let first = LanguageKit:phrase_key_text(state, first_probe)
            if first { text.append(first); free(first) }
        } else if !root_phrase { text.append("one language") }
        if second_probe {
            text.append(" and ")
            let second = LanguageKit:phrase_key_text(state, second_probe)
            if second { text.append(second); free(second) }
        }
        text.append(" both match; prefix one form with 'recurloop ', 'haskell ', 'prolog ', 'erlang ', 'go ', 'cpp ', 'infer ', 'shell ', or 'amber ', or use a preference block such as 'haskell { ... }'")
        let message = text.take()
        if message { context:diagnostic:error(state, message); free(message) }
        text.destroy()
    } else {
        context:diagnostic:error(state, "LanguageKit: ambiguous top-level form; use an explicit language selector")
    }
    if extent > 0 { LanguageKit:Source:advance(state, extent) }
    else { LanguageKit:Source:skip_line(state) }
    context:source:root(state)
    return 1
}

let LanguageKit:selector_present = fn (state:Context*) -> i64 {
    let kit = context:phrase:find(state, "LanguageKit")
    if !kit { return 0 }
    let selectors = context:phrase:find:exact(state, kit, "Selectors")
    if !selectors { return 0 }
    return context:source:probe:longest(state, selectors)
}

// The source hook runs before ordinary root lookup. It only intervenes when a
// structural foreign parser can be selected safely or when ambiguity must be
// diagnosed. Otherwise normal RecurLoop longest-prefix lookup remains in
// control.
let LanguageKit:dispatch_competing = fn (state:Context*) -> i64 {
    if LanguageKit:state_get(state, "__languagekit_dispatch_suspended") { return 0 }

    // Explicit shared-root selectors are one-shot. Keep a second flag alive
    // until we know whether a real root phrase or the empty fallback matched.
    if LanguageKit:state_get(state, "__languagekit_force_root_once") {
        LanguageKit:state_set(state, "__languagekit_force_root_once", 0)
        LanguageKit:state_set(state, "__languagekit_force_root_active", 1)
        return 0
    }
    if LanguageKit:state_get(state, "__languagekit_force_root_active") {
        // A real root phrase completed and control returned to the root.
        LanguageKit:state_set(state, "__languagekit_force_root_active", 0)
    }

    // Let the ordinary phrase graph consume whitespace/comments first. This
    // avoids treating a whitespace phrase as a competing root candidate.
    let first = LanguageKit:Source:peek(state, 0)
    if LanguageKit:is_space(first) { return 0 }
    if LanguageKit:Source:starts_with(state, "//") ||
       LanguageKit:Source:starts_with(state, "--") ||
       LanguageKit:Source:starts_with(state, "%") ||
       LanguageKit:Source:starts_with(state, "?-") { return 0 }

    // Selector spellings are themselves ordinary root phrases. Never let a
    // generic language probe reinterpret `haskell ...` as a Haskell function
    // whose name happens to be "haskell".
    if LanguageKit:selector_present(state) { return 0 }

    let kit = context:phrase:find(state, "LanguageKit")
    if !kit { return 0 }
    let forms = context:phrase:find:exact(state, kit, "Forms")
    if !forms { return 0 }

    LanguageKit:candidate_reset(state)
    LanguageKit:probe_owner(state, forms)

    // A preferred fallback (notably Shell) must be allowed to compete with
    // structural forms. For a preferred structural language this harmlessly
    // re-runs the same non-consuming probe and keeps the result deterministic.
    let preferred_probe = LanguageKit:preferred_probe(state)
    if preferred_probe { context:phrase:dispatch(state, preferred_probe) }

    if !LanguageKit:candidate_present(state) {
        // No structural language form matched. Before ordinary lookup runs,
        // determine whether a real root phrase can claim this source. Only if
        // there is no non-empty root match do generic fallbacks (notably Shell)
        // get a chance. Dispatching the fallback from the source hook is
        // important for streaming grammars: Shell enters its command dictionary
        // without consuming a byte, and ordinary lookup must continue there.
        let root = context:source:root(state)
        let root_phrase = context:source:probe:longest(state, root)
        var root_extent = 0
        if root_phrase { root_extent = context:phrase:key(state, root_phrase, cast(u8*, 0), 0) }
        if root_extent > 0 { return 0 }

        let fallbacks = context:phrase:find:exact(state, kit, "Fallbacks")
        LanguageKit:candidate_reset(state)
        if fallbacks { LanguageKit:probe_owner(state, fallbacks) }
        if !LanguageKit:candidate_present(state) { return 0 }
        if LanguageKit:candidate_ambiguous(state) {
            return LanguageKit:report_ambiguity(
                state, 0, LanguageKit:selected_probe(state), LanguageKit:ambiguous_probe(state),
                LanguageKit:selected_extent(state)
            )
        }
        context:phrase:dispatch(state, LanguageKit:selected_form(state))
        return 1
    }

    let foreign_form = LanguageKit:selected_form(state)
    let foreign_probe = LanguageKit:selected_probe(state)
    let foreign_extent = LanguageKit:selected_extent(state)

    if LanguageKit:candidate_ambiguous(state) {
        return LanguageKit:report_ambiguity(
            state, 0, foreign_probe, LanguageKit:ambiguous_probe(state), foreign_extent
        )
    }

    let root = context:source:root(state)
    var root_phrase = context:source:probe:longest(state, root)
    var root_extent = 0
    if root_phrase { root_extent = context:phrase:key(state, root_phrase, cast(u8*, 0), 0) }

    // Empty-key fallback is not an ordinary root interpretation. It is handled
    // later by dispatch_form, after structural forms have had their chance.
    if root_extent <= 0 { root_phrase = 0 }

    if root_phrase {
        // A root preference (recurloop/amber block) resolves only this conflict;
        // forms which have no root competitor still remain available.
        if LanguageKit:prefer_root(state) { return 0 }

        // A preferred foreign grammar is allowed to resolve the otherwise
        // unknowable root-vs-parser case. The parser has already validated a
        // complete form; without an explicit preference we keep the conservative
        // ambiguity error below.
        if preferred_probe && foreign_probe == preferred_probe {
            context:phrase:dispatch(state, foreign_form)
            return 1
        }

        // A literal root match which already covers at least as much source is
        // the strongest evidence available and keeps normal longest-match
        // semantics. If the foreign parser claims more bytes, the root action
        // may still legitimately consume them; without speculative execution
        // neither interpretation can be proven unique, so require an explicit
        // selector or preference block rather than guessing.
        if root_extent >= foreign_extent { return 0 }
        return LanguageKit:report_ambiguity(state, root_phrase, foreign_probe, 0, foreign_extent)
    }

    context:phrase:dispatch(state, foreign_form)
    return 1
}

let LanguageKit:pre_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        LanguageKit:dispatch_competing(state)
    }
}

let LanguageKit:dispatch_form = fn (state:Context*) -> i64 {
    let kit = context:phrase:find(state, "LanguageKit")
    if !kit { return 0 }

    // If an explicit `recurloop ` / `amber ` selector reached the empty root
    // fallback, the selected shared-root grammar did not actually contain a
    // matching phrase. Do not silently hand it to another language.
    if LanguageKit:state_get(state, "__languagekit_force_root_active") {
        LanguageKit:state_set(state, "__languagekit_force_root_active", 0)
        context:diagnostic:error(state, "LanguageKit: explicit shared-root form did not match a RecurLoop/Amber phrase")
        LanguageKit:Source:skip_line(state)
        return 1
    }

    let forms = context:phrase:find:exact(state, kit, "Forms")
    LanguageKit:candidate_reset(state)
    if forms { LanguageKit:probe_owner(state, forms) }
    let preferred_probe = LanguageKit:preferred_probe(state)
    if preferred_probe { context:phrase:dispatch(state, preferred_probe) }
    if LanguageKit:candidate_present(state) {
        if LanguageKit:candidate_ambiguous(state) {
            return LanguageKit:report_ambiguity(
                state, 0, LanguageKit:selected_probe(state), LanguageKit:ambiguous_probe(state),
                LanguageKit:selected_extent(state)
            )
        }
        context:phrase:dispatch(state, LanguageKit:selected_form(state))
        return 1
    }

    // Catch-alls are a separate ranking phase and can never beat a structural
    // form merely because they consume a whole line.
    let fallbacks = context:phrase:find:exact(state, kit, "Fallbacks")
    LanguageKit:candidate_reset(state)
    if fallbacks { LanguageKit:probe_owner(state, fallbacks) }
    if LanguageKit:candidate_present(state) {
        if LanguageKit:candidate_ambiguous(state) {
            return LanguageKit:report_ambiguity(
                state, 0, LanguageKit:selected_probe(state), LanguageKit:ambiguous_probe(state),
                LanguageKit:selected_extent(state)
            )
        }
        context:phrase:dispatch(state, LanguageKit:selected_form(state))
        return 1
    }
    return 0
}

let LanguageKit:top_form = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if !LanguageKit:dispatch_form(state) {
            context:diagnostic:error(state, "LanguageKit: no loaded language accepted the top-level form")
            LanguageKit:Source:skip_line(state)
        }
        context:source:root(state)
    }
}

let LanguageKit:install_fallback = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let kit = context:phrase:find(state, "LanguageKit")
        let top = context:phrase:find:exact(state, kit, "top_form")
        let fallback = context:phrase:define:alias(state, "", top)
        if !fallback { context:diagnostic:error(state, "LanguageKit: could not install merged source fallback") }
    }
}

let LanguageKit:install_source_hook = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let kit = context:phrase:find(state, "LanguageKit")
        let pre = context:phrase:find:exact(state, kit, "pre_form")
        if !pre || !context:source:hook(state, pre) {
            context:diagnostic:error(state, "LanguageKit: could not install source pre-dispatch hook")
        }
    }
}

// Language-extension libraries are themselves written in ordinary RecurLoop.
// Once one foreign grammar is loaded, later library source could otherwise be
// a legitimate competitor (for example a Haskell equation probe seeing a
// RecurLoop `let ... = ...` definition). These two internal phrases suspend
// only ambiguity probing while a library installs its phrases; they do not
// create a source lexicon, namespace, or persistent language mode.
let LanguageKit:native_begin = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        LanguageKit:state_set(state, "__languagekit_dispatch_suspended", 1)
        context:source:root(state)
    }
}
let LanguageKit:native_end = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        LanguageKit:state_set(state, "__languagekit_dispatch_suspended", 0)
        context:source:root(state)
    }
}
let languagekit_native_begin = <LanguageKit:native_begin>
let languagekit_native_end = <LanguageKit:native_end>

// `recurloop ` is the explicit selector for the ordinary shared root grammar.
// It is intentionally a normal phrase, not a language mode: it affects only
// the immediately following form.
let LanguageKit:recurloop_selector = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if LanguageKit:selector_block_present(state) {
            LanguageKit:execute_preferred_block(state, 0, 1)
            return
        }
        LanguageKit:state_set(state, "__languagekit_force_root_once", 1)
        context:source:root(state)
    }
}
let "recurloop " = <LanguageKit:recurloop_selector>
let LanguageKit:Selectors:"recurloop " = <LanguageKit:recurloop_selector>

// Common top-level comments. A language may add more explicit comment phrases.
let LanguageKit:line_comment = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        LanguageKit:Source:skip_line(state)
        context:source:root(state)
    }
}

// These prefixes have the same line-comment meaning in all workflows which use
// them. They coexist with language forms because longest-prefix lookup wins.
let "--" = <LanguageKit:line_comment>
let "%" = <LanguageKit:line_comment>

let languagekit_install_fallback = <LanguageKit:install_fallback>
languagekit_install_fallback
let languagekit_install_source_hook = <LanguageKit:install_source_hook>
languagekit_install_source_hook

set malloc.serializable = false
set realloc.serializable = false
set free.serializable = false
set memcpy.serializable = false
set strlen.serializable = false
set strcmp.serializable = false
set printf.serializable = false
set LanguageKit:install_fallback.serializable = false
set languagekit_install_fallback.serializable = false
set LanguageKit:install_source_hook.serializable = false
set languagekit_install_source_hook.serializable = false
include "../build/export.rl"
__recurloop_export_library
