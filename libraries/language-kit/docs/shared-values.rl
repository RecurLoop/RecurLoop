// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:shared_values = [
    id = phrase { payload = "shared-values" }
    title = phrase { payload = "Shared values" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "50" }
    body = phrase {
        payload = "## Exchange managed values between vocabularies

LanguageKit values give vocabularies a shared data boundary without sharing private syntax trees. The managed `Value` kinds are null (`0`), integer (`1`), text (`2`), symbol (`3`), list (`4`), tuple (`5`) and opaque (`6`).

```recurloop
import language-kit
let publish_answer = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if !LanguageKit:publish_integer(state, \"shared_answer\", 42) {
            context:diagnostic:error(state, \"publication failed\")
        }
    }
}
publish_answer
assert shared_answer == 42
```

`publish_integer` and `publish_text` mirror supported values into ordinary runtime bindings. Text publication copies its input. `publish` promotes a managed value to root ownership so another vocabulary can read it after the current local scope ends.

## Values, children and callbacks

## Release managed references

Construct values using `Value:integer`, `text_value`, `symbol_value` or `new`. Release your managed references with `Value:release`, not `free`. `set_item` establishes managed child ownership and rejects cycles. Published bindings keep their own root lifetime; do not release a borrowed lookup as if it were a newly created reference.

## Publish and invoke callbacks

`publish_callable` registers a callback with an arity and userdata. A negative arity accepts any count. `invoke` returns a managed result in the caller scope or null for an unavailable/invalid call. Define argument validation and value kinds at this boundary; a callback is responsible for the meaning of its result."
    }
]
