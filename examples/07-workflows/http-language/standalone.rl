// Build the HTTP language image first, then compile this source with:
//
//   build/Release/bin/recurloop \
//     --import /tmp/recurloop-http-library.rli \
//     --file examples/07-workflows/http-language/standalone.rl
//
// Run the generated server with: /tmp/recurloop-http-server

let home = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.header("X-Powered-By", "RecurLoop")
    response.html(200, "<h1>Hello from standalone RecurLoop</h1>\n")
}

let health = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.json(200, "{\"status\":\"ok\"}\n")
}

module auto
module clear
emit executable "/tmp/recurloop-http-server" http_server_main = fn () -> i64 {
    http "127.0.0.1" 8080 {
        GET  "/"       -> home
        GET  "/health" -> health
        POST "/echo"   -> fn (request:Http:Request*, response:Http:Response*) -> void {
            response.send(200, "application/octet-stream", request.body, request.body_length)
        }
    }

    return 0
}
