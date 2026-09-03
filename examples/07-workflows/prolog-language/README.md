# RecurLoop Prolog language compatibility experiment

This workflow is a stress test of RecurLoop's language-extension model.

Unlike the Amber and shell examples, Prolog does not share RecurLoop's normal
imperative execution model. Predicate calls may produce more than one result,
variables are logical variables rather than mutable storage, and execution
requires unification, choice points, rollback, and backtracking.

The implementation in `library.rl` is written entirely in RecurLoop source.

The C++ host contains no Prolog-specific parser, AST, logical-variable type,
unifier, trail, clause solver, or backtracking engine.

This is **not a complete ISO Prolog implementation**.

It is a deliberately small compatibility layer designed to answer a narrower
architecture question:

> Can a loadable RecurLoop language image introduce a substantially different
> execution model without adding a dedicated language implementation to the
> host?

## Build the language image

From the repository root:

```bash
build/Debug/bin/recurloop \
  --file examples/07-workflows/prolog-language/library.rl
```

The library exports:

```text
/tmp/recurloop-prolog-library.rli
```

Run the showcase in a fresh process:

```bash
build/Debug/bin/recurloop \
  --import /tmp/recurloop-prolog-library.rli \
  --file examples/07-workflows/prolog-language/showcase.pl
```

Or use the repository Makefile integration:

```bash
make example EXAMPLE=07-workflows/prolog-language
make examples
```

`make examples` rebuilds the image and runs the compatibility regression suite.

There is intentionally no separate `make prolog` target; this workflow behaves
like the other entries under `examples/07-workflows/`.

## Supported subset

The current image supports:

- lowercase atoms and quoted atoms;
- signed decimal integers;
- logical variables beginning with an uppercase letter or `_`;
- anonymous `_` variables;
- compound terms;
- facts;
- rules with `:-`;
- conjunction with `,`;
- explicit queries with `?-`;
- structural unification with `=`;
- `true` and `fail`;
- `[]`, ordinary lists, and `[Head | Tail]`;
- recursive predicates;
- ordered clause choice points;
- depth-first search;
- trail-based binding rollback;
- automatic enumeration of every solution in non-interactive queries.

For example:

```prolog
parent(tom, bob).
parent(bob, ann).
parent(bob, pat).
parent(pat, jim).

ancestor(X, Y) :-
    parent(X, Y).

ancestor(X, Y) :-
    parent(X, Z),
    ancestor(Z, Y).

?- ancestor(tom, X).
```

produces:

```text
X = bob.
X = ann.
X = pat.
X = jim.
```

The classic `member/2` relation is implemented as ordinary Prolog source rather
than as a RecurLoop builtin:

```prolog
member(X, [X | _]).

member(X, [_ | Tail]) :-
    member(X, Tail).

?- member(X, [1, 2, 3]).
```

which produces:

```text
X = 1.
X = 2.
X = 3.
```

## Why this experiment is different

Amber can reuse a large amount of RecurLoop's existing imperative semantics.

This experiment cannot.

The `.rli` image introduces a separate logical runtime:

```text
Prolog source
    |
    v
empty-key top-level clause phrase / explicit ?- phrase
    |
    v
Prolog parser written in .rl
    |
    +--> raw clause database
    |
    v
runtime terms and logical variables
    |
    v
unification
    |
    v
trail + choice points
    |
    v
depth-first resolution and backtracking
    |
    v
solution bindings
```

The clause database deliberately retains source text. A matching clause is
reparsed each time the solver enters that choice point.

This gives recursive invocations fresh logical variables without requiring a
special variable-frame facility in the host.

Unification uses mutable binding cells only internally. Every variable binding
is recorded on a `Prolog:Trail`.

Before trying another clause, the solver restores the trail to the
choice-point mark, removing bindings created by the failed or completed branch.

The regression test:

```prolog
choice(a).
choice(b).

pair(X, Y) :-
    choice(X),
    choice(Y).

?- pair(X, Y).
```

must produce:

```text
X = a, Y = a.
X = a, Y = b.
X = b, Y = a.
X = b, Y = b.
```

The final two answers are impossible unless bindings from the `X = a` choice
point are actually rolled back.

## RecurLoop phrase integration

The parser and backtracking runtime are Prolog-specific, but user-visible names
are not private strings owned only by that runtime.

The RecurLoop lexicon is the canonical identity registry for user-visible
Prolog symbols:

