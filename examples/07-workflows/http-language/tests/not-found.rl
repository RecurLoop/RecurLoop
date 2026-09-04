let known = fn (request:Http:Request*, response:Http:Response*) -> void {
    response.text(200, "known")
}

let main = fn () -> i64 {
    http once "127.0.0.1" 18083 {
        GET "/known" -> known
    }
    return 0
}

main()
