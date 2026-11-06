// Released-runtime and editor installation. Public documentation object.

let Docs:Pages:installation_troubleshooting = [
    id = phrase { payload = "installation-troubleshooting" }
    title = phrase { payload = "Troubleshoot installation and runtime selection" }
    section = phrase { payload = "Installation" }
    body = phrase {
        payload = "Use **RecurLoop: Show Runtime Info** for the editor selection and `command -v recurloop` plus `recurloop --version` for the terminal selection. They can intentionally refer to different installations.

| Symptom | Action |
| --- | --- |
| The editor works but the terminal cannot find `recurloop` | A managed runtime does not change PATH. Install the standalone package or select its executable explicitly in the tool that needs it. |
| A loose source file stays plain text | Open a trusted application folder, initialize and save its project entry, and include the file in that project's source graph. |
| The runtime is missing | In an initialized project use Install Runtime, or select a compatible executable available on the workspace host. |
| The explicit path is missing | Correct `recurloop.executablePath`; the extension intentionally does not fall back from an explicit selection. |
| The external runtime is incompatible | Select a release meeting the extension's bundled runtime requirement, or use its managed installation. |
| Standard libraries cannot be found or loaded | Keep the complete package layout and check that `RECURLOOP_LIBRARY_PATH` does not select another installation's images. |
| Update Runtime reports it is already current | It targets the installed extension's bundled runtime. Update the extension to change that target release. |
| The managed runtime does not return after removal | Manual removal is remembered. Use Install Runtime in an initialized project to opt in again. |
| VS Code uses the old environment after a PATH change | Fully exit and restart VS Code, or select the executable by its absolute path. |
| A console still uses the old runtime after switching | Restart the language runtime and open a new RecurLoop console. |
| No automatic download is available | Check Linux x86-64 and glibc support in the workspace environment. Use Remote - WSL for a Windows desktop. |

## Inspect the selected runtime

For a standalone installation:

```console
command -v recurloop
recurloop --version
```

In VS Code, open its RecurLoop output channel for setup/runtime messages. **RecurLoop: Show Processing Log** shows project activity. Fix the reported path, platform or version issue before retrying installation. An initialized application's empty saved project entry is enough to enable setup; source files alone do not opt a folder in.

Use [installation](installation.rl), [runtime policy](installation-managed-runtime.rl), [updates](installation-updates.rl) or [custom paths](installation-custom-runtime.rl) for the corresponding procedure. These instructions concern released packages and editor setup."
    }
]
