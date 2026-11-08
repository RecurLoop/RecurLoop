// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Shell" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    order = phrase { payload = "10" }
    body = phrase {
        payload = "Run external programs, connect pipelines and capture their output from RecurLoop. Shell passes argument vectors to programs; it does not delegate each command to another shell.

## Choose the right operation

| Operation | Where to use it | Result |
| --- | --- | --- |
| `run` | top level or a typed function | exit status |
| `capture` | top level or a typed function | standard output |
| `spawn` | inside a typed function | owned `Shell:Invocation*` |
| `Shell:Pipeline` | computed argument lists | owned pipeline object |

```recurloop
import shell
run printf \"hello\\\\n\" | tr a-z A-Z
assert status == 0
```

The output is `HELLO`. At top level `status` is a runtime binding. Inside a typed function, assign the return value of `run` instead of reading that binding.

To check the output automatically, capture it and compare it with the expected
text, including the newline:

```recurloop
import shell
var output = capture printf \"hello\\\\n\" | tr a-z A-Z
assert status == 0
assert output == \"HELLO\\n\"
```


Do not free borrowed `Invocation:stdout` text. Do free the string returned by `capture` inside a typed function. The two APIs deliberately have different ownership.

## Learning path

1. [Commands](commands.rl) — Quote arguments and select command syntax.
2. [Pipelines](pipelines.rl) — Connect streams and handle stage failures.
3. [Capture and jobs](capture.rl) — Collect output and inspect running invocations.
4. [Command objects](pipeline-objects.rl) — Construct commands from runtime data.
5. [Process settings](process-scope.rl) — Scope process settings and coordinate parallel jobs."
    }
]
