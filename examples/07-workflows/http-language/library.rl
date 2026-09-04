// =============================================================================
// RecurLoop HTTP language
//
// A small HTTP/1.1 server runtime and source-defined routing syntax written in
// RecurLoop. The C++ host has no HTTP parser, router, or socket-server support.
//
// Surface syntax:
//
//   let home = fn (req:Http:Request*, res:Http:Response*) -> void {
//       res.text(200, "hello from RecurLoop\n")
//   }
//
//   http "127.0.0.1" 8080 {
//       GET "/" -> home
//   }
//
// `http once ...` accepts exactly one connection and then returns. It exists
// primarily for deterministic examples and tests.
// =============================================================================

link shared "c"

extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern memcpy(destination:u8*, source:u8*, bytes:u64) -> u8* abi sysv-amd64
extern memcmp(left:u8*, right:u8*, bytes:u64) -> i32 abi sysv-amd64
extern snprintf(buffer:u8*, size:u64, format:u8*, ...) -> i32 abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64
extern perror(prefix:u8*) -> void abi sysv-amd64

extern socket(domain:i32, kind:i32, protocol:i32) -> i32 abi sysv-amd64
extern setsockopt(fd:i32, level:i32, option:i32, value:u8*, length:u32) -> i32 abi sysv-amd64
extern bind(fd:i32, address:u8*, length:u32) -> i32 abi sysv-amd64
extern listen(fd:i32, backlog:i32) -> i32 abi sysv-amd64
extern accept(fd:i32, address:u8*, length:u32*) -> i32 abi sysv-amd64
extern recv(fd:i32, buffer:u8*, length:u64, flags:i32) -> i64 abi sysv-amd64
extern send(fd:i32, buffer:u8*, length:u64, flags:i32) -> i64 abi sysv-amd64
extern shutdown(fd:i32, how:i32) -> i32 abi sysv-amd64
extern close(fd:i32) -> i32 abi sysv-amd64
extern htons(value:u16) -> u16 abi sysv-amd64
extern inet_addr(address:u8*) -> u32 abi sysv-amd64

let Http = phrase { dictionary = true permanent = true }
let Http:Internal = phrase { dictionary = true serializable = false }

// Linux/POSIX constants used by this compatibility runtime.

// =============================================================================
// Small text helpers
// =============================================================================

let Http:strlen = fn (text:u8*) -> i64 {
    if !text { return 0 }
    var length = 0
    while text[length] != 0 { length += 1 }
    return length
}

let Http:copy_text = fn (text:u8*) -> u8* {
    if !text { return cast(u8*, 0) }
    let length = Http:strlen(text)
    let out = cast(u8*, malloc(length + 1))
    if !out { return cast(u8*, 0) }
    if length > 0 { memcpy(out, text, length) }
    out[length] = 0
    return out
}

let Http:text_equal = fn (left:u8*, right:u8*) -> i64 {
    if !left || !right { return 0 }
    var i = 0
    while left[i] != 0 && right[i] != 0 {
        if left[i] != right[i] { return 0 }
        i += 1
    }
    return left[i] == right[i]
}

let Http:ascii_lower = fn (value:u8) -> u8 {
    if value >= 65 && value <= 90 { return value + 32 }
    return value
}

let Http:text_equal_ci = fn (left:u8*, right:u8*) -> i64 {
    if !left || !right { return 0 }
    var i = 0
    while left[i] != 0 && right[i] != 0 {
        if Http:ascii_lower(left[i]) != Http:ascii_lower(right[i]) { return 0 }
        i += 1
    }
    return left[i] == right[i]
}

let Http:starts_with = fn (text:u8*, prefix:u8*) -> i64 {
    if !text || !prefix { return 0 }
    var i = 0
    while prefix[i] != 0 {
        if text[i] == 0 || text[i] != prefix[i] { return 0 }
        i += 1
    }
    return 1
}

let Http:is_hex = fn (value:u8) -> i64 {
    if value >= 48 && value <= 57 { return 1 }
    if value >= 65 && value <= 70 { return 1 }
    if value >= 97 && value <= 102 { return 1 }
    return 0
}

