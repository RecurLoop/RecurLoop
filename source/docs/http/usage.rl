// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Http" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Http provides request parsing, responses, routes and server configuration.

## Request limits

Configure `Http:Limits` for headers and body size before accepting untrusted requests. A handler receives request data with a lifetime bounded by the current request. Copy values that must outlive it.

## Responses

Construct response headers and a body through the response API. Check return values and release owned buffers according to each function’s description."
    }
]

