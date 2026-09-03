// =============================================================================
// Phrases, overloads, and the complete Context API
//
// Run:
//   make example EXAMPLE=03-phrases-and-syntax/context-api
//
// Demonstrates overload dictionaries, declarative phrase literals, short and
// explicit Context API variants, bit-string keys, payload access, lookup
// modes, and invocation modes.
// =============================================================================


// This exact signature makes the function a phrase action. Phrase type selects
// elaboration or invocation behavior.
fn count_call(state:Context*, called:Phrase*) -> void {
    state.exec.status += 1
    return
}


// One function name owns signature variants selected by argument types.
fn classify(value:i64) -> i64 {
    return value + 100
}

fn classify(value:u8*) -> i64 {
    return 200
}

fn call_overloads_from_compiled_code() -> i64 {
    return classify(7) + classify("seven")
}


// A phrase literal declares metadata slots. `none` means an explicitly empty
// reference. The API below obtains the actual action type from count_call.
let declarative_phrase = phrase {
    prototype = <count_call>
    successor = none
    action = <count_call>
    dictionary = true
    payload = "declarative"
    serializable = false
}


fn exercise_phrase_api(state:Context*, called:Phrase*) -> void {
    // API constants:
    // find: exact=0, first=1, longest=2
    // call: invoke=0, elaborate=1
    // get:  parent=0, type=1, prototype=2, successor=3,
    //       payloadBytes=4, flags=5
    // flags define: dictionary=1, serializable=2, unserializable=4,
    //               hasType=8, hasPrototype=16, hasSuccessor=32,
    //               hasAction=64
    var ok = 1
    state.exec.status = 0

    // The short find variant searches the root dictionary.
    var action = context:phrase:find(state, "count_call")
    var declarative = context:phrase:find(state, "declarative_phrase")

    // Verify metadata created by the phrase literal.
    if action == 0 {
        ok = 0
    }
    if declarative == 0 {
        ok = 0
    }
    if context:phrase:prototype(state, declarative) != action {
        ok = 0
    }
    if context:phrase:successor(state, declarative) != 0 {
        ok = 0
    }
    if context:phrase:payload:bytes(state, declarative) != 11 {
        ok = 0
    }
    if context:phrase:type(state, declarative) != context:phrase:type(state, action) {
        ok = 0
    }
    // The type is inherited from the prototype; the action is explicit.
    // 117 = dictionary + unserializable + prototype + successor + action.
    // The inherited type does not occupy a local slot.
    if context:phrase:flags(state, declarative) != 117 {
        ok = 0
    }

    // A function name is a dictionary containing signature variants.
    var overloads = context:phrase:find(state, "classify")
    var integer_variant = context:phrase:find:exact(state, overloads, "(i64)", 0, 5)
    var pointer_variant = context:phrase:find:exact(state, overloads, "(u8*)", 0, 5)
    if overloads == 0 {
        ok = 0
    }
    if integer_variant == 0 {
        ok = 0
    }
    if pointer_variant == 0 {
        ok = 0
    }
    if integer_variant == pointer_variant {
        ok = 0
    }

    var action_type = context:phrase:type(state, action)
    var debug = context:phrase:find(state, "debug")
    var ping = context:phrase:find:exact(state, debug, "ping")

    // The explicit define variant creates a root dictionary.
    // 73 = dictionary + hasType + hasAction.
    var generated = context:phrase:define(state, 0, "generated", action_type, 0, 0, action, 73)

    // Slice a name from a larger buffer without copying. The phrase receives
    // every reference slot and its own subdictionary.
    // 123 = dictionary + serializable + hasType + hasPrototype
    //       + hasSuccessor + hasAction.
    var child = context:phrase:define(state, generated, "--generated-child--", 2, 15, action_type, action, ping, action, 123)

    if context:phrase:parent(state, child) != generated {
        ok = 0
    }
    if context:phrase:type(state, child) != action_type {
        ok = 0
    }
    if context:phrase:prototype(state, child) != action {
        ok = 0
    }
    if context:phrase:successor(state, child) != ping {
        ok = 0
    }
    if context:phrase:payload:bytes(state, child) != 0 {
        ok = 0
    }
    if context:phrase:flags(state, child) != 123 {
        ok = 0
    }

    // Payload also comes from a source slice. `data` applies to the most
    // recently defined phrase, so data and executable phrases remain separate.
    var data_phrase = context:phrase:define:data(state, generated, "data")
    context:phrase:data(state, data_phrase, "payload")
    if context:phrase:parent(state, data_phrase) != generated {
        ok = 0
    }
    if context:phrase:payload:bytes(state, data_phrase) != 7 {
        ok = 0
    }
    if context:phrase:flags(state, data_phrase) != 2 {
        ok = 0
    }

    // Explicit lookup can target any owner dictionary.
    var exact = context:phrase:find:exact(state, generated, "generated-child", 0, 15)
    var first = context:phrase:find:first(state, generated, "generated-child", 0, 15)
    var longest = context:phrase:find:longest(state, generated, "generated-child trailing", 0, 24)
    if exact != child {
        ok = 0
    }
    if first != child {
        ok = 0
    }
    if longest != child {
        ok = 0
    }

    // BitString stores a pointer and exact bit count. Literals are packed
    // MSB-first; underscores are separators. `101` and `1010` remain distinct.
    var bit_keys = context:phrase:define(state, 0, "bit-keys", action_type, 0, 0, action, 73)
    var three_bits = context:phrase:define(state, bit_keys, bits"101", action_type, action, 0, action, 88)
    var four_bits = context:phrase:define(state, bit_keys, bits"1010", action_type, action, 0, action, 88)
    if context:phrase:find:exact(state, bit_keys, bits"101") != three_bits {
        ok = 0
    }
    if context:phrase:find:exact(state, bit_keys, bits"1010") != four_bits {
        ok = 0
    }
    // The explicit BitString variant uses bit offsets and lengths.
    if context:phrase:find:exact(state, bit_keys, bits"0010_1011", 2, 4) != four_bits {
        ok = 0
    }
    if context:phrase:find:longest(state, bit_keys, bits"1010_11") != four_bits {
        ok = 0
    }

    // An empty key can serve as a dictionary's default phrase.
    // 88 = hasType + hasPrototype + hasAction.
    var fallback = context:phrase:define(state, generated, "", 0, 0, action_type, action, 0, action, 88)
    if context:phrase:find:exact(state, generated, "", 0, 0) != fallback {
        ok = 0
    }

    // The short define variant creates a root-level prototype alias.
    var alias = context:phrase:define(state, "count_alias", action)
    if context:phrase:find(state, "count_alias") != alias {
        ok = 0
    }

    // This action type supports both call modes; each delegates to count_call.
    if context:phrase:invoke(state, child) != child {
        ok = 0
    }
    if context:phrase:elaborate(state, child) != child {
        ok = 0
    }
    if context:phrase:invoke(state, alias) != alias {
        ok = 0
    }
    if context:phrase:invoke(state, four_bits) != four_bits {
        ok = 0
    }
    if state.exec.status != 4 {
        ok = 0
    }

    if ok == 1 {
        // Visible marker that every API check passed.
        context:phrase:invoke(state, ping)
        state.exec.status = 0
    } else {
        state.exec.status = 1
    }
    return
}


// Overload resolution works during source elaboration and in compiled code.
assert classify(7) == 107
assert classify("seven") == 200
assert call_overloads_from_compiled_code() == 307

print "[overload i64] " + str(classify(7))
print "[overload u8*] " + str(classify("seven"))

exercise_phrase_api

// Oczekiwany wynik:
//   [overload i64] 107
//   [overload u8*] 200
//   pong
