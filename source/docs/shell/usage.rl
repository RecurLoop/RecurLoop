// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Shell" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Shell provides source-defined commands, pipelines, captured output and scoped process settings. Arguments are passed directly to programs.

## Capture output

```recurloop
let output = capture printf \"hello\\n\"
print output
free(output)
```

## Resource ownership

An invocation owns its captured output until `destroy`. A transferred capture string is owned by the caller. Pipeline and command objects have explicit destruction functions. Check the exit code before consuming a command result."
    }
]

