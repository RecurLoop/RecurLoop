# RecurLoop

RecurLoop is a native, extensible programming language. Programs can define and compose syntax, named phrases and language libraries.

RecurLoop is experimental. Its language, library APIs and image format are still evolving. Release binaries currently target Linux x86-64.

## Installation

Install the latest runtime and standard libraries:

```bash
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
recurloop --version
```

The default installation is under `~/.local`. To install system-wide, set `RECURLOOP_PREFIX=/usr/local` for the installer. Run the installer again to update.

## Your first program

Create `hello.rl`:

```recurloop
print "Hello, RecurLoop!"
let square = fn (value:i64) -> i64 { return value * value }
print square(7)
```

Run it:

```bash
recurloop hello.rl
```

Read the [language guide](language.md) for values, functions, records, dictionaries, custom syntax and native output.

## Libraries

Import a library before source that uses its vocabulary:

```bash
recurloop --library shell --library inferred -
```

In project source, library imports can use ordinary RecurLoop:

```recurloop
import shell
import inferred
```

The [standard-library guide](standard-libraries.md) describes reusable images and dependencies. Each library has its own API section in this documentation.

## Projects and editors

A `recurloop.project.rl` file describes executable project targets:

```recurloop
target check {
    assert 6 * 7 == 42
}
```

Run `recurloop --targets` to list targets and `recurloop --target check` to execute one. See [projects](projects.md), [VS Code](vscode.md), and [editor help](editor-help.md).

## Documentation in the terminal

```bash
recurloop --docs search "record"
recurloop --docs show "let"
recurloop --docs search "ownership" --json --limit 10
```

The CLI reads short code help and public manuals, including included source packages. It does not index implementation documentation. Read [documentation and package authoring](documentation.md) to create, edit and export your own manuals.
