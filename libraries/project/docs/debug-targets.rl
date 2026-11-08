// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:debug_targets = [
    id = phrase { payload = "debug-targets" }
    title = phrase { payload = "Debugging" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "40" }
    body = phrase {
        payload = "## Choose source or executable debugging

A debug target describes what an editor or CLI should debug. `debug source` points at RecurLoop source; `debug executable` points at a native executable. Dependencies can prepare that input first.

```recurloop
import project
target debug-source debug source \"application.rl\" {}
target build-debug {
    module auto
    emit executable debug \"./app-debug\" application_main = fn () -> i64 { return 0 }
}
target debug depends [build-debug] debug executable \"./app-debug\" {}
```

## Prepare the application before debugging

These declarations do not launch a debugger during definition. `build-debug` emits a small application executable before selecting `debug`. It does not run tests. `debug-source` is an optional alternative for stepping through source evaluation.

Use `recurloop --debug-target debug` to prepare its dependencies and launch the CLI debugger. Native source breakpoints and local inspection require `emit executable debug`.

## Save a VS Code F5 configuration

Create `.vscode/launch.json` in the folder containing the project entry:

```json
{
  \"version\": \"0.2.0\",
  \"configurations\": [
    {
      \"name\": \"Application: debug\",
      \"type\": \"recurloop\",
      \"request\": \"launch\",
      \"target\": \"debug\",
      \"stopOnEntry\": true
    }
  ]
}
```

Add this object to the `configurations` array if the file already exists. Select **Application: debug** in **Run and Debug**, then press **F5**. The target dependency prepares the executable; a separate `preLaunchTask` is unnecessary. `stopOnEntry` pauses at the native entry so even this short example is visible. Continue with F5 to exit.

For a complete application with an included source file, a source breakpoint and local variables, follow [First project](../../../source/docs/core/first-project.rl#configure-f5-debugging-in-vs-code).

## Select the appropriate inspection level

Use source debugging to step through phrase evaluation and inspect source-level state. Use executable debugging for emitted native applications. The selected debug input must exist when the debugging workflow begins. A target name describes the workflow, while the path after `source` or `executable` identifies the program being debugged."
    }
]