let Http:hex_value = fn (value:u8) -> i64 {
    if value >= 48 && value <= 57 { return value - 48 }
    if value >= 65 && value <= 70 { return value - 65 + 10 }
    if value >= 97 && value <= 102 { return value - 97 + 10 }
    return 0
}

let Http:url_decode_slice = fn (source:u8*, start:i64, finish:i64) -> u8* {
    if !source || finish < start { return cast(u8*, 0) }
    let output = cast(u8*, malloc(finish - start + 1))
    if !output { return cast(u8*, 0) }
    var src = start
    var dst = 0
    while src < finish {
        if source[src] == 43 {
            output[dst] = 32
            dst += 1
            src += 1
        } else if source[src] == 37 && src + 2 < finish && Http:is_hex(source[src + 1]) && Http:is_hex(source[src + 2]) {
            output[dst] = cast(u8, Http:hex_value(source[src + 1]) * 16 + Http:hex_value(source[src + 2]))
            dst += 1
            src += 3
        } else {
            output[dst] = source[src]
            dst += 1
            src += 1
        }
    }
    output[dst] = 0
    return output
}

// =============================================================================
// Request model
// =============================================================================

record Http:Header {
    name:u8*
    value:u8*
    next:Http:Header*
}

record Http:OwnedText {
    value:u8*
    next:Http:OwnedText*
}

record Http:Request {
    buffer:u8*
    bytes:i64
    method:u8*
    target:u8*
    path:u8*
    query:u8*
    version:u8*
    body:u8*
    body_length:i64
    headers:Http:Header*
    scratch:Http:OwnedText*
}

let Http:Request:header = fn (self:Http:Request*, name:u8*) -> u8* {
    if !self || !name { return cast(u8*, 0) }
    var current = self.headers
    while current {
        if Http:text_equal_ci(current.name, name) { return current.value }
        current = current.next
    }
    return cast(u8*, 0)
}

let Http:Request:remember = fn (self:Http:Request*, text:u8*) -> u8* {
    if !self || !text { return text }
    let item = cast(Http:OwnedText*, malloc(16))
    if !item { free(text); return cast(u8*, 0) }
    item.value = text
    item.next = self.scratch
    self.scratch = item
    return text
}

// Returns a request-owned, percent-decoded query parameter. The returned text
// stays valid until the handler returns; callers do not free it.
let Http:Request:param = fn (self:Http:Request*, name:u8*) -> u8* {
    if !self || !self.query || !name { return cast(u8*, 0) }
    let query = self.query
    let name_length = Http:strlen(name)
    var position = 0
    while query[position] != 0 {
        let key_start = position
        while query[position] != 0 && query[position] != 61 && query[position] != 38 { position += 1 }
        let key_end = position
        var value_start = position
        var value_end = position
        if query[position] == 61 {
            position += 1
            value_start = position
            while query[position] != 0 && query[position] != 38 { position += 1 }
            value_end = position
        }
        if key_end - key_start == name_length && memcmp(&query[key_start], name, name_length) == 0 {
            return self.remember(Http:url_decode_slice(query, value_start, value_end))
        }
        if query[position] == 38 { position += 1 }
    }
    return cast(u8*, 0)
}

let Http:Request:destroy = fn (self:Http:Request*) -> void {
    if !self { return }
    var header = self.headers
    while header {
        let next = header.next
        free(cast(u8*, header))
        header = next
    }
    var scratch = self.scratch
    while scratch {
        let next = scratch.next
        if scratch.value { free(scratch.value) }
        free(cast(u8*, scratch))
        scratch = next
    }
    if self.buffer { free(self.buffer) }
    free(cast(u8*, self))
}

// =============================================================================
// Response model
// =============================================================================

record Http:ResponseHeader {
    name:u8*
    value:u8*
    next:Http:ResponseHeader*
}

record Http:Response {
    fd:i32
    sent:i64
    head_only:i64
    headers:Http:ResponseHeader*
}

