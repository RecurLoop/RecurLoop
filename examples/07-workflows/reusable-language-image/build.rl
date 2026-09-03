// Build a reusable language image using phrases and compiled .rl actions.
//
// The host provides only source, lexicon, type, and diagnostic primitives.
// The `repeat` syntax, PhrasePair layout, callable type, and actions below are
// all language state and survive in another RecurLoop process.

extern malloc(bytes:u64) -> u8* abi sysv-amd64
extern free(memory:u8*) -> void abi sysv-amd64
extern puts(text:u8*) -> i32 abi sysv-amd64

let repeat = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let block = state.source_block_capture()
        if !block {
            return
        }
        defer block.release()

        let header = block.header()
        var cursor = 0
        var count = 0
        while header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13 {
            cursor += 1
        }
        if header[cursor] < 48 || header[cursor] > 57 {
            context:diagnostic:error:at(
                state,
                block.path(),
                block.header_line(),
                block.header_position() + cursor,
                "repeat expects a non-negative decimal count"
            )
            return
        }
        while header[cursor] >= 48 && header[cursor] <= 57 {
            count = count * 10 + header[cursor] - 48
            cursor += 1
        }
        while header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13 {
            cursor += 1
        }
        if header[cursor] != 0 {
            context:diagnostic:error:at(
                state,
                block.path(),
                block.header_line(),
                block.header_position() + cursor,
                "unexpected input after repeat count"
            )
            return
        }

        while count > 0 {
            state.source_block_execute_current(block)
            count -= 1
        }
    }
}

// Field order is expressed by ordinary phrase successor links. Each field
// phrase carries only the physical type id in its payload.
let phrase_pair_fields = phrase { dictionary = true }
let phrase_pair_parameters = phrase { dictionary = true }

let install_phrase_types = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let integer = context:type:find(state, "i64")
        let fields = context:phrase:find(state, "phrase_pair_fields")

        let right = context:phrase:define:data(state, fields, "right")
        context:phrase:data(state, right, &integer, 0, 8)
        let left = context:phrase:define:successor(state, fields, "left", right)
        context:phrase:data(state, left, &integer, 0, 8)

        let pair = context:type:structure:declare(state, "PhrasePair")
        context:type:structure:complete:natural(state, pair, left)

        let pair_pointer = context:type:pointer(state, pair)
        let parameters = context:phrase:find(state, "phrase_pair_parameters")
        let first_parameter = context:phrase:define:data(state, parameters, "pair")
        context:phrase:data(state, first_parameter, &pair_pointer, 0, 8)
        let callable = context:type:function:fixed(state, first_parameter, integer, "sysv-amd64")
        if context:type:result(state, callable) != integer {
            context:diagnostic:error(state, "phrase-defined function type has an invalid result")
        }
    }
}
install_phrase_types

let verify_phrase_pair = fn () -> i64 {
    let pair = cast(PhrasePair*, malloc(16))
    if !pair {
        return 0
    }
    defer free(cast(u8*, pair))
    pair.left = 20
    pair.right = 22
    return pair.left + pair.right
}

let announce_phrase_language = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        puts("phrase language loaded in a fresh process")
    }
}

assert verify_phrase_pair() == 42
engine export "/tmp/recurloop-phrase-language.rli"
