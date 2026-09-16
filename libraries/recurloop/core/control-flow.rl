// Compatibility top-level control flow implemented in RecurLoop source.
//
// This replaces the old ControlFlow.cpp subsystem. The host exposes only
// generic block/source and expression-evaluation primitives; `if` and `while`
// themselves are ordinary source-defined phrases.

let RecurLoopCompatibility = phrase { dictionary = true permanent = true }

let RecurLoopCompatibility:if_impl = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        // Parse only the condition/header and consume the opening brace.  The
        // selected body is then consumed directly from Source; it is never
        // copied into SourceBlock::body.
        let accepted = context:source:block:begin(state)
        if !accepted { context:diagnostic:error(state, "if expects a condition and block"); return }
        defer context:source:block:release(accepted)

        let header = context:source:block:header(accepted)
        let path = context:source:block:path(accepted)
        let line = context:source:block:header:line(accepted)
        let position = context:source:block:header:position(accepted)
        if !header { context:diagnostic:error(state, "if requires a boolean expression before '{'"); return }

        let condition = context:expression:boolean:at(state, header, path, line, position)
        if condition {
            context:source:block:stream:execute(state, 1)
        } else {
            context:source:block:stream:skip(state)
        }

        if context:source:consume(state, "else") {
            let rejected = context:source:block:begin(state)
            if !rejected { context:diagnostic:error(state, "else expects a block"); return }
            defer context:source:block:release(rejected)

            let else_header = context:source:block:header(rejected)
            if else_header {
                var header_index = 0
                while else_header[header_index] == 32 || else_header[header_index] == 9 ||
                      else_header[header_index] == 10 || else_header[header_index] == 13 {
                    header_index += 1
                }
                if else_header[header_index] != 0 {
                    context:diagnostic:error(state, "else must be followed directly by '{'")
                    return
                }
            }

            if condition {
                context:source:block:stream:skip(state)
            } else {
                context:source:block:stream:execute(state, 1)
            }
        }
    }
}


let RecurLoopCompatibility:while_impl = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let block = context:source:block:capture(state)
        if !block { context:diagnostic:error(state, "while expects a condition and block"); return }
        defer context:source:block:release(block)

        let header = context:source:block:header(block)
        let path = context:source:block:path(block)
        let line = context:source:block:header:line(block)
        let position = context:source:block:header:position(block)
        if !header { context:diagnostic:error(state, "while requires a boolean expression before '{'"); return }

        while context:expression:boolean:at(state, header, path, line, position) {
            context:source:block:execute:scoped(state, block)
        }
    }
}

let RecurLoopCompatibility:if_marker = <if>
let RecurLoopCompatibility:while_marker = <while>

let "if" = phrase {
    type = <phrase-types:elaborate>
    prototype = <RecurLoopCompatibility:if_marker>
    action = <RecurLoopCompatibility:if_impl>
}

let "while" = phrase {
    type = <phrase-types:elaborate>
    prototype = <RecurLoopCompatibility:while_marker>
    action = <RecurLoopCompatibility:while_impl>
}
