# RecurLoop Erlang language compatibility experiment

This workflow is a stress test of RecurLoop's language-extension model using an
execution model that is very different from ordinary RecurLoop code.

Erlang is built around lightweight processes, immutable single-assignment
variables, pattern matching, asynchronous message passing, per-process
mailboxes, and selective receive.

The implementation in `library.rl` is written entirely in RecurLoop source.

The C++ host contains no Erlang parser, Erlang AST, process scheduler, mailbox,
selective-receive engine, tuple runtime, or Erlang-specific pattern matcher.

This is **not a complete Erlang/OTP implementation** and it does not attempt to
emulate BEAM.

It is a compact compatibility experiment intended to answer a narrow
architecture question:

> Can a loadable RecurLoop language image introduce an actor-oriented execution
> model, including mailbox semantics, without adding a dedicated language
> implementation to the host?

The supported syntax follows ordinary Erlang forms such as `-module`, `-export`,
function clauses terminated by `.`, `Pid ! Message`, `receive ... end`, and
`fun name/arity` references.

## Build the language image

From the repository root:

```bash
build/Debug/bin/recurloop \
  --file examples/07-workflows/erlang-language/library.rl
```

The library exports:

```text
/tmp/recurloop-erlang-library.rli
```

Run the showcase in a fresh process:

```bash
build/Debug/bin/recurloop \
  --import /tmp/recurloop-erlang-library.rli \
  --file examples/07-workflows/erlang-language/showcase.erl
```

Or use the normal examples integration:

```bash
make example EXAMPLE=07-workflows/erlang-language
make examples
```

There is intentionally no separate `make erlang` target.

## Showcase

`showcase.erl` is ordinary Erlang syntax within the supported subset:

```erlang
-module(recurloop_erlang_showcase).
-export([main/0, worker/0, sum/2]).

sum(0, Acc) -> Acc;
sum(N, Acc) -> sum(N - 1, Acc + N).

worker() ->
    receive
        {compute, From, N} ->
            From ! ignored,
            From ! {result, sum(N, 0)}
    end.

main() ->
    Worker = spawn(fun worker/0),
    Worker ! {compute, self(), 10},
    receive
        {result, Value} -> io:format("result=~p~n", [Value])
    end,
    receive
        ignored -> io:format("mailbox-preserved~n")
    end.
```

It prints:

```text
result=55
mailbox-preserved
```

The first `receive` deliberately skips the older `ignored` message while
looking for `{result, Value}`.

The second `receive` proves that the skipped message was left in the mailbox
rather than discarded.

## Supported subset

The current image supports:

- `-module(...)` and `-export([...])` forms implemented as dedicated RecurLoop
  phrases;
- module and exported function names registered in the RecurLoop lexicon;
- integer values;
- atoms;
- strings;
- tuples such as `{ok, Value}`;
- proper list literals such as `[1, 2, 3]`;
- uppercase variables and `_`;
- single-assignment matching with `=`;
- repeated-variable constraints during pattern matching;
- function declarations and multiple clauses separated by `;`;
- strict function arguments;
- `+`, `-`, and `*` integer arithmetic;
- local function calls;
- `fun name/arity` local function references;
- `self()`;
- `spawn(Fun)` for a local arity-zero function reference;
- asynchronous `Pid ! Message`;
- one mailbox per spawned process;
- `receive Pattern -> Body; ... end`;
- selective receive that keeps unmatched messages in queue order;
- tuple/list patterns in function and receive clauses;
- `io:format/1` and `io:format/2` with the small formatting subset `~p`, `~n`,
  and `~~`;
- process-local function frames and variable bindings;
- deterministic cooperative scheduling of spawned actors.

## RecurLoop phrase integration

Erlang expressions still need a custom parser/AST and the actor model needs its
own scheduler and mailboxes, but foreign names use the RecurLoop lexicon as
their canonical identity:

```text
Erlang
├── Symbols
├── Functions
├── Variables
├── Atoms
├── Modules
├── Builtins
├── Grammar
└── Processes
```

