# Language guide

RecurLoop source is interpreted through a mutable dictionary of phrases. Each
phrase has a key and may carry behavior, data, a prototype, a type, a
successor, and a nested dictionary. The normal lookup rule selects the longest
matching key in the current dictionary.

## Values and expressions

Runtime values are `null`, `bool`, `int`, `real`, and `string`.

```rl
const project = "Recur" + "Loop"
var result = 2 + 3 * 4
result += 7

assert result == 21
print project + ": " + str(result)
```

Operator precedence, from highest to lowest:

1. unary `!`, `+`, `-`;
2. `*`, `/`, `%`;
3. `+`, `-`;
4. `<`, `<=`, `>`, `>=`;
5. `==`, `!=`;
6. `&&`;
7. `||`.

Integer arithmetic checks overflow and division by zero. Mixed numeric
operations produce `real`. String addition concatenates, and boolean operators
short-circuit.

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

## Source-defined syntax

Syntax fields and parser behaviors are phrases, so source can alias or install
statements, operators, delimiters, type spellings, assembler mnemonics, and
whole block rewrites. A compiled function with the exact signature
`(Context*, Phrase*) -> void` can act as a phrase action.

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
```

`module auto` closes native dependencies automatically. `module manual`,
`module include`, `module exclude`, `module dynamic`, `module entry`,
`module embed`, `module strip`, and `module clear` control composition
explicitly. `link object`, `link archive`, `link path`,
`link library`, and `link shared` configure external inputs.

## Next steps

Run `make showcase` for the complete executable tour and use
[../examples/README.md](../examples/README.md) for focused programs.
