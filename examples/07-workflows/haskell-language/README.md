# RecurLoop Haskell language compatibility experiment

This workflow is a deliberately hostile test of RecurLoop's language-extension
model.

Haskell differs from RecurLoop not only in surface syntax but also in its
execution model: function application is curried, values are non-strict,
arguments are represented by thunks, algebraic data constructors participate
in pattern matching, and multiple equations select a function body by patterns.

The implementation in `library.rl` is written entirely in RecurLoop source.

The C++ host contains no Haskell parser, Haskell AST, thunk runtime,
algebraic-data-type runtime, currying engine, or Haskell-specific pattern
matcher.

This is **not a complete Haskell implementation** and should not be presented as
one.

It is a compact compatibility experiment intended to answer a narrower
architecture question:

> Can a loadable RecurLoop language image introduce a lazy functional execution
> model without adding a dedicated language implementation to the host?

## Build the language image

From the repository root:

```bash
build/Debug/bin/recurloop \
  --file examples/07-workflows/haskell-language/library.rl
```

The library exports:

```text
/tmp/recurloop-haskell-library.rli
```

Run the showcase in a fresh process:

```bash
build/Debug/bin/recurloop \
  --import /tmp/recurloop-haskell-library.rli \
  --file examples/07-workflows/haskell-language/showcase.hs
```

Or use the normal examples integration:

```bash
make example EXAMPLE=07-workflows/haskell-language
make examples
```

There is intentionally no separate `make haskell` target.

## Supported subset

The current image supports:

- decimal `Int` values;
- `+`, `-`, and `*`;
- ordinary Haskell-style function application by whitespace;
- curried functions and partial application;
- higher-order functions;
- recursive functions;
- multiple function equations;
- variable, wildcard, and integer patterns;
- algebraic constructor patterns;
- `data` declarations sufficient to register simple constructors;
- `[]`, list literals, and the `(:)` constructor;
- list-cons patterns such as `(x:xs)`;
- call-by-need argument thunks with memoization;
- recursive infinite bindings when only a finite portion is demanded;
- `print` and `div` as small runtime builtins;
- top-level type-signature lines containing `::`, parsed for source
  compatibility and symbol registration but not type-checked or enforced.

For example:

```haskell
factorial :: Int -> Int
factorial 0 = 1
factorial n = n * factorial (n - 1)

main :: IO ()
main = print (factorial 6)
```

produces:

```text
720
```

## RecurLoop phrase integration

The current implementation deliberately does **not** treat the Haskell AST as a
second, unrelated symbol universe.

Every identifier is interned in the RecurLoop lexicon and the evaluator carries
the resulting phrase identity alongside the syntax node.

The image exposes:

```text
Haskell
├── Symbols
├── Functions
├── Values
├── Constructors
├── Types
├── Variables
├── Builtins
└── Grammar
```

Function-equation selection, constructor matching, environment lookup, and
builtin dispatch use phrase identity rather than string comparison.

`data` is also a real top-level RecurLoop phrase rather than going through the
generic fallback.

A custom parser/AST remains necessary for whitespace application, precedence,
Haskell patterns, and lazy syntax, while thunks and currying remain custom
semantic runtime state.

The regression suite proves that symbols are visible from RecurLoop itself:

```text
haskell_assert function fromMaybe
haskell_assert constructor Just
haskell_assert type Maybe
haskell_assert variable x
```

`haskell_assert` consults only Context phrase dictionaries.

## Currying

Partial application is a runtime value rather than a syntax rewrite:

```haskell
add x y = x + y

inc = add 1

main = print (inc 41)
```

produces:

```text
42
```

The evaluator represents `add` as an arity-2 callable.

Applying the first argument creates a new callable carrying one lazy argument;
only the second application selects and evaluates the function equation.

## Algebraic data and pattern matching

A source-level declaration registers constructors with the language runtime:

```haskell
data Maybe a = Nothing | Just a

fromMaybe d Nothing = d
fromMaybe _ (Just x) = x

main = print (fromMaybe 0 (Just 42))
```

produces:

```text
42
```

Constructor fields are themselves thunks.

Matching a constructor forces only the outer value to weak-head normal form;
variable and wildcard patterns do not force the values they bind or discard.

## Higher-order functions

The regression suite contains a source-defined `mapList`:

```haskell
mapList f [] = []
mapList f (x:xs) = f x : mapList f xs

double x = x * 2

main = print (mapList double [1,2,3])
```

