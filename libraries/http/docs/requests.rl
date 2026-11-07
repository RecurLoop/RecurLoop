// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:requests = [
    id = phrase { payload = "requests" }
    title = phrase { payload = "Requests" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "30" }
    body = phrase {
        payload = "## Read headers and query parameters

The server owns request storage. `request.header(name)` looks up names without regard to ASCII case. `request.param(name)` percent-decodes a query value, including `+` as a space, and returns request-owned storage. Null means no value was found or storage could not be produced; an empty string is a present empty value.

```recurloop
import http
let greeting = fn (request:Http:Request*, response:Http:Response*) -> void {
    let name = request.param(\"name\")
    if !name { response.text(400, \"missing name\"); return }
    if name[0] == 0 { response.text(400, \"empty name\"); return }
    response.text(200, name)
}
```

## Validate decoded input

For `/hello?name=Ada+Lovelace`, `name` is `Ada Lovelace`. Validate values according to the operation you perform; decoding does not validate application data.

## Body length is authoritative

`request.body_length` counts bytes. A body can contain zero bytes, so do not measure binary data with `strlen` or treat it as an arbitrary null-terminated string.

```recurloop
import http
let echo_bytes = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.send(200, \"application/octet-stream\", request.body, request.body_length)
}
```

Do not destroy handler arguments or free a returned parameter/header. For asynchronous work, make your own copy of the necessary bytes before the handler returns. Never store a borrowed request pointer for a later job."
    }
]
