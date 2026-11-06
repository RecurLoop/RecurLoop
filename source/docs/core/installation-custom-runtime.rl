// Released-runtime and editor installation. Public documentation object.

let Docs:Pages:installation_custom_runtime = [
    id = phrase { payload = "installation-custom-runtime" }
    title = phrase { payload = "Select a custom runtime and replace the managed installation" }
    section = phrase { payload = "Installation" }
    body = phrase {
        payload = "Set `recurloop.executablePath` in VS Code's user settings or in your application's workspace settings. Use the absolute executable path as seen by the extension host. For an installation whose prefix is `/opt/recurloop`:

```json
{
  \"recurloop.executablePath\": \"/opt/recurloop/bin/recurloop\"
}
```

Choose the executable file, not its containing directory. A missing, non-executable or incompatible selection is reported rather than silently replaced.

## Workspace-relative installations

The extension expands `${workspaceFolder}`. For a runtime installed inside your application folder:

```json
{
  \"recurloop.executablePath\": \"${workspaceFolder}/.tools/recurloop/bin/recurloop\"
}
```

Plain relative paths also resolve against the workspace folder. `~`, `$HOME` and arbitrary `${env:...}` substitutions are not expanded by this setting; use a real absolute path or the supported workspace variable. Paths in a remote window are remote paths, even when VS Code's visible window is on another operating system.

## Switch from the automatic runtime to your own

1. Run **RecurLoop: Uninstall Runtime** to remove managed copies. The extension remembers that choice and leaves external installations intact.
2. Install your chosen published runtime with the [standalone installer](installation-runtime.rl), including its matching standard libraries.
3. Set `recurloop.executablePath` to that installation's executable, or leave it as `recurloop` if the intended executable is on the extension host's PATH.
4. Run **RecurLoop: Restart Language Runtime**, close old RecurLoop consoles and open new ones.
5. Check **RecurLoop: Show Runtime Info** to verify the workspace is using your selected installation.

The external version must satisfy the installed extension's compatibility requirement. Updating or uninstalling a managed copy does not modify your external executable. To use managed selection again, return the setting to `recurloop` and run **RecurLoop: Install Runtime** in an initialized project; an external executable still present first on PATH will retain precedence.

## Keep library selection consistent

For a prefix such as `/opt/recurloop`, the matching library directory is `/opt/recurloop/share/recurloop/libraries`. Preserve the complete installed layout. If `RECURLOOP_LIBRARY_PATH` is set, ensure it points to libraries belonging to the selected runtime rather than another installation.

After changing shell PATH or library-path environment variables, fully exit and reopen VS Code so its extension host receives the new environment. A path configured explicitly in VS Code avoids relying on a launcher having read your shell startup file."
    }
]
