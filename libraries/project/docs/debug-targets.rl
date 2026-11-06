// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:debug_targets = [
    id = phrase { payload = "debug-targets" }
    title = phrase { payload = "Declare source and executable debug targets" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "A debug target describes what an editor or CLI should debug. `debug source` points at RecurLoop source; `debug executable` points at a native executable. Dependencies can prepare that input first.

```recurloop
import project
target inspect_source debug source \"application.rl\" {}
target prepare_binary {
    module auto
    emit executable \"./application\" application_main = fn () -> i64 { return 0 }
}
target inspect_binary depends [prepare_binary] debug executable \"./application\" {}
```

These declarations do not launch a debugger during definition. The preparation target emits a small application executable before selecting `inspect_binary`.

Use source debugging to step through phrase evaluation and inspect source-level state. Use executable debugging for emitted native applications. The selected debug input must exist when the debugging workflow begins. A target name describes the workflow, while the path after `source` or `executable` identifies the program being debugged."
    }
]