let Http:status_reason = fn (status:i64) -> u8* {
    if status == 200 { return "OK" }
    if status == 201 { return "Created" }
    if status == 202 { return "Accepted" }
    if status == 204 { return "No Content" }
    if status == 301 { return "Moved Permanently" }
    if status == 302 { return "Found" }
    if status == 304 { return "Not Modified" }
    if status == 400 { return "Bad Request" }
    if status == 401 { return "Unauthorized" }
    if status == 403 { return "Forbidden" }
    if status == 404 { return "Not Found" }
    if status == 405 { return "Method Not Allowed" }
    if status == 409 { return "Conflict" }
    if status == 413 { return "Payload Too Large" }
    if status == 415 { return "Unsupported Media Type" }
    if status == 422 { return "Unprocessable Content" }
    if status == 429 { return "Too Many Requests" }
    if status == 500 { return "Internal Server Error" }
    if status == 501 { return "Not Implemented" }
    if status == 502 { return "Bad Gateway" }
    if status == 503 { return "Service Unavailable" }
    return "Status"
}

let Http:write_all = fn (fd:i32, data:u8*, bytes:i64) -> i64 {
    if fd < 0 || !data || bytes < 0 { return 0 }
    var sent_bytes = 0
    while sent_bytes < bytes {
        let amount = send(fd, &data[sent_bytes], bytes - sent_bytes, 16384)
        if amount <= 0 { return 0 }
        sent_bytes += amount
    }
    return 1
}

let Http:Response:header = fn (self:Http:Response*, name:u8*, value:u8*) -> void {
    if !self || self.sent || !name || !value { return }
    let item = cast(Http:ResponseHeader*, malloc(24))
    if !item { return }
    item.name = name
    item.value = value
    item.next = self.headers
    self.headers = item
}

let Http:Response:send = fn (self:Http:Response*, status:i64, content_type:u8*, body:u8*, body_length:i64) -> void {
    if !self || self.sent { return }
    if !content_type { content_type = "application/octet-stream" }
    if !body { body_length = 0 }
    if body_length < 0 { body_length = 0 }

    let line = cast(u8*, malloc(512))
    if !line { return }
    defer free(line)

    let reason = Http:status_reason(status)
    let first_bytes = snprintf(line, 512, "HTTP/1.1 %ld %s\r\n", status, reason)
    if first_bytes <= 0 || !Http:write_all(self.fd, line, first_bytes) { return }

    let length_bytes = snprintf(line, 512, "Content-Length: %ld\r\n", body_length)
    if length_bytes <= 0 || !Http:write_all(self.fd, line, length_bytes) { return }

    if !Http:write_all(self.fd, "Content-Type: ", 14) { return }
    if !Http:write_all(self.fd, content_type, Http:strlen(content_type)) { return }
    if !Http:write_all(self.fd, "\r\n", 2) { return }
    if !Http:write_all(self.fd, "Connection: close\r\n", 19) { return }

    var current = self.headers
    while current {
        if !Http:write_all(self.fd, current.name, Http:strlen(current.name)) { return }
        if !Http:write_all(self.fd, ": ", 2) { return }
        if !Http:write_all(self.fd, current.value, Http:strlen(current.value)) { return }
        if !Http:write_all(self.fd, "\r\n", 2) { return }
        current = current.next
    }

    if !Http:write_all(self.fd, "\r\n", 2) { return }
    if !self.head_only && body_length > 0 {
        if !Http:write_all(self.fd, body, body_length) { return }
    }
    self.sent = 1
}

let Http:Response:text = fn (self:Http:Response*, status:i64, body:u8*) -> void {
    self.send(status, "text/plain; charset=utf-8", body, Http:strlen(body))
}

let Http:Response:html = fn (self:Http:Response*, status:i64, body:u8*) -> void {
    self.send(status, "text/html; charset=utf-8", body, Http:strlen(body))
}

let Http:Response:json = fn (self:Http:Response*, status:i64, body:u8*) -> void {
    self.send(status, "application/json; charset=utf-8", body, Http:strlen(body))
}

let Http:Response:empty = fn (self:Http:Response*, status:i64) -> void {
    self.send(status, "text/plain; charset=utf-8", cast(u8*, 0), 0)
}

