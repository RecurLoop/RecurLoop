// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:memory = [
    id = phrase { payload = "memory" }
    title = phrase { payload = "Memory" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "190" }
    body = phrase {
        payload = "Native pointers borrow or own storage according to the API that produced them. A pointer's type does not tell you who must release it. Check that contract before retaining, freeing, or passing it to another function.

## Allocate and release a record

```recurloop
link shared \"c\"
extern free(pointer:u8*) -> void abi sysv-amd64
record Counter { value:i64 }
let count_once = fn () -> i64 {
    let counter = alloc(Counter)
    if !counter { return -1 }
    defer free(cast(u8*, counter))
    counter.value = 41
    counter.value += 1
    return counter.value
}
assert count_once() == 42
```

The local variable owns this allocation. The `defer` releases it when the function exits, including through the final `return`. Treat allocation failure before dereferencing the pointer.

## Borrow or transfer ownership

Borrowing permits temporary access while the owner remains alive. Transferring ownership gives another object responsibility for cleanup; stop freeing that resource yourself after a successful transfer. Copy borrowed text if it must outlive its owner.

Each standard-library guide names the matching release operation. Use that operation rather than assuming every pointer can be passed to `free`.

## Scope-owned resources

Use [LanguageKit managed lifetimes](../../../libraries/language-kit/docs/lifetimes.rl) for values or adopted resources that participate in managed ownership. A native allocation and a managed value have different cleanup contracts."
    }
]
