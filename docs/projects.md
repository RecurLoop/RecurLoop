# Executable projects

`recurloop.project.rl` is ordinary RecurLoop source shared by the CLI, servers
and editors. Its grammar lives in the lightweight `project.rli` library; it does
not depend on VS Code, GUI or IDE libraries. An empty entry is a valid project.
Imports/includes establish the language and processing graph. Target bodies
are deferred source, so loading or inspecting the project does not build/run them.

```rl
include "src/main.rl"

target build-release {
    emit executable ".cache/recurloop/app" app_main = fn () -> i64 {
        return Application:main()
    }
}

target build-debug {
    emit executable debug ".cache/recurloop/app-debug" app_debug_main = fn () -> i64 {
        return Application:main()
    }
}

target run depends [build-release] {
    ./.cache/recurloop/app
}

target debug depends [build-debug] debug executable ".cache/recurloop/app-debug" {
    var status = Application:main()
}

target check {
    assert Application:answer() == 42
}
```

Names are nonempty tokens without whitespace, commas, brackets, braces or quotes;
hyphens are allowed. Dependencies may be separated by spaces or commas. The
optional `debug` entry is either `debug executable "path"` or `debug source "path"`.
A target always has a source block, including `{}` for a dependency-only target.
Its body is used for ordinary execution; debugging runs its dependencies and
launches the debug entry instead. Relative includes in bodies keep their original
project source path. Native output and debug-entry paths use the project working
directory.

`target` is a normal source-defined syntax action. It publishes command source,
dependency names, debug paths and source locations in `Project:Targets`, using
portable phrase payloads. Programs can extend the syntax or construct that
registry with the ordinary Context API. There is no editor-side project parser.
The host consumes this shared registry for graph validation and execution.

## CLI

```bash
recurloop --targets
recurloop --target build-release
recurloop --debug-target debug
recurloop --inspect src/main.rl
recurloop --trace src/main.rl
recurloop --project recurloop.project.rl --serve
recurloop --project config/build.rl --project-root . --target build-release
```

Project actions discover the nearest saved `recurloop.project.rl` by walking
from the current directory to its parents. `--project` selects an explicit entry.
The working directory defaults to the entry's parent; `--project-root` overrides
it for entries stored inside a configuration directory. Inspection operands are
resolved relative to the caller before changing directories.
`RECURLOOP_PROJECT_ROOT` exposes the selected directory to source code.

Project mode imports `project`, `shell` and `inferred` by default. Explicit
`--library` options select the library baseline instead of the Shell/Inferred
defaults; the project vocabulary is still loaded. Normal `--library-path` and
`--import` startup options are supported. Low-level `--file` execution does not
implicitly import libraries: use `--library project` before a project source,
or use `--project` for the complete workflow.

Each target request validates its entire reachable dependency graph before
executing commands. Unknown dependencies and cycles fail before any command
runs. Shared dependencies run once per request in topological order, in one
mutable Session. A failure stops subsequent targets. Request rollback restores
language state; it cannot undo filesystem writes or external process effects.
Multiple `--target`/`--debug-target` actions run in command-line order.

`--inspect` returns the runtime's semantic color/documentation spans and
diagnostics; `--trace` also returns phrase matches and the visible catalog.
They use the published processing graph and transactional inspection, including
custom syntax and metadata. Sources outside that graph report analysis unavailable.
The line record format is documented in [project-runtime.md](project-runtime.md).

## Debugging

`--debug-target` builds dependencies, then opens the same native/source debugger
used by editors. At the initial native stop, install breakpoints and continue:

```text
break function "Application:main"
continue
threads
thread 12345
stack
frame 0
locals
value "point"
children "point"
children "values", 100, 100
eval point.x + values[0]
set point.x = 42
next
step
finish
continue
```

Use the actual ID returned by `threads`. `value` and `children` take variable
path strings; record members, array indices and pointer `[0]`/`->` access are
supported. Array expansion is paged (default 100, at most 1024 children per
request). Scalar members/elements can be assigned and used in expressions.
Recursive pointer types refer to portable type schemas by name.

Native debugging uses Linux x86-64 `ptrace` and requires an executable emitted
with `emit executable debug`. This works from both LLVM-enabled and built-in
hosts: debug emission rebuilds reachable source functions with the generator
that supplies exact statement maps and local layouts. Optimized release output
is not advertised as source-debuggable. Debug metadata v2 adds record/array/
pointee layouts; v1 scalar metadata remains readable.

New native threads are traced automatically. A stop suspends all traced threads
before inspecting memory or modifying shared breakpoints. Select a stopped
thread to view its stack, evaluate/assign its frame variables or step it.
Continue resumes all threads; stepping keeps the other threads stopped, so
stepping into a blocking synchronization operation can require continuing the
application. Spawned separate processes are not part of thread debugging.

For an interactive CLI, the application owns the terminal while it runs and the
controller regains it at stops; Ctrl+C pauses the application. A separate terminal
can be selected with `--debug-terminal /dev/pts/N` (obtain its path with `tty`).
VS Code provides its own application terminal and uses a separate pause channel.
The operating system must permit tracing; a denied ptrace call reports its
operation and errno rather than an ambiguous child exit code.

## Server and editors

The runtime transport exposes the same operations to any client:

| Request | Response |
| --- | --- |
| `:project-targets` | JSON object with a `targets` array |
| `:project-run<TAB>hex(name)` | Command output and request status |
| `:project-debug-prepare<TAB>hex(name)` | Dependency output followed by the selected target's JSON descriptor |
| `:inspect<TAB>hex(path)<TAB>hex(source)` | Semantic spans and diagnostics |
| `:trace<TAB>hex(path)<TAB>hex(source)` | Spans, diagnostics and language facts |

Output/status framing uses `:transport-stream-v2`; v1/plain transports are also
available. See [project-runtime.md](project-runtime.md).

The debug preparation request validates the target's debug entry and runs its
entire dependency closure once. The client then launches a dedicated debugger
controller so interactive debug commands do not consume a shared server's stdin.
Connected and stdio consoles also accept `:targets` and `:target build-debug`.
JSON is generated by the runtime protocol; project files never build JSON strings.
VS Code uses these requests for Tasks and Run and Debug; it has no dependency
walker of its own. Source navigation remains a LanguageKit policy layered on
runtime facts. The graphical IDE imports `ide.rli` explicitly alongside the
project vocabulary.