let Http:Response:destroy_headers = fn (self:Http:Response*) -> void {
    if !self { return }
    var current = self.headers
    while current {
        let next = current.next
        free(cast(u8*, current))
        current = next
    }
    self.headers = cast(Http:ResponseHeader*, 0)
}

// =============================================================================
// HTTP request parsing
// =============================================================================

let Http:find_header_end = fn (buffer:u8*, bytes:i64) -> i64 {
    var i = 0
    while i + 3 < bytes {
        if buffer[i] == 13 && buffer[i + 1] == 10 && buffer[i + 2] == 13 && buffer[i + 3] == 10 {
            return i
        }
        i += 1
    }
    return -1
}

let Http:parse_decimal = fn (source:u8*, start:i64, finish:i64) -> i64 {
    var value = 0
    var i = start
    while i < finish && (source[i] == 32 || source[i] == 9) { i += 1 }
    while i < finish && source[i] >= 48 && source[i] <= 57 {
        value = value * 10 + source[i] - 48
        i += 1
    }
    return value
}

let Http:span_equal_ci = fn (source:u8*, start:i64, finish:i64, text:u8*) -> i64 {
    let length = Http:strlen(text)
    if finish - start != length { return 0 }
    var i = 0
    while i < length {
        if Http:ascii_lower(source[start + i]) != Http:ascii_lower(text[i]) { return 0 }
        i += 1
    }
    return 1
}

let Http:raw_content_length = fn (buffer:u8*, request_line_end:i64, header_end:i64) -> i64 {
    var position = request_line_end + 2
    while position < header_end {
        let line_start = position
        while position < header_end && !(buffer[position] == 13 && position + 1 < header_end + 2 && buffer[position + 1] == 10) {
            position += 1
        }
        let line_end = position
        var colon = line_start
        while colon < line_end && buffer[colon] != 58 { colon += 1 }
        if colon < line_end && Http:span_equal_ci(buffer, line_start, colon, "Content-Length") {
            return Http:parse_decimal(buffer, colon + 1, line_end)
        }
        position += 2
    }
    return 0
}

let Http:read_request = fn (fd:i32) -> Http:Request* {
    let capacity = 1048576
    let buffer = cast(u8*, malloc(capacity + 1))
    if !buffer { return cast(Http:Request*, 0) }

    var used = 0
    var header_end = -1
    var request_line_end = -1
    var expected = -1

    while used < capacity {
        let amount = recv(fd, &buffer[used], capacity - used, 0)
        if amount <= 0 { free(buffer); return cast(Http:Request*, 0) }
        used += amount
        buffer[used] = 0

        if request_line_end < 0 {
            var i = 0
            while i + 1 < used {
                if buffer[i] == 13 && buffer[i + 1] == 10 { request_line_end = i; i = used }
                i += 1
            }
        }

        if header_end < 0 { header_end = Http:find_header_end(buffer, used) }
        if header_end >= 0 && request_line_end >= 0 && expected < 0 {
            let content_length = Http:raw_content_length(buffer, request_line_end, header_end)
            expected = header_end + 4 + content_length
            if expected > capacity { free(buffer); return cast(Http:Request*, 0) }
        }
        if expected >= 0 && used >= expected {
            used = expected
            buffer[used] = 0
            break
        }
    }

    if header_end < 0 || request_line_end < 0 || expected < 0 { free(buffer); return cast(Http:Request*, 0) }

    let request = cast(Http:Request*, malloc(88))
    if !request { free(buffer); return cast(Http:Request*, 0) }
    request.buffer = buffer
    request.bytes = used
    request.method = buffer
    request.target = cast(u8*, 0)
    request.path = cast(u8*, 0)
    request.query = cast(u8*, 0)
    request.version = cast(u8*, 0)
    request.body = &buffer[header_end + 4]
    request.body_length = expected - header_end - 4
    request.headers = cast(Http:Header*, 0)
    request.scratch = cast(Http:OwnedText*, 0)

    // Request line: METHOD SP TARGET SP VERSION CRLF
    var first_space = 0
    while first_space < request_line_end && buffer[first_space] != 32 { first_space += 1 }
    if first_space >= request_line_end { request.destroy(); return cast(Http:Request*, 0) }
    buffer[first_space] = 0
    request.target = &buffer[first_space + 1]

    var second_space = first_space + 1
    while second_space < request_line_end && buffer[second_space] != 32 { second_space += 1 }
    if second_space >= request_line_end { request.destroy(); return cast(Http:Request*, 0) }
    buffer[second_space] = 0
    request.version = &buffer[second_space + 1]
    buffer[request_line_end] = 0

    request.path = request.target
    var target_index = 0
    while request.target[target_index] != 0 {
        if request.target[target_index] == 63 {
            request.target[target_index] = 0
            request.query = &request.target[target_index + 1]
            target_index = Http:strlen(request.target)
        } else {
            target_index += 1
        }
    }

    // Parse headers in place. Header nodes only own the linked-list structure;
    // names and values point into request.buffer.
    var position = request_line_end + 2
    var tail = cast(Http:Header*, 0)
    while position < header_end {
        let line_start = position
        while position < header_end && !(buffer[position] == 13 && buffer[position + 1] == 10) { position += 1 }
        let line_end = position
        var colon = line_start
        while colon < line_end && buffer[colon] != 58 { colon += 1 }
        if colon < line_end {
            buffer[colon] = 0
            var value_start = colon + 1
            while value_start < line_end && (buffer[value_start] == 32 || buffer[value_start] == 9) { value_start += 1 }
            buffer[line_end] = 0
            let item = cast(Http:Header*, malloc(24))
            if item {
                item.name = &buffer[line_start]
                item.value = &buffer[value_start]
                item.next = cast(Http:Header*, 0)
                if !request.headers { request.headers = item } else { tail.next = item }
                tail = item
            }
        }
        position += 2
    }

    return request
}

