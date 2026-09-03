# RecurLoop Amber language compatibility experiment

Among the current foreign-language experiments, Amber maps most directly onto
RecurLoop's native phrase and imperative execution model.

This workflow demonstrates how much of another language can be represented by
composing and extending the RecurLoop lexicon rather than by embedding a
separate whole-language interpreter.

The compatibility image is written entirely in RecurLoop source. It combines:

- direct phrase aliases for Amber spellings such as `and`, `or`, and `not`;
- source-defined phrases for `fun`, `for`, command modifiers, error handlers,
  interpolation, arrays, and top-level assignments;
- a phrase-graph command grammar for `$ ... $`, pipelines, redirections, and
  interpolation;
- RecurLoop's normal expression evaluator, `if`/`else`, typed `fn` compiler,
  Context values, source blocks, and native FFI;
- a custom POSIX process runtime only for semantics that RecurLoop itself does
  not provide, such as pipelines, `fork`, `execvp`, redirection, and capture.

This is **not a complete Amber implementation**.

It is a compatibility experiment intended to answer a narrower architecture
question:

> How far can an independently designed imperative language be represented as
> a loadable RecurLoop language image while continuing to use RecurLoop's
> ordinary phrase, expression, and function machinery?

## Relationship to Amber

Amber is an independent programming language project.

This compatibility experiment is not affiliated with, maintained by, sponsored
by, or endorsed by the Amber project or its contributors.

The implementation in `library.rl` is a RecurLoop compatibility layer. It is
not a translation of the Amber compiler and does not add a dedicated Amber
parser or whole-language evaluator to the RecurLoop C++ host.

The name "Amber" is used here only to identify the language syntax and behavior
being exercised by the compatibility experiment.

## Phrase-backed symbols

User-visible foreign names are mirrored into the RecurLoop lexicon.

The image contains the stable dictionaries:

```text
Amber
├── Symbols
├── Functions
├── Variables
├── Arrays
├── Types
├── Builtins
└── Grammar
```

For example, after the basic-syntax sample is elaborated, `name` and `fruits`
are present as RecurLoop phrases. `fruits` is also registered in
`Amber:Arrays`.

A function created through the compatibility `fun` path is present in
`Amber:Functions` in addition to the normal typed function phrase installed by
RecurLoop.

The regression suite verifies phrase visibility using the RecurLoop-side
helper:

```text
amber_assert variable name
amber_assert array fruits
amber_assert function amber_add
```

`amber_assert` consults only Context phrase dictionaries. It does not inspect
Amber compatibility array storage or ordinary Context runtime values.

A successful assertion is therefore evidence that the foreign declaration is
actually represented in the RecurLoop lexicon.

## Supported subset

The current compatibility image includes:

- Amber-style mutable `let` for ordinary runtime values;
- text interpolation consumed by compatibility builtins;
- array forms exercised by the compatibility tests;
- source-defined `for ... in ...` iteration;
- `and`, `or`, and `not` aliases;
- Amber-shaped `fun` compatibility paths;
- `$ command $` statements and command expressions;
- pipelines and output redirection;
- command interpolation;
- command capture;
- command result handling;
- small Amber-style builtins used by the tests.

Where Amber syntax maps naturally onto existing RecurLoop behavior, the
compatibility layer deliberately reuses normal RecurLoop expressions,
functions, Context values, and phrase dispatch instead of inserting a separate
Amber evaluator.

## Unchanged compatibility sample

`tests/basic-syntax.ab` is the Amber basic-syntax sample used by this
experiment.

It exercises:

- mutable `let`;
- text interpolation;
- `if`/`else`;
- multiline arrays;
- comments;
- trailing commas;
- `for ... in ...`.

The sample runs unchanged after importing the language image.

It is kept as a compatibility fixture so the experiment can answer a concrete
question:

> Can RecurLoop execute an existing Amber-shaped source example without
> rewriting that example into native RecurLoop syntax?

The sample is upstream material and is not presented as original RecurLoop
source.

## Build and test

From the repository root:

```bash
build/Debug/bin/recurloop \
  --file examples/07-workflows/amber-language/library.rl
```

The image is written to:

```text
/tmp/recurloop-amber-library.rli
```

Run the showcase:

```bash
build/Debug/bin/recurloop \
  --import /tmp/recurloop-amber-library.rli \
  --file examples/07-workflows/amber-language/showcase.ab
```

Run the compatibility regression suite:

```bash
examples/07-workflows/amber-language/run-tests.sh \
  build/Debug/bin/recurloop
```

The workflow also participates in the normal repository examples integration:

```bash
make example EXAMPLE=07-workflows/amber-language
make examples
```

## Runtime architecture

Amber is intentionally useful as the phrase-native end of the compatibility
spectrum.

Most of its language frontend is implemented through RecurLoop phrase
machinery:

```text
Amber-compatible source
        |
        v
RecurLoop phrase grammar
        |
        +----> aliases / compatibility phrases
        |
        +----> variables / arrays / functions
        |
        +----> command phrase graph
        |
        v
ordinary RecurLoop expressions and functions
        |
        +----> POSIX command runtime where required
        |
        v
execution
```

There is no standalone Amber AST/evaluator sitting between ordinary
Amber-compatible expressions and RecurLoop's normal expression/function
machinery.

The POSIX command process engine and several compatibility structures are
custom runtime code, but they are used for the semantics that do not already
exist in RecurLoop.

## Current scope

This experiment deliberately does not claim complete Amber compatibility.

A feature is considered supported only when the compatibility layer and its
regression tests exercise that behavior. Similar-looking native RecurLoop
syntax is not, by itself, treated as evidence of Amber compatibility.

The purpose of this workflow is architectural validation rather than complete
language coverage.

## What this experiment demonstrates

Amber provides the phrase-native positive control for the foreign-language
experiments.

The important result is not merely that RecurLoop can recognize Amber-like
syntax. It is that a substantial imperative compatibility layer can be
constructed primarily by extending RecurLoop's phrase system while continuing
to use the host language's normal expression and function machinery.

This makes Amber materially different from the Haskell, Prolog, and Erlang
experiments:

```text
Amber
    phrase-oriented imperative compatibility

Prolog
    custom logical runtime + unification + backtracking

Haskell
    custom lazy runtime + currying + pattern matching

Erlang
    custom actor runtime + mailboxes + selective receive
```

The latter languages require custom parsers or semantic runtimes for constructs
that do not map naturally onto RecurLoop's existing expression model. Their
user-visible names are nevertheless interned as RecurLoop phrases and used as
canonical identities by those runtimes.
