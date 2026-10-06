# RecurLoop for Visual Studio Code

VS Code support for RecurLoop. The extension intentionally uses the language's
own runtime/introspection facilities instead of duplicating the RecurLoop grammar
in TypeScript.

## Getting started

Runtime installation supports **Linux x86-64 with glibc >= 2.35**, including WSL.
On Windows, open the folder with **Remote - WSL** and install this extension in WSL.
Native Windows, macOS, ARM and Alpine do not have automatic runtime downloads.

1. Open a folder in a trusted VS Code workspace.
2. Run **RecurLoop: Initialize Project** from the Command Palette.
3. If no runtime is available, choose **Install** to download RecurLoop and its libraries.
4. Create a `.rl` file and use completion, **RecurLoop: Run Current File**, or **RecurLoop: Open Project Console**.

If an incompatible installation is found on `PATH`, set `recurloop.executablePath`
to a compatible executable. Installing a managed runtime does not override `PATH`;
you can select its `bin/recurloop` explicitly. A stale `RECURLOOP_LIBRARY_PATH` can
also select libraries from another installation; remove it or point it at the
libraries belonging to the selected runtime.

## Features

- Console input colors from the active session's phrase metadata, with wrapped
  command editing and full command text retained in terminal scrollback.
- VS Code shell integration for command decorations, command navigation and
  sticky scroll (when enabled in VS Code terminal settings).

- `.rl` and `.rl.example` language registration.
- TextMate fallback highlighting for comments, strings, numbers, declarations,
  common core phrases and operators.
- Runtime semantic colors using the exact `color` metadata returned by
  RecurLoop `:trace` in initialized projects.
- Diagnostics from runtime inspection.
- Hover documentation from phrase `docs` metadata.
- Completion from the live phrase/type/function catalog.
- Function signature help.
- Go to Definition, Find References, Go to Type Definition, Go to Implementation,
  Rename and document symbols, resolved by the shared LanguageKit analyzer on the
  project server (the same engine used by the IDE example).
- `RecurLoop: Run Current File` command.
- Native Debug executable integration: source/function breakpoints, conditional
  and hit-count breakpoints, logpoints, continue, pause, step into/over/out, restart, call
  stack, frame-local variables, Watches, evaluation and variable assignment.
- Application stdin/stdout/stderr in a separate VS Code terminal. Debug Console
  contains debugger messages and expression evaluation.

Native debugging requires Linux x86-64, permission to use `ptrace`, and an
executable built with `emit executable debug`. Locals include expandable records, paged arrays and pointer pointees. Newly
created threads are traced; stacks, Watches, assignments and stepping use the
selected thread/frame. Stops suspend every traced thread; Continue resumes all
threads while stepping runs the selected thread alone. Debug emission works
in LLVM-enabled hosts by rebuilding source functions with the generator that
provides the exact statement maps. Direct `program`
launches retain the source-event debugger with one frame; use `debugExecutable`
for debugging inside compiled functions. Navigation indexes sources in the
published project dependency graph and includes unsaved editor buffers. When terminal imports omit LanguageKit, the
analyzer image is loaded only in a private analysis session; project and terminal
imports stay as configured.

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
There is no generic startup activation. With a custom entry name, open a RecurLoop
source file or use Initialize Project to let the extension discover the entry.
The repository selects RecurLoop as its default Linux terminal profile. With a
project entry it opens the project console; without an entry it opens the normal
shell (`SHELL`, or `/bin/sh`) without starting any RecurLoop processes.

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
This extension release requires RecurLoop 0.2.4 or a newer patch in the 0.2
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

## Install from a release or source

