// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Http" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Build an IPv4 HTTP server with typed handlers, exact or prefix routes, bounded request parsing and a worker pool. Import `http`; route callbacks receive borrowed `Http:Request*` and `Http:Response*` arguments.

## A small service

```recurloop
import http
let serve_health = fn () -> i64 {
    http \"127.0.0.1\" 8080 {
        GET \"/health\" -> fn (request:Http:Request*, response:Http:Response*) -> void {
            response.json(200, \"{\\\"status\\\":\\\"ok\\\"}\")
        }
    }
    return 0
}
// Call serve_health() to start the blocking server.
```

The example defines the server without starting it. Serving blocks until the accept loop stops or fails. A handler should produce one response before returning; if it sends none, the server supplies an empty `204` response.

## API map

| Need | API |
| --- | --- |
| Declare routes | `http`, `Http:Server:route` |
| Read headers or query values | `Request:header`, `Request:param` |
| Send text, HTML, JSON or bytes | `Response:text`, `html`, `json`, `send` |
| Limit work and memory | `Http:Limits`, the `limits` clause |
| Serve one connection | `http once`, `Server:serve_once` |

Read [routing](routing.rl), [request data](requests.rl), [responses](responses.rl), [limits](limits.rl) and [server lifetime](server-lifetime.rl) before exposing a service to clients. The response JSON helper sets a content type; it is not a serializer or JSON validator."
    }
]