// =============================================================================
// Routing and server
// =============================================================================

let Http:Handler = fn (request:Http:Request*, response:Http:Response*) -> void

record Http:Route {
    method:u8*
    path:u8*
    handler:Http:Handler
    next:Http:Route*
}

record Http:Server {
    fd:i32
    port:i64
    address:u8*
    routes:Http:Route*
    route_tail:Http:Route*
    fallback:Http:Handler
}

record Http:SockAddrIn {
    family:u16
    port:u16
    addr:u32
    zero:u64
}

let Http:path_matches = fn (pattern:u8*, path:u8*) -> i64 {
    if !pattern || !path { return 0 }
    let length = Http:strlen(pattern)
    if length > 0 && pattern[length - 1] == 42 {
        var i = 0
        while i < length - 1 {
            if path[i] == 0 || path[i] != pattern[i] { return 0 }
            i += 1
        }
        return 1
    }
    return Http:text_equal(pattern, path)
}

let Http:Server:new_on = fn (port:i64, address_text:u8*) -> Http:Server* {
    let fd = socket(2, 1, 0)
    if fd < 0 { perror("socket"); return cast(Http:Server*, 0) }

    var reuse:i32 = 1
    if setsockopt(fd, 1, 2, cast(u8*, &reuse), 4) < 0 {
        perror("setsockopt")
        close(fd)
        return cast(Http:Server*, 0)
    }

    let socket_address = cast(Http:SockAddrIn*, malloc(16))
    if !socket_address { close(fd); return cast(Http:Server*, 0) }
    socket_address.family = cast(u16, 2)
    socket_address.port = htons(cast(u16, port))
    socket_address.addr = 0
    if address_text { socket_address.addr = inet_addr(address_text) }
    socket_address.zero = 0

    if bind(fd, cast(u8*, socket_address), 16) < 0 {
        perror("bind")
        free(cast(u8*, socket_address))
        close(fd)
        return cast(Http:Server*, 0)
    }
    free(cast(u8*, socket_address))

    if listen(fd, 128) < 0 {
        perror("listen")
        close(fd)
        return cast(Http:Server*, 0)
    }

    let server = cast(Http:Server*, malloc(48))
    if !server { close(fd); return cast(Http:Server*, 0) }
    server.fd = fd
    server.port = port
    var bind_address = address_text
    if !bind_address { bind_address = "0.0.0.0" }
    server.address = Http:copy_text(bind_address)
    server.routes = cast(Http:Route*, 0)
    server.route_tail = cast(Http:Route*, 0)
    server.fallback = cast(Http:Handler, 0)
    return server
}

