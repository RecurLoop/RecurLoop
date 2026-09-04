let assets = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.text(200, request.path)
}

let main = fn () -> i64 {
    http once "127.0.0.1" 18082 {
        GET "/assets/*" -> assets
    }
    return 0
}
main()
