let Haskell:Grammar:Tokens:"⟪" = <Haskell:Grammar:Tokens:"(">
let Haskell:Grammar:Tokens:"⟫" = <Haskell:Grammar:Tokens:")">
let Haskell:Grammar:Tokens:"⟦" = <Haskell:Grammar:Tokens:"[">
let Haskell:Grammar:Tokens:"⟧" = <Haskell:Grammar:Tokens:"]">
let Haskell:Grammar:Tokens:"plus" = <Haskell:Grammar:Tokens:"+">
let Haskell:Grammar:Tokens:"times" = <Haskell:Grammar:Tokens:"*">
let Haskell:Grammar:Tokens:":=" = <Haskell:Grammar:Tokens:"=">
let Haskell:Grammar:Tokens:":::" = <Haskell:Grammar:Tokens:"::">
let Haskell:Grammar:Tokens:"otherwise" = <Haskell:Grammar:Tokens:"|">
let Haskell:Grammar:Tokens:ANY = <Haskell:Grammar:Tokens:"_">
let "define " = <"data ">
let Haskell:Grammar:Tokens:strongplus = phrase { dictionary = true prototype = <Haskell:Grammar:Tokens:"+"> }
let configure_precedence = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        LanguageKit:define_infix(state, Haskell:grammar(state), "strongplus", 1, 100, 0)
        LanguageKit:define_infix(state, Haskell:grammar(state), "subtract_right", 2, 10, 1)
        // Replacing metadata twice must update the existing payload safely.
        LanguageKit:define_infix(state, Haskell:grammar(state), "strongplus", 1, 100, 0)
        context:source:root(state)
    }
}
configure_precedence

define Maybe a := Nothing otherwise Just a
fromMaybe d Nothing := d
fromMaybe ANY ⟪Just x⟫ := x
answer ::: Int
data' := 6 times 7
answer := data'
main := print ⟦fromMaybe 0 ⟪Just answer⟫, 20 plus 22, 2 times 3 strongplus 4, 10 subtract_right 3 subtract_right 1⟧