let Http:Server:new = fn (port:i64) -> Http:Server* {
    return Http:Server:new_on(port, "0.0.0.0")
}

let Http:Server:route = fn (self:Http:Server*, method:u8*, path:u8*, handler:Http:Handler) -> i64 {
    if !self || !method || !path || !handler { return 0 }
    let route = cast(Http:Route*, malloc(32))
    if !route { return 0 }
    route.method = Http:copy_text(method)
    route.path = Http:copy_text(path)
    route.handler = handler
    route.next = cast(Http:Route*, 0)
    if !route.method || !route.path {
        if route.method { free(route.method) }
        if route.path { free(route.path) }
        free(cast(u8*, route))
        return 0
    }
    if !self.routes { self.routes = route } else { self.route_tail.next = route }
    self.route_tail = route
    return 1
}

let Http:Server:on_not_found = fn (self:Http:Server*, handler:Http:Handler) -> void {
    if self { self.fallback = handler }
}

let Http:Server:destroy = fn (self:Http:Server*) -> void {
    if !self { return }
    if self.fd >= 0 {
        shutdown(self.fd, 2)
        close(self.fd)
        self.fd = -1
    }
    var route = self.routes
    while route {
        let next = route.next
        if route.method { free(route.method) }
        if route.path { free(route.path) }
        free(cast(u8*, route))
        route = next
    }
    if self.address { free(self.address) }
    free(cast(u8*, self))
}

let Http:Server:dispatch = fn (self:Http:Server*, request:Http:Request*, response:Http:Response*) -> void {
    if !self || !request || !response { return }
    var route = self.routes
    while route {
        if Http:text_equal(route.method, "ANY") {
            if Http:path_matches(route.path, request.path) {
                let handler = route.handler
                handler(request, response)
                return
            }
        }
        if Http:text_equal_ci(route.method, request.method) {
            if Http:path_matches(route.path, request.path) {
                let handler = route.handler
                handler(request, response)
                return
            }
        }
        if Http:text_equal_ci(request.method, "HEAD") {
            if Http:text_equal_ci(route.method, "GET") {
                if Http:path_matches(route.path, request.path) {
                    let handler = route.handler
                    handler(request, response)
                    return
                }
            }
        }
        route = route.next
    }
    if self.fallback {
        let handler = self.fallback
        handler(request, response)
        return
    }
    response.text(404, "404 Not Found\n")
}

let Http:Server:serve_client = fn (self:Http:Server*, client:i32) -> i64 {
    let request = Http:read_request(client)
    if !request {
        let response = cast(Http:Response*, malloc(32))
        if response {
            response.fd = client
            response.sent = 0
            response.head_only = 0
            response.headers = cast(Http:ResponseHeader*, 0)
            response.text(400, "400 Bad Request\n")
            response.destroy_headers()
            free(cast(u8*, response))
        }
        return 0
    }
    defer request.destroy()

    let response = cast(Http:Response*, malloc(32))
    if !response { return 0 }
    defer free(cast(u8*, response))
    response.fd = client
    response.sent = 0
    response.head_only = Http:text_equal_ci(request.method, "HEAD")
    response.headers = cast(Http:ResponseHeader*, 0)
    defer response.destroy_headers()

    self.dispatch(request, response)
    if !response.sent { response.empty(204) }
    return 1
}

let Http:Server:serve_once = fn (self:Http:Server*) -> i64 {
    if !self || self.fd < 0 { return 0 }
    let client = accept(self.fd, cast(u8*, 0), cast(u32*, 0))
    if client < 0 { return 0 }
    let ok = self.serve_client(client)
    shutdown(client, 2)
    close(client)
    return ok
}

