// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Shell" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
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
run printf \"hello\\n\" | tr a-z A-Z
assert status == 0
```

The output is `HELLO`. At top level `status` is a runtime binding. Inside a typed function, assign the return value of `run` instead of reading that binding.

## Read next

- [Commands and arguments](commands.rl): quoting, interpolation and language selection.
- [Pipelines and failures](pipelines.rl): stream composition, redirects and exit codes.
- [Capture and asynchronous work](capture.rl): owned strings and running jobs.
- [Programmatic pipelines](pipeline-objects.rl): arguments computed at runtime.
- [Process settings and parallel jobs](process-scope.rl): environment, directories and concurrency.

Do not free borrowed `Invocation:stdout` text. Do free the string returned by `capture` inside a typed function. The two APIs deliberately have different ownership."
    }
]
