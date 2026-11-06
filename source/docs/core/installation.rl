// Released binary and editor installation. Subtopics belong to this page.

let Docs:Pages:installation = [
    id = phrase { payload = "installation" }
    title = phrase { payload = "Install the RecurLoop binary" }
    section = phrase { payload = "Installation" }
    body = phrase {
        payload = "Install the RecurLoop binary and its standard libraries for use in terminals and other tools.

If you want to use VS Code, start with [installing the VS Code extension](installation-vscode.rl). The extension can install and manage a compatible binary for you, or use an installation you manage yourself.

## Requirements

Official binary installation currently targets Linux x86-64 with glibc. The installer checks for glibc 2.35 or newer and requires `curl`, `tar`, `sha256sum`, `awk`, `mktemp` and `getconf`. On Windows, use a Linux environment through WSL. Native Windows, macOS, ARM and musl/Alpine do not have an automatic binary download.

## Install for your user

```console
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh | sh
export PATH=\"$HOME/.local/bin:$PATH\"
export RECURLOOP_LIBRARY_PATH=\"$HOME/.local/share/recurloop/libraries\"
recurloop --version
```

For a normal user the installation prefix is `~/.local`: the executable is `bin/recurloop`, and matching standard `.rli` libraries are in `share/recurloop/libraries` below that prefix. Add the two exports to your shell configuration to keep them in new terminals.

The installer downloads a published package and verifies its SHA-256 and internal file manifest before copying it to the destination. Keep the complete installed layout together; copying only the executable can leave its libraries or installed documentation unavailable.

## Choose an installation location

### A custom personal directory

Set `RECURLOOP_PREFIX` on the process that executes the installer:

```console
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh \\
  | env RECURLOOP_PREFIX=\"$HOME/.local/opt/recurloop\" sh
export PATH=\"$HOME/.local/opt/recurloop/bin:$PATH\"
export RECURLOOP_LIBRARY_PATH=\"$HOME/.local/opt/recurloop/share/recurloop/libraries\"
recurloop --version
```

### A system-wide installation

```console
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh \\
  | sudo env RECURLOOP_PREFIX=/usr/local sh
```

The default prefix when running as root is `/usr/local`.

## Update or select a version

Run the same installer again with the same prefix to update that installation. Without `RECURLOOP_VERSION`, it resolves the latest published release and downloads its versioned asset.

To select a particular published version, set `RECURLOOP_VERSION` to its `X.Y.Z` version on the installer process. An exported pin remains effective until changed or unset. Keep the executable and its standard libraries from the same selected release.

If VS Code uses this installation, its extension must accept the selected runtime version. After replacing the binary, run **RecurLoop: Restart Language Runtime** and reopen RecurLoop consoles. The [VS Code installation page](installation-vscode.rl) explains compatibility, executable selection and editor updates.

## Verify the installation and resolve problems

```console
command -v recurloop
recurloop --version
```

| Symptom | Check |
| --- | --- |
| The terminal cannot find `recurloop` | Add the chosen prefix's `bin` directory to PATH, or invoke the executable by its absolute path. |
| The wrong version runs | `command -v` identifies the first matching executable on PATH. Adjust PATH or use the intended absolute path. |
| Standard libraries cannot be found | Preserve the complete package layout and point `RECURLOOP_LIBRARY_PATH` at the selected installation's `share/recurloop/libraries`. |
| VS Code works but the terminal command is missing | The editor may use a managed installation that does not modify terminal PATH. Follow this page for a standalone command. |

For editor-specific setup, custom executable paths and managed-runtime removal, see [installing the VS Code extension](installation-vscode.rl)."
    }
]
