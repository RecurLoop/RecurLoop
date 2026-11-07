// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:commands = [
    id = phrase { payload = "commands" }
    title = phrase { payload = "Commands" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "20" }
    body = phrase {
        payload = "## Quote and interpolate arguments

Use `run program argument ...` for an explicit command. Arguments can contain spaces without becoming multiple arguments, and RecurLoop expressions can be interpolated with `{expression}`.

```recurloop
import shell
var label = \"release candidate\"
run printf \"%s\\n\" \"{label}\"
assert status == 0
```

This passes one value argument, `release candidate`, to `printf`. Quotes group an argument; they are not passed to the program. `{label}` evaluates a RecurLoop expression rather than a shell variable.

## Select Shell syntax explicitly

Use `shell` when a program name overlaps a phrase in another vocabulary. A selector block applies that selection to its contents.

```recurloop
import shell
shell {
    printf \"selected shell syntax\\n\"
}
```

Prefer `run` or an explicit selector in reusable code. Recognition of a bare program name depends on the active vocabulary.

## Arguments are data

There is no automatic shell expansion of `$NAME`, command substitution or a shell script hidden inside a string. Use `environment` for process variables and `Shell:Command:add` for data assembled at runtime. To intentionally execute a shell script, invoke a shell explicitly and treat that script as code."
    }
]
