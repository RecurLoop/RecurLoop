// Released-runtime and editor installation. Public documentation object.

let Docs:Pages:installation_updates = [
    id = phrase { payload = "installation-updates" }
    title = phrase { payload = "Update the extension and runtime" }
    section = phrase { payload = "Installation" }
    body = phrase {
        payload = "The VS Code extension, its managed runtime and a standalone runtime have separate update actions. First identify the selected executable with **RecurLoop: Show Runtime Info**.

## Update the extension

For a Marketplace installation, enable automatic updates for RecurLoop in VS Code's Extensions view, or select its update action when an update is available. Restart the extension host when VS Code requests it. A VSIX installation starts with automatic updates disabled; enable them deliberately or install a newer downloaded VSIX. See [VS Code extension management](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_extension-autoupdate).

The command-line interface can install or update the Marketplace extension:

```console
code --install-extension recurloop.recurloop-vscode --force
```

This command targets the extension; it does not update a separately installed RecurLoop executable. Use it in the intended VS Code environment and profile. The [VS Code CLI reference](https://code.visualstudio.com/docs/configure/command-line#_working-with-extensions) describes command-line extension management.

## Update the managed runtime

When an initialized project selects a managed runtime, activating the updated extension provisions its newly required bundled release automatically. Run **RecurLoop: Update Runtime** to retry or check that installation on demand. The update command also works without an initialized project when managed files already exist.

The command follows the release bundled with the installed extension, not an unrelated latest runtime release. If the required managed version is already installed, it reports that the runtime is up to date. Update the extension first when you want it to follow a newer bundled release.

External executables retain precedence and are not changed. A compatible older managed installation can remain usable after a failed download; otherwise setup reports the failure. Reopen existing RecurLoop consoles after a runtime update so they connect to the new server.

## Update a standalone or custom runtime

Repeat the [standalone installation command](installation-runtime.rl) with the original `RECURLOOP_PREFIX`. Omit or unset a version pin to follow the latest release, or select a published compatible version explicitly. Keep the matching standard libraries with that executable.

Then run **RecurLoop: Restart Language Runtime** if VS Code uses the updated installation, reopen its consoles and check **Show Runtime Info**. `recurloop --version` checks the terminal's selected binary; it can differ from the editor selection. `code --list-extensions --show-versions` reports extension versions, not the runtime version.

Refreshing a console's source environment is different from replacing its executable. After switching runtime versions, open a new console rather than expecting `:refresh` to move an old session to another binary."
    }
]
