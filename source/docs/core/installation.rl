// Released-runtime and editor installation. Public documentation object.

let Docs:Pages:installation = [
    id = phrase { payload = "installation" }
    title = phrase { payload = "Install RecurLoop" }
    section = phrase { payload = "Installation" }
    body = phrase {
        payload = "Choose a standalone runtime for the terminal, a runtime managed by the VS Code extension, or both. Both installation methods provide the executable and its matching standard libraries.

| Method | Use it when | Who updates it |
| --- | --- | --- |
| Standalone installer | You want `recurloop` in ordinary terminals or tools | You rerun the installer |
| Extension-managed runtime | You want VS Code to provision its compatible runtime | The extension follows its bundled release |
| Explicit external executable | You keep a particular installation in a custom location | You manage that installation |

## Install for the terminal

```console
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh | sh
export PATH=\"$HOME/.local/bin:$PATH\"
export RECURLOOP_LIBRARY_PATH=\"$HOME/.local/share/recurloop/libraries\"
recurloop --version
```

For a normal user the prefix is `~/.local`; the executable is `bin/recurloop` and standard images are in `share/recurloop/libraries` below that prefix. Add the two exports to your shell configuration to keep them in new terminals. The [standalone installation guide](installation-runtime.rl) covers custom prefixes, versions and updates.

## Install for VS Code

Install [RecurLoop from the Marketplace](https://marketplace.visualstudio.com/items?itemName=RecurLoop.recurloop-vscode), open a trusted application folder and run **RecurLoop: Initialize Project**. If no runtime is available, accept the offered managed installation. See [VS Code setup](installation-vscode.rl).

A managed runtime stays in the extension's storage. It does not add `recurloop` to your terminal PATH. A successful editor setup therefore does not imply that `recurloop --version` works in an unrelated terminal.

## Supported environment

Official binary installation currently targets Linux x86-64 with glibc. The automatic installer checks for glibc 2.35 or newer. On Windows, use a Linux environment through Remote - WSL. Native Windows, macOS, ARM and musl/Alpine do not have an automatic runtime download.

For WSL, SSH and containers, install and configure the extension in the workspace's remote environment. Executable paths, library paths and runtime installation all belong to that environment, not necessarily the computer displaying VS Code.

Read [the managed-runtime policy](installation-managed-runtime.rl), [updates and version selection](installation-updates.rl), [custom executable paths](installation-custom-runtime.rl) or [troubleshooting](installation-troubleshooting.rl) for the corresponding task."
    }
]
