// Named Context API variants keep matching modes, metadata fields, and phrase
// layout flags out of ordinary RecurLoop code. The same primitives are usable
// in namespace form and, for common operations, as Context methods.

let friendly_context_prototype = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {}
}

let friendly_context_api = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let words = state.phrase_define_dictionary("friendly-api-words")
        let alpha = state.phrase_define_data(words, "alpha")
        let alphabet = context:phrase:define:data(state, words, "alphabet")

        if context:phrase:find:exact(state, words, "alpha") != alpha {
            context:diagnostic:error(state, "named exact phrase lookup failed")
            return
        }
        if state.phrase_find_longest(words, "alphabet soup") != alphabet {
            context:diagnostic:error(state, "method-style longest phrase lookup failed")
            return
        }
        if context:phrase:find:first(state, words, "alphabet") == 0 {
            context:diagnostic:error(state, "named first phrase lookup failed")
            return
        }

        let inherited = context:phrase:define:from(
            state, words, "alias", context:phrase:find(state, "friendly_context_prototype")
        )
        if context:phrase:prototype(state, inherited) == 0 {
            context:diagnostic:error(state, "prototype-based phrase definition failed")
            return
        }

        let tail = context:phrase:define:data(state, words, "tail")
        let head = context:phrase:define:successor(state, words, "head", tail)
        if context:phrase:successor(state, head) != tail {
            context:diagnostic:error(state, "named phrase successor failed")
            return
        }

        let generated = context:phrase:define:action(
            state, words, "generated",
            fn (context:Context*, phrase:Phrase*) -> void {}
        )
        if context:phrase:invoke(state, generated) != generated {
            context:diagnostic:error(state, "named phrase action definition failed")
            return
        }

        let integer = context:type:find(state, "i64")
        if context:type:size(state, integer) != 8 || context:type:signed(state, integer) != 1 {
            context:diagnostic:error(state, "named type metadata access failed")
        }
    }
}

friendly_context_api
