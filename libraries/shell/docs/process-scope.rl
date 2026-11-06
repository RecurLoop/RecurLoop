// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:process_scope = [
    id = phrase { payload = "process-scope" }
    title = phrase { payload = "Environment, working directories and parallel jobs" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`directory` temporarily changes the process working directory for a block. `environment` exposes a named runtime binding to child processes and restores the previous environment on exit.

```recurloop
import shell
var RECURLOOP_DOCS_EXAMPLE = \"visible to children\"
environment \"RECURLOOP_DOCS_EXAMPLE\" {
    run printenv RECURLOOP_DOCS_EXAMPLE
}
assert status == 0
```

For typed functions, `Shell:cwd_enter` and `Shell:env_enter` return guards. Check for null and pair them with `cwd_leave` or `env_leave`, preferably using `defer`. The guards restore the old value, including an originally absent environment variable.

## Run independent pipelines together

```recurloop
import shell
parallel {
    run printf \"first job\\n\"
    run printf \"second job\\n\"
}
assert status == 0
```

The block waits for its jobs. Output order is not guaranteed. Keep files and other shared resources independent or explicitly coordinate access. Environment and working-directory guards affect the process; avoid overlapping changes from unrelated threads.

For programmatic jobs use `Shell:Parallel:new`, `spawn`, `wait` and `destroy`. `wait` returns the first nonzero status and clears pending jobs. `destroy` waits for outstanding work before releasing the group."
    }
]