Download the `.vsix` asset from [GitHub Releases](https://github.com/RecurLoop/RecurLoop/releases/latest)
and use VS Code's **Extensions → ... → Install from VSIX...**, or
`code --install-extension <downloaded-file.vsix> --force`. Reload the window afterwards.
See the [repository installation guide](../../README.md#vs-code-extension) for
runtime setup and downloading with GitHub CLI.

From the repository root, `make install-vscode-extension` installs locked npm
build dependencies, checks TypeScript, builds the VSIX and installs it through
`code --install-extension ... --force`. Node.js 22+, npm and `code` are required.
Use `make vscode-extension` to build the package without installing it.

## Development from this repository

From the repository root:

```bash
cd tools/vscode-recurloop
npm ci
npm run compile
cd ../..
```

Then open the RecurLoop repository in VS Code and choose:

```text
Run and Debug -> RecurLoop: Extension Development Host
```

or press `F5` and select that configuration. A second VS Code window opens with
the extension loaded directly from `tools/vscode-recurloop`.

This repository's `.vscode/settings.json` overrides `recurloop.executablePath`
with `${workspaceFolder}/build/Release/bin/recurloop`. Build it with `make build`.
The override applies both to an installed VSIX and to the Extension Development
Host when that window opens this repository. Other workspaces use the public
`recurloop` default; set a workspace path explicitly to test a repository build
against another project. No separate development VSIX is required.

In the Extension Development Host, open any `.rl` file. `Ctrl+Space` triggers
completion; hover shows RecurLoop docs; ordinary VS Code breakpoints work with
the `RecurLoop: Debug current file` debug configuration.

After editing TypeScript, run `npm run compile` again and execute
`Developer: Reload Window` in the Extension Development Host. For continuous
compilation use:

```bash
cd tools/vscode-recurloop
npm run watch
```

## Local VSIX installation

Package the extension:

```bash
cd tools/vscode-recurloop
npm ci
npm run package
```

Then install the generated VSIX:

```bash
code --install-extension recurloop-vscode-0.1.2.vsix
```

When using Remote - WSL, install/enable the extension in WSL because it needs to
spawn the RecurLoop workspace executable.

Console input colors require RecurLoop 0.2.4 and respect `NO_COLOR` in ordinary
terminals. The extension removes that variable for its interactive console client.
Shell integration is emitted only in VS Code (`TERM_PROGRAM=vscode`). It reports
prompt boundaries, exact command text and completion status; it does not add Bash
startup files or Bash-specific IntelliSense. After updating, rebuild RecurLoop,
reinstall this VSIX, reload the VS Code window and open a new RecurLoop console.

## Executable project entry and shared console

The default entry is `recurloop.project.rl` in each workspace folder; override
`recurloop.projectFile` to select another entry. Opening this repository starts
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
[project guide](../../docs/projects.md) for the CLI and complete contract.

The supplied repository overlay exposes `build-release`, `build-debug`, `run`,
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
repository's Linux default terminal profile selects this console. Each console
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

The extension requires a trusted workspace because loading the project executes
source. It targets the Linux/WSL runtime and Unix socket transport.

Run headless integration tests after building the host and libraries:

```bash
npm test --prefix tools/vscode-recurloop
```

These tests use the real runtime, a temporary project with custom syntax,
project dependency state, failing and cyclic targets, console attachment and
restart, plus native Debug/Release builds of the repository application. The
Debugger tests use real ptrace processes and a real PTY, check frame variables,
stepping, Watches, assignments, and terminal/Debug Console isolation. The
VS Code API is shimmed at the editor boundary; UI behavior still needs checking
in the Extension Development Host.

Configure automatic imports in `.vscode/settings.json`:

```json
"recurloop.terminal.libraries": ["shell", "inferred", "http"]
```

Use an empty array for the standard core alone. Each item becomes a separate
`--library` argument, so names are never interpreted by a system shell. Because
terminal sessions share the project runtime, these libraries are available to
project analysis and execution too. Changing the list restarts the relevant
workspace runtime; reopen existing terminals afterwards. Source debug launches
use the same configured imports. After host/Shell changes, rebuild both with
`make libraries` (or `make install PREFIX="$HOME/.local"` for an installed host).
The console regression test uses a real PTY to verify `echo`, stderr, pipelines,
Ctrl+C during `sleep 100`, session state and isolation from another client.
