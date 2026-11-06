// Released binary and editor installation. Subtopics belong to this page.

let Docs:Pages:installation_vscode = [
    id = phrase { payload = "installation-vscode" }
    title = phrase { payload = "Install the VS Code extension" }
    section = phrase { payload = "Installation" }
    body = phrase {
        payload = "Install the RecurLoop extension for project-aware editing and consoles in VS Code. You can let the extension manage the RecurLoop binary, use an existing binary on PATH, or select an installation in a custom location. For a separate terminal installation, follow [installing the RecurLoop binary](installation.rl).

## Install the extension

Use VS Code 1.96 or a newer version supported by the extension. Install [RecurLoop from the Marketplace](https://marketplace.visualstudio.com/items?itemName=RecurLoop.recurloop-vscode), or use:

```console
code --install-extension recurloop.recurloop-vscode
```

You can also download `recurloop-vscode-*.vsix` from an [official release](https://github.com/RecurLoop/RecurLoop/releases/latest), choose **Install from VSIX** in the Extensions view and select the downloaded file. Apply any restart requested by VS Code.

For WSL, SSH and containers, install the extension in the workspace's remote environment. The binary and its paths belong to that environment. Automatic runtime installation supports Linux x86-64 with glibc 2.35 or newer; use Remote - WSL for a Windows desktop.

## Initialize your application folder

1. Open your application as a trusted workspace folder.
2. Run **RecurLoop: Initialize Project** from the Command Palette.
3. Save `recurloop.project.rl`. An empty saved entry is sufficient; initialization preserves an existing entry.
4. If a runtime is missing, choose the offered installation, select your own executable, or postpone setup.

The saved project entry opts the folder into runtime execution. A loose `.rl` file alone does not trigger a download, server or project analysis. Each folder in a multi-folder workspace opts in separately. Source colors come from the project's runtime inspection; files must belong to its included source graph for project-aware inspection.

### Use another project-entry filename

Set the filename in your application's VS Code settings, then create and save that entry. Initialization follows this setting:

```json
{
  \"recurloop.projectFile\": \"application.project.rl\"
}
```

## Choose how the RecurLoop binary is managed

| Choice | Configuration | Updates and removal |
| --- | --- | --- |
| Extension-managed binary | Keep the default `recurloop` setting; accept installation when no external binary is found | Managed by the extension |
| Your binary on PATH | Install it separately and keep the default `recurloop` setting | Managed by you |
| Your binary at a custom path | Set `recurloop.executablePath` to its executable | Managed by you |

### Let the extension install the binary

If the default executable is missing, an initialized project offers a compatible runtime installation after confirmation. **RecurLoop: Install Runtime** retries setup later. The package includes the binary and matching standard libraries, needs no administrator access and stays under the extension's global storage in `runtime/<version>/`.

The extension verifies the download checksum and package manifest. It does not add the managed binary to your shell PATH. For a command available in ordinary terminals, use the [standalone binary installer](installation.rl).

### Use a binary already on PATH

Install the binary and its libraries using the [binary installation instructions](installation.rl), then keep this setting:

```json
{
  \"recurloop.executablePath\": \"recurloop\"
}
```

An external `recurloop` on the extension host's PATH takes precedence over a managed copy. If you change PATH or `RECURLOOP_LIBRARY_PATH`, fully exit and reopen VS Code so its extension host receives the updated environment.

### Use a custom executable path

Set the executable file in user or workspace settings. For an installation below `/opt/recurloop`:

```json
{
  \"recurloop.executablePath\": \"/opt/recurloop/bin/recurloop\"
}
```

For an installation inside your application folder, `${workspaceFolder}` is supported:

```json
{
  \"recurloop.executablePath\": \"${workspaceFolder}/.tools/recurloop/bin/recurloop\"
}
```

Relative paths containing a directory component resolve against the workspace folder. This setting does not expand `~`, `$HOME` or arbitrary `${env:...}` substitutions. In a remote window, use the executable's remote path. A missing or incompatible explicit selection produces an error instead of selecting another binary.

### Compatibility and ownership

The binary must match the extension's bundled runtime release or be a newer patch with the same major and minor numbers. For example, a requirement of `0.2.11` accepts `0.2.12`, but not `0.2.10` or `0.3.0`; the expected release depends on the installed extension.

Keep the complete package layout and its matching standard libraries. If `RECURLOOP_LIBRARY_PATH` is set, check that it selects this installation's images. An explicit external executable has priority, followed by the default command on PATH, then a managed installation. Managed-runtime commands do not update or delete your external installations.

### Remove the automatic installation and use your own

1. Run **RecurLoop: Uninstall Runtime** to remove all managed versions and their libraries while keeping the extension.
2. Install a compatible published binary using the [standalone installer](installation.rl).
3. Set `recurloop.executablePath` to that installation, or leave `recurloop` if it is on the extension host's PATH.
4. Run **RecurLoop: Restart Language Runtime** and reopen RecurLoop consoles.
5. Check **RecurLoop: Show Runtime Info** to confirm the selected executable.

Manual removal is remembered across window reloads. To opt into managed installation again, run **RecurLoop: Install Runtime** in an initialized project. An external executable still on PATH retains precedence when using the default setting.

Uninstalling the extension removes its managed runtimes on the next full VS Code restart. Disabling it or only reloading a window preserves those files. Separately installed binaries remain untouched. During runtime maintenance, active target work finishes and shared servers stop before files are switched or removed.

## Update the extension and binary

### Extension updates

For a Marketplace installation, enable automatic updates for RecurLoop in the Extensions view, or select its update action. Apply the requested extension-host restart. A VSIX installation has auto-update disabled by default; enable it deliberately or install a newer downloaded VSIX. See [VS Code's extension-update settings](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_extension-autoupdate).

The command-line equivalent for installing or updating the Marketplace extension is:

```console
code --install-extension recurloop.recurloop-vscode --force
```

### Managed-binary updates

When an updated extension requires a different bundled runtime and an initialized project selects a managed installation, it installs that release automatically before server startup. The initial installation consent covers these managed updates.

**RecurLoop: Update Runtime** checks or retries the managed update on demand, including without a project when managed files already exist. It targets the release bundled with the installed extension, not an unrelated latest release. If that version is already installed, it reports that the runtime is current. A compatible older managed version can remain usable after a failed download.

### Updates to your own binary

Repeat the [binary installation procedure](installation.rl) with the original prefix and your chosen version policy. The extension does not update that installation for you. After a replacement, restart the language runtime and open new consoles. `:refresh` updates a console's source environment; it does not move an old session to another executable.

## Verify setup and troubleshoot

Use **RecurLoop: Show Runtime Info** for the workspace server's executable and PID, and **RecurLoop: Open Project Console** to connect a console. `recurloop --version` checks the binary selected by the terminal; `code --list-extensions --show-versions` reports extension versions. These are separate selections.

| Symptom | Action |
| --- | --- |
| Source remains plain text | Open a trusted folder, save its configured project entry and include the source file in that project's graph. |
| The runtime is missing | Use Install Runtime in an initialized project, or select an available compatible executable. |
| Your explicit path fails | Correct `recurloop.executablePath`, executable permissions or version compatibility. |
| Libraries cannot be loaded | Preserve the installed layout and remove or correct a stale `RECURLOOP_LIBRARY_PATH`. |
| Update Runtime reports it is current | It follows the installed extension's bundled release; update the extension to change that release. |
| A console still uses the old binary | Restart the language runtime and open a new console. |

Open the RecurLoop output channel for setup messages. **RecurLoop: Show Processing Log** displays project activity. For terminal installation and prefix selection, return to [installing the RecurLoop binary](installation.rl)."
    }
]
