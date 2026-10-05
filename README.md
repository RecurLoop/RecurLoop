# RecurLoop

**A native, extensible programming language where syntax, semantics, and namespaces are built from the same phrase system.**

RecurLoop lets programs define and compose language features instead of requiring every new construct to be hard-coded into the C++ host. The runtime includes native compilation, an LLVM backend, engine images, a phrase-aware debugger, and reusable language libraries such as Shell and Inferred.

> **Project status:** RecurLoop is an active research implementation. The language, extension APIs, and engine-image format are still evolving. Current release binaries target Linux x86-64.

## Install the latest release

The easiest installation uses the latest published GitHub Release and installs the complete runtime, including the standard `.rli` libraries:

```bash
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh | sh
```

Run the same command again later to update to the newest release. For a normal user it installs to:

```text
~/.local/bin/recurloop
~/.local/share/recurloop/libraries/{language-kit,shell,inferred,http,gui,ide,project,embed}.rli
```

If `~/.local/bin` is not already in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Set the library search path for an installation below `~/.local`:

```bash
export RECURLOOP_LIBRARY_PATH="$HOME/.local/share/recurloop/libraries"
```

Add both exports to your shell configuration (for example `~/.bashrc`) to keep
them across terminal sessions.

For a system-wide installation:

```bash
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh \
  | sudo env RECURLOOP_PREFIX=/usr/local sh
```

Check the installation:

```bash
recurloop --version
```

The installer resolves the immutable versioned asset for the latest GitHub Release, verifies its published SHA-256 checksum and the package-internal file manifest before installation.

## VS Code extension