Function-clause dispatch, local calls, fun references, atom equality, variable
environment lookup, and pattern matching carry phrase identities instead of
selecting names by string comparison.

`-module` and `-export` are dedicated phrase actions.

Arbitrary function forms still enter the custom Erlang parser through the
language fallback.

Runtime-created PID records remain actor-runtime state. Lexicon mutations
performed during runtime invocation do not currently behave like
elaboration-time language mutations, so the experiment does not claim that
live PIDs themselves are persistent language phrases.

Their function entrypoints are phrase-backed.

The regression suite checks lexicon visibility after loading a normal `.erl`
program:

```text
erlang_assert module ping_pong
erlang_assert function pong
erlang_assert variable From
erlang_assert atom ping
erlang_assert builtin spawn
```

These checks use only Context phrase lookup.

## Function clauses and strict pattern matching

Multiple Erlang equations select a function body by pattern:

```erlang
sum(0, Acc) -> Acc;
sum(N, Acc) -> sum(N - 1, Acc + N).

main() -> io:format("~p~n", [sum(100, 0)]).
```

The regression test produces:

```text
5050
```

A variable is single-assignment within a frame.

This deliberately fails:

```erlang
main() -> X = 1, X = 2.
```

with:

```text
Erlang: badmatch
```

The compatibility layer does not silently turn Erlang variables into mutable
RecurLoop locals.

## Processes and message passing

The actor test uses ordinary Erlang send and receive syntax:

```erlang
pong() ->
    receive
        {ping, From} -> From ! pong
    end.

main() ->
    Pong = spawn(fun pong/0),
    Pong ! {ping, self()},
    receive
        pong -> io:format("pong~n")
    end.
```

The runtime creates a distinct process record for `pong/0`, gives it its own
PID and mailbox, enqueues the tuple message, and runs the process when `main/0`
blocks in `receive`.

The result is:

```text
pong
```

`spawn` does not simply call the function synchronously.

It creates a runnable actor whose function is evaluated by the compatibility
scheduler.

## Selective receive

Selective receive is one of the most useful semantic tests in this workflow.

The worker sends two messages in this order:

```erlang
From ! noise,
From ! {answer, 42}
```

The caller then asks specifically for the second one:

```erlang
receive
    {answer, Value} -> io:format("answer=~p~n", [Value])
end,
receive
    noise -> io:format("noise~n")
end.
```

The output is:

```text
answer=42
noise
```

The mailbox scanner walks messages from oldest to newest and tests receive
clauses in source order.

Only the selected message is removed.

Earlier unmatched messages remain linked in the queue.

This behavior is materially different from an ordinary FIFO channel and is one
of the reasons Erlang is a useful stress test for RecurLoop.

## Scheduler model

This experiment intentionally does **not** embed a second operating-system
threading runtime or call pthreads.

Actors are process records managed by the RecurLoop compatibility layer:

```text
Erlang source
    |
    v
source-defined form parser
    |
    +--> ordered function clauses
    +--> patterns / expressions
    |
    v
strict evaluator
    |
    +--> process table
    +--> PID allocation
    +--> per-process mailbox
    +--> asynchronous send
    +--> selective receive
    |
    v
cooperative scheduler
```

`spawn(fun worker/0)` registers a runnable actor.

When a process enters a `receive` for which no current mailbox message matches,
the scheduler runs one pending actor and retries the mailbox.

This is deterministic and sufficient for the compatibility tests.

The model is deliberately much smaller than BEAM.

It does not implement preemptive reductions, scheduler fairness, SMP execution,
process heaps, copying GC, distribution, links, or monitors.

## Runtime state and engine images

The `.rli` image contains the language implementation and source-level phrase
state.

It does **not** serialize live process pointers or a live mailbox graph.

After import, the first Erlang form lazily creates a process-local runtime:

```text
.rli import
    |
    v
Erlang source arrives
    |
    v
allocate database + main process
    |
    +--> clauses
    +--> process table
    +--> mailboxes
    +--> current PID
```