let Http:Server:run = fn (self:Http:Server*) -> i64 {
    if !self || self.fd < 0 { return 0 }
    printf("HTTP server listening on http://%s:%ld\n", self.address, self.port)
    while 1 {
        let client = accept(self.fd, cast(u8*, 0), cast(u32*, 0))
        if client >= 0 {
            self.serve_client(client)
            shutdown(client, 2)
            close(client)
        }
    }
    return 1
}

// =============================================================================
// Source-defined `http` routing syntax
// =============================================================================

let HttpSyntax = phrase { dictionary = true }

let HttpSyntax:is_space = fn (value:u8) -> i64 {
    return value == 32 || value == 9 || value == 10 || value == 13
}

let HttpSyntax:trim_left = fn (source:u8*, start:i64, finish:i64) -> i64 {
    var i = start
    while i < finish && HttpSyntax:is_space(source[i]) { i += 1 }
    return i
}

let HttpSyntax:trim_right = fn (source:u8*, start:i64, finish:i64) -> i64 {
    var i = finish
    while i > start && HttpSyntax:is_space(source[i - 1]) { i -= 1 }
    return i
}

let HttpSyntax:emit_slice = fn (state:Context*, source:u8*, start:i64, finish:i64) -> void {
    if finish > start { context:syntax:emit(state, source, start, finish - start) }
}

let HttpSyntax:error = fn (state:Context*, message:u8*) -> void {
    context:diagnostic:error(state, message)
}

let HttpSyntax:block_end = fn (source:u8*, open:i64, finish:i64) -> i64 {
    var depth = 1
    var i = open + 1
    var quote:u8 = 0
    while i < finish {
        let c = source[i]
        if quote != 0 {
            if c == 92 { i += 2 }
            else {
                if c == quote { quote = 0 }
                i += 1
            }
        } else {
            if c == 34 || c == 39 { quote = c; i += 1 }
            else if c == 47 && i + 1 < finish && source[i + 1] == 47 {
                i += 2
                while i < finish && source[i] != 10 { i += 1 }
            } else if c == 123 { depth += 1; i += 1 }
            else if c == 125 {
                depth -= 1
                if depth == 0 { return i }
                i += 1
            } else { i += 1 }
        }
    }
    return -1
}

let HttpSyntax:is_digit = fn (value:u8) -> i64 { return value >= 48 && value <= 57 }

let HttpSyntax:parse_port = fn (source:u8*, start:i64, finish:i64, next:i64*) -> i64 {
    var i = HttpSyntax:trim_left(source, start, finish)
    if i >= finish || !HttpSyntax:is_digit(source[i]) { return -1 }
    var port = 0
    while i < finish && HttpSyntax:is_digit(source[i]) {
        port = port * 10 + source[i] - 48
        i += 1
    }
    next[0] = i
    return port
}

let HttpSyntax:skip_quoted = fn (source:u8*, start:i64, finish:i64) -> i64 {
    if start >= finish || (source[start] != 34 && source[start] != 39) { return -1 }
    let quote = source[start]
    var i = start + 1
    while i < finish {
        if source[i] == 92 { i += 2 }
        else {
            if source[i] == quote { return i + 1 }
            i += 1
        }
    }
    return -1
}

let HttpSyntax:word_equal = fn (source:u8*, start:i64, finish:i64, text:u8*) -> i64 {
    let length = Http:strlen(text)
    if finish - start != length { return 0 }
    return memcmp(&source[start], text, length) == 0
}

