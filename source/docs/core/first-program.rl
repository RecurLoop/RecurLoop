// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:first_program = [
    id = phrase { payload = "first-program" }
    title = phrase { payload = "First program" }
    section = phrase { payload = "Getting started" }
    order = phrase { payload = "40" }
    body = phrase {
        payload = "Write a small file, run it and check its result before introducing custom syntax or application libraries.

## Create a source file

Save the following as `hello.rl`:

```recurloop
const greeting = \"Hello, RecurLoop\"
var answer = 6 * 7
print greeting
print answer
assert answer == 42
```

## Run and verify

```console
recurloop --file hello.rl
```

The program prints a greeting and `42`. A failed assertion reports a problem and causes the run to fail. The embedded standard language is available without a separate bootstrap step.

## Introduce a function

```recurloop
let double = fn (value:i64) -> i64 { return value * 2 }
assert double(21) == 42
```

`i64` is a signed native integer type. Functions compile to native code and can be called from ordinary expressions.

## Find help while reading code

```console
recurloop --docs search \"function\"
recurloop --docs search \"ownership\" --json
```

Search finds public language and package documentation. The `--json` form is useful for tools. Continue through [Values](values.rl), [Control flow](control-flow.rl) and [Functions](functions.rl), or use the [Learning path](language.rl) to see the full sequence."
    }
]
