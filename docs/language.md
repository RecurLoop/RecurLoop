# Language guide

RecurLoop source is interpreted through a mutable dictionary of phrases. Each
phrase has a key and may carry behavior, data, a prototype, a type, a
successor, and a nested dictionary. The normal lookup rule selects the longest
matching key in the current dictionary.

## Process diagnostics

`debug:stats` prints a process-monitor snapshot: PID, process age, threads,
CPU time and CPU usage since the previous snapshot (100% is one core), resident/peak/virtual
memory and swap, context switches, page faults, and storage I/O counters.
An engine section shows the current context's lexicon arena occupancy, program
and action JIT bytes, and accumulated elaboration/invocation timings. Those
timings cover completed scopes, can overlap, and are not reset by a snapshot.
Arena capacity and JIT bytes are not additional resident-memory totals.
Linux process metrics come from `/proc` and `getrusage`; unavailable values are
shown as `n/a`. Output uses a bordered panel with color only on a terminal
(`NO_COLOR` disables color), so redirected snapshots contain no ANSI escapes.
The first snapshot shows average CPU usage since process start and establishes
a baseline (or `n/a` if the process age cannot yet be measured).
Subsequent snapshots use process CPU-time deltas over a monotonic wall-clock
interval; sampling is immediate and does not sleep. The baseline belongs to
the current context and is not serialized in engine images.

## Values and expressions

Runtime values are `null`, `bool`, `int`, `real`, and `string`.

The `recurloop_version` phrase returns the running host's release version as a
`string`, without a `v` prefix. It reads the host version on evaluation rather
than storing a version in the language image:

```rl
var version = recurloop_version
print version
```

For a host built from release 0.2.7, this prints `0.2.7`.

```rl
const project = "Recur" + "Loop"
var result = 2 + 3 * 4
result += 7

assert result == 21
print project + ": " + str(result)
```

Operator precedence, from highest to lowest:

1. unary `!`, `~`, `+`, `-`;
2. `*`, `/`, `%`;
3. `+`, `-`;
4. `<<`, `>>`;
5. `<`, `<=`, `>`, `>=`;
6. `==`, `!=`;
7. bitwise `&`;
8. bitwise `^`;
9. bitwise `|`;
10. `&&`;
11. `||`.

Primary and postfix syntax is phrase-backed too. The standard runtime-expression
grammar declares grouping as a primary phrase and qualification, calls, and
member calls as postfix phrases. Compiled `fn` expressions use the corresponding
phrase dictionaries, so aliases of structural tokens work consistently in both
paths instead of being recognized by spelling-specific parser branches.

Integer arithmetic checks overflow and division by zero. Mixed numeric
operations produce `real`. String addition concatenates, and boolean operators
short-circuit.

Bitwise operators require integers. `~` inverts bits, while `&`, `|`, and `^`
combine bits. `<<` shifts left, and `>>` shifts right arithmetically for signed
types and logically for unsigned types. Shift counts are reduced modulo the
left operand's bit width. Left shifts discard bits past that width. The top-level
`int` has 64 bits. Compound assignments
`&=`, `|=`, `^=`, `<<=`, and `>>=` use the same operations.

`var` is mutable, `const` is immutable, and assignment updates the nearest
visible binding. Function bodies, branches, loops, and explicit blocks create
lexical value scopes.

## Control flow and functions

```rl
fn fibonacci(value:i64) -> i64 {
    if value < 2 {
        return value
    }
    return fibonacci(value - 1) + fibonacci(value - 2)
}

var index = 0
while index < 8 {
    print fibonacci(index)
    index += 1
}
```

Every `fn` is compiled. Functions support typed parameters and results,
recursion, overloads, function values, `if`, `while`, `return`, local bindings,
pointers, indexing, records, method calls, and calls to typed imports.

Expressions can also appear directly at top level, including in the console:
`Probe:main()`, `(Probe:main())`, or `2 + 3`. Expression statements use the same
phrase-backed grammar as expression values and discard their result; use
`print str(Probe:advance(0, 10))` to display it. Ordinary executable phrases retain
priority. With LanguageKit, expression recognition runs without evaluation before
generic Shell commands. Once expression syntax claims a form, its errors stay in
RecurLoop.