let HttpSyntax:emit_route_line = fn (state:Context*, source:u8*, start:i64, finish:i64) -> void {
    let s = HttpSyntax:trim_left(source, start, finish)
    let e = HttpSyntax:trim_right(source, s, finish)
    if s >= e { return }
    if source[s] == 47 && s + 1 < e && source[s + 1] == 47 { return }

    var i = s
    while i < e && !HttpSyntax:is_space(source[i]) { i += 1 }
    let method_end = i
    if method_end == s { HttpSyntax:error(state, "http route expects METHOD \"/path\" -> handler"); return }
    i = HttpSyntax:trim_left(source, i, e)
    if i >= e || source[i] != 34 { HttpSyntax:error(state, "http route path must be a quoted string"); return }
    let path_end = HttpSyntax:skip_quoted(source, i, e)
    if path_end < 0 { HttpSyntax:error(state, "http route path string is not closed"); return }
    let path_start = i
    i = HttpSyntax:trim_left(source, path_end, e)
    if i + 1 >= e || source[i] != 45 || source[i + 1] != 62 {
        HttpSyntax:error(state, "http route expects -> before the handler")
        return
    }
    i = HttpSyntax:trim_left(source, i + 2, e)
    let handler_end = HttpSyntax:trim_right(source, i, e)
    if i >= handler_end { HttpSyntax:error(state, "http route needs a handler function"); return }

    context:syntax:emit(state, "__http_server.route(\"")
    HttpSyntax:emit_slice(state, source, s, method_end)
    context:syntax:emit(state, "\", ")
    HttpSyntax:emit_slice(state, source, path_start, path_end)
    context:syntax:emit(state, ", ")
    HttpSyntax:emit_slice(state, source, i, handler_end)
    context:syntax:emit(state, ")\n")
}

let HttpSyntax:emit_routes = fn (state:Context*, source:u8*, start:i64, finish:i64) -> void {
    var line_start = start
    var i = start
    var quote:u8 = 0
    while i <= finish {
        var split = i == finish
        if i < finish {
            if quote != 0 {
                if source[i] == 92 { i += 1 }
                else if source[i] == quote { quote = 0 }
            } else {
                if source[i] == 34 || source[i] == 39 { quote = source[i] }
                else if source[i] == 10 { split = 1 }
            }
        }
        if split {
            HttpSyntax:emit_route_line(state, source, line_start, i)
            line_start = i + 1
        }
        i += 1
    }
}

let http = phrase {
    type = <phrase-types:elaborate>
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = context:syntax:data(state)
        let bytes = context:syntax:bytes(state)
        var i = HttpSyntax:trim_left(source, 0, bytes)
        var once = 0

        if i + 4 <= bytes && memcmp(&source[i], "once", 4) == 0 && (i + 4 == bytes || HttpSyntax:is_space(source[i + 4])) {
            once = 1
            i = HttpSyntax:trim_left(source, i + 4, bytes)
        }

        var address_start = -1
        var address_end = -1
        if i < bytes && source[i] == 34 {
            address_start = i
            address_end = HttpSyntax:skip_quoted(source, i, bytes)
            if address_end < 0 { HttpSyntax:error(state, "http address string is not closed"); return }
            i = HttpSyntax:trim_left(source, address_end, bytes)
        }

        var after_port:i64 = 0
        let port = HttpSyntax:parse_port(source, i, bytes, &after_port)
        if port <= 0 || port > 65535 { HttpSyntax:error(state, "http expects a TCP port from 1 to 65535"); return }
        i = HttpSyntax:trim_left(source, after_port, bytes)
        if i >= bytes || source[i] != 123 { HttpSyntax:error(state, "http expects a route block"); return }
        let close_index = HttpSyntax:block_end(source, i, bytes)
        if close_index < 0 { HttpSyntax:error(state, "http route block is not closed"); return }

        context:syntax:emit(state, "if 1 {\n")
        context:syntax:emit(state, "let __http_server = Http:Server:new_on(")
        let port_text = cast(u8*, malloc(32))
        if !port_text { HttpSyntax:error(state, "http could not format its port"); return }
        defer free(port_text)
        snprintf(port_text, 32, "%ld", port)
        context:syntax:emit(state, port_text)
        context:syntax:emit(state, ", ")
        if address_start >= 0 { HttpSyntax:emit_slice(state, source, address_start, address_end) }
        else { context:syntax:emit(state, "\"0.0.0.0\"") }
        context:syntax:emit(state, ")\n")
        context:syntax:emit(state, "defer Http:Server:destroy(__http_server)\n")
        HttpSyntax:emit_routes(state, source, i + 1, close_index)
        if once { context:syntax:emit(state, "__http_server.serve_once()\n") }
        else { context:syntax:emit(state, "__http_server.run()\n") }
        context:syntax:emit(state, "}\n")
        context:syntax:advance(state, close_index + 1)
    }
}

engine export "/tmp/recurloop-http-library.rli"
