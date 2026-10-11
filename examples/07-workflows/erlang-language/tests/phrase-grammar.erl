let Erlang:Grammar:Tokens:"⟪" = <Erlang:Grammar:Tokens:"(">
let Erlang:Grammar:Tokens:"⟫" = <Erlang:Grammar:Tokens:")">
let Erlang:Grammar:Tokens:"⟦" = <Erlang:Grammar:Tokens:"[">
let Erlang:Grammar:Tokens:"⟧" = <Erlang:Grammar:Tokens:"]">
let Erlang:Grammar:Tokens:"⟨" = <Erlang:Grammar:Tokens:"{">
let Erlang:Grammar:Tokens:"⟩" = <Erlang:Grammar:Tokens:"}">
let Erlang:Grammar:Tokens:"=>" = <Erlang:Grammar:Tokens:"->">
let Erlang:Grammar:Tokens:".end" = <Erlang:Grammar:Tokens:".">
let Erlang:Grammar:Tokens:"await" = <Erlang:Grammar:Tokens:receive>
let Erlang:Grammar:Tokens:"done" = <Erlang:Grammar:Tokens:end>
let Erlang:Grammar:Tokens:"plus" = <Erlang:Grammar:Tokens:"+">
let Erlang:Grammar:Tokens:discard = <Erlang:Grammar:Tokens:"_">
let Erlang:Grammar:Tokens:strongplus = phrase { dictionary = true prototype = <Erlang:Grammar:Tokens:"+"> }
let configure_precedence = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        LanguageKit:define_infix(state, Erlang:grammar(state), "strongplus", 1, 100, 0)
        LanguageKit:define_infix(state, Erlang:grammar(state), "subtract_right", 2, 10, 1)
        // Replacing metadata twice must update the existing payload safely.
        LanguageKit:define_infix(state, Erlang:grammar(state), "strongplus", 1, 100, 0)
        context:source:root(state)
    }
}
configure_precedence

always_answer⟪discard, discard⟫ => 42 .end
receive@worker⟪⟫ =>
    await
        ⟨start, From⟩ => From ! ⟨answer, always_answer⟪20, 22⟫ plus 0⟩
    done .end
main⟪⟫ =>
    discard = 1, discard = 2,
    Worker = spawn⟪fun receive@worker/0⟫,
    Worker ! ⟨start, self⟪⟫⟩,
    await
        ⟨answer, Value⟩ => io:format⟪"answer=~p.}, precedence=~p, right=~p~n", ⟦Value, 2 * 3 strongplus 4, 10 subtract_right 3 subtract_right 1⟧⟫
    done .end
