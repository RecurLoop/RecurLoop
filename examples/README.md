# RecurLoop examples

This directory is a guided path through the language, not a scratch-file
archive. Start with `01-getting-started` and move down the numbered groups.
Every standalone example has the same entry point, `main.rl`.

From the repository root:

```bash
make build
make list-examples
make example EXAMPLE=01-getting-started/hello-world
make examples
```

`make example` builds RecurLoop when necessary and runs one `main.rl`.
`make examples` validates every standalone example and all multi-process
workflows. The examples contain assertions, so a successful exit also checks
their documented result. Generated ELF files and engine images are written to
`/tmp`; the source tree stays clean.

## Learning path

### 01 — Getting started

| Example | What it demonstrates |
|---|---|
| `hello-world` | Constants, strings, arithmetic, `print`, and `assert` |
| `values-and-control-flow` | Mutable values, `while`, and conditional branches |
| `functions-and-recursion` | Typed compiled functions, loops, and recursion |
| `namespaces` | Dictionaries used as namespaces |
| `records-and-methods` | Recursive record layouts, allocation, and receiver methods |
| `lifetime-and-null` | LIFO `defer` and pointer-null propagation with `?` |

### 02 — Compiled functions and types

| Example | What it demonstrates |
|---|---|
| `function-values` | Structural function types, callbacks, and overload selection |
| `signature-aliases` | Reusable function-signature phrases |
| `lexical-lookup` | Function lookup through nested dictionaries |
| `floating-point` | Native real arithmetic and numeric casts |

### 03 — Phrases and custom syntax

| Example | What it demonstrates |
|---|---|
| `phrase-aliases` | Renaming keywords and operators through prototypes |
| `lexicon-composition` | Merging and flattening dictionaries |
| `friendly-context-api` | High-level phrase lookup and definition APIs |
| `context-api` | Overloads, bit-string keys, and low-level Context operations |
| `context-actions` | A compiled phrase action that installs new commands |
| `phrase-mutation` | Phrase metadata mutation and inline actions |
| `custom-operators` | Adding syntax shared by top-level and compiled code |
| `custom-parselets` | Aliasing primary and postfix expression syntax |
| `expression-aliases` | Replacing expression group delimiters |
| `indentation-syntax` | Python-style blocks assembled from ordinary phrases |
| `persistent-extensions` | Exporting and restoring source-defined syntax |
| `switch-extension` | A complete `switch` family implemented in RecurLoop |

### 04 — Native output

| Example | What it demonstrates | Result |
|---|---|---|
| `assembler` | Typed x86-64 assembler and ELF object output | `/tmp/recurloop-assembler-example.o` |
| `standalone-fibonacci` | A libc-linked executable emitted from `fn` | `/tmp/recurloop-fibonacci` |
| `backend-selection` | The built-in backend and LLVM enabled by `make release` | `/tmp/recurloop-llvm-example` |
| `engine-images` | Exporting and importing runtime/language state | `/tmp/recurloop-*-state.rli` |

For example:

```bash
make example EXAMPLE=04-native-output/standalone-fibonacci
/tmp/recurloop-fibonacci 8
```

### 05 — Complete applications

These sources emit standalone programs. First run the example with `make
example`, then invoke the generated executable.

| Example | Generated program | Try it with |
|---|---|---|
| `cidr-calculator` | `/tmp/recurloop-cidr` | `/tmp/recurloop-cidr 192.168.10.42 24` |
| `number-inspector` | `/tmp/recurloop-numinfo` | `/tmp/recurloop-numinfo 360` |
| `number-lab` | `/tmp/recurloop-number-lab` | `/tmp/recurloop-number-lab 100` |
| `task-queue` | `/tmp/recurloop-showcase` | `/tmp/recurloop-showcase add 1 10 deploy list top stats` |
| `containers` | `/tmp/recurloop-containers-production` | `/tmp/recurloop-containers-production` |

### 06 — Application benchmarks

These larger programs are intentionally kept out of the learning path. They
exercise application-shaped workloads and emit deterministic benchmark
executables: `exchange-simulator`, `json-processor`, and `ray-tracer`. Their
`main.rl` headers document arguments, expected checksums, and output files.

### 07 — Multi-process workflows

These examples contain several source files because the process boundary is
the feature being demonstrated:

- `reusable-language-image` builds a language image and consumes it in a fresh
  RecurLoop process.
- `reusable-syntax-image` persists compiled syntax rewrites and imports them in
  a fresh process.
- `shell-language` builds a reusable shell DSL, then imports it into four
  independent programs. See its local `README.md` for an interactive tour.
- `source-debugger` contains source and executable debugger controllers plus
  their target program. The controller comments list useful prompt commands.

`make examples` runs the non-interactive validation for all four workflows.
The executable debugger controller itself is covered by `make feature` and is
automatically skipped on systems whose security policy blocks `ptrace`.

## Conventions for new examples

- Put each new standalone example in its own descriptive folder with a
  `main.rl` entry point.
- Keep the source self-checking with `assert` where practical.
- Explain only the concept that is new at that point in the learning path.
- Write generated artifacts to `/tmp`, never into the repository.
- Add multi-file examples only when the split itself teaches something.
