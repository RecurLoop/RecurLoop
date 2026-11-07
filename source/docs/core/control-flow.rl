// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:control_flow = [
    id = phrase { payload = "control-flow" }
    title = phrase { payload = "Control flow" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "110" }
    body = phrase {
        payload = "Branch and repeat computations using runtime values. Begin with a condition, then introduce a loop whose state changes on each iteration.

## Conditions and branches

`if` selects its body when the condition is true; `else` provides the alternative.

```recurloop
var total = 0
var odd_count = 0
var index = 0
while index < 5 {
    if index % 2 == 0 {
        total += index
    } else {
        odd_count += 1
    }
    index += 1
}
assert total == 6
assert odd_count == 2
```

## Loops and scopes

`while` checks its condition before each iteration. Update a value that affects the condition to make progress. Branch and loop bodies create lexical value scopes; assignment can update an existing binding in an outer scope.

## Return from a function

Inside a compiled function, `return` supplies the declared result and exits the call. Use a small function when a repeated calculation deserves a name; continue with [Functions](functions.rl)."
    }
]
