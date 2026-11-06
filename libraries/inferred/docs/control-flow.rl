// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:control_flow = [
    id = phrase { payload = "control-flow" }
    title = phrase { payload = "Branches, local bindings and recursion" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "Use ordinary local names inside a function and return from each intended branch. The selected argument kinds determine the operations available in that specialization.

```recurloop
import inferred
poly fn maximum(a, b) {
    if a > b { return a }
    else { return b }
}
poly fn doubled(value) {
    let result = value + value
    return result
}
print maximum(9, 4)
print doubled(21)
```

## Recursive definitions

```recurloop
import inferred
poly fn factorial(n) {
    if n <= 1 { return 1 }
    return n * factorial(n - 1)
}
print factorial(5)
```

The result is `120`. The base case prevents unbounded recursion for the intended nonnegative input. This example returns `1` for negative input too; validate a domain explicitly when that behavior is not appropriate. Integer arithmetic has finite range, so this is a small-input example rather than an arbitrary-precision factorial.

For a failed specialization, first check the argument kinds, the operator used in the failing expression and all return paths. Adding unrelated annotations or relying on another active vocabulary can conceal the actual mismatch."
    }
]
