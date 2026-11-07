// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:specialization = [
    id = phrase { payload = "specialization" }
    title = phrase { payload = "Specialization" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "20" }
    body = phrase {
        payload = "## Compile a variant for each argument shape

A definition records a function body. An actual call selects or compiles a variant for its argument kinds. Errors that depend on those kinds can therefore appear at the call site rather than at the definition.

```recurloop
import inferred
poly fn twice(value) {
    return value + value
}
poly specializations twice
print twice(21)
print twice(7)
print twice(\"ha\")
poly specializations twice
```

Before the calls, no argument-kind variant is needed. The two integer calls share a specialization; the text call needs another. `poly specializations name` prints the recorded variants for inspection.

## Keep call boundaries deliberate

Do not assume that an operation exists for every kind. A body using multiplication is appropriate for supported numeric operands; passing text does not make multiplication meaningful. Keep return paths compatible within a specialization. If an external API requires a particular native ABI, define that boundary explicitly in the typed vocabulary instead of assuming a lazy function has a fixed foreign signature.

`inferred_assert function name` checks phrase-backed visibility. Other supported categories are `variable`, `grammar` and `symbol`; these checks inspect definitions, not the truth of an arbitrary runtime condition."
    }
]
