# Runtime reference

For installation and everyday use, start with the [extension guide](../README.md).

## Runtime requirements

Runtime-backed features require a saved `recurloop.project.rl` in the workspace
folder, or the entry selected by `recurloop.projectFile`. An empty file is enough.
Use **RecurLoop: Initialize Project** to create and open the configured entry;
the command preserves an existing file. You can also create it manually with
`touch recurloop.project.rl`. In a multi-folder workspace each folder opts in
independently. A loose `.rl` file does not enable the runtime.

Without the entry, the extension provides basic syntax highlighting and the
initialization command, but does not launch RecurLoop for version checks,
installation, analysis, tasks, consoles, Run or Debug. It watches for creation
of the entry, including custom filenames, and stops the shared server when the
entry is removed. Until a project is present, activation callbacks and command entry points
remain available: no output channel, setup service,
language analysis providers or runtime are created. Explicit runtime commands without a project explain the required setup and offer
**Initialize Project**; debug launches cancel after showing the same guidance.
Opening a loose source file does not show setup prompts.
A lightweight startup activation detects saved entries, including custom filenames,
without opening a source file. It allocates runtime services only when a project
is present. Detection selects the RecurLoop profile in workspace terminal settings
and remembers the previous values across window reloads. Removing the last project
restores the settings if they have not been changed manually. Global settings and
unrelated profiles are preserved. In a multi-folder workspace, the default is
selected while any folder has a project; the console uses the active editor's
folder, or the first project folder when no editor is active. A profile opened in
a non-project folder uses the normal shell (`SHELL`, or `/bin/sh`).

The extension must run in the same environment as the RecurLoop executable.
For WSL, open the repository through **Remote - WSL** so this extension runs in
the workspace extension host and can launch the Linux RecurLoop binary.

Default executable:

```text
recurloop
```

The extension first looks on the extension host's `PATH`. If the default is
missing, it offers **Install**, **Choose Executable**, or **Later** in an initialized project.
Installation requires your confirmation and downloads the complete official
GitHub Release, including the `.rli` libraries. The bundled installer verifies
the archive SHA-256 and internal file manifest. Its version is pinned to the
runtime version in the source tree's `CMakeLists.txt` when the extension is built.
This extension release requires RecurLoop 0.2.9 or a newer patch in the 0.2
series. Compatibility is checked whenever an executable is selected; incompatible
runtimes produce an error rather than being replaced.

Managed installations live below the extension's global storage directory in
`runtime/<version>/`. They require no administrator access and do not modify
your terminal `PATH`. Runtime selection is an explicit configured path, otherwise
`recurloop` on `PATH`, otherwise the managed installation. A missing explicit
path produces an error; the extension never substitutes another local build.
Use **RecurLoop: Install Runtime** to retry after choosing **Later**. On unsupported
platforms the setup offers a file picker instead of a download.

