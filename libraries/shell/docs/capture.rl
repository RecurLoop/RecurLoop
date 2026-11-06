// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:capture = [
    id = phrase { payload = "capture" }
    title = phrase { payload = "Capture output and manage asynchronous jobs" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "Inside a typed function, `capture` returns a newly allocated null-terminated `u8*`. Check for null, consume the text and release it with `free`. At top level it produces a runtime string binding instead.

```recurloop
import shell
let read_output = fn () -> i64 {
    let output = capture printf \"ready\"
    if !output { return 1 }
    defer free(output)
    return strcmp(output, \"ready\") != 0
}
assert read_output() == 0
```

Capture text alone does not carry an exit status. When both are required, use `spawn` or `Shell:capture_pipeline` and inspect the associated result.

## Start, inspect, destroy

```recurloop
import shell
let start_job = fn () -> i64 {
    let job = spawn printf \"ready\"
    if !job { return 1 }
    defer job.destroy()
    let code = job.exit_code()
    if code != 0 { return code }
    let output = job.stdout()
    if !output { return 2 }
    return strcmp(output, \"ready\") != 0
}
assert start_job() == 0
```

`exit_code`, `await`, `wait` and `stdout` wait for completion when necessary. Repeated waits return the stored result. `stdout` borrows storage from the invocation and must not be freed. Copy it if it must survive `destroy`. Destroying a running invocation also waits; destruction is not cancellation."
    }
]
