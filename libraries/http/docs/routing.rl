// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:routing = [
    id = phrase { payload = "routing" }
    title = phrase { payload = "Routing" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "20" }
    body = phrase {
        payload = "## Register specific routes before wildcards

Routes are considered in registration order. An exact path matches itself. A path ending in `*` matches its prefix. Put specific paths before broad prefixes; this is not a parameterized router with `{id}` captures.

```recurloop
import http
let define_routes = fn () -> i64 {
    http \"127.0.0.1\" 8080 {
        GET \"/api/health\" -> fn (request:Http:Request*, response:Http:Response*) -> void {
            response.text(200, \"ok\")
        }
        GET \"/api/*\" -> fn (request:Http:Request*, response:Http:Response*) -> void {
            response.text(404, \"unknown API endpoint\")
        }
    }
    return 0
}
```

## Method handling

- Method comparisons are case insensitive.
- A `GET` route also handles `HEAD`; the writer omits the response body while preserving its declared length.
- A programmatic `ANY` route accepts any method and still follows registration order.
- No match produces `404`, unless `Server:on_not_found` supplies another handler.

## Check registration and callback lifetime

`Server:route` copies the method and path but borrows the callback. Check its return value; allocation failure means the route was not registered. Keep callback code available for the entire serving lifetime."
    }
]