This keeps process-local addresses out of the persistent language image.

## Tests

Run directly:

```bash
examples/07-workflows/erlang-language/run-tests.sh \
  "$PWD/build/Debug/bin/recurloop"
```

The suite contains:

| Test | What it checks |
|---|---|
| `arithmetic.erl` | normal calls and strict arguments |
| `function-clauses.erl` | ordered clauses and recursive accumulator style |
| `tuple-pattern.erl` | tuple destructuring and wildcard fallback |
| `ping-pong.erl` | PID creation, `spawn`, `self`, send and receive |
| `selective-receive.erl` | skipped messages stay in the mailbox |
| `main-before-worker.erl` | `main/0` is launched only after all forms are loaded |
| `mailbox-recursion.erl` | mailbox persistence across recursive actor calls |
| `badmatch.erl` | single-assignment failure |
| `deadlock.erl` | deterministic diagnostic when receive cannot make progress |

A successful run prints:

```text
[erlang] arithmetic           ok
[erlang] function-clauses     ok
[erlang] tuple-pattern        ok
[erlang] ping-pong            ok
[erlang] selective-receive    ok
[erlang] main-before-worker   ok
[erlang] mailbox-recursion    ok
[erlang] badmatch             ok
[erlang] deadlock             ok
[erlang] all compatibility tests passed
```

## What this experiment tests in RecurLoop

Erlang is useful after Amber, Prolog, and Haskell because it stresses another
orthogonal dimension:

```text
Amber
    imperative + phrase-oriented compatibility

Prolog
    unification + choice points + backtracking

Haskell
    currying + ADTs + thunks + call-by-need

Erlang
    actor processes + asynchronous mailboxes + selective receive
```

The significant result is not merely that RecurLoop can parse Erlang-like
surface syntax.

The significant result is that a `.rl` library can introduce process
identities, independent mailboxes, and receive-selection semantics while the
C++ host remains unchanged.

## Limitations

This experiment intentionally omits large parts of Erlang and OTP, including:

- anonymous `fun (...) -> ... end` closures;
- `spawn(Module, Function, Args)` and remote fun references;
- guards (`when`);
- `case`, `if`, `try`, `catch`, `after`, and receive timeouts;
- maps, binaries, bit syntax, and improper lists;
- list-cons syntax `[Head | Tail]`;
- floats and arbitrary-precision integers;
- quoted atoms and full string/Unicode semantics;
- registered process names;
- links, monitors, exits, trapping exits, and supervision trees;
- OTP behaviours such as `gen_server`;
- distributed nodes;
- BEAM bytecode;
- BEAM-style per-process heaps and garbage collection;
- preemptive reduction counting and SMP schedulers;
- hot code loading;
- exact Erlang exception classes and stack traces;
- full `io`/stdlib compatibility.

The current scheduler is cooperative and deterministic.

A spawned process runs when another process needs scheduler progress; it is not
time-sliced in parallel with the caller.

Recursive source functions work, but the compatibility layer does not claim
BEAM's tail-call stack behavior for arbitrarily deep recursion.

## Current RecurLoop boundary

As with the Prolog and Haskell experiments, the compatibility layer is
installed through an empty-key root fallback plus explicit phrases for
colliding top-level forms such as `-module` and `-export`.

That means a foreign language still shares the host root dictionary.

If a future Erlang function name collides with a stronger existing RecurLoop
root phrase, longest-prefix lookup can select the host phrase before the Erlang
fallback.

This reinforces the same architectural question exposed by the other language
experiments:

> A per-source or explicitly selected language root dictionary would let an
> imported language own its source grammar first and then choose which RecurLoop
> facilities to inherit or merge.

The experiment deliberately does not hide that limitation behind a large list
of hard-coded collision aliases.

## Reference syntax

The supported subset follows the Erlang reference-manual forms used by this
experiment:

- https://www.erlang.org/doc/system/modules.html
- https://www.erlang.org/doc/system/expressions.html
