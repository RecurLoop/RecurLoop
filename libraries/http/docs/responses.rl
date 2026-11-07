// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:responses = [
    id = phrase { payload = "responses" }
    title = phrase { payload = "Responses" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "40" }
    body = phrase {
        payload = "## Set headers before sending

Set headers first, then send the body. `text` and `html` accept null-terminated text and set a UTF-8 content type. `json` accepts already serialized JSON. `send` accepts an explicit byte length and is suitable for binary output. `empty` emits a status with no body.

```recurloop
import http
let health_response = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.header(\"Cache-Control\", \"no-store\")
    response.json(200, \"{\\\"healthy\\\":true}\")
}
```

## Lifetimes and repeated sends

## Keep response data alive

`header` borrows both strings until sending. Use string literals or keep allocated values alive until the send completes. `send` borrows body bytes for the duration of that call. A second send is ignored; headers added after sending are ignored too. Return immediately after handling an error to avoid ambiguous control flow.

```recurloop
import http
let require_token = fn (request:Http:Request*, response:Http:Response*) -> void {
    let token = request.header(\"X-Api-Token\")
    if !token || token[0] == 0 {
        response.text(401, \"token required\")
        return
    }
    response.empty(204)
}
```

This checks presence only, not token validity. Application authentication must validate credentials. The writer generates Content-Length and closes the connection after the response. Do not add competing framing headers or insert unvalidated line breaks into header values."
    }
]
