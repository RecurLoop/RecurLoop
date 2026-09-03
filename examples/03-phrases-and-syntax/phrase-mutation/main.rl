// Mutable phrase metadata and serializable inline actions.
//
// Run:
//   make example EXAMPLE=03-phrases-and-syntax/phrase-mutation
//
// Expected output:
//   inline literal
//   copied action
//   defined action
//   replaced action

extern puts(text:u8*) -> i32 abi sysv-amd64

let copied-action = phrase {
    type = <phrase-types:callable>
    action = fn (context:Context*, phrase:Phrase*) -> void {
        puts("copied action")
    }
}

// Only declared fields receive storage. `none` reserves a slot containing an
// empty reference.
let mutable-phrase = phrase {
    type = <phrase-types:callable>
    prototype = none
    successor = none
    action = fn (context:Context*, phrase:Phrase*) -> void {
        puts("inline literal")
    }
    serializable = true
}

// Field-assignment syntax works on named phrases. Changing the prototype does
// not copy the type, successor, or action.
set mutable-phrase.prototype = <copied-action>
set mutable-phrase.successor = <copied-action>
mutable-phrase

set mutable-phrase.action = <copied-action>
mutable-phrase

fn exercise_mutation_api(state:Context*, called:Phrase*) -> void {
    var types = context:phrase:find(state, "phrase-types")
    var callable = context:phrase:find:exact(state, types, "callable")
    var copied = context:phrase:find(state, "copied-action")

    // 122 = serializable + has-type + has-prototype + has-successor + has-action.
    var generated = context:phrase:define(
        state, 0, "generated-action", callable, 0, 0,
        fn (context:Context*, phrase:Phrase*) -> void {
            puts("defined action")
        }, 122)

    var ok = generated != 0
    if context:phrase:set:prototype(state, generated, copied) != generated { ok = 0 }
    if context:phrase:set:successor(state, generated, copied) != generated { ok = 0 }
    if context:phrase:set:type(state, generated, callable) != generated { ok = 0 }
    context:phrase:invoke(state, generated)

    if context:phrase:set:action(
        state, generated,
        fn (context:Context*, phrase:Phrase*) -> void {
            puts("replaced action")
        }) != generated { ok = 0 }
    context:phrase:invoke(state, generated)

    if context:phrase:set:transient(state, generated) != generated { ok = 0 }
    if context:phrase:set:serializable(state, generated) != generated { ok = 0 }

    // A phrase without a prototype slot is not moved or expanded by mutation.
    // The setter returns zero.
    var no_prototype_slot = context:phrase:define:data(state, "no-prototype-slot")
    if context:phrase:set:prototype(state, no_prototype_slot, copied) != 0 { ok = 0 }

    if ok == 0 { state.exec.status = 1 }
}

exercise_mutation_api
