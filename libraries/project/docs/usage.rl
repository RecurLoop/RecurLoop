// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "target" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "A target is a named, deferred source block. Declaring it does not execute the body. Dependencies run before the selected target, and shared dependencies execute once.

```recurloop
target check {
    assert 6 * 7 == 42
}
target prepare {}
target run depends [prepare] {
    print \"ready\"
}
```

A failing dependency prevents subsequent dependent bodies from running. Target bodies use the same phrase definitions and language state as the project that declares them."
    }
]

