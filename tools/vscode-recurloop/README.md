# RecurLoop for Visual Studio Code

Edit, run and debug RecurLoop projects in VS Code. The extension provides
completion, diagnostics, navigation, project tasks and an interactive console
using the language's own runtime. Custom phrases and syntax are inspected by
RecurLoop rather than a separate editor grammar.

Install [RecurLoop from the VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=RecurLoop.recurloop-vscode),
or download a `.vsix` from
[GitHub Releases](https://github.com/RecurLoop/RecurLoop/releases/latest) and use
**Extensions → … → Install from VSIX…**.

## Get started

You need VS Code 1.96 or newer and a trusted workspace folder. Automatic runtime
installation supports **Linux x86-64 with glibc >= 2.35**, including WSL, SSH and
compatible development containers. On Windows, open your folder using
**Remote - WSL** and install/enable RecurLoop in WSL. The extension and runtime
must run in the same workspace environment.

1. Open your project folder with **File → Open Folder**.
2. Open the Command Palette and run **RecurLoop: Initialize Project**.
   This creates and opens `recurloop.project.rl`, preserving an existing file.
3. If the runtime is missing, choose **Install** to download a compatible
   RecurLoop release and its libraries. Use **RecurLoop: Install Runtime** to retry later.
4. Create `src/main.rl` with the following program:

   ```rl
   print "Hello from RecurLoop!"
   ```

5. In `recurloop.project.rl`, include that source:

   ```rl
   include "src/main.rl"
   ```

6. Save both files. With `src/main.rl` active, run **RecurLoop: Run Current File**.
   Open **RecurLoop: Open Project Console** and try `print str(2 + 3)`.

The saved project entry enables runtime-backed features. An empty entry is
valid, but including source makes it part of the project graph used for analysis
and navigation. Without an entry, `.rl` and `.rl.example` files use the theme's
plain text color. The extension has no static syntax grammar; source colors
appear only after runtime inspection in the project's language context.
Each folder in a multi-folder workspace has its own entry.

**The project entry executes when loaded.** Keep builds and application startup
inside targets for larger projects. The introductory `print` example above runs
when the project loads as well as when you run its source explicitly. The next
section shows how to defer execution.

Native Windows, macOS, ARM and Alpine do not have automatic runtime downloads.
On unsupported platforms, setup offers an executable picker; a selected runtime
still needs to satisfy the runtime's platform requirements. Native executable
output requires separate **Clang/LLD** tools. Native debugging requires
**Linux x86-64**, permission to use **`ptrace`**, and debug output produced by RecurLoop.

## Create a project with run and debug targets

Replace `src/main.rl` with a function definition. Loading this file defines the
function without starting the application:

```rl
let Application = phrase { dictionary = true permanent = true }

let Application:main = fn () -> i64 {
    var answer:i64 = 40
    answer += 2
    return answer
}
```

Replace `recurloop.project.rl` with:

```rl
include "src/main.rl"

target check {
    assert Application:main() == 42
    print "OK: application check passed."
}

target demo {
    print str(Application:main())
}

target prepare {
    mkdir -p .cache/recurloop
}

target build-debug depends [prepare, check] {
    emit executable debug ".cache/recurloop/app-debug" app_main = fn () -> i64 {
        return Application:main() - 42
    }
}

target debug depends [build-debug] debug executable ".cache/recurloop/app-debug" {}
```

Save the files, then use **Terminal → Run Task** to select the discovered `check`
or `demo` target. `demo` prints `42` without producing an executable. Select
`debug` in **Run and Debug** to build the Debug executable and launch it.
Set a breakpoint on `answer += 2` in `src/main.rl` first; inspect `answer` when
execution stops. Debug dependencies are built automatically.

To make a task your default build action, add `.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Application: build debug",
      "type": "recurloop",
      "target": "build-debug",
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

Now **Ctrl+Shift+B** saves files, waits for the project to reload, and runs that
target. Stopping a task or a target run sends cancellation to its runtime request.
To save a debug configuration, add
`.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Application: debug",
      "type": "recurloop",
      "request": "launch",
      "target": "debug",
      "stopOnEntry": true
    }
  ]
}
```

Select **Application: debug** and press **F5**. Because `stopOnEntry` is enabled,
Continue to your source breakpoint. A `preLaunchTask` is unnecessary: the runtime
executes the target dependency graph, running shared dependencies once per request.

Use `emit executable` without `debug` for Release output. A run target can depend
on that build and invoke its executable. The
[project guide](https://github.com/RecurLoop/RecurLoop/blob/main/docs/projects.md)
explains the full target syntax and CLI workflow.

## Explore the extension

| Feature | How to use it |
| --- | --- |
| Semantic highlighting and diagnostics | Open an included `.rl` file; colors and Problems come from runtime inspection. |
| Completion and signature help | Complete phrases from the current dictionary, follow syntax choices and inspect documented arguments. |
| RecurLoop: Help | Search phrase summaries and tags, then insert an author-provided snippet. |
| Hover documentation | Hover core phrases or custom phrases with `docs` metadata. |
| Navigation | Use Go to Definition, Find All References, Go to Type Definition or Go to Implementation; use **Ctrl+T** to search project symbols. |
| Rename and symbols | Rename a symbol through VS Code; browse definitions in the Outline view. |
| Run a source file | Use **RecurLoop: Run Current File** for direct source execution. |
| Project tasks | Use **Terminal → Run Task**; targets are discovered from the project runtime. |
| Native debugging | Set breakpoints, inspect Variables and Watches, evaluate expressions and step through compiled functions. |
| Project console | Use **RecurLoop: Open Project Console** to call functions and run targets interactively. |

Snippets and argument guidance live in the language, including user libraries.
See [authoring editor help](../../docs/editor-help.md) for the small contract.

Analysis follows the project's `include` and import graph and includes unsaved
editor buffers. A source outside that graph cannot receive project analysis;
include it from the entry or an included source. Save valid changes before
running a target, since execution uses the published project.

The native debugger supports source/function breakpoints, conditions, hit counts,
logpoints, stepping, pause, restart, call stacks, frame-local values and assignment.
Records, arrays and pointer pointees can be expanded. Breakpoint conditions and
Watch expressions use RecurLoop expressions. For example, use `answer == 40` as a
condition, `3` as a hit count, or `answer={answer}` as a logpoint.

Application stdin/stdout/stderr use a separate terminal. **Debug Console** shows
debugger messages and evaluates expressions while stopped. Direct source-file
launches use the source-event debugger; use a target with `debug executable` to
step inside compiled functions. **Run Without Debugging** executes a target's
ordinary body, so give that body a run action if you want it to run a program.

## Use the project console

When the extension detects a saved project entry, it selects **RecurLoop** as the
workspace's default terminal. Use **Terminal → New Terminal** or the terminal's
**+** button. This also works with a custom `recurloop.projectFile` path.
You can explicitly use **RecurLoop: Open Project Console** or select the
**RecurLoop** terminal profile. For the project above, enter these commands separately:

```rl
print str(Application:main())
:targets
:target check
```

The console inherits project definitions and the default `shell` and `inferred`
libraries. Input colors follow the active session's phrase metadata; VS Code
shell integration provides command decorations and navigation.

The extension changes workspace terminal settings only. Removing the last
project entry restores the previous default; a later manual terminal selection
is preserved. Existing terminals keep their sessions.

Each console keeps its own session state. Saved source changes republish the
project; use `:refresh` to adopt the latest generation in an existing console.
For example, change `answer += 2` to `answer += 3` in `src/main.rl` and save.
After the project reloads, enter `:refresh`, then `print str(Application:main())`
in the same console: the result changes from **42** to **43**. The application
and terminal use the same source-defined function. Restore `2` before running
`check`, whose assertion expects 42.

A failed project load retains the previous valid publication. Use `:publish`
when you intentionally want console changes shared with future sessions.
After **RecurLoop: Restart Language Runtime**, reopen consoles to reconnect.

## Runtime selection and settings

The extension selects an explicitly configured executable first, then
`recurloop` on the workspace host's `PATH`, then its managed installation.
Managed installs require no administrator access and do not modify your shell
`PATH`. This extension version requires RecurLoop 0.2.10 or a newer patch in the
0.2 series. Downloads are pinned to the release bundled with the extension and
verified against the archive checksum and file manifest.

Common settings in VS Code's user or workspace settings:

| Setting | Default | Purpose |
| --- | --- | --- |
| `recurloop.executablePath` | `"recurloop"` | Executable on PATH or an explicit path; supports `${workspaceFolder}`. |
| `recurloop.projectFile` | `"recurloop.project.rl"` | Project entry relative to the workspace folder. |
| `recurloop.terminal.libraries` | `["shell", "inferred"]` | Libraries shared by project analysis, execution and console sessions. |
| `recurloop.analysis.enabled` | `true` | Enables runtime-backed language analysis. |
| `recurloop.analysis.debounceMs` | `180` | Delay before analyzing an edited document. |
| `recurloop.analysis.timeoutMs` | `5000` | Maximum time for a semantic inspection request. |

**RecurLoop: Show Runtime Info** identifies the selected runtime.
**RecurLoop: Update Runtime** updates a managed installation to the release
bundled with the extension; managed installations also follow extension updates.
External installations retain precedence and are never updated by these commands.
**RecurLoop: Uninstall Runtime** removes managed runtimes and libraries, remembering
your choice until you install again. Uninstalling the extension removes its
managed runtime on VS Code's next full restart. Disabling the extension preserves it.

Changing imported libraries restarts the shared runtime; reopen consoles afterwards.
For a standalone CLI installation, follow the
[runtime installation guide](https://github.com/RecurLoop/RecurLoop#install-the-latest-release).

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Source stays plain text | Open a trusted workspace folder with a saved project entry; include the source in its graph and keep analysis enabled. Colors appear after runtime inspection. |
| Runtime is missing | Run **RecurLoop: Install Runtime**, or set `recurloop.executablePath` to a compatible runtime in the workspace environment. |
| Wrong or incompatible runtime is selected | Check **Show Runtime Info**, explicit settings and PATH. An explicit missing path is an error; installing a managed runtime does not override PATH. |
| Libraries cannot be loaded | Remove a stale `RECURLOOP_LIBRARY_PATH` or point it at the libraries belonging to the selected runtime. |
| Native build fails | Make Clang and LLD available in the same Linux/WSL/remote environment as the extension. |
| Debugging cannot start | Build with `emit executable debug` and check Linux x86-64 and `ptrace` permissions. |
| Console still sees old code | Save valid source, then enter `:refresh`; reopen after a runtime restart or update. |

Open **View → Output → RecurLoop** for runtime messages in an initialized project.
If problems persist after fixing configuration, use **RecurLoop: Restart Language Runtime**.

## Try the quick example

[RecurLoop VS Code Quickstart](https://github.com/RecurLoop/recurloop-vscode-quickstart)
provides ready-to-use launch configurations and targets. Run or debug a tiny
probe program, then call the same function from the RecurLoop terminal.
Edit the function, save and enter `:refresh` to see the changed result.

For runtime lifecycle and advanced project/console behavior, see the
[runtime reference](docs/runtime.md).