Uninstalling the extension removes its managed runtime versions and their
libraries, including installations discovered from earlier extension versions.
VS Code runs the uninstall hook on its next full restart after uninstalling.
Disabling the extension or reloading a window preserves the managed runtime.
Executables installed separately or selected through settings are not removed.
For a global installation available on `PATH` outside VS Code, follow the
[repository installation instructions](https://github.com/RecurLoop/RecurLoop#install-the-latest-release).
The missing-runtime dialog also links to this guide.

When an initialized project selects a managed runtime and an extension update
requires a different bundled runtime release, the extension installs that release
automatically before starting the server. The original managed-installation consent
covers these updates. A separately installed executable on `PATH` or an explicit
external path retains precedence and is never updated by the extension.
Downloads and library manifests are verified before switching; previous managed
versions remain available, and a failed download can keep a compatible older runtime.

Use **RecurLoop: Update Runtime** to update an existing managed installation to
the release bundled with the installed extension. If it is already installed,
the command reports that the runtime is up to date; it does not fetch an unrelated
latest release. Use **RecurLoop: Uninstall Runtime** to remove all managed runtime
versions and libraries without removing the extension. Both commands also work
without an initialized project. Before switching or deleting files, active project
targets finish and shared servers stop; new runtime requests wait for maintenance.
After updating, reopen existing RecurLoop consoles to connect to the new server.
Manual removal is remembered across window reloads, so opening a project does not
immediately prompt to reinstall. **RecurLoop: Install Runtime** restores the runtime.
Explicit settings pointing to a managed version follow updates and return to
`recurloop` after manual removal; external executable settings are preserved.

Server startup retries connections until it receives the RecurLoop protocol
greeting, then loads and publishes the project before enabling clients. Socket
existence and a fixed startup delay do not establish readiness. Stopping the
runtime or a server process failure cancels the pending startup.

Automatic installation currently supports Linux x86-64 with glibc >= 2.35.
In WSL, SSH or a container, installation occurs on the workspace extension host,
not on the machine displaying the editor. For an ordinary terminal command,
use the repository's standalone installer and add its bin directory to `PATH`.
Clang/LLD for native file output remain separate optional host tools.

Override `recurloop.executablePath` with your own executable if necessary. The
extension does not rewrite project settings when it installs a managed runtime;
choosing a file explicitly saves its path in the current workspace folder's
settings, or user settings when no workspace folder is available.
Runtime and analysis settings apply per folder, including in a multi-folder
workspace. The console client uses the executable selected for its server.
**RecurLoop: Show Runtime Info** reports that server's executable and PID; if
the current selection differs, it also reports the configured executable.
After changing the executable or restarting the runtime, close the old console
and open **RecurLoop: Open Project Console** to connect to the new server.

## Executable project entry and shared console

The default entry is `recurloop.project.rl` in each workspace folder; override
`recurloop.projectFile` to select another entry. Opening the RecurLoop source repository starts
one RecurLoop server per workspace. `recurloop.terminal.libraries` selects the
libraries imported into its immutable baseline, in order; the default is
`["shell", "inferred"]`. The extension enables the linked module cache, executes the entry
through `:load-file`, then publishes the complete environment. `include` and
engine imports in the entry define the processing graph and language dependencies.
Project analysis uses `:trace`/`:inspect` to reconstruct the state immediately
before each graph source, including its unsaved editor buffer. Files outside that
graph report analysis unavailable; without a project entry, standalone analysis
is disabled. TextMate remains the fallback while the runtime starts.

The entry is ordinary executable RecurLoop source, not a separate configuration
format. For a simple project it can just select the starting source:

```rl
include "src/main.rl"
```

An empty entry enables the server and console without task targets. Outside
VS Code, select the same entry using the existing CLI options, from the project
directory:

```bash
recurloop --project recurloop.project.rl
recurloop --project recurloop.project.rl --serve
recurloop --project config/my-project.rl --project-root . --serve
```

The first command loads the project once; `--serve` publishes the loaded environment and
opens a project console. CLI project mode imports Project, Shell and Inferred by default. Explicit
`--library` options select a different library baseline. To serve additional
clients, also pass `--unix /tmp/my-project.sock`; connect another console with
`recurloop --connect /tmp/my-project.sock`. Standalone CLI use does not require
the VS Code project marker.

The server refuses an existing Unix socket path and removes only the socket it
created. After an unclean shutdown, remove the stale socket before restarting;
an active server or another file at that path is never replaced automatically.

The entry declares targets with source-defined syntax:

```rl
target build-debug {
    emit executable debug ".cache/recurloop/app-debug" app_main = fn () -> i64 {
        return Application:main()
    }
}
target debug depends [build-debug] debug executable ".cache/recurloop/app-debug" {}
```

The project runtime lists these through `:project-targets` and executes them
through `:project-run`, validating the dependency graph and running shared
dependencies once in one session. VS Code consumes this common protocol;
project files are never parsed in TypeScript. Target bodies can contain
multiline source and arbitrary project-defined syntax. See the
[project guide](https://github.com/RecurLoop/RecurLoop/blob/main/docs/projects.md) for the CLI and complete contract.

The RecurLoop source repository overlay exposes `build-release`, `build-debug`, `run`,
`debug`, and `check` for the IDE example application. Build artifacts go below
`.cache/recurloop`. Tasks are discovered automatically and can also be
configured explicitly:

```json
{"type":"recurloop","target":"build-release","label":"Build application"}
```

Run and Debug discovers project targets dynamically. A saved launch entry is:

```json
{"type":"recurloop","request":"launch","name":"Application","target":"debug"}
```

Targets with `debugExecutable` build their dependencies, then launch the native
executable under the debugger. The supplied `debug` target depends on
`build-debug` and uses `.cache/recurloop/application-debug`. Its application
uses a real terminal for input and output; debugging controls use a separate
channel. Ctrl+C in that terminal pauses the target. Closing the terminal ends the
debug session. Other targets execute on the shared server and show their results
in a task terminal. `noDebug: true` executes the target on the server.
`debugProgram` remains available for the source-event debugger.

A native executable can also be launched directly:

```json
{"type":"recurloop","request":"launch","name":"Native application","executable":"${workspaceFolder}/.cache/recurloop/application-debug","stopOnEntry":true}
```

Breakpoint conditions are RecurLoop expressions. Hit conditions accept a count,
`>= N`, `> N`, `== N`, or `% N`. Logpoints interpolate expressions in `{...}`.
Watches and assignments run in the selected frame. Native source/function
breakpoints stop only at emitted RecurLoop statements, with local values and aggregate layouts
read from the actual target process and its embedded metadata.

**RecurLoop: Open Project Console** and the **RecurLoop** terminal profile use
`recurloop --connect` to attach persistent sessions to the same server. The
extension selects this console as the default terminal in project workspaces. Each console
owns its session state and inherits Shell, Inferred and the published project.
`:publish` shares changes with future sessions; `:refresh` attaches an existing
session to the latest generation. Saved/created/deleted `.rl` or `.rli` files
republish the workspace environment after active target requests finish. Failed
loads retain the previous publication; existing consoles keep their connection
and session state and can use `:refresh` to adopt the new generation. The explicit
Restart Language Runtime command ends console connections; reopen them afterwards.
In a connected console, Ctrl+C interrupts the foreground Shell pipeline and its
child process groups, while preserving the client, server and session state.
Shell stdout and stderr are returned to that console (buffered until the command
finishes); output redirection still writes to the selected file. Ctrl+C is a
transport control byte, scoped to the socket request; it does not interrupt
other sessions or arbitrary native RecurLoop computations. Closing a task
terminal is still not an asynchronous cancellation of language execution.

Expressions also work as ordinary statements, for example `Probe:main()`,
`(Probe:main())`, or `2 + 3`. LanguageKit probes the same expression grammar
without evaluation before selecting generic Shell commands. Statements discard
their return value; use `print str(Probe:advance(0, 10))` to display it. Literal
executable phrases retain priority, and explicit `shell ...` continues to select
command syntax.
Native C stdio imports (`printf`, `fprintf`, `puts`, `fputs`, `putchar`, `fputc`,
`fwrite`, `vprintf`, `vfprintf`) write to the calling session's stdout/stderr.
This routing is per thread and does not redirect process file descriptors.
Writes to other `FILE*` streams, Shell child processes, and emitted executables
keep their usual libc behavior. Raw descriptor writes and output originating
inside external shared libraries still use the server process's descriptors.

The extension requires a trusted workspace because loading the project executes
source. It targets the Linux/WSL runtime and Unix socket transport.

Configure automatic imports in `.vscode/settings.json`:

```json
"recurloop.terminal.libraries": ["shell", "inferred", "http"]
```

Use an empty array for the standard core alone. Each item becomes a separate
`--library` argument, so names are never interpreted by a system shell. Because
terminal sessions share the project runtime, these libraries are available to
project analysis and execution too. Changing the list restarts the relevant
workspace runtime; reopen existing terminals afterwards. Source debug launches
use the same configured imports.
