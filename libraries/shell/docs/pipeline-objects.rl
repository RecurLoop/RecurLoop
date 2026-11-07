// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:pipeline_objects = [
    id = phrase { payload = "pipeline-objects" }
    title = phrase { payload = "Command objects" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "50" }
    body = phrase {
        payload = "## Build argument vectors at runtime

Use command objects when arguments come from a user, a collection or another function. Add the program name first. `Command:add` copies its input; `add_owned` transfers an allocated string only on success.

```recurloop
import shell
let echo_argument = fn (value:u8*) -> i64 {
    let pipeline = Shell:Pipeline:new()
    if !pipeline { return 1 }
    defer pipeline.destroy()
    let command = Shell:Command:new()
    if !command { return 2 }
    if !command.add(\"printf\") || !command.add(\"%s\") || !command.add(value) {
        command.destroy()
        return 3
    }
    if !pipeline.add(command) { command.destroy(); return 4 }
    let result = Shell:capture_pipeline(pipeline)
    if !result { return 5 }
    defer result.destroy()
    if result.exit_code != 0 { return result.exit_code }
    return strcmp(result.output, value) != 0
}
assert echo_argument(\"one argument; no shell expansion\") == 0
```

## Ownership transitions

1. A newly created command belongs to its caller.
2. Successful `pipeline.add(command)` transfers that command to the pipeline.
3. `capture_pipeline` returns an independent, owned `Shell:Capture`; the pipeline remains caller-owned.
4. Destroy the capture after reading its output, and destroy the pipeline after its last execution.

## Insert text transformations

`Pipeline:add_function` adds a text transformation. A callback receives borrowed input valid during that call. It returns the text to print; ensure the result remains valid for the callback contract. Do not retain the input pointer in a longer-lived object."
    }
]