`defer` evaluates cleanup expressions in LIFO order when leaving a compiled
function. Postfix `?` propagates null from pointer-returning functions.

## Types

Built-in native types include signed and unsigned integers (`i8` through
`i64`, `u8` through `u64`), `f32`, `f64`, `void`, `Context`, and `Phrase`.
Pointers use `*`, arrays use `[N]`, and function types use
`fn (...) -> ...`.

Function types are structural: parameter types, result, calling convention,
and variadic state determine identity. A named signature phrase can be reused
as both a definition template and a type.

```rl
let Unary = fn (value:i64) -> i64

let increment = Unary {
    return value + 1
}

let apply = fn (callback:Unary, value:i64) -> i64 {
    return callback(value)
}
```

## Dictionaries and phrases

`let` defines language phrases rather than runtime values.

```rl
let Math = [
    answer = <debug:ping>
]

Math:answer
```

`[...]` creates a nested dictionary. `:` traverses dictionary paths. Phrase
keys are byte or bit strings and are not limited to C identifiers. A reference
such as `<if>` returns a phrase that can be used as a prototype.

Aliases inherit behavior:

```rl
let branch = <if>
let otherwise = <else>
let done = <return>
let plus = <+>
```

An explicit `{ ... }` phrase block creates a lexicon checkpoint; phrases added
inside it disappear when the block ends. This is independent of runtime value
scopes.

Phrase descriptors can protect public language contracts and expose the same
phrase to compiled-function expansion:

```rl
let command = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        // Elaborate top-level source or emit core fn source.
    }
}
```

A permanent phrase cannot be redefined or modified. A rewritable root
phrase is matched directly while an `fn` body is expanded; there is no second
copy in a function-specific dictionary.

### Semantic metadata

`kind`, `color`, and `docs` are ordinary phrase fields, not an editor-side
registry. Libraries can attach them to language phrases and prototypes; semantic
inspection clients inherit the nearest metadata through the normal prototype
chain. The source-defined IDE uses the same metadata for highlighting and hover
documentation, so custom syntax can describe itself without adding an AST or a
separate IntelliSense grammar.

The fields accepted inside `phrase { ... }` are phrases too. Their standard
definitions carry semantic metadata, which means hovering `type`, `prototype`,
`successor`, `action`, `serializable`, and the other descriptor fields explains
the phrase contract directly in the editor.

Write `docs` as compact Markdown: show the invocation first in a fenced
`recurloop` code block, then explain its effect and any scope restriction.
Add one small example when the signature alone is insufficient. The registered
RecurLoop grammar supplies syntax colors in editor hovers and completions;
plain Markdown clients can still read the same text. In signatures, `...`
stands for additional parameters or statements unless described as variadic.

Document public constructs and meaningful grammar variants on their owning
phrases. Aliases inherit those docs through prototypes; override them when an
alias changes the usage. Internal continuation states, whitespace handlers and
compiler implementation hooks do not need independent usage documentation.

## Records and methods

`record` defines physical native layout, including field offsets, alignment,
arrays, nested records, packed layout, and recursive pointer fields.

```rl
record Point {
    x:i64
    y:i64
}

let Point:sum = fn (self:Point*) -> i64 {
    return self.x + self.y
}
```

A function whose first parameter is a pointer to the owning record is
available through method syntax (`point.sum()`).

Dictionary `struct` declarations are different: they create phrase templates
and inherited subdictionaries, not native memory layouts.

## Calling conventions and imports

`extern` introduces a typed symbol contract. Built-in conventions include
`sysv-amd64`, `microsoft-x64`, `cdecl-x86`, `stdcall-x86`, and `fastcall-x86`.
Source can also define calling conventions.

```rl
link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
```

Repeating an identical external declaration reuses the existing import,
including imports supplied by an engine image. The source name, native symbol,
parameter and result types, variadic flag, and calling convention must match.
A conflicting declaration or an external declaration over a function definition
is rejected.

## Source-defined syntax

Syntax fields and parser behaviors are phrases, so source can alias or install
statements, operators, delimiters, type spellings, assembler mnemonics, and
whole block rewrites. A compiled function with the exact signature
`(Context*, Phrase*) -> void` can act as a phrase action.

For ordinary language construction, `syntax` provides a declarative layer over
the same phrase/rewrite machinery. Layout between pattern items is ignored by
default. Named captures can parse expressions, blocks, identifiers, tokens, or
raw source:

