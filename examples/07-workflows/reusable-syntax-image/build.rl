// Build a language image whose fn syntax is extended entirely by phrases.
// Run before use.rl; the resulting rewrite actions are compiled .rl code.

let truth_words = phrase { dictionary = true }

let unless = phrase {
    type = <phrase-types:elaborate>
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        context:syntax:emit(state, "if")
    }
}

let unless all = phrase {
    type = <phrase-types:elaborate>
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        context:syntax:emit(state, "if !")
    }
}

let integer = phrase {
    type = <phrase-types:elaborate>
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        context:syntax:emit(state, "i64")
    }
}

let number = phrase {
    type = <phrase-types:elaborate>
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        // The next expansion pass lowers this emitted spelling to i64.
        context:syntax:emit(state, "integer")
    }
}

let plus = phrase {
    type = <phrase-types:elaborate>
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        context:syntax:emit(state, " + ")
    }
}

// This rewrite consumes its own syntax and delegates its vocabulary to
// another phrase dictionary through matchLongest.
let truth = phrase {
    type = <phrase-types:elaborate>
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = context:syntax:data(state)
        var skipped = 0
        while skipped < context:syntax:bytes(state) && (source[skipped] == 32 || source[skipped] == 9) {
            skipped += 1
        }
        context:syntax:advance(state, skipped)

        let owner = context:phrase:find(state, "truth_words")
        let matched = context:syntax:match:longest(state, owner)
        if matched == context:phrase:find:exact(state, owner, "only") || matched == context:phrase:find:exact(state, owner, "on") {
            context:syntax:emit(state, "1")
            return
        }
        if matched == context:phrase:find:exact(state, owner, "off") {
            context:syntax:emit(state, "0")
            return
        }
        context:diagnostic:error:at(
            state,
            context:syntax:path(state),
            context:syntax:line(state),
            context:syntax:position(state),
            "truth expects on, only, or off"
        )
    }
}

let install_truth_words = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let words = context:phrase:find(state, "truth_words")
        context:phrase:define:data(state, words, "on")
        context:phrase:define:data(state, words, "only")
        context:phrase:define:data(state, words, "off")
    }
}
install_truth_words

let verify_build_syntax = fn (enabled:number) -> number {
    unless all enabled {
        return truth off
    }
    return 20 plus 22
}

assert verify_build_syntax(1) == 42
assert verify_build_syntax(0) == 0

engine export "/tmp/recurloop-phrase-syntax.rli"
