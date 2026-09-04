let test_handler = fn (request:Http:Request*, response:Http:Response*) -> void {
    let test = request.header("X-Test")
    if test && Http:text_equal(test, "yes") {
        let name = request.param("name")
        if name { response.text(200, name); return }
    }
    response.text(400, "bad")
}

let main = fn () -> i64 {
    http once "127.0.0.1" 18080 {
        GET "/hello" -> test_handler
    }
    return 0
}
main()