```rl
syntax unless <condition:expr> <body:block> => if !(${condition}) ${body}
```

The resulting phrase is serializable and rewritable, so the construct works at
top level and while compiled `fn` bodies are expanded. Optional pattern parts
use `[ ... ]`, choices use `(left | right)`, and exact punctuation can be
quoted. Common capture matchers are `expr`, `block`, `id`, `qualified-id`,
`token`, `string`, `number`, `raw`, `code`, and `rest`. Explicit layout controls
include `<whitespaces:ignore>`, `<space:required>`, `<space:none>`, and
`<line:newline>`.

`syntax extend` adds a higher-priority pattern while preserving the previous
definition as a fallback when the new pattern does not match. `syntax replace`
intentionally shadows an existing spelling and treats a pattern mismatch as an
error. `as <phrase>` validates the declared pattern and reuses an existing
phrase's semantics. At top level the target phrase consumes the validated source tail directly; inside
compiled functions the target spelling and the same tail are handed back to the
ordinary function grammar. This is useful when changing the root spelling or
adding delimiters while keeping the target phrase's remaining source shape:

```rl
syntax replace if "(" <condition:expr> ")" <body:block> [else <rejected:block>] as <if>
```

For constructs that cannot be expressed as a rewrite, `action fn` is the escape
hatch. The action reads named matches through `context:syntax:capture` and
`context:syntax:capture:exists`; during compiled-function expansion it can use
the existing `context:syntax:*` emission API.

The public Context API exposes named operations for phrase lookup, definition,
metadata, payloads, child iteration, source capture, diagnostics, and syntax
emission. Low-level variants accept explicit owners, offsets, bit lengths,
flags, and call modes. See these focused examples:

- `examples/03-phrases-and-syntax/friendly-context-api/`
- `examples/03-phrases-and-syntax/context-api/`
- `examples/03-phrases-and-syntax/custom-operators/`
- `examples/03-phrases-and-syntax/switch-extension/`

## Output directives

The language can emit exact bytes, objects, and executables:

```rl
emit raw "/tmp/data.bin" = hex { 52 4c 0a }
emit object "/tmp/module.o" add = fn (a:i64, b:i64) -> i64 {
    return a + b
}
emit executable "/tmp/app" app_main = fn () -> i64 {
    return 0
}
emit executable debug "/tmp/app-debug" app_debug_main = fn () -> i64 {
    return 0
}
```

`emit executable` defaults to release output: PIE, immediate binding with
full RELRO, a non-executable stack, x86-64 CET/IBT metadata and landing pads,
stack canaries in generated `fn` code, and a stripped static symbol table.
The `debug` form retains symbols and exact statement/local-layout metadata while
retaining the security properties. LLVM-enabled hosts use the built-in debug
generator for the entry and reachable source functions, linked by the configured
Clang/LLD toolchain. See [projects.md](projects.md) for native debugging.
Hand-written `asm` remains responsible for valid indirect-branch landing
pads inside the user-controlled instruction stream.

`_FORTIFY_SOURCE` is a C/C++ preprocessing feature, not an ELF property or a
RecurLoop code-generation mode. C/C++ objects linked into RecurLoop output
must therefore be compiled with their desired fortify level separately;
RecurLoop does not advertise a misleading fortify flag for native `fn` code.

`module auto` closes native dependencies automatically. `module manual`,
`module include`, `module exclude`, `module dynamic`, `module entry`,
`module embed`, `module strip`, and `module clear` control composition
explicitly. `link object`, `link archive`, `link path`,
`link library`, and `link shared` configure external inputs.

On Linux, `link shared "name"` first uses the normal `libname.so` lookup. If
only a runtime SONAME such as `libname.so.1` is installed, RecurLoop also
searches the configured runtime-loader directories (`link path`,
`LD_LIBRARY_PATH`, and `ld.so.conf`) for versioned `.so` files. JIT execution
loads that file directly; native executable emission passes its directory and
exact basename to the platform linker (`-L... -l:libname.so.1`). Neither path
therefore depends on a development-package `libname.so` linker symlink.

## Next steps

Run `make examples` for the complete executable tour and use
[../examples/README.md](../examples/README.md) for focused programs.
