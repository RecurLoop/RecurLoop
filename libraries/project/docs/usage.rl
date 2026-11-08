// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Project" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    order = phrase { payload = "10" }
    body = phrase {
        payload = "Project provides named, deferred targets. Declaring a target does not run its body. Selecting a target runs its dependencies first and executes a shared dependency once during that target resolution.

For a complete walkthrough from an empty folder through CLI tasks, the project console and F5 debugging in VS Code, start with [First project](../../../source/docs/core/first-project.rl).

## First example

Save this as `recurloop.project.rl`:

```recurloop
import project
let Application = [
    answer = fn () -> i64 { return 42 }
]
target run { print Application:answer() }
target test { assert Application:answer() == 42 }
```

From the directory containing that file, run:

```console
recurloop --target run
recurloop --target test
```

`run` prints `42`; `test` verifies it without printing. Neither target executes
the other. The body is ordinary RecurLoop source and sees the project vocabulary.

Targets describe the execution workflow of your application.

## Conventional application targets

| Target | Responsibility |
| --- | --- |
| `run` | Start the application in the runtime without emitting an executable. |
| `build` | Create the application's distributable native executable or library artifact. |
| `build-debug` | Create a native executable with source debug information. |
| `debug` | Declare the debugger input; depend on `build-debug` for native debugging. |
| `test` | Run the application's tests and fail on an unsuccessful assertion. |
| `docs` | Export the application's manual objects and short API help as portable JSON. |
| `clean` | Remove the project's generated output directory. |

These names are conventions, not mandatory or reserved targets. Running,
building and exporting documentation should not silently execute tests. The
[First project](../../../source/docs/core/first-project.rl) chapter supplies all
seven targets, source and test files, documentation settings and F5 configuration.
Only `debug` depends on `build-debug` in that starter.

Use `recurloop --target docs` to generate its own documentation, then read it
with `recurloop --docs search \"answer\" --from build/docs/my-application.json`.
The export includes generated navigation and search postings; it does not run
the application or create an HTML website. Add `package`, `dev` or `deploy`
only when the application has a concrete workflow for them.

## Learning path

1. [Dependencies](dependencies.rl) — Define the graph and its execution rules.
2. [Project paths](root-paths.rl) — Resolve application paths consistently.
3. [Debugging](debug-targets.rl) — Prepare and select source or native debugging."
    }
]
