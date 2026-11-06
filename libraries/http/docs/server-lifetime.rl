// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:server_lifetime = [
    id = phrase { payload = "server-lifetime" }
    title = phrase { payload = "Server construction, ownership and shutdown" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`Server:new(port)` binds all IPv4 interfaces. Use `new_on(port, address)` for an explicit bind address. `new_on_with_limits` also accepts an owned limits record. A null server means initialization failed; no server handle may be used afterward.

```recurloop
import http
let serve_one_request = fn () -> i64 {
    let limits = Http:Limits:defaults()
    if !limits { return 1 }
    limits.body = 65536
    let server = Http:Server:new_on_with_limits(8080, \"127.0.0.1\", limits)
    if !server { return 2 }
    defer server.destroy()
    if !server.route(\"GET\", \"/health\", fn (request:Http:Request*, response:Http:Response*) -> void {
        response.text(200, \"ok\")
    }) { return 3 }
    return !server.serve_once()
}
// Calling this waits for one client connection.
```

`serve_once` is synchronous and returns `1` for a served connection, `0` on failure. `run` starts the bounded worker loop and blocks. Do not call `destroy` concurrently with active workers: destruction requires that serving work has already stopped. The current public API does not provide a graceful stop token or promise cancellation through destruction.

The library implements HTTP transport, not TLS termination. Select a deployment arrangement appropriate to your application. Protocol parsing handles framing; route handlers still validate application data and authorization."
    }
]
