# RecurLoop

**An extensible native programming language where syntax, semantics, and namespaces share the same phrase system.**

RecurLoop is an experimental programming language and language runtime for
building extensible languages and domain-specific languages from within the
language itself.

Its core abstraction is the **phrase**. A phrase can represent executable
behavior, grammar, data, a prototype, or a nested dictionary. The same
hierarchical lexicon participates in both name lookup and language lookup, and
longest-prefix matching allows source-defined phrases to take part directly in
source elaboration and compilation.

A program can therefore rename existing syntax, introduce operators and
control-flow constructs, define grammar dictionaries, or load a reusable
language extension without adding a new hard-coded rule to the C++ host.

```rl
let branch = <if>
let otherwise = <else>
let done = <return>
let plus = <+>
let make = <fn>

let calculate = make (value:i64) -> i64 {
    branch value > 2 {
        done value plus 10
    } otherwise {
        done 1
    }
}

assert calculate(3) == 13
```

`branch`, `otherwise`, `done`, `plus`, and `make` are ordinary phrases. The
host compiler does not contain separate keywords for those spellings;
prototype resolution leads them to existing language behavior.

RecurLoop goes beyond aliases. The repository includes source-defined control
flow, custom operators and parselets, indentation-based syntax, a shell
language, and compatibility experiments for Amber, Prolog, Haskell, and
Erlang.

> **Project status:** RecurLoop is an active research implementation. The
> language, extension APIs, and engine-image format are not yet stable.

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

The examples include generated applications such as a CIDR calculator, number
tools, a task queue, container-oriented code, a JSON processor, an exchange
simulator, and a ray tracer.

## LLVM backend

LLVM is disabled by default in direct CMake configurations. The standard
optimized build enables it:

```bash
make release
```

With LLVM enabled, source-defined `fn` implementations, nested functions,
phrase actions, and compiled phrase blocks can be lowered to LLVM IR and
optimized for immediate execution and native output.

Runtime compilation targets the host. LLVM object output can be configured
with:

- `RECURLOOP_LLVM_TARGET_TRIPLE`;
- `RECURLOOP_LLVM_CPU`;
- `RECURLOOP_LLVM_FEATURES`;
- `RECURLOOP_LLVM_SYSROOT`.

An `asm` block defines exact target instructions and is therefore preserved
rather than semantically rewritten by LLVM.

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

Images can contain serializable lexicon state including values, phrases,
types, compiled modules, and relocations. Process-local JIT entries are not
stored as raw addresses; they are rebuilt after import.

This allows a language extension to be built once and loaded before application
source:

```bash
build/Debug/bin/recurloop \
  --import /tmp/recurloop-shell-library.rli \
  --file application.rl
```

The current engine-image wire format is version 7 and remains experimental.

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

The built-in backend currently provides the precise instruction map used by
the source debugger. LLVM debug-map emission is not implemented yet, so a
Debug build is the recommended debugger workflow.

See [`examples/07-workflows/source-debugger/`](examples/07-workflows/source-debugger/).

## Quick start

### Requirements

- Linux;
- x86-64 for the built-in native backend;
- CMake 3.28 or newer;
- Ninja;
- Clang 18 or newer with `lld`.

Build and run:

```bash
make build
make run
make example EXAMPLE=01-getting-started/hello-world
make test
```

The default executable is:

```text
build/Debug/bin/recurloop
```

For an optimized LLVM-enabled build:

```bash
make release
```

Build configurations are isolated below `build/`, for example:

```text
build/Debug/
build/Release/
build/RelWithDebInfo/
```

Downloaded dependency sources are shared in `build/_deps/`.

The first test-enabled configure may download GoogleTest and Google Benchmark.

To build only the host executable:

```bash
make build ENABLE_TESTS=OFF
```

Run `make` to list the common development commands.

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

```text
Recurloop [options] [file...]

  -h, --help            Show help and exit
  -v, --version         Show version and exit
  -f, --file <path>     Read source from a file
  -s, --string <code>   Read source from the command line
  --import <path>       Import an engine image before sources
  --engine-image <path> Compatibility alias for --import
  -                     Read standard input; interactive on a terminal
```

With no arguments, RecurLoop starts the interactive standard-input mode.

Recoverable input errors do not affect the session's final status. Use `exit`
to return status `0`, or `exit <integer-expression>` to return a status from
0 through 255.

## Tests

```bash
make unit
make feature
make examples
make test
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
- LLVM source-debug mapping is not implemented yet;
- foreign-language experiments implement deliberately limited compatibility
  subsets rather than claiming complete language implementations;
- the current shared root lexicon can cause collisions between a foreign
  language's top-level forms and existing RecurLoop root phrases;
- examples such as the shell language demonstrate the extensibility model and
  are not intended to be complete replacements for mature production tools.

The project is currently focused on making source-defined language extensions
more robust, composable, serializable, debuggable, and suitable for building
larger domain-specific and general-purpose language layers.

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
