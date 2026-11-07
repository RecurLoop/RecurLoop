// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:pipelines = [
    id = phrase { payload = "pipelines" }
    title = phrase { payload = "Pipelines" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "30" }
    body = phrase {
        payload = "## Connect streams and redirect output

A pipeline sends the standard output of one stage to the standard input of the next. `&&` runs a following pipeline only after success; `||` runs it after failure. `>` replaces a file and `>>` appends to it.

```recurloop
import shell
let check = fn () -> i64 {
    let code = run printf \"alpha\\nbeta\\n\" | grep beta
    if code != 0 { return code }
    return 0
}
assert check() == 0
```

## Exit status belongs to the whole pipeline

The invocation records the first failing stage, rather than merely the last program. A successful consumer does not hide a producer failure. Test the returned status before treating output as a successful result.

```recurloop
import shell
let verify_pipeline = fn () -> i64 {
    let code = run false | cat
    if code == 0 { return 1 }
    return 0
}
assert verify_pipeline() == 0
```

Use `Shell:run_pipeline` when constructing stages dynamically. The caller still owns that pipeline after execution. The special result `126` indicates that the pipeline could not be started; a nonzero program exit is also failure and should be handled by the caller."
    }
]
