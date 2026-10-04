engine import "@HTTP_IMAGE@"

http "127.0.0.1" 18087 {
    POST "/echo" -> fn (request:Http:Request*, response:Http:Response*) -> void {
        response.send(200, "application/octet-stream", request.body, request.body_length)
    }
}
