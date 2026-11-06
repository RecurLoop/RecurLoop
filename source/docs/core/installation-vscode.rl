// Released-runtime and editor installation. Public documentation object.

let Docs:Pages:installation_vscode = [
    id = phrase { payload = "installation-vscode" }
    title = phrase { payload = "Install the VS Code extension and initialize a project" }
    section = phrase { payload = "Installation" }
    body = phrase {
        payload = "Use VS Code 1.96 or a newer version supported by the extension. Open your application as a trusted workspace folder. For WSL, SSH or a container, install RecurLoop into that workspace's extension host so it can run the Linux executable there.

## Install the extension

Install [RecurLoop in the Marketplace](https://marketplace.visualstudio.com/items?itemName=RecurLoop.recurloop-vscode), or use the VS Code command-line tool:

```console
code --install-extension recurloop.recurloop-vscode
```

Alternatively, download the `recurloop-vscode-*.vsix` asset from an [official release](https://github.com/RecurLoop/RecurLoop/releases/latest), open the Extensions view, choose **Install from VSIX** and select the downloaded file. Apply any restart requested by VS Code. VSIX installations have auto-update disabled by default; see [updating the extension](installation-updates.rl).

## Enable the application workspace

1. Open your application folder in VS Code.
2. Open the Command Palette and run **RecurLoop: Initialize Project**.
3. Save the resulting `recurloop.project.rl`. An empty saved entry is sufficient; initialization preserves an existing entry.
4. If a runtime is missing, select the offered managed installation, select your own executable, or postpone setup. **RecurLoop: Install Runtime** retries setup later in an initialized project.

The project entry opts the folder into runtime execution. Before it exists, opening a loose `.rl` file does not trigger a runtime download, server or analysis. Source colors come from the active project's runtime inspection rather than a static syntax grammar.

Each folder in a multi-folder workspace opts in separately. The `recurloop.projectFile` setting selects a different entry filename if needed:

```json
{
  \"recurloop.projectFile\": \"application.project.rl\"
}
```

Create and save that selected entry in your application folder. Initialization follows the setting. A file must belong to the project's included source graph for project-aware inspection to be available.

## Confirm the editor runtime

Run **RecurLoop: Show Runtime Info** to see the executable and PID serving the workspace. Use **RecurLoop: Open Project Console** to connect a console. With an initialized project, a new VS Code terminal can use the RecurLoop console profile.

The editor's managed executable is not automatically exposed in ordinary terminal PATH. Use the [standalone installer](installation-runtime.rl) if other tools need a terminal command, or [select a custom executable](installation-custom-runtime.rl) to share an existing installation."
    }
]
