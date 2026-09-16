// Comprehensive declarative-syntax showcase.
// Run with:
//   build/Release/bin/recurloop --file examples/03-phrases-and-syntax/declarative-syntax/showcase.rl

// -----------------------------------------------------------------------------
// 1. A new construct from a typed expression capture and a structural block.
// Layout between pattern items is ignored by default.
// -----------------------------------------------------------------------------
syntax unless <condition:expr> <body:block> => if (!(${condition})) ${body}

var unless_value = 0
unless false {
    unless_value = 10
}
assert unless_value == 10

let unless_in_fn = fn (value:i64) -> i64 {
    unless value == 0 {
        return value
    }
    return 99
}
assert unless_in_fn(7) == 7
assert unless_in_fn(0) == 99

// -----------------------------------------------------------------------------
// 2. Identifier, number, string and token captures.
// -----------------------------------------------------------------------------
syntax zero <name:id> => ${name} = 0
syntax plus-one <value:number> => print ${value} + 1
syntax say <value:string> => print ${value}
syntax show-token <value:token> => print ${value}

var counter = 42
zero counter
assert counter == 0
plus-one 41
say "string capture"
show-token "token capture"

// -----------------------------------------------------------------------------
// 3. Whole-line/rest capture. `rest` stops at the end of the logical line.
// -----------------------------------------------------------------------------
syntax echo <value:rest> => print ${value}
echo "rest capture"

// -----------------------------------------------------------------------------
// 4. Block interpolation. `${body}` keeps braces; `${body.body}` removes the
// outer braces and injects only the block contents.
// -----------------------------------------------------------------------------
syntax twice <body:block> => """
${body.body}
${body.body}
"""

var repeated = 0
twice {
    repeated += 1
}
assert repeated == 2

// -----------------------------------------------------------------------------
// 5. Optional pattern group. The optional literal is validation-only here, so
// the rewrite does not need conditional template logic.
// -----------------------------------------------------------------------------
syntax announce [please] <value:string> => print ${value}
announce "optional absent"
announce please "optional present"

// -----------------------------------------------------------------------------
// 6. Choice group. A choice can constrain accepted spellings without changing
// the produced rewrite.
// -----------------------------------------------------------------------------
syntax banner (now | please) <value:string> => print ${value}
banner now "choice: now"
banner please "choice: please"

// -----------------------------------------------------------------------------
// 7. Explicit layout controls. Normal pattern items skip layout automatically.
// `required` demands at least one whitespace byte; `none` forbids whitespace;
// `newline` requires a physical line break.
// -----------------------------------------------------------------------------
syntax spaced <space:required> <value:number> => print ${value}
syntax compact <space:none> ":" <value:number> => print ${value}
syntax next-line <line:newline> <value:number> => print ${value}

spaced 7
compact:8
next-line
9

// `<whitespaces:ignore>` is an explicit spelling of the normal layout behavior.
syntax explicit-layout <whitespaces:ignore> <value:number> => print ${value}
explicit-layout     10

// -----------------------------------------------------------------------------
// 8. `as <phrase>` reuses semantics rather than rewriting to source. This gives
// a new spelling for an existing construct while still validating the tail.
// -----------------------------------------------------------------------------
syntax when "(" <condition:expr> ")" <accepted:block> [else <rejected:block>] as <if>

var when_value = 0
when (true) {
    when_value = 11
} else {
    when_value = -1
}
assert when_value == 11

let when_in_fn = fn (value:i64) -> i64 {
    when (value > 0) {
        return value
    } else {
        return -value
    }
}
assert when_in_fn(12) == 12
assert when_in_fn(-12) == 12

// -----------------------------------------------------------------------------
// 9. `syntax extend` adds a higher-priority form and falls back to the previous
// phrase when the new pattern does not match.
// -----------------------------------------------------------------------------
syntax extend if "(" <condition:expr> ")" <accepted:block> [else <rejected:block>] as <if>

var plain_if = 0
if true {
    plain_if = 1
}
assert plain_if == 1

var parenthesized_if = 0
if (true) {
    parenthesized_if = 2
}
assert parenthesized_if == 2

// `unless` was defined before the extension. Its rewrite deliberately emits a
// parenthesized condition, so it remains valid after the public `if` grammar is
// extended.
var composed = 0
unless false {
    composed = 3
}
assert composed == 3

// -----------------------------------------------------------------------------
// 10. `syntax replace` shadows an existing spelling intentionally. Use it for
// a language-level grammar change where falling back would be undesirable.
// -----------------------------------------------------------------------------
syntax replace say "(" <value:string> ")" => print ${value}
say("replacement syntax")

// -----------------------------------------------------------------------------
// 11. Custom action escape hatch. The matcher has already parsed captures when
// this action executes. Captures are exposed through context:syntax:capture*.
// This sample emits a number while fn syntax expansion is active.
// -----------------------------------------------------------------------------
syntax literal <value:number> action fn (state:Context*, called:Phrase*) -> void {
    if !context:syntax:active(state) {
        context:diagnostic:error(state, "literal syntax is only valid while expanding fn source")
        return
    }
    if !context:syntax:capture:exists(state, "value") {
        context:diagnostic:error(state, "literal syntax lost its value capture")
        return
    }
    context:syntax:emit(state, context:syntax:capture(state, "value"))
}

let literal_answer = fn () -> i64 {
    return literal 42
}
assert literal_answer() == 42

print "declarative syntax showcase ok"
