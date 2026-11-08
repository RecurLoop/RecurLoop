// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Project" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    order = phrase { payload = "10" }
    body = phrase {
        payload = "Project provides named, deferred targets. Declaring a target does not run its body. Selecting a target runs its dependencies first and executes a shared dependency once during that target resolution.

## First example

Save this as `recurloop.project.rl`:

```recurloop
import project
target prepare { print \"prepare\" }
target check depends [prepare] { assert 6 * 7 == 42 }
target application depends [prepare, check] { print \"ready\" }
```

Selecting `application` runs `prepare`, then `check`, then the application body.
From the directory containing that file, run:

```console
recurloop --project recurloop.project.rl --target application
```

The output is `prepare` followed by `ready`; the shared prerequisite runs once.
The body is ordinary RecurLoop source and sees the project vocabulary.

Targets describe the execution workflow of your application.

## Learning path

1. [Dependencies](dependencies.rl) — Define the graph and its execution rules.
2. [Project paths](root-paths.rl) — Resolve application paths consistently.
3. [Debugging](debug-targets.rl) — Prepare and select source or native debugging."
    }
]
