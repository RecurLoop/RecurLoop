let home = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.text(200, "hello")
}

let main = fn () -> i64 {
    http once "127.0.0.1" 18084 {
        GET "/" -> home
    }
    return 0
}
main()
