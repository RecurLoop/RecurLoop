let echo_handler = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.send(201, "application/octet-stream", request.body, request.body_length)
}

let main = fn () -> i64 {
    http once "127.0.0.1" 18081 {
        POST "/echo" -> echo_handler
    }
    return 0
}
main()
