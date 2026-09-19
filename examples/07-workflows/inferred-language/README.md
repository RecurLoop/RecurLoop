# RecurLoop inferred / native lazy-specialization language experiment

This workflow explores a deliberately type-light function model on top of
RecurLoop and LanguageKit. Function parameters and results have no declared
source type. Each function owns a family of lazily materialized native
specializations keyed by the runtime `LanguageKit:Value.kind` tuple seen at a
call site.

The implementation is split deliberately:

- `libraries/inferred/library.rl` owns the inferred-language parser, type-directed specialization,
  generated RecurLoop source and dispatch cache;
- the generic host primitive `context:function:compile` accepts a typed
  RecurLoop function signature/body, compiles it with RecurLoop's ordinary
  function compiler, materializes the module through the normal JIT linker and
  returns its native entry address;
- the C++ host contains no inferred-language parser, inference rules or
  specialization policy.

The important property is that an inferred function is **not interpreted after
specialization**. Its AST is used only while generating a typed/native RecurLoop
body. The specialization cache stores a JIT entry and subsequent calls jump to
that compiled entry.

The workflow parser uses the shared `LanguageKit:Cursor` for character-level source access (trivia, exact literals, identifiers, strings and integers). It does not carry a private lexer/token stream; only the inferred-language-specific grammar/AST and runtime semantics remain local to this workflow.

## Surface

```text
poly fn combine(a, b) {
    return a + b
}

poly specializations combine
print combine(20, 22)
print combine("Recur", "Loop")
poly specializations combine
```

The same grammar can be selected explicitly:

```text
infer fn combine(a, b) {
    return a + b
}
```

or preferred inside a block while every other loaded grammar remains active:

```text
infer {
    fn combine(a, b) {
        return a + b
    }
}

print combine(2, 3)
```

`infer { ... }` is only LanguageKit's dynamically scoped ambiguity preference;
it does not create another lexicon or language mode. `poly fn` publishes a normal
LanguageKit callable, so ordinary core expressions can call it directly. `print`
is always the ordinary RecurLoop/core phrase.

## Native lazy specialization

For:

```text
poly fn combine(a, b) {
    return a + b
}
```

definition creates no specialization. The first `combine(1, 2)`:

1. observes `(integer, integer)`;
2. clones/annotates the parser tree only for specialization-time inference;
3. emits a native RecurLoop function body using the shared `LanguageKit:Call`
   ABI;
4. calls `context:function:compile`;
5. RecurLoop parses and compiles that body into a relocatable native module;
6. the normal JIT linker materializes a process-local entry address;
7. the address is cached on the specialization and invoked directly.

A later integer call resolves directly to the same compiled entry. The first text call creates a
separate `(text,text)` specialization. The observable report deliberately
contains `compiled=1` so tests prove that a native entry exists:

```text
combine specializations=2
  (integer,integer) -> integer compiled=1
  (text,text) -> text compiled=1
```

Recursive functions use the same specialization cache. Calls between inferred
functions and Go/C++/Haskell/Erlang/other LanguageKit callables cross the common
boxed ABI, while each inferred specialization itself executes as compiled
native RecurLoop code.

## Supported subset

- `poly fn name(args...) { ... }` or selected/preferred `fn name(args...)`;
- omitted argument and result annotations;
- lazy specialization by runtime argument-kind tuple;
- native JIT entry cached per specialization;
- integer and text literals;
- local `let` / `var`, reassignment, `if` / `else`, `return`;
- arithmetic, comparisons, equality and boolean operators;
- type-directed `+` for integer addition or text concatenation;
- calls to any callable published through LanguageKit;
- functions published back through the same LanguageKit callable ABI;
- recursive inferred functions;
- ordinary core expressions and `print` can call inferred functions directly;
- `poly specializations function` diagnostics;
- `infer <form>` explicit selection and `infer { ... }` preference blocks;
- phrase-backed visibility through `inferred_assert`.

The current generated-call helpers support up to six call arguments. The
compatibility experiment still focuses on integer/text values; it does not yet
implement unions, arbitrary structural records, specialization eviction,
megamorphic fallback, closures, floating point or a whole-program static solver.
Tracing GC is deliberately not part of this model: boxed LanguageKit values use
deterministic scopes/ownership around the compiled specialization boundary.

## What is and is not dynamic

Source syntax is dynamic/type-light:

```text
poly fn twice(x) {
    return x * 2
}
```

but execution after first use is native:

```text
first twice(integer)
    -> infer signature
    -> compile native specialization
    -> cache JIT entry

later twice(integer)
    -> cached native entry
```

The remaining dynamic part is the LanguageKit boundary: a cross-language call
looks up the callable and passes boxed `LanguageKit:Value*` arguments. Inside a
specialization, known integer/text operations are emitted to native compiled
helpers rather than walked by an AST interpreter.

## Build and test

Rebuild the host after changing the language/runtime bridge because the
ordinary core expression parser and LanguageKit callable registry share the
generic Context API boundary:

```bash
make build BUILD_TYPE=Debug
examples/07-workflows/inferred-language/run-tests.sh build/Release/bin/recurloop
```

Or run the repository integration path:

```bash
make example EXAMPLE=07-workflows/inferred-language
make example EXAMPLE=07-workflows/polyglot-showcase
```

The resulting reusable language image remains:

```text
/tmp/recurloop-inferred-library.rli
```

JIT addresses are process-local and are intentionally materialized again after
an engine image is imported, following the same native-module model used by
ordinary RecurLoop compiled functions.
