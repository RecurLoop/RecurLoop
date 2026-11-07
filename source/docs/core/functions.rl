// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:functions = [
    id = phrase { payload = "functions" }
    title = phrase { payload = "Functions" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "120" }
    body = phrase {
        payload = "Functions name reusable computations. Each `fn` compiles its body using the active vocabulary; argument and result annotations describe its native interface.

## Define and call a function

```recurloop
fn fibonacci(value:i64) -> i64 {
    if value < 2 {
        return value
    }
    return fibonacci(value - 1) + fibonacci(value - 2)
}

var index = 0
while index < 8 {
    print fibonacci(index)
    index += 1
}
```

Every `fn` is compiled. Functions support typed parameters and results,
recursion, overloads, function values, `if`, `while`, `return`, local bindings,
pointers, indexing, records, method calls, and calls to typed imports.

## Expression statements

Expressions can also appear directly at top level, including in the console:
`Probe:main()`, `(Probe:main())`, or `2 + 3`. Expression statements use the same
phrase-backed grammar as expression values and discard their result; use
`print str(Probe:advance(0, 10))` to display it. Ordinary executable phrases retain
priority. With LanguageKit, expression recognition runs without evaluation before
generic Shell commands. Once expression syntax claims a form, its errors stay in
RecurLoop.

## Cleanup and early returns

`defer` evaluates cleanup expressions in LIFO order when leaving a compiled
function. Postfix `?` propagates null from pointer-returning functions."
    }
]
