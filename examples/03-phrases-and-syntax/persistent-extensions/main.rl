// A language extension implemented entirely as compiled RecurLoop actions.
//
// The host only exposes stable source, lexicon, diagnostic, and type primitives.
// `repeat`, `select`, and the `counter` type below do not have C++ parsers or
// C++ actions of their own. The compiled actions also survive an engine image
// round trip.

extern puts(text:u8*) -> i32 abi sysv-amd64

// This is a genuinely new top-level control-flow construct. Its action owns
// parsing of the header and block. It is not an alias of `while`.
let repeat = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let block = state.source_block_capture()
        if !block {
            return
        }
        defer block.release()

        let header = block.header()
        var index = 0
        var count = 0
        while header[index] == 32 || header[index] == 9 || header[index] == 10 || header[index] == 13 {
            index += 1
        }
        if header[index] < 48 || header[index] > 57 {
            context:diagnostic:error:at(
                state,
                block.path(),
                block.header_line(),
                block.header_position() + index,
                "repeat expects a non-negative decimal count before its block"
            )
            return
        }
        while header[index] >= 48 && header[index] <= 57 {
            count = count * 10 + header[index] - 48
            index += 1
        }
        while header[index] == 32 || header[index] == 9 || header[index] == 10 || header[index] == 13 {
            index += 1
        }
        if header[index] != 0 {
            context:diagnostic:error:at(
                state,
                block.path(),
                block.header_line(),
                block.header_position() + index,
                "repeat expects a non-negative decimal count before its block"
            )
            return
        }
        while count > 0 {
            if state.source_block_execute_current(block) == 0 {
                return
            }
            count -= 1
        }
    }
}

var repeated = 0
repeat 3 {
    repeated += 14
}
assert repeated == 42

// New scalar types can be installed by an .rl action before later functions
// are parsed. No TypeRegistry layout is exposed to generated code.
let install_counter_type = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        var counter_type = context:type:find(state, "counter")
        if counter_type == 0 {
            context:type:integer:signed(state, "counter", 64)
            counter_type = context:type:find(state, "counter")
        }
        if context:type:size(state, counter_type) != 8 || context:type:signed(state, counter_type) != 1 {
            context:diagnostic:error(state, "counter type metadata is invalid")
            return
        }
        let pointer_type = context:type:pointer(state, counter_type)
        let array_type = context:type:array(state, counter_type, 4)
        if context:type:element(state, pointer_type) != counter_type || context:type:element:count(state, array_type) != 4 {
            context:diagnostic:error(state, "derived .rl type metadata is invalid")
        }
    }
}
install_counter_type

let verify_counter_type = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        var left:counter = 20
        var right:counter = 22
        if left + right != 42 {
            context:diagnostic:error(state, "the .rl-defined counter type is not usable by fn")
        }
    }
}
verify_counter_type

let add_counter = fn (left:counter, right:counter) -> counter {
    return left + right
}
assert add_counter(20, 22) == 42

// A private grammar dictionary and a source-consuming action demonstrate that
// extensions can dispatch their own input through matchLongest.
let command_words = phrase {
    dictionary = true
}

let install_command_words = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let owner = context:phrase:find(state, "command_words")
        state.phrase_define_data(owner, "alpha")
        state.phrase_define_data(owner, "alphabet")

        let payload = context:phrase:define:data(state, "api-payload")
        context:phrase:data(state, payload, "payload")
        var copied:u64 = 0
        if context:phrase:key(state, payload, &copied, 8) != 11 || context:phrase:read(state, payload, 0, &copied, 7) != 7 {
            context:diagnostic:error(state, "phrase key or payload access failed")
            return
        }

        var children = 0
        var child = context:phrase:child:first(state, owner)
        while child != 0 {
            children += 1
            child = context:phrase:child:next(state, owner, child)
        }
        if children != 2 {
            context:diagnostic:error(state, "command dictionary iteration failed")
        }
    }
}
install_command_words

let select = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        while context:source:peek(state, 0) == 32 || context:source:peek(state, 0) == 9 {
            context:source:advance(state, 1)
        }

        let owner = context:phrase:find(state, "command_words")
        let matched = state.source_match_longest(owner)
        let alphabet = state.phrase_find_exact(owner, "alphabet")
        if matched != alphabet {
            context:diagnostic:error(state, "select expected the longest command word")
            return
        }
        puts("matchLongest selected alphabet")
    }
}

select alphabet

let report_survival = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        puts("compiled .rl syntax survived the engine image")
    }
}

engine export "/tmp/recurloop-persistent-extensions.rli"
engine import "/tmp/recurloop-persistent-extensions.rli"

verify_counter_type
assert add_counter(20, 22) == 42
repeated = 0
repeat 2 {
    repeated += 21
}
assert repeated == 42
report_survival
