// Released-runtime and editor installation. Public documentation object.

let Docs:Pages:installation_managed_runtime = [
    id = phrase { payload = "installation-managed-runtime" }
    title = phrase { payload = "Managed runtime policy and removal" }
    section = phrase { payload = "Installation" }
    body = phrase {
        payload = "The extension can install a compatible runtime and its libraries after your initial confirmation. This installation belongs to the extension and is maintained separately from executables you install yourself.

## Selection and compatibility

For each workspace folder, selection follows this order:

1. An explicit executable configured through `recurloop.executablePath` or a launch override.
2. With the default `recurloop` setting, an executable available on the extension host's PATH.
3. The extension-managed installation when the default executable is missing.

A missing explicit path is an error; it does not silently select another runtime. An incompatible external executable also produces an error rather than being replaced by a managed copy.

The required runtime release is bundled with the extension. Compatibility accepts that version or a newer patch with the same major and minor numbers. For example, a requirement of `0.2.11` accepts `0.2.12`, but not `0.2.10` or `0.3.0`. Check the installed extension's expected release rather than treating this example as a permanent version pin.

## Storage and ownership

Managed files live under the extension's global storage directory, in `runtime/<version>/`. Each version has `bin/recurloop`, matching standard libraries and package metadata. The actual storage root depends on the VS Code environment; **RecurLoop: Show Runtime Info** identifies the selected executable.

The installation needs no administrator access and does not edit your shell PATH. In a remote workspace it resides on the WSL, SSH or container host. Downloads are verified against the archive checksum and internal file manifest before switching to the installed version.

## Automatic maintenance

When a managed installation is in use and an extension update requires a different bundled runtime release, the extension installs it before starting the server. The original installation consent also covers those managed updates. Existing compatible older versions may remain available if a download fails.

An external executable keeps precedence. Installing or updating a managed copy does not override an explicit external path or a usable external `recurloop` on PATH. Commands for managed runtimes never update or delete those external installations.

## Remove the automatic installation

Run **RecurLoop: Uninstall Runtime** to remove all managed runtime versions and their libraries for this extension storage, while keeping the extension installed. Active target work finishes and shared servers stop before maintenance. The removal choice is remembered across window reloads, so reopening the project does not immediately install it again.

To restore a managed installation, open an initialized project and run **RecurLoop: Install Runtime**. To use your own version instead, follow [switching to an external executable](installation-custom-runtime.rl).

Uninstalling the extension removes its managed runtimes through the uninstall hook on the next full VS Code restart. A window reload or merely disabling the extension preserves these files. Separately installed runtimes remain untouched."
    }
]
