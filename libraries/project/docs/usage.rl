// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Project" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Project provides named, deferred targets. Declaring a target does not run its body. Selecting a target runs its dependencies first and executes a shared dependency once during that target resolution.

```recurloop
import project
target prepare { print \"prepare\" }
target check depends [prepare] { assert 6 * 7 == 42 }
target application depends [prepare, check] { print \"ready\" }
```

Selecting `application` runs `prepare`, then `check`, then the application body. The body is ordinary RecurLoop source and sees the project vocabulary. With an installed runtime, select it using `recurloop --project recurloop.project.rl --target application`.

The guides cover [dependency graphs](dependencies.rl), [debug targets](debug-targets.rl) and [project-relative paths](root-paths.rl). Targets describe an application workflow; they are independent of the tooling used to build RecurLoop itself."
    }
]
