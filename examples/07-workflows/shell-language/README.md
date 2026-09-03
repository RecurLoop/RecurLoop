# RecurLoop shell library

Build the reusable language image:

```bash
build/Debug/bin/recurloop --file examples/07-workflows/shell-language/library.rl
```

Import the image and start interactive input:

```text
$ build/Debug/bin/recurloop --import /tmp/recurloop-shell-library.rli -
$ echo "hello directly"
hello directly
$ echo alpha | tr a-z A-Z
ALPHA
$ cd /tmp
$ pwd
/tmp
$ print 6 * 7
42
```

An otherwise unknown top-level line enters the shell phrase dictionary;
ordinary RecurLoop phrases retain longest-prefix priority. Dispatch then moves
between phrase dictionaries for an unquoted word, single and double quotes,
escapes, interpolation, pipelines and redirection. Those phrase actions build
`Shell:Pipeline` directly; there is no command string tokenizer or mini shell
parser. Explicit `run` uses the same graph in scripts and, inside `fn`, emits
native builder calls before the ordinary function compiler sees the expanded
source.

The image defines the ordinary RecurLoop value `PS1` as `"$ "`. The core line
editor has no hard-coded prompt and renders `PS1` when a loaded language
defines it. Assigning a new string to `PS1` changes the next prompt. The `cd`
builtin runs in the host process (rather than a child), supports `cd`, `cd -`,
`cd ~`, `cd ~/...` and normal relative/absolute paths, and maintains `PWD` and
`OLDPWD`.

When standard input is a terminal, the same `Recurloop -` input supports
session-local history and normal line editing: Left/Right, Ctrl+Left/Right,
Up/Down, Home/End, Delete/Backspace, Ctrl+Delete, Alt+B/F/D/Backspace, reverse
history search with Ctrl+R, transpose/yank with Ctrl+T/Y, and the usual
Ctrl+A/E/B/F/P/N/U/K/W/L/D/C keys. There is no separate shell executable or
shell-specific interactive mode.

Run a top-level automation script without wrapping it in a function:

```bash
build/Debug/bin/recurloop \
  --import /tmp/recurloop-shell-library.rli \
  --file examples/07-workflows/shell-language/top_level.rl
```

Additional examples:

- `pipeline.rl` — pipelines, redirection and capture into an ordinary
  RecurLoop variable;
- `functions.rl` — the same constructs inside compiled native functions;
- `example.rl` — a larger imported-library application;
- `../shell.rl` — standalone implementation and integration showcase.

Top-level `var`, `const`, `set`, `print`, `assert` and shell interpolation share
the phrase-backed RecurLoop Values store. The shell library does not create a
second user-variable store.

Each top-level `run` updates the integer value `status`. Top-level
`capture command ...` updates both `captured` (stdout) and `status`; inside a
compiled function, `capture command ...` remains an expression returning
`Shell:Capture*`.
