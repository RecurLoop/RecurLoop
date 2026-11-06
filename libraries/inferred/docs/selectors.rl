// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:selectors = [
    id = phrase { payload = "selectors" }
    title = phrase { payload = "Select Inferred syntax and share values" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`infer` explicitly selects Inferred for one definition or an entire block. It makes vocabulary choice visible when several syntax libraries are active.

```recurloop
import inferred
infer {
    fn add(a, b) { return a + b }
    print add(2, 5)
}
infer fn multiply(a, b) { return a * b }
print multiply(6, 7)
```

## Interoperate through shared values

```recurloop
import inferred
recurloop var seed = 7
poly fn step(value) { return value * 3 }
poly fn next(value) { return step(value) + 1 }
print next(seed)
```

The explicit `recurloop` selector creates the shared binding with the core vocabulary. Inferred then reads it at the call boundary. Use explicit selectors when a token could belong to multiple active vocabularies; adding a library can otherwise change which form wins resolution.

LanguageKit provides shared symbol/value facilities for deeper integration. Preserve their managed ownership rules when implementing another vocabulary; a shared value is not an arbitrary pointer that the receiving vocabulary may free."
    }
]
