// Released-runtime and editor installation. Public documentation object.

let Docs:Pages:installation_runtime = [
    id = phrase { payload = "installation-runtime" }
    title = phrase { payload = "Install and update the standalone runtime" }
    section = phrase { payload = "Installation" }
    body = phrase {
        payload = "The standalone installer downloads a published binary package with its standard `.rli` libraries. It verifies the archive SHA-256 and package file manifest before copying the package to the destination.

## Personal installation

```console
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh | sh
export PATH=\"$HOME/.local/bin:$PATH\"
export RECURLOOP_LIBRARY_PATH=\"$HOME/.local/share/recurloop/libraries\"
recurloop --version
```

Keep the exports in your shell startup configuration. The defaults are `~/.local` for a normal user and `/usr/local` when run as root. The installer requires the standard command-line tools `curl`, `tar`, `sha256sum`, `awk`, `mktemp` and `getconf`.

## Choose another prefix

Set `RECURLOOP_PREFIX` on the `sh` process that executes the installer. For a personal installation in a dedicated directory:

```console
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh \\
  | env RECURLOOP_PREFIX=\"$HOME/.local/opt/recurloop\" sh
export PATH=\"$HOME/.local/opt/recurloop/bin:$PATH\"
export RECURLOOP_LIBRARY_PATH=\"$HOME/.local/opt/recurloop/share/recurloop/libraries\"
recurloop --version
```

For a system-wide installation:

```console
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh \\
  | sudo env RECURLOOP_PREFIX=/usr/local sh
```

Keep the installed `bin` and `share/recurloop` layout together. Copying only the executable can leave its libraries or installed documentation unavailable. If a library path is configured, use libraries from the same selected runtime installation.

## Update or select a published version

Run the same installer again with the same prefix to update that installation. Without `RECURLOOP_VERSION`, it resolves the latest published release and then downloads its versioned asset. Set `RECURLOOP_VERSION` on the installer process to a published `X.Y.Z` version when you want a particular release. An exported pin remains effective until changed or unset.

Updating a standalone runtime does not update the VS Code extension. After replacing a runtime used by VS Code, run **RecurLoop: Restart Language Runtime** and reopen RecurLoop consoles. See [update policy](installation-updates.rl) before selecting a version for the editor.

## Verify which executable the terminal sees

```console
command -v recurloop
recurloop --version
```

If another installation appears first on PATH, these commands refer to that executable. Use its absolute path or adjust PATH deliberately. VS Code can select a different installation through [recurloop.executablePath](installation-custom-runtime.rl)."
    }
]
