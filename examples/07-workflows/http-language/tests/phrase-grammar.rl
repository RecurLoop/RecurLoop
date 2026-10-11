let HttpSyntax:Grammar:one = <HttpSyntax:Grammar:once>
let HttpSyntax:Grammar:settings = <HttpSyntax:Grammar:limits>
let HttpSyntax:Grammar:begin = <HttpSyntax:Grammar:"{">
let HttpSyntax:Grammar:end = <HttpSyntax:Grammar:"}">
let HttpSyntax:Grammar:is = <HttpSyntax:Grammar:"=">
let HttpSyntax:Grammar:to = <HttpSyntax:Grammar:"->">
let HttpSyntax:Grammar:fetch = <HttpSyntax:Grammar:GET>
let HttpSyntax:Grammar:native = <HttpSyntax:Grammar:fn>
let HttpSyntax:Grammar:request_bytes = <HttpSyntax:Grammar:request_line>
let HttpSyntax:Grammar:kb = <HttpSyntax:Grammar:KiB>
let HttpSyntax:Grammar:"#" = <HttpSyntax:Grammar:"//">
syntax opaque_http <payload:code> "|" => 42

// Compile the same syntax inside a native function without starting it.
fn unused_server() -> i64 {
    http one "127.0.0.1" 18089 settings begin request_bytes is 1 kb end begin
        # fake native close: }
        fetch "/phrases" to native (request:Http:Request*, response:Http:Response*) -> void {
            let value = opaque_http } " /* |
            if value == 42 { response.text(200, "phrase-ok") }
        }
    end
    return 0
}

// Streamed root capture must use the same grammar and protect opaque native data.
http one "127.0.0.1" 18089 settings begin request_bytes is 1 kb end begin
    # This fake delimiter is a comment: end
    fetch "/phrases" to native (request:Http:Request*, response:Http:Response*) -> void {
        let value = opaque_http } " /* |
        if value == 42 { response.text(200, "phrase-ok") }
    }
end
