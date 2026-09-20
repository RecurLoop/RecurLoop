# Project runtime and generations

RecurLoop can keep one initialized project alive and expose independent client
sessions over stdio and Unix sockets. The runtime deliberately separates four
lifetimes instead of sharing one mutable `Context` between clients.

```text
Project generation
  immutable, published
  sealed memfd lexicon
          |
          +-- MAP_PRIVATE --> Context generation / session A
          |                     +-- request generation 1
          |                     +-- request generation 2
          |
          +-- MAP_PRIVATE --> Context generation / session B
                                +-- request generation 3
```

## Memory model

A published `LexiconGeneration` stores one contiguous radix arena in a sealed
Linux `memfd`. Every client maps the same file with `MAP_PRIVATE`. The radix
therefore keeps its existing contiguous-address/offset model, while the kernel
shares all untouched physical pages and creates private pages only when a
session modifies them.

This is intentionally simpler than a second overlay radix or a persistent tree:
lookup remains exactly the normal RecurLoop lookup path and no phrase needs a
cross-generation indirection.

`ContextGeneration` is a runtime wrapper; it does not add fields to `context::Context`, so the existing Host ABI layout remains unchanged. It owns process-local state that cannot be shared safely:

- JIT and source-action executable mappings;
- compiler workspace;
- lookup/staging/reference cursors;
- streams, pending errors and debugger state.

Each `Session` owns exactly one context and serializes requests for that
context. Different sessions have different contexts and may execute in
parallel.

A `RequestGeneration` is a small transaction over one session. It snapshots
only the lexicon bytes currently in use rather than the entire configured arena,
and records append watermarks for JIT/workspace storage. A failed request
restores the previous bytes and cursors, including writes to existing phrase
payloads. Successful requests advance the session and lexicon generation ids.
The rollback buffer is reused by the session, so repeated requests do not keep
allocating buffers. External/native side effects are intentionally outside this
transaction: code that acquires OS or foreign-runtime resources must still use
its normal cleanup/defer discipline. Publication remains stricter and rejects a
live native pointer before it can escape into a project generation.

## Publishing

Session changes are private until explicitly published. Publication crosses the
normal engine-image persistence boundary first:

1. encode the session semantic state as an `EngineImage`;
2. restore it into a clean runtime context;
3. bind the stable Host ABI;
4. capture that clean lexicon into a new sealed `LexiconGeneration`;
5. atomically replace the project's current generation.

Consequently a live process-local pointer prevents publication instead of
escaping from the client that owns it. Existing sessions continue on their old
shared generation until they refresh; new sessions immediately use the new one.

## Unified command-line execution

The CLI no longer has a separate batch execution path. After core/import
initialization, every mode creates a `Project` and executes source through a
`Session`/`RequestGeneration`:

```text
--file / --string / piped stdin -> one-shot Session request
terminal `-` / no source        -> stdio Session transport
--serve --file app.rl           -> bootstrap Session -> publish -> Server
Unix socket                     -> independent Session per client
```

Startup operations (`--reset`, `--import`, `--library`, `--library-path`) are
still applied before the project snapshot. The remaining argv is preserved
verbatim and passed to `Session::executeArguments()`, so source code that owns
trailing arguments (for example `--file library.rl -- output.rli`) keeps the
same semantics. `Recurloop::execute()` remains available as a low-level API,
but the normal executable entry point does not bypass the project/session
runtime.

## Server

Start a project runtime on stdio and a Unix socket:

```bash
build/Release/bin/recurloop \
  --library shell \
  --serve \
  --unix /tmp/recurloop.sock
```

For a daemon without a stdio client:

```bash
build/Release/bin/recurloop \
  --library shell \
  --serve \
  --unix /tmp/recurloop.sock \
  --no-stdio
```

Every Unix connection gets a new session. For an interactive terminal, use the
built-in console client:

```bash
build/Release/bin/recurloop --connect /tmp/recurloop.sock
```

It uses the same line editor as the local stdio REPL, including independent
history, Ctrl+Left/Right word movement, Home/End, editing keys and Ctrl+C to
cancel the current input line. The Unix protocol itself stays line-oriented, so
a non-interactive client can still use `socat` or a normal socket API without
having terminal escape handling mixed into the request protocol:

```bash
printf 'print 42\n:quit\n' | socat - UNIX-CONNECT:/tmp/recurloop.sock
```

 A line that does not
start with `:` is evaluated as one RecurLoop source request. Transport commands
are:

```text
:generations   show project/lexicon/context/session/request ids
:publish       publish this session as the next project generation
:refresh       discard private session changes and attach the latest project
:load <path>   evaluate one source file in this session
:help          show transport commands
:quit          close this client
```

The ordinary language-level `exit` also exits an interactive console. On the
server's stdio console it ends the RecurLoop process (and therefore the server);
on a Unix client it closes only that client session. EOF/Ctrl+D has the same
session-local meaning. Ctrl+C while editing discards the unfinished line and
returns to the `> ` prompt without creating a request.

Stdio and Unix sockets are transport adapters only. They do not own language
state. Future HTTP/WebSocket/LSP adapters should open/use the same `Session`
and `RequestGeneration` objects rather than adding another execution model.
