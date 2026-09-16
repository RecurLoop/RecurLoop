module auto
module clear
module strip
emit executable "/tmp/recurloop-http-production-test-server" http_production_test_main = fn () -> i64 {
    http "127.0.0.1" 18086 limits {
        request_line = 1KiB,
        headers_total = 4KiB,
        header_count = 8,
        body = 64KiB,
        header_timeout = 2s,
        body_timeout = 700ms,
        write_timeout = 1s,
        workers = 2,
        queue_capacity = 2,
        listen_backlog = 16,
        chunk_line = 1KiB
    } {
        GET "/health" -> fn (request:Http:Request*, response:Http:Response*) -> void {
            response.text(200, "ok")
        }
        POST "/echo" -> fn (request:Http:Request*, response:Http:Response*) -> void {
            response.send(200, "application/octet-stream", request.body, request.body_length)
        }
    }
    return 0
}
