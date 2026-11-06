# VS Code extension development

For editor setup and features, see the [extension guide](../tools/vscode-recurloop/README.md).
The runtime toolchain is described in [release development](releases.md#development).
The extension itself requires Node.js 22+, npm and VS Code.

## Build and install

From the repository root:

```sh
make build libraries
make install-vscode-extension
```

`make vscode-extension` produces `tools/vscode-recurloop/recurloop-vscode-<version>.vsix`
without installing it. Installation requires the `code` command on `PATH`;
reload VS Code after installing a new VSIX.

The repository's `.vscode/settings.json` selects
`${workspaceFolder}/build/Release/bin/recurloop` for both installed extensions
and development hosts. Other workspaces use `recurloop` on `PATH` unless they
set `recurloop.executablePath` explicitly. A missing explicit path is an error;
it does not silently select another binary.

## Run an Extension Development Host

```sh
npm ci --prefix tools/vscode-recurloop
npm run compile --prefix tools/vscode-recurloop
```

Open the repository in VS Code, press **F5** and select
**RecurLoop: Extension Development Host**. The new window loads the extension
from source; no VSIX installation is required. Open a workspace with a saved
`recurloop.project.rl` to enable the runtime, then open an `.rl` file to try
completion, hover and navigation.

After editing TypeScript, compile again and run **Developer: Reload Window**
in the development host. For continuous compilation:

```sh
npm run watch --prefix tools/vscode-recurloop
```

After replacing the runtime or library images, run
**RecurLoop: Restart Language Runtime** and reopen project consoles.

## Check changes

```sh
npm run check --prefix tools/vscode-recurloop
npm test --prefix tools/vscode-recurloop
```

Tests use the built runtime and standard libraries. They cover project setup,
analysis, targets, consoles and native debugging through a shim at the VS Code
API boundary. Check actual editor interaction in the development host as well.