```text
Prolog
├── Symbols
├── Predicates
├── Atoms
├── Variables
├── Builtins
├── Operators
└── Grammar
```

Predicate dispatch and structural term unification use phrase identity.

A logical variable still has a clause-local binding cell, as required by the
compatibility semantics, but its spelling is interned as a phrase.

`?-` is a real RecurLoop phrase.

Arbitrary predicate clauses still use the top-level fallback and the custom
Prolog term parser because the current RecurLoop host has no per-source
language root that could safely hand every arbitrary functor token to a Prolog
phrase graph without conflicting with existing root phrases.

The regression suite verifies phrase visibility with:

```text
prolog_assert predicate ancestor
prolog_assert atom parent
prolog_assert variable X
prolog_assert builtin true
prolog_assert operator :-
```

These assertions consult only Context phrase dictionaries, not the Prolog
clause database.

## Query behavior

This compatibility layer is deliberately batch-oriented.

A query such as:

```prolog
?- member(X, [1, 2, 3]).
```

automatically enumerates every solution instead of pausing after the first one
for the traditional interactive `;` prompt.

A query with no named variables prints:

```text
true.
```

when at least one proof exists, and:

```text
false.
```

when no proof exists.

## Tests

Run directly:

```bash
examples/07-workflows/prolog-language/run-tests.sh \
  build/Debug/bin/recurloop
```

The suite currently checks:

- `tests/family.pl` — recursive rules and fresh variables;
- `tests/lists.pl` — list construction, list unification, and recursive
  `member/2`;
- `tests/backtracking.pl` — nested choice points and trail rollback;
- `tests/unification.pl` — structural unification and repeated-variable
  constraints;
- `tests/failure.pl` — ground success/failure plus the `true` and `fail`
  builtins.

All tests execute in fresh processes after importing the generated engine
image.

## Architectural limitation exposed by the experiment

The experiment has identified a real boundary in the current RecurLoop
abstraction.

The Prolog clause parser is installed as the root dictionary's empty-key
fallback. Longest-prefix lookup therefore still gives an existing RecurLoop
root phrase priority over the fallback.

For example:

```prolog
print(foo).
```

can collide with RecurLoop's existing top-level `print` phrase.

At the moment, `print` is resolved as the RecurLoop phrase before the Prolog
fallback can consume the clause.

This does not affect the compatibility tests, but it is architecturally
important:

> A fully isolated foreign-language image needs a way to select or replace the
> top-level root grammar for a source unit rather than merely extending the
> shared root dictionary.

The limitation is intentionally documented instead of being hidden behind a
list of hard-coded conflicting predicate names.

Fixing it generically in the language/context model would strengthen the
architecture. Adding a Prolog-specific exception in C++ would defeat the
purpose of the experiment.

## Current limitations

This experiment does not currently implement:

- ISO operator declarations and the full Prolog token/operator grammar;
- `;` disjunction;
- cut (`!`);
- negation as failure;
- arithmetic evaluation and `is`;
- numeric comparison predicates;
- modules;
- dynamic predicates;
- DCGs;
- exceptions;
- I/O and streams;
- attributed variables or constraint logic programming;
- tabling;
- an occurs check;
- safe rendering of cyclic/rational trees;
- the traditional interactive semicolon-driven query loop.

A single captured top-level statement is also limited to 1 MiB in this
experiment.

## Files

```text
prolog-language/
├── README.md
├── library.rl
├── run-tests.sh
├── showcase.pl
└── tests/
    ├── backtracking.pl
    ├── failure.pl
    ├── family.pl
    ├── lists.pl
    └── unification.pl
```

`library.rl` is the only implementation file.

The `.pl` files contain ordinary Prolog-style source for the supported subset
and do not contain RecurLoop wrappers.

## What this experiment demonstrates

The important result is not that RecurLoop contains a production Prolog
implementation.

The experiment demonstrates that a reusable language image written in
RecurLoop can introduce:

- foreign concrete syntax;
- its own parser;
- runtime terms and logical variables;
- a clause database;
- structural unification;
- reversible bindings;
- choice points;
- recursive resolution;
- backtracking;
- multiple solutions for a single query.

without adding those concepts as dedicated facilities to the C++ host.

This tests whether RecurLoop's extension model can change not only source
grammar but also fundamental assumptions about how programs execute.
