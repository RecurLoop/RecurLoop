# RecurLoop HTTP language

A small HTTP/1.1 server runtime and routing syntax implemented in RecurLoop
source.

The C++ host contains no HTTP parser, router, request model, or socket server.
The library uses RecurLoop's C FFI for POSIX sockets and exposes a
source-defined `http` construct for routing.

## Quick start

Build the reusable engine image:

```bash
recurloop --file examples/07-workflows/http-language/library.rl
```

This writes:

```text
/tmp/recurloop-http-library.rli
```

Run an application through the image:

```bash
recurloop \
  --import /tmp/recurloop-http-library.rli \
  --file examples/07-workflows/http-language/showcase.rl
```

The showcase listens on `127.0.0.1:8080`.

```bash
curl http://127.0.0.1:8080/
curl http://127.0.0.1:8080/health
curl 'http://127.0.0.1:8080/hello?name=Alice'
curl -X POST --data-binary 'hello' http://127.0.0.1:8080/echo
```

## Routing syntax

Handlers are ordinary typed RecurLoop functions:

```rl
let home = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.html(200, "<h1>Hello from RecurLoop</h1>\n")
}

let health = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.json(200, "{\"status\":\"ok\"}\n")
}

let echo = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.send(
        200,
        "application/octet-stream",
        request.body,
        request.body_length
    )
}
```

The route table is language syntax defined by `library.rl`:

```rl
let main = fn () -> i64 {
    http "127.0.0.1" 8080 {
        GET  "/"       -> home
        GET  "/health" -> health
        POST "/echo"   -> echo
    }

    return 0
}

main()
```

The `http` phrase captures its block and emits ordinary typed RecurLoop calls
roughly equivalent to:

```rl
let __http_server = Http:Server:new_on(8080, "127.0.0.1")
defer Http:Server:destroy(__http_server)

__http_server.route("GET", "/", home)
__http_server.route("GET", "/health", health)
__http_server.route("POST", "/echo", echo)

__http_server.run()
```

No HTTP-specific C++ parser is involved.

## Request API

`Http:Request` exposes borrowed request data valid for the duration of the
handler:

```rl
request.method
request.target
request.path
request.query
request.version
request.body
request.body_length
```

Headers are case-insensitive:

```rl
let content_type = request.header("Content-Type")
```

Query parameters are percent-decoded and request-owned:

```rl
let name = request.param("name")
if name {
    response.text(200, name)
}
```

For:

```text
/hello?name=Recur%20Loop
```

`request.param("name")` returns:

```text
Recur Loop
```

The returned text is automatically released with the request.

## Response API

Convenience responses:

```rl
response.text(200, "hello\n")
response.html(200, "<h1>hello</h1>\n")
response.json(200, "{\"ok\":true}\n")
response.empty(204)
```

Binary or explicitly sized output:

```rl
response.send(
    201,
    "application/octet-stream",
    request.body,
    request.body_length
)
```

Custom headers must be set before sending the response:

```rl
response.header("Cache-Control", "no-store")
response.header("X-Powered-By", "RecurLoop")
response.json(200, "{\"status\":\"ok\"}\n")
```

Responses automatically contain:

```text
Content-Length
Content-Type
Connection: close
```

A handler that does not send a response produces `204 No Content`.

## Matching

Methods are matched case-insensitively.

Supported route methods are not hard-coded by the router: the DSL copies the
method spelling into the route table. Common examples are:

```text
GET
POST
PUT
PATCH
DELETE
OPTIONS
HEAD
ANY
```

`ANY` matches every method.

Exact paths:

```rl
GET "/api/status" -> status
```

A trailing `*` performs prefix matching:

```rl
GET "/assets/*" -> assets
```

A catch-all route can therefore be expressed as:

```rl
ANY "/*" -> fallback
```

The request path excludes the query string, so:

```text
GET /hello?name=Ada
```

matches:

```rl
GET "/hello" -> hello
```

A `HEAD` request can use a matching `GET` route. The handler runs normally,
but the response body is suppressed while `Content-Length` still describes the
corresponding body.

## Deterministic one-request mode

For tests and small examples:

```rl
http once "127.0.0.1" 18080 {
    GET "/" -> home
}
```

This accepts one connection, handles it, closes it, and returns to the calling
RecurLoop function.

## Direct server API

The routing DSL is optional:

```rl
let main = fn () -> i64 {
    let server = Http:Server:new_on(8080, "127.0.0.1")
    if !server { return 1 }
    defer server.destroy()

    server.route("GET", "/", home)
    server.route("GET", "/health", health)
    server.run()

    return 0
}
```

Available lifecycle operations include:

```text
Http:Server:new(port)
Http:Server:new_on(port, address)
server.route(method, path, handler)
server.on_not_found(handler)
server.serve_once()
server.run()
server.destroy()
```

## Runtime architecture

The server is deliberately implemented above the host:

```text
RecurLoop source
    |
    +-- `http` source rewrite
    |      |
    |      +-- route declarations
    |      +-- typed handler references
    |
    +-- Http:Server / Request / Response
    |
    +-- HTTP/1.1 request parser
    |
    +-- POSIX C FFI
           |
           +-- socket
           +-- setsockopt
           +-- bind
           +-- listen
           +-- accept
           +-- recv
           +-- send
           +-- shutdown
           +-- close
```

The engine image persists the RecurLoop-side language/runtime definitions.
Application handlers are compiled after importing the image.

## Current scope

This is a real socket server and is useful as an extensibility example, but it
is intentionally not presented as a production replacement for mature HTTP
servers.

Implemented:

- IPv4 TCP listeners;
- configurable bind address and port;
- HTTP/1.1 request-line parsing;
- request headers;
- `Content-Length` request bodies;
- exact and trailing-wildcard routes;
- typed RecurLoop handler callbacks;
- query-string access and percent-decoding;
- text, HTML, JSON, empty, and binary responses;
- custom response headers;
- automatic `Content-Length`;
- `HEAD` through matching `GET` routes;
- built-in `404 Not Found`;
- reusable `.rli` engine image;
- deterministic one-request mode for tests.

Not implemented yet:

- TLS/HTTPS;
- HTTP/2 or HTTP/3;
- chunked request bodies;
- persistent keep-alive connections;
- multipart/form-data parsing;
- WebSockets;
- streaming responses;
- asynchronous I/O / epoll;
- worker pools;
- production-grade request smuggling / slow-client hardening;
- configurable request limits beyond the current 1 MiB request cap.

The current `run()` loop handles connections sequentially and closes each
connection after one request. That keeps the implementation small enough to
serve as an understandable RecurLoop language/runtime example.

## Tests

```bash
examples/07-workflows/http-language/run-tests.sh \
  "$(realpath build/Release/bin/recurloop)"
```

The regression runner verifies:

- reusable image creation;
- route dispatch;
- case-insensitive request headers;
- percent-decoded query parameters;
- POST request bodies;
- wildcard routes;
- 404 responses;
- HEAD-to-GET behavior.
