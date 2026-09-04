// Build library.rl first, then import /tmp/recurloop-http-library.rli.

let home = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.header("X-Powered-By", "RecurLoop")
    response.html(200, "<h1>Hello from RecurLoop</h1>\n")
}

let health = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.json(200, "{\"status\":\"ok\"}\n")
}

let hello = fn (request:Http:Request*, response:Http:Response*) -> void {
    let name = request.param("name")
    if name {
        response.text(200, name)
    } else {
        response.text(200, "world")
    }
}

let echo = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.send(200, "application/octet-stream", request.body, request.body_length)
}

let http_main = fn () -> i64 {
    http "127.0.0.1" 8080 {
        GET  "/"       -> home
        GET  "/health" -> health
        GET  "/hello"  -> hello
        POST "/echo"   -> echo
    }
    return 0
}

http_main()
