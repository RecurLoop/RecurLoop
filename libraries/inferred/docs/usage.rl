// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Inferred" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    order = phrase { payload = "10" }
    body = phrase {
        payload = "Define functions without spelling every parameter and return type. The Inferred vocabulary specializes a function lazily for the argument kinds used by a call. Import `inferred` and use `poly fn` or an explicit `infer` selector.

## First example

```recurloop
import inferred
poly fn combine(a, b) {
    return a + b
}
print combine(20, 22)
print combine(\"Recur\", \"Loop\")
```

The calls produce `42` and `RecurLoop`. They need different argument-kind specializations. Repeated calls with the same kinds reuse the corresponding variant.


Inferred is a source-defined vocabulary with its own supported forms. It is not a guarantee that every expression accepted by another vocabulary can be used without annotations or conversion.

## Learning path

1. [Specialization](specialization.rl) — Understand when argument shapes create native variants.
2. [Control flow](control-flow.rl) — Use branches, local values and recursion.
3. [Interoperability](selectors.rl) — Choose a vocabulary and exchange shared values."
    }
]
