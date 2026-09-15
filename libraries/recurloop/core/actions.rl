// Source-owned standard phrase actions.
//
// These are compiled as normal RecurLoop functions and persisted in core.rli.
// Core:ActionBindings maps the legacy bootstrap host-action name to a carrier
// phrase whose inline action owns the compiled implementation.  A generic
// Context primitive performs the one-time build binding; final core phrases
// then use fn.bound-action and no longer reference the migrated host callback.

let Core:Actions = []
let Core:ActionBindings = []

let Core:Actions:language_ignore = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        return
    }
}

let Core:Actions:language_ping = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        context:io:write(state, "pong\n")
        return
    }
}

let Core:Actions:source_progress_byte = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        context:source:advance(state, 1)
        return
    }
}

let Core:Actions:workspace_pass_byte = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:source:ensure(state, 1) == 0 { return }
        let byte = context:source:peek(state, 0)
        context:workspace:key:append_byte(state, byte)
        context:source:advance(state, 1)
        return
    }
}

let Core:Actions:workspace_pass_cr = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        context:workspace:key:append_byte(state, 13)
        return
    }
}

let Core:Actions:workspace_pass_lf = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        context:workspace:key:append_byte(state, 10)
        return
    }
}

let Core:Actions:workspace_pass_tab = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        context:workspace:key:append_byte(state, 9)
        return
    }
}

let Core:Actions:workspace_pass_vtab = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        context:workspace:key:append_byte(state, 11)
        return
    }
}

let Core:Actions:hex_nibble = fn (state:Context*, value:u64, high:i64) -> i64 {
    if value >= 48 && value <= 57 { return cast(i64, value - 48) }
    if value >= 65 && value <= 70 { return cast(i64, value - 65 + 10) }
    if value >= 97 && value <= 102 { return cast(i64, value - 97 + 10) }
    if high {
        context:diagnostic:error(state, "Hex: high invalid code")
    } else {
        context:diagnostic:error(state, "Hex: low invalid code")
    }
    return -1
}

let Core:Actions:hex_byte = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:source:ensure(state, 2) < 2 { return }
        let high = Core:Actions:hex_nibble(state, context:source:peek(state, 0), 1)
        if high < 0 { return }
        let low = Core:Actions:hex_nibble(state, context:source:peek(state, 1), 0)
        if low < 0 { return }
        context:workspace:code:append_byte(state, cast(u64, high * 16 + low))
        context:source:advance(state, 2)
        return
    }
}

let Core:Actions:is_space = fn (value:u64) -> i64 {
    return value == 32 || value == 9 || value == 10 || value == 13
}

// Record/type instances are ordinary semantic phrases.  The legacy C++
// callback only parsed one identifier and copied the type phrase payload; keep
// that policy in the source-owned compiler instead of growing the host action
// surface when core-defined records are added.
let Core:Actions:typed_instantiate = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        let prototype = context:phrase:address(state, called)
        if !prototype { context:diagnostic:error(state, "typed instance has no prototype phrase"); return }

        let line = Core:Work:ByteBuffer:new(state, 32)
        if !line { context:diagnostic:error(state, "typed instance input allocation failed"); return }
        defer line.destroy(state)

        while context:source:ensure(state, 1) {
            let ch = context:source:peek(state, 0)
            if ch == 10 || ch == 13 { break }
            if !line.push(state, ch) { context:diagnostic:error(state, "typed instance input allocation failed"); return }
            context:source:advance(state, 1)
        }
        if !line.push(state, 0) { context:diagnostic:error(state, "typed instance input allocation failed"); return }

        var begin:u64 = 0
        while begin < line.length - 1 && Core:Actions:is_space(line.data[begin]) { begin += 1 }
        var finish = begin
        while finish < line.length - 1 && !Core:Actions:is_space(line.data[finish]) { finish += 1 }
        if finish == begin { context:diagnostic:error(state, "typed declaration: expected an instance name"); return }
        var trailing = finish
        while trailing < line.length - 1 && Core:Actions:is_space(line.data[trailing]) { trailing += 1 }
        if trailing != line.length - 1 { context:diagnostic:error(state, "typed declaration: unexpected token after instance name"); return }
        line.data[finish] = 0

        var type_id:u64 = 0
        var storage_bytes:u64 = 0
        if context:phrase:read(state, prototype, 0, cast(u8*, &type_id), 8) != 8 ||
           context:phrase:read(state, prototype, 8, cast(u8*, &storage_bytes), 8) != 8 {
            context:diagnostic:error(state, "typed declaration: invalid prototype payload")
            return
        }

        let phrase_types = context:phrase:find(state, "phrase-types")
        let data_type = context:phrase:find:exact(state, phrase_types, "data")
        if !data_type { context:diagnostic:error(state, "typed declaration: data phrase type is unavailable"); return }

        // Serializable | HasType | HasPrototype = 1 | 8 | 16.
        let instance = context:phrase:define(state, 0, &line.data[begin], data_type, prototype, 0, 0, 25)
        if !instance { context:diagnostic:error(state, "typed declaration: could not create instance"); return }
        if context:phrase:data(state, instance, cast(u8*, &type_id), 0, 8) != instance ||
           context:phrase:data(state, instance, cast(u8*, &storage_bytes), 0, 8) != instance {
            context:diagnostic:error(state, "typed declaration: could not store instance metadata")
            return
        }

        var zero:u64 = 0
        var remaining = storage_bytes
        while remaining >= 8 {
            if context:phrase:data(state, instance, cast(u8*, &zero), 0, 8) != instance { return }
            remaining -= 8
        }
        if remaining && context:phrase:data(state, instance, cast(u8*, &zero), 0, remaining) != instance { return }
        return
    }
}

// Source-owned mapping.  Adding another migrated action requires only a new
// carrier function and binding entry; the binder does not know these names.
let Core:ActionBindings:"language.ignore" = <Core:Actions:language_ignore>
let Core:ActionBindings:"language.ping" = <Core:Actions:language_ping>
let Core:ActionBindings:"source.progress-byte" = <Core:Actions:source_progress_byte>
let Core:ActionBindings:"workspace.pass-byte" = <Core:Actions:workspace_pass_byte>
let Core:ActionBindings:"workspace.pass-cr" = <Core:Actions:workspace_pass_cr>
let Core:ActionBindings:"workspace.pass-lf" = <Core:Actions:workspace_pass_lf>
let Core:ActionBindings:"workspace.pass-tab" = <Core:Actions:workspace_pass_tab>
let Core:ActionBindings:"workspace.pass-vtab" = <Core:Actions:workspace_pass_vtab>
let Core:ActionBindings:"hex.byte" = <Core:Actions:hex_byte>
let Core:ActionBindings:"typed.instantiate" = <Core:Actions:typed_instantiate>

let Core:ApplyActionBindings = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        let core = context:phrase:find(state, "Core")
        if !core { context:diagnostic:error(state, "source action namespace is missing"); return }
        let bindings = context:phrase:find:exact(state, core, "ActionBindings")
        if !bindings { context:diagnostic:error(state, "source action binding registry is missing"); return }
        if context:actions:bind_root(state, bindings) == 0 {
            context:diagnostic:error(state, "source action binding did not replace any phrase")
            return
        }
        // Qualified invocation enters the Core dictionary; restore root before
        // core.rl continues with engine export.
        context:source:root(state)
        return
    }
}

Core:ApplyActionBindings