Download `recurloop-vscode-*.vsix` from the assets of the
[latest GitHub Release](https://github.com/RecurLoop/RecurLoop/releases/latest).
In VS Code, open **Extensions**, choose **... → Install from VSIX...**, select
that downloaded file, then reload the window. You can also install it from the
command line (use the filename you downloaded):

```bash
code --install-extension ./recurloop-vscode-0.1.1.vsix --force
```

For a command-line download of the latest release with GitHub CLI:

```bash
extension_dir="$(mktemp -d)"
gh release download --repo RecurLoop/RecurLoop \
  --pattern 'recurloop-vscode-*.vsix' --dir "$extension_dir"
code --install-extension "$extension_dir"/recurloop-vscode-*.vsix --force
```

The extension starts its runtime only in workspace folders containing a saved
`recurloop.project.rl` (or the file selected by `recurloop.projectFile`). An empty
file is enough. Use **RecurLoop: Initialize Project** to create and open that file
without overwriting an existing entry, or create it yourself:

```bash
touch recurloop.project.rl
```

Without a project entry, files retain basic syntax highlighting; analysis,
runtime installation, consoles, tasks, Run and Debug do not launch RecurLoop.
The extension stays inactive silently: it creates no runtime resources or
language providers, and missing projects produce no error notifications.
Each folder in a multi-folder workspace opts in separately. Creating the entry
enables the runtime; deleting it stops the shared server.

The extension defaults to `recurloop` on `PATH`. If it is missing, opening an
initialized project offers to install the compatible runtime and all its
libraries after confirmation. This managed installation stays in the extension's
data directory, requires no administrator access, and does not change your shell
`PATH`. Use **RecurLoop: Install Runtime** to retry later. Automatic installation
supports Linux x86-64 with glibc >= 2.35, including WSL and remote workspaces.

You can also install the runtime using the instructions above and select it in
VS Code's user or workspace settings:

```json
{
  "recurloop.executablePath": "recurloop",
  "recurloop.terminal.libraries": ["shell", "inferred"]
}
```

For development, this repository's `.vscode/settings.json` explicitly selects
`${workspaceFolder}/build/Release/bin/recurloop`; run `make build` first. Other
projects use the `recurloop` default. A missing explicit path is reported without
silently falling back to a different build.

The extension provides semantic highlighting, project targets in Tasks and Run
and Debug, and a RecurLoop terminal. The project `debug` target launches the
emitted Debug executable with application IO in its own terminal, while Debug
Console handles debugger messages and expressions. It provides breakpoints,
stepping, a call stack, local variables and Watches. Go to Definition, Find
References, type/implementation navigation and Rename use the project server. The runtime currently runs on Linux; for
WSL, open the project in a **Remote - WSL** window and install the extension in
that WSL environment. See the [extension guide](tools/vscode-recurloop/README.md)
for executable project configuration and debugging.

The extension uses `recurloop.project.rl` in each workspace folder as the project
entry. It is executable RecurLoop source: the shared server loads it and
publishes the resulting environment for project analysis, tasks, and new console
sessions. Use `include` and engine imports to define the project's source graph
and language dependencies. Opening a workspace containing this file starts
the runtime; opening a project console connects a
separate session to that server.

Declare build, run and debug targets using ordinary source blocks:

```rl
target build-debug {
    emit executable debug ".cache/recurloop/app-debug" app_main = fn () -> i64 {
        return Application:main()
    }
}
target debug depends [build-debug] debug executable ".cache/recurloop/app-debug" {}
```

The same project works from the command line:

```bash
recurloop --targets
recurloop --target build-debug
recurloop --debug-target debug
recurloop --trace src/main.rl
recurloop --project recurloop.project.rl --serve
```

Actions discover `recurloop.project.rl` in parent directories; `--project`
selects another entry. The CLI and editors share graph validation, dependency
execution and semantic inspection. Project mode defaults to the Project,
Shell and Inferred libraries. See [docs/projects.md](docs/projects.md) for the
source-defined grammar, custom roots/imports and client protocol.

Saved changes to `.rl` and `.rli` files reload and republish the project using
the module cache under `.cache/recurloop`. Existing consoles keep their
session state; run `:refresh` to adopt the published environment. After replacing
the host or installed libraries, use **RecurLoop: Restart Language Runtime**
and reopen the consoles.

From a source checkout, build and install the extension with Node.js 22+, npm
and the VS Code `code` command on `PATH`:

```bash
make install-vscode-extension
```

`make vscode-extension` builds the VSIX without installing it. GitHub CI builds
and packages the extension alongside the runtime; tagged releases publish the
VSIX and its SHA-256 checksum as separate release assets. The extension version
comes from `tools/vscode-recurloop/package.json` and is independent of the host
release version.

## First program

Create `hello.rl`:

```rl
const language = "RecurLoop"
const answer = 6 * 7

print "Hello from " + language + "!"
print "The answer is " + str(answer) + "."

assert answer == 42
```

Run it directly:

```bash
recurloop --file hello.rl
```

RecurLoop embeds its standard core language, so a normal `.rl` file does not need bootstrap flags or a separate runtime image.

### Compile a native executable

Native executable generation is part of the language. Create `native-hello.rl`:

```rl
link shared "c"
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

emit executable "./native-hello" main = fn () -> i64 {
    printf("Hello from native RecurLoop\n")
    return 0
}
```

Compile and run it:

```bash
recurloop --file native-hello.rl
./native-hello
```

RecurLoop can also emit objects, executables, engine images, and code produced through its built-in or LLVM backend.

## Interactive shell and language libraries

The installed libraries are loaded by name. Start the Shell library as an interactive RecurLoop session:

```bash
recurloop --library shell -
```

Example:

```text
$ echo "hello from RecurLoop"
hello from RecurLoop
$ echo alpha | tr a-z A-Z
ALPHA
$ cd /tmp
$ pwd
/tmp
$ print 6 * 7
42
```

Shell is a RecurLoop language library, not a separate executable or hard-coded shell mode.

You can load multiple language libraries into the same session. For example, Shell + Inferred:

```bash
recurloop --library shell --library inferred -
```

```text
$ poly fn add(a, b) {
$     return a + b
$ }
$ print add(20, 22)
42
```

`Inferred` lazily specializes type-light functions into native RecurLoop functions, while the normal core language and Shell remain available in the same process.

## Build, test, and install from source

### Requirements

- Linux x86-64;
- CMake 3.25 or newer;
- Ninja;
- Clang with C++23 support;
- `make` and `git`.

On Ubuntu/Debian, a typical starting point is:

```bash
sudo apt update
sudo apt install -y cmake ninja-build clang lld make git
```

Clone the project:

```bash
git clone https://github.com/RecurLoop/RecurLoop.git
cd RecurLoop
```

Build the optimized runtime:

```bash
make
```

Run fast incremental checks. CMake/Ninja reruns only affected unit tests, feature tests, examples, and workflows:

```bash
make check
```

Run the complete release verification with the exact pinned LLVM/zlib/zstd toolchain:

```bash
make verify
```

Build the complete local release set — executable plus standard libraries:

```bash
make release
```

Install everything in one command without root access:

```bash
make install PREFIX="$HOME/.local"
```

That installs the executable, private LLVM tools and native linking files, all standard `.rli` libraries, and project documentation. For a system-wide source installation, use:

```bash
sudo make install
```

The default system layout is:

```text
/usr/local/bin/recurloop
/usr/local/share/recurloop/libraries/language-kit.rli
/usr/local/share/recurloop/libraries/shell.rli
/usr/local/share/recurloop/libraries/inferred.rli
/usr/local/share/recurloop/libraries/http.rli
/usr/local/share/recurloop/libraries/{gui,ide,project,embed}.rli
/usr/local/share/doc/RecurLoop/{LICENSE,README.md,TRADEMARKS.md}
```

Useful development commands:

```bash
make             # optimized Release + LLVM build
make check       # incremental affected checks + examples
make test        # full unit + feature tests
make libraries   # build all distributable .rli libraries
make release     # pinned release binary + libraries
make verify      # full release verification
make install     # pinned release + libraries + docs -> install prefix
```

LLVM itself is never built by RecurLoop. Development uses `AUTO`: an already
cached pinned LLVM 22.1.8 archive is preferred; otherwise a compatible system
LLVM 22.x is used, and the pinned archive is downloaded only when neither is
available. `make release`,
`make verify`, and `make install` force that exact checksum-pinned archive.

On Debian/Ubuntu, a system development setup is simply:

```bash
sudo apt install llvm-22 llvm-22-dev clang-22 lld-22
```

For C++ host debugging, use the dedicated Debug preset instead of the normal Make workflow:

```bash
cmake --preset debug
cmake --build --preset debug --target Recurloop
```

## What is included in a release?

The current GitHub binary release is Linux x86-64 with a glibc >= 2.35 ABI
contract and is tested in clean containers. LLVM backend code is linked into
`recurloop`; the package does not contain a private Clang/LLD or copied libc
sysroot. `emit object` uses compatible LLD; `emit executable` uses compatible
Clang/LLD from the host (`clang-22`/`lld-22` on Debian/Ubuntu). See
[production builds and compatibility](docs/releases.md).

```text
bin/recurloop
share/recurloop/libraries/language-kit.rli
share/recurloop/libraries/shell.rli
share/recurloop/libraries/inferred.rli
share/recurloop/libraries/http.rli
share/recurloop/libraries/{gui,ide,project,embed}.rli
share/recurloop/{BUILD-COMPATIBILITY.txt,RELEASE-METADATA.txt,PACKAGE-MANIFEST.sha256}
share/doc/RecurLoop/...
```

The runtime searches `RECURLOOP_LIBRARY_PATH` before its built-in and local
fallback directories. The variable accepts a colon-separated list on Linux, so
custom prefixes can be used without rebuilding the executable.

The rest of this README explains the language model, compiler/runtime architecture, examples, and current limitations in more detail.

## Why RecurLoop?

Most programming languages place a hard boundary between the language
implementation and programs written in that language. Extending syntax often
means changing the compiler, using a predefined macro system, preprocessing
source, or placing a DSL behind a separate parser.

RecurLoop explores a different design point:

1. **Syntax is language state.** Grammar entries live in the same hierarchical
   lexicon as ordinary named phrases.
2. **Semantics are programmable.** Phrase actions can inspect and consume
   source, define phrases and types, report diagnostics, and execute, compile,
   or reinterpret captured source.
3. **Language extensions are composable.** Dictionaries can be nested, merged,
   flattened, aliased, and matched using longest-prefix lookup.
4. **Language extensions are persistable.** Serializable phrases, compiled
   actions, values, types, and relocatable language state can be exported into
   an engine image and restored in another process.
5. **Extensibility does not stop at interpretation.** RecurLoop also provides
   typed compiled functions, native code generation, LLVM-backed optimization,
   ELF output, linking, and source-level debugging.

The long-term goal is to make language features and domain-specific languages
behave more like libraries: definable in source, composable with other
extensions, distributable, inspectable, and usable without forking the host
compiler.

## Foreign-language experiments

The compatibility examples are not presented as complete implementations of
their upstream languages. They are architecture tests that deliberately stress
different parts of RecurLoop's extension model.

| Experiment | What it stresses | Where the foreign semantics live |
|---|---|---|
| Shell | processes, pipelines, redirection, environment and directory state | phrase grammar plus a POSIX process layer written in RecurLoop |
| Amber | imperative syntax close to native RecurLoop semantics | primarily phrase composition and ordinary RecurLoop expressions/functions |
| Prolog | logical variables, unification, choice points and backtracking | a Prolog-specific parser and logical runtime written in RecurLoop |
| Haskell | currying, algebraic data, pattern matching and call-by-need | a Haskell-specific parser and lazy runtime written in RecurLoop |
| Erlang | actors, single-assignment matching, mailboxes and selective receive | an Erlang-specific parser and cooperative actor runtime written in RecurLoop |

The important claim is **not** that every foreign language can be represented
only by aliases or without a parser.

For languages whose syntax or execution model differs substantially from
native RecurLoop, a compatibility layer can implement its own parser, AST, or
semantic runtime in RecurLoop source. User-visible foreign symbols can still
be interned in the RecurLoop lexicon and used as canonical phrase identities,
while the C++ host remains free of a dedicated implementation for that
language.

This distinction is intentional:

```text
Amber
    mostly phrase-native imperative compatibility

Prolog
    custom logical runtime + unification + rollback

Haskell
    custom lazy runtime + currying + thunks

Erlang
    custom actor runtime + mailboxes + selective receive
```

These experiments have also exposed a common architectural boundary: a foreign
language currently shares the root RecurLoop dictionary and can collide with a
stronger existing root phrase. A first-class per-source **language root** is a
natural next step for stronger language isolation.

See:

- [`examples/07-workflows/amber-language/`](examples/07-workflows/amber-language/)
- [`examples/07-workflows/prolog-language/`](examples/07-workflows/prolog-language/)
- [`examples/07-workflows/haskell-language/`](examples/07-workflows/haskell-language/)
- [`examples/07-workflows/erlang-language/`](examples/07-workflows/erlang-language/)
- [`examples/07-workflows/shell-language/`](examples/07-workflows/shell-language/)

## The phrase model

Conceptually, a phrase is a node in a hierarchical lexicon:

```text
phrase
├── lexical key / path
├── prototype
├── data and metadata
├── executable or compiler action
└── nested phrase dictionary
```

Source is resolved against phrase dictionaries using longest-prefix lookup.
Prototype chains let a new spelling inherit grammar or behavior without
copying hidden compiler state.

A simplified view of the system is:

```text
source
  |
  v
phrase dictionaries -- longest-prefix lookup -- prototype resolution
  |
  +--> elaboration / source-defined actions
  |
  +--> expression and type parsing
  |
  v
typed compiler
  |
  +--> built-in x86-64 backend
  |
  +--> LLVM backend
          |
          +--> immediate execution
          +--> ELF objects
          +--> standalone executables
```

The language-facing layer is therefore not only a separate fixed grammar
database. Ordinary RecurLoop source can participate in it.

## Source-defined language extensions

### Aliases and operators

Keywords, operators, type constructors, parselets, and function syntax can be
re-exposed through new phrases:

```rl
let mutable = <var>
let when = <if>
let yield = <return>
let "%%" = <+>

let twice = fn (value:i64) -> i64 {
    yield value %% value
}

assert twice(21) == 42
assert 20 %% 22 == 42
```

The same `%%` phrase participates in top-level expressions and compiled
functions.

### New control flow written in RecurLoop

Extensions are not limited to aliases.
`examples/03-phrases-and-syntax/` contains source-defined compiler actions that
consume source and introduce new constructs.

For example, the `persistent-extensions` workflow defines `repeat` in `.rl`:

```rl
var repeated = 0

repeat 3 {
    repeated += 14
}

assert repeated == 42
```

The action implementing `repeat` captures its header and block through the
public Context API. It can then be exported in an engine image, imported again,
and used after the round trip.

The `switch-extension` example goes further and implements a source-defined:

```text
switch
case
default
finally
break
continue
```

family including matching, fallthrough, loop interaction, and `finally`
semantics. No dedicated C++ `switch` parser is required for that extension.

### Alternative surface syntax

The same phrase mechanism can expose different spellings and parsing styles.

The examples include Python-style indentation with source-level aliases:

```rl
let def = <fn>
let done = <return>
let plus = <+>

def add(left:i64, right:i64) -> i64:
    done left plus right

assert add(20, 22) == 42
```

This is not intended as a Python implementation. It demonstrates that the
surface language can be adapted while continuing to use the typed compiler
beneath it.

## Shell language implemented as a library

One of the larger workflows builds a Bash-like system scripting language in
RecurLoop source and exports it as a reusable engine image.

After importing the library:

```text
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

The shell extension includes:

- direct command execution;
- native process pipelines;
- `>` and `>>` redirection;
- `capture`;
- asynchronous `spawn`;
- directory scopes;
- environment scopes;
- parallel jobs;
- a parent-process `cd` builtin with `PWD` and `OLDPWD`;
- interpolation with RecurLoop values;
- use of shell syntax at top level and from compiled functions.

The phrase actions build argument and pipeline objects directly. Ordinary
pipelines are not assembled into a command string and passed to Bash or
`/bin/sh`. The implementation uses POSIX process primitives such as `fork`,
`pipe`, `dup2`, `execvp`, and `waitpid`.

There is no separate shell executable or shell-specific REPL. Importing the
language image extends ordinary RecurLoop input.

See [`examples/07-workflows/shell-language/`](examples/07-workflows/shell-language/).

## Language at a glance

RecurLoop currently exposes two visible kinds of bindings:

- `var` and `const` create runtime values;
- `let` defines phrases in the lexicon.

Runtime and compiled-language features exercised by the repository include:

- integers, reals, booleans, strings, and null;
- arithmetic, comparisons, assignment, and short-circuit logic;
- lexical scopes, `if`, and `while`;
- typed compiled functions and recursion;
- structural function types, callbacks, and overload selection;
- pointers and pointer indexing;
- records and receiver methods;
- native floating-point operations and numeric casts;
- `defer` with LIFO execution;
- null propagation with `?`;
- dictionaries used as namespaces;
- external C functions and explicit calling conventions.

Example:

```rl
let Math = [
    gcd = fn (left:i64, right:i64) -> i64 {
        var a = left
        var b = right

        while b != 0 {
            const remainder = a % b
            a = b
            b = remainder
        }

        return a
    }
]

assert Math:gcd(84, 30) == 6
```

See [`docs/language.md`](docs/language.md) for the language guide.

## Native code and output

RecurLoop includes a built-in Linux x86-64 backend and an optional LLVM
backend. Compiled functions use explicit types and calling conventions.

The host can:

- execute compiled functions immediately;
- emit exact machine-code bytes;
- emit ELF64 relocatable objects;
- emit standalone ELF executables;
- define x86-64 assembly with labels, sections, symbols, and relocations;
- import object files and Unix archives;
- link static objects internally;
- link shared libraries through the system toolchain;
- embed RecurLoop language and source metadata in emitted files.

A regular RecurLoop function can become part of a standalone executable:

```rl
link shared "c"

extern printf(format:u8*, ...) -> i64 abi sysv-amd64

emit executable "/tmp/hello-recurloop" main = fn () -> i64 {
    printf("hello from native RecurLoop\n")
    return 0
}
```

Executable output is a hardened, stripped release build by default. Use
`emit executable debug "/tmp/hello-recurloop" ...` to keep the symbol table
and lower the newly compiled LLVM function without optimization; linker
hardening remains enabled in debug output.

The examples include generated applications such as a CIDR calculator, number
tools, a task queue, container-oriented code, a JSON processor, an exchange
simulator, and a ray tracer.

## LLVM backend

LLVM is disabled by default in direct CMake configurations. Normal optimized
Make builds enable it without compiling LLVM itself. Dependency selection is:

```text
RECURLOOP_LLVM_PROVIDER=AUTO|SYSTEM|ARCHIVE
```

`AUTO` prefers an already-cached pinned LLVM 22.1.8 archive, falls back to an
installed LLVM 22.x, and downloads the pinned archive only when neither is
available. `SYSTEM` is useful for distro/Docker builds;
`ARCHIVE` is the deterministic production mode and verifies a hard-coded
SHA-256 before extraction.

The production backend is native-only:

```text
RECURLOOP_LLVM_LINK_TARGETS=native
```

`RECURLOOP_LLVM_LINK_TARGETS=all` remains an explicit opt-in and links all
backends present in the same downloaded/installed LLVM distribution; it does
not trigger another LLVM build.

With LLVM enabled, source-defined `fn` implementations, nested functions,
phrase actions, and compiled phrase blocks can be lowered to LLVM IR and
optimized for immediate execution and native output. `emit object` uses compatible `ld.lld` on `PATH`; `emit executable` performs the final OS link through
compatible Clang/LLD on `PATH`, keeping platform libc/sysroot policy outside
the RecurLoop archive.

Runtime compilation targets the host. LLVM object output can be configured
with `RECURLOOP_LLVM_TARGET_TRIPLE`, `RECURLOOP_LLVM_CPU`,
`RECURLOOP_LLVM_FEATURES`, and `RECURLOOP_LLVM_SYSROOT`. An `asm` block defines
exact target instructions and is preserved rather than semantically rewritten
by LLVM.

## Engine images

RecurLoop can serialize language state into an **engine image** and restore it
in another context or process.

```rl
var answer = 42

engine export "/tmp/example.rli"

answer = 0

engine import "/tmp/example.rli"

assert answer == 42
```

A compiled `lexicon` object can be stored as a reusable fragment instead of a
complete engine snapshot:

```rl
let routes = lexicon {
    let api = [ health = <debug:ping> ]
}

engine export <routes> "/tmp/routes.rli"

let application = [
    merge "/tmp/routes.rli"
]
```

The fragment can be merged below any active dictionary and does not replace
the global language state.

Images can contain serializable lexicon state including values, phrases,
types, compiled modules, and relocations. Process-local JIT entries and native
pointers are not stored as raw addresses; JIT state is rebuilt, while a nonzero
field explicitly declared as a native pointer makes export fail.

Libraries loaded before source execution become reusable image dependencies.
For example, `shell.rli`, `inferred.rli`, and `http.rli` can contain only their
own delta while sharing `language-kit.rli`. Import follows these dependencies
recursively, resolves relative paths from the declaring image, and skips an
already-loaded image with the same content identity.

```bash
build/Release/bin/recurloop \
  --library shell \
  --file application.rl
```

The current engine-image wire format is version 8; version-7 images remain
readable. The format is still experimental.

See [`docs/engine-images.md`](docs/engine-images.md).

## Debugger

RecurLoop includes a phrase-aware source debugger. Debugger commands are
phrases in the `debug` dictionary:

```rl
debug:trace on
debug:break phrase "print"
debug:break line "worker.rl":12
debug:run "worker.rl"
```

At a stop, the debugger supports commands including:

```text
where
eval
locals
registers
step
next
finish
continue
```

Static executables emitted by RecurLoop can also be debugged when they contain
RecurLoop source metadata.

`emit executable debug` supplies precise statement maps and local layouts from
both LLVM-enabled and built-in hosts. LLVM-enabled hosts rebuild debug entry
points and reachable source functions with the built-in debug generator.
Records, arrays and pointer pointees can be expanded, and new threads are
traced automatically. See [docs/projects.md](docs/projects.md) for CLI debugging,
thread selection and aggregate inspection.

See [`examples/07-workflows/source-debugger/`](examples/07-workflows/source-debugger/).

## Examples

The `examples/` tree is an ordered, self-checking tour of the project rather
than a collection of scratch programs.

| Group | Focus |
|---|---|
| `01-getting-started` | values, control flow, functions, namespaces, records, lifetime |
| `02-functions` | function values, signatures, lexical lookup, floating point |
| `03-phrases-and-syntax` | aliases, Context APIs, custom operators, parselets, indentation, persistent extensions, source-defined `switch` |
| `04-native-output` | assembler, ELF output, backend selection, engine images |
| `05-applications` | standalone application-shaped programs |
| `06-benchmarks` | exchange simulator, JSON processor, ray tracer |
| `07-workflows` | reusable language images, shell DSL, Amber/Prolog/Haskell/Erlang compatibility experiments, source debugger |

From the repository root:

```bash
make list-examples
make example EXAMPLE=03-phrases-and-syntax/custom-operators
make examples
```

The examples contain assertions and regression runners, so successful
execution also validates their documented behavior.

See [`examples/README.md`](examples/README.md) for the full learning path.

## Command line

The final executable embeds the standard `core.rli`, so ordinary source files
need no language/bootstrap flags:

```text
Recurloop [options] [file...]

  -h, --help            Show help and exit
  -v, --version         Show version and exit
  -f, --file <path>     Read source from a file
  -s, --string <code>   Read source from the command line
  --import <path>       Import an additional engine image
  --reset               Clear the embedded language back to the host kernel
  -                     Read standard input; interactive on a terminal
```

Normal execution starts from the embedded core:

```bash
recurloop --file program.rl
recurloop --import shell.rli --file program.rl
```

To start from an empty language state and explicitly choose the image to load:

```bash
recurloop --reset --import core.rli --file program.rl
```

`--reset` and `--import` are state-selection operations and must appear before
the first source input. Engine images do not contain a special `root`, `core`,
or `bootstrap` kind; an image is simply imported into the current state.

With no arguments, RecurLoop starts the interactive standard-input mode.

Recoverable input errors do not affect the session's final status. Use `exit`
to return status `0`, or `exit <integer-expression>` to return a status from
0 through 255.

## Tests

```bash
make check    # incremental affected checks, AUTO LLVM toolchain
make test     # complete unit + feature suite, AUTO LLVM toolchain
make verify   # pinned release toolchain + tests + libraries + examples + core fixed point
```

The test suite covers the radix tree, compiler, assembler, expressions, engine
image round trips, LLVM integration, CLI behavior, language features, and
multi-process example workflows.

## Repository layout

```text
include/       public C++ headers
source/        C++ host implementation
cmake/         tracked CMake modules
tests/         unit, feature, benchmark, and LLVM tests
examples/      guided examples, applications, benchmarks, and language experiments
docs/          language and architecture documentation
build/         generated build tree (ignored)
```

The host libraries are layered as:

```text
utilities -> radix -> lexicon -> context -> compiler -> recurloop -> CLI
```

See [`docs/architecture.md`](docs/architecture.md) for architecture details.

## Current scope and limitations

RecurLoop is deliberately experimental. In particular:

- the language and source-level extension APIs may still change;
- the engine-image wire format is not stable;
- the built-in native backend currently targets Linux x86-64;
- runtime LLVM compilation targets the host;
- source debugging requires `emit executable debug`; release output stays optimized;
- foreign-language experiments implement deliberately limited compatibility
  subsets rather than claiming complete language implementations;
- the current shared root lexicon can cause collisions between a foreign
  language's top-level forms and existing RecurLoop root phrases;
- examples such as the shell language demonstrate the extensibility model and
  are not intended to be complete replacements for mature production tools.

The host boundary is intentionally frozen: new language constructs, compiler
registries and ordinary compiler collections are expected to be implemented in
RecurLoop source. The remaining C++ surface is the reviewed kernel/process/backend
ABI; its exact direct-action set is audited during the core build.

## Project goals

RecurLoop explores whether a programming language can make its own language
layer a normal programmable interface while retaining native-code capabilities.

The main goals are:

- make syntax extensible from RecurLoop source rather than only from the C++
  host;
- allow language-specific parsers and semantic runtimes to be implemented in
  RecurLoop source when phrase composition alone is not sufficient;
- make independently developed language extensions composable;
- make language state distributable and reproducible through engine images;
- preserve typed native compilation and interoperability with existing system
  software;
- keep enough compiler, phrase, and debugger metadata to make dynamically
  assembled languages understandable and inspectable;
- provide a practical platform for experimenting with programming-language and
  DSL design without requiring a new C++ compiler implementation for every
  experiment.

## License and trademarks

RecurLoop source code is distributed under the
[Apache License 2.0](LICENSE).

The RecurLoop name and logo are governed separately from the source-code
license. See [`TRADEMARKS.md`](TRADEMARKS.md) for the trademark policy.

Contributions are described in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Core image and self-hosted rebuild

`core.rli` is the standard RecurLoop language image. A clean build uses an
isolated, non-installed C++ **seed** that contains only enough grammar to enter
`engine define { ... }`. The seed is deliberately not the standard language.
`libraries/recurloop/core.rl` replaces that seed lexicon and builds the real core
from symbolic source declarations.

A normal development build stops after the first source-built core and embeds it:

```text
empty kernel
  -> private C++ seed
  -> seed.rli
  -> core.rl
  -> core.rli
  -> embed core.rli
  -> final recurloop
```

The expensive second self-hosting pass is explicit verification rather than a
dependency of every executable build. `make verify` builds `core-2.rli`,
requires `core.rli == core-2.rli` byte-for-byte, and also checks that
`seed.rli` remains distinct and smaller than the final core. The fixed-point
target can also be invoked directly with `cmake --build --preset release --target RecurloopCoreVerify`.

The public rebuild path uses the final executable itself:

```bash
libraries/recurloop/build-core.sh build/Release/bin/recurloop build/Release/core.rli

# Equivalent source-driven forms:
recurloop --file libraries/recurloop/core.rl
recurloop --reset --import core.rli --file libraries/recurloop/core.rl
```

`libraries/recurloop/core.rl` is semantic source rather than an engine-image
dump: phrase references are symbolic and Host ABI primitives are named. Numeric
phrase ids, numeric parent/prototype/successor ids and serialized payload dumps
are rejected from the checked-in source core.

The compiler registry topology is source-owned as well. `core/compiler.rl`
declares the physical keys, registry roles, setting/counter slots and ABI-kind
mapping. Production `LanguageState` and `TypeRegistry` discover those objects by
stable semantic tags stored in the lexicon rather than by hard-coded registry
paths. A build-time audit rejects reintroduction of those physical keys into
production compiler code.

Compiler scratch collections are also source-owned. `core/collections.rl`
provides byte buffers, vectors, deques, maps and arenas over a minimal raw-memory
Host ABI. Source-owned phrase actions are compiled into `core.rli`; final phrases
use those compiled implementations. Stable compatibility action names remain in
the process registry so `core.rl` can rebuild itself from a running executable.
See `docs/host-abi.md` for the frozen boundary.

There is no public `--bootstrap`, `--language-image`, `--engine-image`, `--core`,
or `--no-core` mode. The final runtime registers process-local Host ABI action
names, restores the embedded source-built core image, and binds native
ContextAPI addresses against that restored state. The seed language code is
linked only into the private build tool under `bootstrap/`.