which produces:

```text
[2,4,6]
```

`mapList` is not a builtin.

Both `f` and every list element travel through the same thunk/application
machinery as ordinary user functions.

## Laziness

The compatibility runtime uses call-by-need argument thunks with memoization.

The test suite intentionally contains an expression that would fail under
strict evaluation:

```haskell
first x _ = x

main = print (first 42 (div 1 0))
```

The result is:

```text
42
```

`div 1 0` is never evaluated because the wildcard pattern never demands the
second argument.

An even stronger test uses an infinite definition:

```haskell
ones = 1 : ones

takeList 0 _ = []
takeList n (x:xs) = x : takeList (n - 1) xs

main = print (takeList 5 ones)
```

and terminates with:

```text
[1,1,1,1,1]
```

This requires the evaluator to construct and inspect only the demanded prefix
rather than eagerly expand `ones`.

## Runtime architecture

The imported image builds a process-local runtime only after Haskell source is
loaded:

```text
Haskell source
    |
    v
empty-key top-level phrase fallback
    |
    v
line-oriented parser written in .rl
    |
    +--> constructor table
    +--> ordered function equations
    |
    v
lazy expression evaluator
    |
    +--> thunks + memoization
    +--> curried callable values
    +--> pattern-driven equation selection
    +--> algebraic constructor values
    |
    v
main
```

All process pointers are created after the `.rli` image is imported.

They are stored in context-local runtime state and are not serialized into the
image.

### Mutual recursion inside the compatibility runtime

Implementing laziness naturally creates a cycle:

```text
eval -> apply -> pattern match -> force -> eval
```

RecurLoop currently does not provide ordinary forward declarations for named
function implementations.

The compatibility layer therefore uses one recursive typed dispatcher and
passes it into helper functions as a structural function value.

This keeps the implementation entirely in `.rl` and also exercises RecurLoop's
typed callback support.

## Tests

Run directly:

```bash
examples/07-workflows/haskell-language/run-tests.sh \
  build/Debug/bin/recurloop
```

The suite checks:

- `factorial.hs` — recursion, multiple equations, and integer patterns;
- `currying.hs` — partial application;
- `algebraic-data.hs` — `data` constructors and constructor patterns;
- `constructor-value.hs` — construction and rendering of an ADT value;
- `higher-order.hs` — function values and recursive list processing;
- `lazy.hs` — an unused `div 1 0` argument must never be forced;
- `infinite-list.hs` — a finite prefix of an infinite recursive list;
- `non-exhaustive.hs` — failed pattern selection must produce a diagnostic.

## Current limitations

This experiment deliberately stops well before full Haskell compatibility.

Not implemented yet are, among other things:

- Hindley-Milner type inference or any real type checking;
- type classes and instances;
- modules and imports;
- strings, characters, and tuples;
- guards;
- `where` and local `let`;
- lambdas;
- `case`;
- records;
- list comprehensions;
- `do` notation and general monadic I/O;
- exceptions;
- deriving;
- numeric type classes;
- the full Haskell layout rule.

For simplicity, this subset expects one top-level declaration per physical line.

Type signatures are parsed for source compatibility and symbol registration,
but their types are not semantically checked or enforced.

## Architectural limitation exposed by the experiment

Like the Prolog experiment, the language currently uses an empty-key fallback
in the root lexicon.

A top-level name that already exists as a longer RecurLoop phrase can therefore
be claimed by the host before the Haskell fallback sees it.

A first-class per-source language root would remove that collision.

This is useful architectural evidence because the same boundary appears across
multiple independently implemented compatibility layers rather than only in
Haskell.

## What this experiment demonstrates

Amber mostly reuses RecurLoop's imperative semantics.

Prolog replaces them with unification and backtracking.

This Haskell experiment stresses another axis: **non-strict functional
evaluation**.

The important result is not the number of Haskell features implemented. It is
that the same RecurLoop language-image mechanism can host:

```text
imperative / native RecurLoop
shell command semantics
Amber-compatible syntax
Prolog unification + backtracking
Haskell-style currying + lazy thunks + pattern matching
```

without adding a dedicated Haskell parser or runtime implementation to the C++
host.

Instead, the Haskell-specific parser and semantic runtime are implemented in
RecurLoop source while their user-visible symbols remain integrated with the
RecurLoop lexicon.
