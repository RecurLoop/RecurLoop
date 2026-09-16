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

languagekit_native_begin
link shared "c"
link shared "pthread"

let Http = phrase { dictionary = true permanent = true }
let Http:Internal = phrase { dictionary = true serializable = false }
let Http:ThreadMain = fn (argument:u8*) -> u8*

// LanguageKit supplies allocation/text helpers and the SliceLexer. The HTTP
// runtime stays source-defined; only POSIX/glibc primitives are imported.

extern memcmp(left:u8*, right:u8*, bytes:u64) -> i32 abi sysv-amd64
extern __memcpy_chk(destination:u8*, source:u8*, bytes:u64, destination_size:u64) -> u8* abi sysv-amd64
extern __snprintf_chk(buffer:u8*, size:u64, flag:i32, object_size:u64, format:u8*, ...) -> i32 abi sysv-amd64

extern socket(domain:i32, kind:i32, protocol:i32) -> i32 abi sysv-amd64
extern setsockopt(fd:i32, level:i32, option:i32, value:u8*, length:u32) -> i32 abi sysv-amd64
extern bind(fd:i32, address:u8*, length:u32) -> i32 abi sysv-amd64
extern listen(fd:i32, backlog:i32) -> i32 abi sysv-amd64
extern accept4(fd:i32, address:u8*, length:u32*, flags:i32) -> i32 abi sysv-amd64
extern recv(fd:i32, buffer:u8*, length:u64, flags:i32) -> i64 abi sysv-amd64
extern send(fd:i32, buffer:u8*, length:u64, flags:i32) -> i64 abi sysv-amd64
extern shutdown(fd:i32, how:i32) -> i32 abi sysv-amd64
extern htons(value:u16) -> u16 abi sysv-amd64
extern inet_addr(address:u8*) -> u32 abi sysv-amd64
extern poll(descriptors:u8*, count:u64, timeout_ms:i32) -> i32 abi sysv-amd64
extern clock_gettime(clock_id:i32, value:u8*) -> i32 abi sysv-amd64
extern __errno_location() -> i32* abi sysv-amd64
extern get_nprocs() -> i32 abi sysv-amd64
extern usleep(microseconds:u32) -> i32 abi sysv-amd64
extern open(path:u8*, flags:i32, ...) -> i32 abi sysv-amd64

extern pthread_create(thread:u64*, attributes:u8*, start:Http:ThreadMain, argument:u8*) -> i32 abi sysv-amd64
extern pthread_detach(thread:u64) -> i32 abi sysv-amd64
extern pthread_mutex_init(mutex:u8*, attributes:u8*) -> i32 abi sysv-amd64
extern pthread_mutex_destroy(mutex:u8*) -> i32 abi sysv-amd64
extern pthread_mutex_lock(mutex:u8*) -> i32 abi sysv-amd64
extern pthread_mutex_unlock(mutex:u8*) -> i32 abi sysv-amd64
extern pthread_cond_init(condition:u8*, attributes:u8*) -> i32 abi sysv-amd64
extern pthread_cond_destroy(condition:u8*) -> i32 abi sysv-amd64
extern pthread_cond_wait(condition:u8*, mutex:u8*) -> i32 abi sysv-amd64
extern pthread_cond_signal(condition:u8*) -> i32 abi sysv-amd64

// Linux/POSIX constants are kept numeric so the generated standalone binary
// does not depend on C headers.

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
    if length > 0 { __memcpy_chk(out, text, length, length + 1) }
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
    body_storage:u8*
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
    if self.body_storage { free(self.body_storage) }
    if self.buffer { free(self.buffer) }
    free(cast(u8*, self))
}

// =============================================================================
// Production limits and non-blocking I/O
// =============================================================================

record Http:Limits {
    request_line:i64
    headers_total:i64
    header_count:i64
    body:i64
    header_timeout_ms:i64
    body_timeout_ms:i64
    write_timeout_ms:i64
    workers:i64
    queue_capacity:i64
    listen_backlog:i64
    chunk_line:i64
}

let Http:Limits:defaults = fn () -> Http:Limits* {
    let limits = cast(Http:Limits*, malloc(88))
    if !limits { return cast(Http:Limits*, 0) }
    limits.request_line = 16384
    limits.headers_total = 65536
    limits.header_count = 100
    limits.body = 1048576
    limits.header_timeout_ms = 10000
    limits.body_timeout_ms = 30000
    limits.write_timeout_ms = 30000
    limits.workers = 0
    limits.queue_capacity = 0
    limits.listen_backlog = 1024
    limits.chunk_line = 4096
    return limits
}

let Http:Limits:valid = fn (self:Http:Limits*) -> i64 {
    if !self { return 0 }
    if self.request_line < 256 || self.request_line > 1048576 { return 0 }
    if self.headers_total < 1024 || self.headers_total > 8388608 { return 0 }
    if self.header_count < 1 || self.header_count > 4096 { return 0 }
    if self.body < 0 || self.body > 1073741824 { return 0 }
    if self.header_timeout_ms < 100 || self.header_timeout_ms > 300000 { return 0 }
    if self.body_timeout_ms < 100 || self.body_timeout_ms > 300000 { return 0 }
    if self.write_timeout_ms < 100 || self.write_timeout_ms > 300000 { return 0 }
    if self.workers < 0 || self.workers > 1024 { return 0 }
    if self.queue_capacity < 0 || self.queue_capacity > 65536 { return 0 }
    if self.listen_backlog < 1 || self.listen_backlog > 65535 { return 0 }
    if self.chunk_line < 64 || self.chunk_line > 65536 { return 0 }
    return 1
}

record Http:PollFd {
    fd:i32
    events:u16
    revents:u16
}

// scratch must point at 24 writable bytes: 16 for timespec and 8 for pollfd.
let Http:now_ms = fn (scratch:u8*) -> i64 {
    if !scratch { return 0 }
    if clock_gettime(1, scratch) != 0 { return 0 }
    let fields = cast(i64*, scratch)
    return fields[0] * 1000 + fields[1] / 1000000
}

let Http:last_errno = fn () -> i64 {
    let location = __errno_location()
    if !location { return 0 }
    return location[0]
}

let Http:wait_fd = fn (fd:i32, events:i64, deadline_ms:i64, scratch:u8*) -> i64 {
    if fd < 0 || !scratch { return 0 }
    let descriptor = cast(Http:PollFd*, &scratch[16])
    while 1 {
        let now = Http:now_ms(scratch)
        if now <= 0 || now >= deadline_ms { return 0 }
        var remaining = deadline_ms - now
        if remaining > 2147483647 { remaining = 2147483647 }
        descriptor.fd = fd
        descriptor.events = cast(u16, events)
        descriptor.revents = cast(u16, 0)
        let ready = poll(cast(u8*, descriptor), 1, cast(i32, remaining))
        if ready > 0 { return 1 }
        if ready == 0 { return 0 }
        if Http:last_errno() != 4 { return 0 }
    }
    return 0
}

// Return values: >=0 bytes/EOF, -1 hard I/O error, -2 deadline expired.
let Http:recv_deadline = fn (
    fd:i32, destination:u8*, bytes:i64, deadline_ms:i64, scratch:u8*
) -> i64 {
    if bytes <= 0 { return 0 }
    while 1 {
        if !Http:wait_fd(fd, 1, deadline_ms, scratch) { return -2 }
        let amount = recv(fd, destination, bytes, 64)
        if amount >= 0 { return amount }
        let error = Http:last_errno()
        if error != 4 && error != 11 { return -1 }
    }
    return -1
}

let Http:send_deadline = fn (
    fd:i32, source:u8*, bytes:i64, deadline_ms:i64, scratch:u8*
) -> i64 {
    if bytes <= 0 { return 0 }
    while 1 {
        if !Http:wait_fd(fd, 4, deadline_ms, scratch) { return -2 }
        let amount = send(fd, source, bytes, 16448)
        if amount >= 0 { return amount }
        let error = Http:last_errno()
        if error != 4 && error != 11 { return -1 }
    }
    return -1
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
    io_scratch:u8*
    write_timeout_ms:i64
    write_deadline_ms:i64
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
    if status == 408 { return "Request Timeout" }
    if status == 409 { return "Conflict" }
    if status == 413 { return "Payload Too Large" }
    if status == 414 { return "URI Too Long" }
    if status == 415 { return "Unsupported Media Type" }
    if status == 422 { return "Unprocessable Content" }
    if status == 429 { return "Too Many Requests" }
    if status == 431 { return "Request Header Fields Too Large" }
    if status == 500 { return "Internal Server Error" }
    if status == 501 { return "Not Implemented" }
    if status == 502 { return "Bad Gateway" }
    if status == 503 { return "Service Unavailable" }
    if status == 505 { return "HTTP Version Not Supported" }
    return "Status"
}

let Http:write_all = fn (
    fd:i32, data:u8*, bytes:i64, io_scratch:u8*, deadline_ms:i64
) -> i64 {
    if fd < 0 || !data || bytes < 0 || !io_scratch { return 0 }
    var sent_bytes = 0
    while sent_bytes < bytes {
        let amount = Http:send_deadline(fd, &data[sent_bytes], bytes - sent_bytes, deadline_ms, io_scratch)
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
    if !self || self.sent || !self.io_scratch { return }
    if self.write_deadline_ms <= 0 {
        let now = Http:now_ms(self.io_scratch)
        if now <= 0 { return }
        self.write_deadline_ms = now + self.write_timeout_ms
    }
    if !content_type { content_type = "application/octet-stream" }
    if !body { body_length = 0 }
    if body_length < 0 { body_length = 0 }

    let line = cast(u8*, malloc(512))
    if !line { return }
    defer free(line)

    let reason = Http:status_reason(status)
    let first_bytes = __snprintf_chk(line, 512, 2, 512, "HTTP/1.1 %ld %s\r\n", status, reason)
    if first_bytes <= 0 || !Http:write_all(self.fd, line, first_bytes, self.io_scratch, self.write_deadline_ms) { return }

    let length_bytes = __snprintf_chk(line, 512, 2, 512, "Content-Length: %ld\r\n", body_length)
    if length_bytes <= 0 || !Http:write_all(self.fd, line, length_bytes, self.io_scratch, self.write_deadline_ms) { return }

    if !Http:write_all(self.fd, "Content-Type: ", 14, self.io_scratch, self.write_deadline_ms) { return }
    if !Http:write_all(self.fd, content_type, Http:strlen(content_type), self.io_scratch, self.write_deadline_ms) { return }
    if !Http:write_all(self.fd, "\r\n", 2, self.io_scratch, self.write_deadline_ms) { return }
    if !Http:write_all(self.fd, "Connection: close\r\n", 19, self.io_scratch, self.write_deadline_ms) { return }

    var current = self.headers
    while current {
        if !Http:write_all(self.fd, current.name, Http:strlen(current.name), self.io_scratch, self.write_deadline_ms) { return }
        if !Http:write_all(self.fd, ": ", 2, self.io_scratch, self.write_deadline_ms) { return }
        if !Http:write_all(self.fd, current.value, Http:strlen(current.value), self.io_scratch, self.write_deadline_ms) { return }
        if !Http:write_all(self.fd, "\r\n", 2, self.io_scratch, self.write_deadline_ms) { return }
        current = current.next
    }

    if !Http:write_all(self.fd, "\r\n", 2, self.io_scratch, self.write_deadline_ms) { return }
    if !self.head_only && body_length > 0 {
        if !Http:write_all(self.fd, body, body_length, self.io_scratch, self.write_deadline_ms) { return }
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

let Http:is_token_char = fn (value:u8) -> i64 {
    if value >= 48 && value <= 57 { return 1 }
    if value >= 65 && value <= 90 { return 1 }
    if value >= 97 && value <= 122 { return 1 }
    if value == 33 || value == 35 || value == 36 || value == 37 || value == 38 { return 1 }
    if value == 39 || value == 42 || value == 43 || value == 45 || value == 46 { return 1 }
    if value == 94 || value == 95 || value == 96 || value == 124 || value == 126 { return 1 }
    return 0
}

// 1 = valid, 0 = malformed, -1 = syntactically valid but above configured body limit.
let Http:parse_content_length = fn (
    source:u8*, start:i64, finish:i64, maximum:i64, output:i64*
) -> i64 {
    if !source || !output || start < 0 || finish < start || maximum < 0 { return 0 }
    var i = start
    while i < finish && (source[i] == 32 || source[i] == 9) { i += 1 }
    if i >= finish || source[i] < 48 || source[i] > 57 { return 0 }

    var value = 0
    while i < finish && source[i] >= 48 && source[i] <= 57 {
        let digit = source[i] - 48
        if value > maximum / 10 { return -1 }
        if value == maximum / 10 && digit > maximum % 10 { return -1 }
        value = value * 10 + digit
        i += 1
    }
    while i < finish && (source[i] == 32 || source[i] == 9) { i += 1 }
    if i != finish { return 0 }
    output[0] = value
    return 1
}

// Returns 0 on success or the HTTP status that should be returned on failure.
let Http:inspect_headers = fn (
    buffer:u8*, request_line_end:i64, header_end:i64, limits:Http:Limits*,
    content_length:i64*, chunked:i64*
) -> i64 {
    if !buffer || !limits || !content_length || !chunked { return 500 }
    content_length[0] = -1
    chunked[0] = 0
    var saw_content_length = 0
    var saw_transfer_encoding = 0
    var count = 0
    var position = request_line_end + 2

    while position < header_end {
        let line_start = position
        while position < header_end && !(buffer[position] == 13 && buffer[position + 1] == 10) { position += 1 }
        let line_end = position
        if line_end <= line_start { return 400 }
        if buffer[line_start] == 32 || buffer[line_start] == 9 { return 400 }

        count += 1
        if count > limits.header_count { return 431 }

        var colon = line_start
        while colon < line_end && buffer[colon] != 58 {
            if !Http:is_token_char(buffer[colon]) { return 400 }
            colon += 1
        }
        if colon <= line_start || colon >= line_end { return 400 }

        if Http:span_equal_ci(buffer, line_start, colon, "Content-Length") {
            if saw_content_length { return 400 }
            saw_content_length = 1
            let parsed = Http:parse_content_length(buffer, colon + 1, line_end, limits.body, content_length)
            if parsed == 0 { return 400 }
            if parsed < 0 { return 413 }
        } else if Http:span_equal_ci(buffer, line_start, colon, "Transfer-Encoding") {
            if saw_transfer_encoding { return 400 }
            saw_transfer_encoding = 1
            var value_start = colon + 1
            var value_end = line_end
            while value_start < value_end && (buffer[value_start] == 32 || buffer[value_start] == 9) { value_start += 1 }
            while value_end > value_start && (buffer[value_end - 1] == 32 || buffer[value_end - 1] == 9) { value_end -= 1 }
            if !Http:span_equal_ci(buffer, value_start, value_end, "chunked") { return 400 }
            chunked[0] = 1
        }
        position += 2
    }

    if saw_content_length && saw_transfer_encoding { return 400 }
    return 0
}

record Http:BodyStream {
    fd:i32
    buffer:u8*
    start:i64
    finish:i64
    deadline_ms:i64
    io_scratch:u8*
}

let Http:BodyStream:new = fn (
    fd:i32, initial:u8*, initial_bytes:i64, deadline_ms:i64, io_scratch:u8*
) -> Http:BodyStream* {
    if initial_bytes < 0 || initial_bytes > 8192 || !io_scratch { return cast(Http:BodyStream*, 0) }
    let stream = cast(Http:BodyStream*, malloc(48))
    if !stream { return cast(Http:BodyStream*, 0) }
    stream.buffer = cast(u8*, malloc(8192))
    if !stream.buffer { free(cast(u8*, stream)); return cast(Http:BodyStream*, 0) }
    stream.fd = fd
    stream.start = 0
    stream.finish = initial_bytes
    stream.deadline_ms = deadline_ms
    stream.io_scratch = io_scratch
    if initial_bytes > 0 { __memcpy_chk(stream.buffer, initial, initial_bytes, 8192) }
    return stream
}

let Http:BodyStream:destroy = fn (self:Http:BodyStream*) -> void {
    if !self { return }
    if self.buffer { free(self.buffer) }
    free(cast(u8*, self))
}

let Http:BodyStream:fill = fn (self:Http:BodyStream*, status:i64*) -> i64 {
    if !self || !status { return 0 }
    if self.start < self.finish { return 1 }
    let amount = Http:recv_deadline(self.fd, self.buffer, 8192, self.deadline_ms, self.io_scratch)
    if amount > 0 {
        self.start = 0
        self.finish = amount
        return 1
    }
    if amount == -2 { status[0] = 408 } else { status[0] = 400 }
    return 0
}

let Http:BodyStream:byte = fn (self:Http:BodyStream*, status:i64*) -> i64 {
    if !self.fill(status) { return -1 }
    let value = self.buffer[self.start]
    self.start += 1
    return value
}

let Http:BodyStream:read = fn (
    self:Http:BodyStream*, destination:u8*, bytes:i64, destination_capacity:i64, status:i64*
) -> i64 {
    if !self || !destination || bytes < 0 || destination_capacity < bytes || !status { return 0 }
    var copied = 0
    while copied < bytes {
        if !self.fill(status) { return 0 }
        var available = self.finish - self.start
        var amount = bytes - copied
        if amount > available { amount = available }
        __memcpy_chk(&destination[copied], &self.buffer[self.start], amount, destination_capacity - copied)
        copied += amount
        self.start += amount
    }
    return 1
}

let Http:read_chunk_size = fn (
    stream:Http:BodyStream*, maximum:i64, line_limit:i64, status:i64*
) -> i64 {
    var size = 0
    var digits = 0
    var extension = 0
    var line_bytes = 0
    while 1 {
        let value = stream.byte(status)
        if value < 0 { return -1 }
        line_bytes += 1
        if line_bytes > line_limit { status[0] = 400; return -1 }

        if value == 13 {
            let lf = stream.byte(status)
            if lf != 10 || digits == 0 { status[0] = 400; return -1 }
            return size
        }
        if value == 10 { status[0] = 400; return -1 }

        if !extension {
            if Http:is_hex(cast(u8, value)) {
                let digit = Http:hex_value(cast(u8, value))
                if size > maximum / 16 { status[0] = 413; return -1 }
                if size == maximum / 16 && digit > maximum % 16 { status[0] = 413; return -1 }
                size = size * 16 + digit
                digits += 1
            } else if value == 59 && digits > 0 {
                extension = 1
            } else {
                status[0] = 400
                return -1
            }
        } else {
            if value < 32 && value != 9 { status[0] = 400; return -1 }
        }
    }
    return -1
}

let Http:read_chunk_trailers = fn (
    stream:Http:BodyStream*, limits:Http:Limits*, status:i64*
) -> i64 {
    var total = 0
    var count = 0
    while 1 {
        var line_bytes = 0
        var saw_colon = 0
        var first = 1
        while 1 {
            let value = stream.byte(status)
            if value < 0 { return 0 }
            total += 1
            if total > limits.headers_total { status[0] = 431; return 0 }
            if value == 13 {
                let lf = stream.byte(status)
                if lf != 10 { status[0] = 400; return 0 }
                total += 1
                if total > limits.headers_total { status[0] = 431; return 0 }
                if line_bytes == 0 { return 1 }
                if !saw_colon { status[0] = 400; return 0 }
                count += 1
                if count > limits.header_count { status[0] = 431; return 0 }
                first = 0
                line_bytes = -1
            } else {
                if value == 10 { status[0] = 400; return 0 }
                if first && (value == 32 || value == 9) { status[0] = 400; return 0 }
                if value == 58 { saw_colon = 1 }
                line_bytes += 1
                first = 0
            }
            if line_bytes < 0 { line_bytes = 0; saw_colon = 0; first = 1; break }
        }
    }
    return 0
}

let Http:decode_chunked = fn (
    stream:Http:BodyStream*, limits:Http:Limits*, status:i64*, body_length:i64*
) -> u8* {
    let output = cast(u8*, malloc(limits.body + 1))
    if !output { status[0] = 500; return cast(u8*, 0) }
    var used = 0

    while 1 {
        let remaining = limits.body - used
        let chunk = Http:read_chunk_size(stream, remaining, limits.chunk_line, status)
        if chunk < 0 { free(output); return cast(u8*, 0) }
        if chunk == 0 {
            if !Http:read_chunk_trailers(stream, limits, status) { free(output); return cast(u8*, 0) }
            output[used] = 0
            body_length[0] = used
            return output
        }
        if !stream.read(&output[used], chunk, limits.body + 1 - used, status) {
            free(output)
            return cast(u8*, 0)
        }
        used += chunk
        let cr = stream.byte(status)
        let lf = stream.byte(status)
        if cr != 13 || lf != 10 {
            status[0] = 400
            free(output)
            return cast(u8*, 0)
        }
    }
    return cast(u8*, 0)
}

let Http:read_request = fn (fd:i32, limits:Http:Limits*, io_scratch:u8*, status:i64*) -> Http:Request* {
    if !limits || !io_scratch || !status { return cast(Http:Request*, 0) }
    status[0] = 400

    let capacity = limits.request_line + limits.headers_total + 6
    let buffer = cast(u8*, malloc(capacity + 1))
    if !buffer { status[0] = 500; return cast(Http:Request*, 0) }

    var used = 0
    var header_end = -1
    var request_line_end = -1
    let header_deadline = Http:now_ms(io_scratch) + limits.header_timeout_ms
    if header_deadline <= limits.header_timeout_ms {
        free(buffer)
        status[0] = 500
        return cast(Http:Request*, 0)
    }

    while header_end < 0 {
        if used >= capacity {
            free(buffer)
            if request_line_end < 0 { status[0] = 414 } else { status[0] = 431 }
            return cast(Http:Request*, 0)
        }
        var available = capacity - used
        if available > 8192 { available = 8192 }
        let amount = Http:recv_deadline(fd, &buffer[used], available, header_deadline, io_scratch)
        if amount <= 0 {
            free(buffer)
            if amount == -2 { status[0] = 408 } else { status[0] = 400 }
            return cast(Http:Request*, 0)
        }
        used += amount
        buffer[used] = 0

        if request_line_end < 0 {
            var i = 0
            while i + 1 < used && request_line_end < 0 {
                if buffer[i] == 13 && buffer[i + 1] == 10 { request_line_end = i }
                i += 1
            }
            if request_line_end > limits.request_line {
                free(buffer)
                status[0] = 414
                return cast(Http:Request*, 0)
            }
            if request_line_end < 0 && used > limits.request_line + 2 {
                free(buffer)
                status[0] = 414
                return cast(Http:Request*, 0)
            }
        }

        header_end = Http:find_header_end(buffer, used)
        if request_line_end >= 0 && header_end >= 0 {
            if header_end < request_line_end + 2 {
                free(buffer)
                status[0] = 400
                return cast(Http:Request*, 0)
            }
            if header_end - request_line_end - 2 > limits.headers_total {
                free(buffer)
                status[0] = 431
                return cast(Http:Request*, 0)
            }
        } else if request_line_end >= 0 && used - request_line_end - 2 > limits.headers_total + 4 {
            free(buffer)
            status[0] = 431
            return cast(Http:Request*, 0)
        }
    }

    if request_line_end < 0 {
        free(buffer)
        status[0] = 400
        return cast(Http:Request*, 0)
    }

    var content_length:i64 = -1
    var chunked:i64 = 0
    let framing_status = Http:inspect_headers(buffer, request_line_end, header_end, limits, &content_length, &chunked)
    if framing_status != 0 {
        free(buffer)
        status[0] = framing_status
        return cast(Http:Request*, 0)
    }

    let body_start = header_end + 4
    let preread = used - body_start
    if preread < 0 || preread > 8192 {
        free(buffer)
        status[0] = 400
        return cast(Http:Request*, 0)
    }

    var body = cast(u8*, 0)
    var body_length:i64 = 0
    if chunked || content_length > 0 {
        let body_deadline = Http:now_ms(io_scratch) + limits.body_timeout_ms
        let stream = Http:BodyStream:new(fd, &buffer[body_start], preread, body_deadline, io_scratch)
        if !stream {
            free(buffer)
            status[0] = 500
            return cast(Http:Request*, 0)
        }
        if chunked {
            body = Http:decode_chunked(stream, limits, status, &body_length)
            stream.destroy()
            if !body { free(buffer); return cast(Http:Request*, 0) }
        } else {
            body = cast(u8*, malloc(content_length + 1))
            if !body {
                stream.destroy()
                free(buffer)
                status[0] = 500
                return cast(Http:Request*, 0)
            }
            if content_length > 0 && !stream.read(body, content_length, content_length + 1, status) {
                stream.destroy()
                free(body)
                free(buffer)
                return cast(Http:Request*, 0)
            }
            stream.destroy()
            body[content_length] = 0
            body_length = content_length
        }
    }

    let request = cast(Http:Request*, malloc(96))
    if !request {
        if body { free(body) }
        free(buffer)
        status[0] = 500
        return cast(Http:Request*, 0)
    }
    request.buffer = buffer
    request.bytes = body_start + body_length
    request.method = buffer
    request.target = cast(u8*, 0)
    request.path = cast(u8*, 0)
    request.query = cast(u8*, 0)
    request.version = cast(u8*, 0)
    request.body = body
    request.body_length = body_length
    request.headers = cast(Http:Header*, 0)
    request.scratch = cast(Http:OwnedText*, 0)
    request.body_storage = body

    // Request line: METHOD SP TARGET SP VERSION CRLF. Empty components and
    // unknown HTTP versions are rejected rather than interpreted loosely.
    var first_space = 0
    while first_space < request_line_end && buffer[first_space] != 32 { first_space += 1 }
    if first_space <= 0 || first_space >= request_line_end { request.destroy(); status[0] = 400; return cast(Http:Request*, 0) }
    buffer[first_space] = 0
    request.target = &buffer[first_space + 1]

    var second_space = first_space + 1
    while second_space < request_line_end && buffer[second_space] != 32 { second_space += 1 }
    if second_space <= first_space + 1 || second_space >= request_line_end { request.destroy(); status[0] = 400; return cast(Http:Request*, 0) }
    buffer[second_space] = 0
    request.version = &buffer[second_space + 1]
    buffer[request_line_end] = 0
    if !Http:text_equal(request.version, "HTTP/1.1") && !Http:text_equal(request.version, "HTTP/1.0") {
        request.destroy()
        status[0] = 505
        return cast(Http:Request*, 0)
    }

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
    if request.path[0] == 0 { request.destroy(); status[0] = 400; return cast(Http:Request*, 0) }

    // Parse validated headers in place. Header nodes own only list structure;
    // names and values point into request.buffer.
    var position = request_line_end + 2
    var tail = cast(Http:Header*, 0)
    while position < header_end {
        let line_start = position
        while position < header_end && !(buffer[position] == 13 && buffer[position + 1] == 10) { position += 1 }
        let line_end = position
        var colon = line_start
        while colon < line_end && buffer[colon] != 58 { colon += 1 }
        buffer[colon] = 0
        var value_start = colon + 1
        var value_end = line_end
        while value_start < value_end && (buffer[value_start] == 32 || buffer[value_start] == 9) { value_start += 1 }
        while value_end > value_start && (buffer[value_end - 1] == 32 || buffer[value_end - 1] == 9) { value_end -= 1 }
        buffer[value_end] = 0
        let item = cast(Http:Header*, malloc(24))
        if !item {
            request.destroy()
            status[0] = 500
            return cast(Http:Request*, 0)
        }
        item.name = &buffer[line_start]
        item.value = &buffer[value_start]
        item.next = cast(Http:Header*, 0)
        if !request.headers { request.headers = item } else { tail.next = item }
        tail = item
        position += 2
    }

    status[0] = 200
    return request
}


// =============================================================================
// Routing, bounded worker queue and server
// =============================================================================

let Http:Handler = fn (request:Http:Request*, response:Http:Response*) -> void

record Http:Route {
    method:u8*
    path:u8*
    handler:Http:Handler
    next:Http:Route*
}

record Http:WorkQueue {
    mutex:u8*
    condition:u8*
    items:i32*
    capacity:i64
    head:i64
    tail:i64
    count:i64
}

record Http:Server {
    fd:i32
    reserve_fd:i32
    port:i64
    address:u8*
    routes:Http:Route*
    route_tail:Http:Route*
    fallback:Http:Handler
    limits:Http:Limits*
    queue:Http:WorkQueue*
}

record Http:SockAddrIn {
    family:u16
    port:u16
    addr:u32
    zero:u64
}

let Http:WorkQueue:new = fn (capacity:i64) -> Http:WorkQueue* {
    if capacity < 1 || capacity > 65536 { return cast(Http:WorkQueue*, 0) }
    let queue = cast(Http:WorkQueue*, malloc(56))
    if !queue { return cast(Http:WorkQueue*, 0) }
    queue.mutex = cast(u8*, malloc(64))
    queue.condition = cast(u8*, malloc(64))
    queue.items = cast(i32*, malloc(capacity * 4))
    queue.capacity = capacity
    queue.head = 0
    queue.tail = 0
    queue.count = 0
    if !queue.mutex || !queue.condition || !queue.items {
        if queue.mutex { free(queue.mutex) }
        if queue.condition { free(queue.condition) }
        if queue.items { free(cast(u8*, queue.items)) }
        free(cast(u8*, queue))
        return cast(Http:WorkQueue*, 0)
    }
    if pthread_mutex_init(queue.mutex, cast(u8*, 0)) != 0 {
        free(queue.mutex)
        free(queue.condition)
        free(cast(u8*, queue.items))
        free(cast(u8*, queue))
        return cast(Http:WorkQueue*, 0)
    }
    if pthread_cond_init(queue.condition, cast(u8*, 0)) != 0 {
        pthread_mutex_destroy(queue.mutex)
        free(queue.mutex)
        free(queue.condition)
        free(cast(u8*, queue.items))
        free(cast(u8*, queue))
        return cast(Http:WorkQueue*, 0)
    }
    return queue
}

let Http:WorkQueue:destroy = fn (self:Http:WorkQueue*) -> void {
    if !self { return }
    if self.condition { pthread_cond_destroy(self.condition); free(self.condition) }
    if self.mutex { pthread_mutex_destroy(self.mutex); free(self.mutex) }
    if self.items { free(cast(u8*, self.items)) }
    free(cast(u8*, self))
}

// Non-blocking producer: a full application queue is overload, not a reason to
// let the acceptor stall behind work that is already queued.
let Http:WorkQueue:push = fn (self:Http:WorkQueue*, client:i32) -> i64 {
    if !self || client < 0 { return 0 }
    if pthread_mutex_lock(self.mutex) != 0 { return 0 }
    if self.count >= self.capacity {
        pthread_mutex_unlock(self.mutex)
        return 0
    }
    self.items[self.tail] = client
    self.tail = (self.tail + 1) % self.capacity
    self.count += 1
    pthread_cond_signal(self.condition)
    pthread_mutex_unlock(self.mutex)
    return 1
}

let Http:WorkQueue:pop = fn (self:Http:WorkQueue*) -> i64 {
    if !self { return -1 }
    if pthread_mutex_lock(self.mutex) != 0 { return -1 }
    while self.count == 0 {
        if pthread_cond_wait(self.condition, self.mutex) != 0 {
            pthread_mutex_unlock(self.mutex)
            return -1
        }
    }
    let client = self.items[self.head]
    self.head = (self.head + 1) % self.capacity
    self.count -= 1
    pthread_mutex_unlock(self.mutex)
    return client
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

// Takes ownership of limits on both success and failure.
let Http:Server:new_on_with_limits = fn (port:i64, address_text:u8*, limits:Http:Limits*) -> Http:Server* {
    if !limits || !limits.valid() {
        if limits { free(cast(u8*, limits)) }
        return cast(Http:Server*, 0)
    }

    let fd = socket(2, 524289, 0)
    if fd < 0 { perror("socket"); free(cast(u8*, limits)); return cast(Http:Server*, 0) }

    var reuse:i32 = 1
    if setsockopt(fd, 1, 2, cast(u8*, &reuse), 4) < 0 {
        perror("setsockopt")
        close(fd)
        free(cast(u8*, limits))
        return cast(Http:Server*, 0)
    }

    let socket_address = cast(Http:SockAddrIn*, malloc(16))
    if !socket_address {
        close(fd)
        free(cast(u8*, limits))
        return cast(Http:Server*, 0)
    }
    socket_address.family = cast(u16, 2)
    socket_address.port = htons(cast(u16, port))
    socket_address.addr = 0
    if address_text { socket_address.addr = inet_addr(address_text) }
    socket_address.zero = 0

    if bind(fd, cast(u8*, socket_address), 16) < 0 {
        perror("bind")
        free(cast(u8*, socket_address))
        close(fd)
        free(cast(u8*, limits))
        return cast(Http:Server*, 0)
    }
    free(cast(u8*, socket_address))

    if listen(fd, cast(i32, limits.listen_backlog)) < 0 {
        perror("listen")
        close(fd)
        free(cast(u8*, limits))
        return cast(Http:Server*, 0)
    }

    let server = cast(Http:Server*, malloc(64))
    if !server {
        close(fd)
        free(cast(u8*, limits))
        return cast(Http:Server*, 0)
    }
    server.fd = fd
    server.reserve_fd = open("/dev/null", 524288)
    server.port = port
    var bind_address = address_text
    if !bind_address { bind_address = "0.0.0.0" }
    server.address = Http:copy_text(bind_address)
    server.routes = cast(Http:Route*, 0)
    server.route_tail = cast(Http:Route*, 0)
    server.fallback = cast(Http:Handler, 0)
    server.limits = limits
    server.queue = cast(Http:WorkQueue*, 0)
    if !server.address {
        if server.reserve_fd >= 0 { close(server.reserve_fd) }
        close(fd)
        free(cast(u8*, limits))
        free(cast(u8*, server))
        return cast(Http:Server*, 0)
    }
    return server
}

let Http:Server:new_on = fn (port:i64, address_text:u8*) -> Http:Server* {
    return Http:Server:new_on_with_limits(port, address_text, Http:Limits:defaults())
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
    if self.reserve_fd >= 0 { close(self.reserve_fd); self.reserve_fd = -1 }
    if self.queue { self.queue.destroy(); self.queue = cast(Http:WorkQueue*, 0) }
    var route = self.routes
    while route {
        let next = route.next
        if route.method { free(route.method) }
        if route.path { free(route.path) }
        free(cast(u8*, route))
        route = next
    }
    if self.address { free(self.address) }
    if self.limits { free(cast(u8*, self.limits)) }
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
    if !self || !self.limits || client < 0 { return 0 }
    let io_scratch = cast(u8*, malloc(24))
    if !io_scratch { return 0 }
    defer free(io_scratch)

    var parse_status:i64 = 400
    let request = Http:read_request(client, self.limits, io_scratch, &parse_status)
    if !request {
        let response = cast(Http:Response*, malloc(56))
        if response {
            response.fd = client
            response.sent = 0
            response.head_only = 0
            response.headers = cast(Http:ResponseHeader*, 0)
            response.io_scratch = io_scratch
            response.write_timeout_ms = self.limits.write_timeout_ms
            response.write_deadline_ms = 0
            response.text(parse_status, Http:status_reason(parse_status))
            response.destroy_headers()
            free(cast(u8*, response))
        }
        return 0
    }
    defer request.destroy()

    let response = cast(Http:Response*, malloc(56))
    if !response { return 0 }
    defer free(cast(u8*, response))
    response.fd = client
    response.sent = 0
    response.head_only = Http:text_equal_ci(request.method, "HEAD")
    response.headers = cast(Http:ResponseHeader*, 0)
    response.io_scratch = io_scratch
    response.write_timeout_ms = self.limits.write_timeout_ms
    response.write_deadline_ms = 0
    defer response.destroy_headers()

    self.dispatch(request, response)
    if !response.sent { response.empty(204) }
    return 1
}

let Http:Server:reject_busy = fn (self:Http:Server*, client:i32) -> void {
    if !self || !self.limits || client < 0 { return }
    let scratch = cast(u8*, malloc(24))
    if scratch {
        let deadline = Http:now_ms(scratch) + self.limits.write_timeout_ms
        Http:write_all(client,
            "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            74, scratch, deadline)
        free(scratch)
    }
}

let Http:worker_main = fn (argument:u8*) -> u8* {
    let server = cast(Http:Server*, argument)
    if !server || !server.queue { return cast(u8*, 0) }
    while 1 {
        let client = server.queue.pop()
        if client >= 0 {
            server.serve_client(cast(i32, client))
            shutdown(cast(i32, client), 2)
            close(cast(i32, client))
        } else {
            usleep(1000)
        }
    }
    return cast(u8*, 0)
}

let Http:Server:start_workers = fn (self:Http:Server*) -> i64 {
    if !self || !self.limits { return 0 }
    var workers = self.limits.workers
    if workers <= 0 { workers = get_nprocs() }
    if workers < 1 { workers = 1 }
    if workers > 1024 { workers = 1024 }

    var capacity = self.limits.queue_capacity
    if capacity <= 0 {
        capacity = workers * 64
        if capacity < 256 { capacity = 256 }
        if capacity > 4096 { capacity = 4096 }
    }
    self.queue = Http:WorkQueue:new(capacity)
    if !self.queue { return 0 }

    var started = 0
    while started < workers {
        var thread:u64 = 0
        let created = pthread_create(&thread, cast(u8*, 0), Http:worker_main, cast(u8*, self))
        if created != 0 {
            if started == 0 {
                self.queue.destroy()
                self.queue = cast(Http:WorkQueue*, 0)
                return 0
            }
            return started
        }
        pthread_detach(thread)
        started += 1
    }
    return started
}

let Http:Server:handle_fd_exhaustion = fn (self:Http:Server*) -> void {
    if !self { return }
    if self.reserve_fd >= 0 {
        close(self.reserve_fd)
        self.reserve_fd = -1
    }
    let dropped = accept4(self.fd, cast(u8*, 0), cast(u32*, 0), 526336)
    if dropped >= 0 { close(dropped) }
    self.reserve_fd = open("/dev/null", 524288)
    usleep(10000)
}

let Http:Server:serve_once = fn (self:Http:Server*) -> i64 {
    if !self || self.fd < 0 { return 0 }
    var client = -1
    while client < 0 {
        client = accept4(self.fd, cast(u8*, 0), cast(u32*, 0), 526336)
        if client < 0 {
            let error = Http:last_errno()
            if error == 4 { client = -1 }
            else { return 0 }
        }
    }
    let ok = self.serve_client(cast(i32, client))
    shutdown(cast(i32, client), 2)
    close(cast(i32, client))
    return ok
}

let Http:Server:run = fn (self:Http:Server*) -> i64 {
    if !self || self.fd < 0 { return 0 }
    let workers = self.start_workers()
    if workers <= 0 {
        printf("HTTP server could not start worker pool\n")
        return 0
    }
    printf("HTTP server listening on http://%s:%ld with %ld workers and queue %ld\n",
        self.address, self.port, workers, self.queue.capacity)

    while 1 {
        let client = accept4(self.fd, cast(u8*, 0), cast(u32*, 0), 526336)
        if client >= 0 {
            if !self.queue.push(cast(i32, client)) {
                self.reject_busy(cast(i32, client))
                shutdown(cast(i32, client), 2)
                close(cast(i32, client))
            }
        } else {
            let error = Http:last_errno()
            if error == 4 || error == 103 {
                // EINTR / ECONNABORTED: retry immediately.
            } else if error == 24 || error == 23 {
                // EMFILE / ENFILE: reserve-fd pattern prevents a hot accept loop
                // and drains one queued connection while descriptors recover.
                self.handle_fd_exhaustion()
            } else if error == 12 || error == 105 {
                // ENOMEM / ENOBUFS: transient resource pressure.
                usleep(50000)
            } else {
                perror("accept4")
                usleep(10000)
            }
        }
    }
    return 1
}


// =============================================================================
// Source-defined `http` routing syntax.
//
// The phrase runs as a rewrite inside compiled RecurLoop code. At that point
// the host has already materialized a context:syntax slice, so LanguageKit's
// SliceLexer is used instead of a private HTTP scanner.
// =============================================================================

let HttpSyntax = phrase { dictionary = true }

let HttpSyntax:error = fn (state:Context*, message:u8*) -> void {
    context:diagnostic:error(state, message)
}

let HttpSyntax:emit_raw = fn (
    state:Context*, source:u8*, start:i64, finish:i64
) -> void {
    if finish > start { context:syntax:emit(state, source, start, finish - start) }
}

let HttpSyntax:emit_number = fn (state:Context*, value:i64) -> void {
    let text = cast(u8*, malloc(32))
    if !text { HttpSyntax:error(state, "http could not format configuration value"); return }
    __snprintf_chk(text, 32, 2, 32, "%ld", value)
    context:syntax:emit(state, text)
    free(text)
}

let HttpSyntax:emit_limit = fn (state:Context*, name:u8*, value:i64) -> void {
    if value < 0 { return }
    context:syntax:emit(state, "__http_limits.")
    context:syntax:emit(state, name)
    context:syntax:emit(state, " = ")
    HttpSyntax:emit_number(state, value)
    context:syntax:emit(state, "\n")
}

let HttpSyntax:safe_decimal = fn (text:u8*, maximum:i64) -> i64 {
    if !text || text[0] == 0 || maximum < 0 { return -1 }
    var value = 0
    var i = 0
    while text[i] != 0 {
        if text[i] < 48 || text[i] > 57 { return -1 }
        let digit = text[i] - 48
        if value > maximum / 10 { return -1 }
        if value == maximum / 10 && digit > maximum % 10 { return -1 }
        value = value * 10 + digit
        i += 1
    }
    return value
}

// kind: 0 plain integer, 1 byte quantity, 2 duration (default milliseconds).
let HttpSyntax:take_scaled = fn (
    state:Context*, reader:LanguageKit:SliceReader*, kind:i64
) -> i64 {
    if LanguageKit:SliceReader:kind_of(reader) != 2 {
        HttpSyntax:error(state, "http limit expects a non-negative integer")
        return -1
    }
    let value = HttpSyntax:safe_decimal(LanguageKit:SliceReader:text_of(reader), 2147483647)
    if value < 0 {
        HttpSyntax:error(state, "http limit integer is too large")
        return -1
    }
    LanguageKit:SliceReader:consume(reader)

    var factor = 1
    if kind == 1 {
        if LanguageKit:SliceReader:is(reader, "B") { LanguageKit:SliceReader:consume(reader) }
        else if LanguageKit:SliceReader:is(reader, "KiB") { factor = 1024; LanguageKit:SliceReader:consume(reader) }
        else if LanguageKit:SliceReader:is(reader, "MiB") { factor = 1048576; LanguageKit:SliceReader:consume(reader) }
        else if LanguageKit:SliceReader:is(reader, "GiB") { factor = 1073741824; LanguageKit:SliceReader:consume(reader) }
    } else if kind == 2 {
        if LanguageKit:SliceReader:is(reader, "ms") { LanguageKit:SliceReader:consume(reader) }
        else if LanguageKit:SliceReader:is(reader, "s") { factor = 1000; LanguageKit:SliceReader:consume(reader) }
    }
    if factor > 1 && value > 2147483647 / factor {
        HttpSyntax:error(state, "http limit value is too large")
        return -1
    }
    return value * factor
}

let HttpSyntax:emit_route = fn (
    state:Context*, method:u8*, source:u8*, path_start:i64, path_end:i64,
    handler_start:i64, handler_end:i64
) -> void {
    context:syntax:emit(state, "__http_server.route(\"")
    context:syntax:emit(state, method)
    context:syntax:emit(state, "\", ")
    HttpSyntax:emit_raw(state, source, path_start, path_end)
    context:syntax:emit(state, ", ")
    HttpSyntax:emit_raw(state, source, handler_start, handler_end)
    context:syntax:emit(state, ")\n")
}

// A route handler is either one identifier or an inline function literal. For
// the latter, consume through its balanced body; SliceReader already keeps
// braces inside strings and comments out of the token stream.
let HttpSyntax:handler_end = fn (reader:LanguageKit:SliceReader*) -> i64 {
    if LanguageKit:SliceReader:kind_of(reader) != 1 { return -1 }
    if !LanguageKit:SliceReader:is(reader, "fn") {
        LanguageKit:SliceReader:consume(reader)
        return reader.position
    }

    LanguageKit:SliceReader:consume(reader)
    var body_started = 0
    var depth = 0
    while LanguageKit:SliceReader:kind_of(reader) != 0 {
        if LanguageKit:SliceReader:match(reader, "{") {
            body_started = 1
            depth += 1
        } else if LanguageKit:SliceReader:match(reader, "}") {
            if !body_started { return -1 }
            depth -= 1
            if depth == 0 { return reader.position }
        } else {
            LanguageKit:SliceReader:consume(reader)
        }
    }
    return -1
}

let http = phrase {
    type = <phrase-types:elaborate>
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = context:syntax:data(state)
        let bytes = context:syntax:bytes(state)
        let reader = LanguageKit:SliceReader:new(state, source, bytes, 136)
        if !reader { HttpSyntax:error(state, "http could not allocate syntax reader"); return }
        defer LanguageKit:SliceReader:destroy(reader)

        var once = 0
        var address_start = -1
        var address_end = -1
        LanguageKit:SliceReader:skip_trivia(reader)
        var address_token_start = reader.position
        if LanguageKit:SliceReader:is(reader, "once") {
            once = 1
            LanguageKit:SliceReader:consume(reader)
            LanguageKit:SliceReader:skip_trivia(reader)
            address_token_start = reader.position
        }
        if LanguageKit:SliceReader:kind_of(reader) == 3 {
            address_start = address_token_start
            address_end = reader.position
            LanguageKit:SliceReader:consume(reader)
        }

        if LanguageKit:SliceReader:kind_of(reader) != 2 {
            HttpSyntax:error(state, "http expects a TCP port from 1 to 65535")
            return
        }
        let port = HttpSyntax:safe_decimal(LanguageKit:SliceReader:text_of(reader), 65535)
        LanguageKit:SliceReader:consume(reader)
        if port <= 0 || port > 65535 {
            HttpSyntax:error(state, "http expects a TCP port from 1 to 65535")
            return
        }

        var request_line = -1
        var headers_total = -1
        var header_count = -1
        var body = -1
        var header_timeout_ms = -1
        var body_timeout_ms = -1
        var write_timeout_ms = -1
        var workers = -1
        var queue_capacity = -1
        var listen_backlog = -1
        var chunk_line = -1

        if LanguageKit:SliceReader:is(reader, "limits") {
            LanguageKit:SliceReader:consume(reader)
            if !LanguageKit:SliceReader:expect(reader, "{", "http limits expects {") { return }
            var limits_closed = 0
            while !limits_closed && LanguageKit:SliceReader:kind_of(reader) != 0 {
                if LanguageKit:SliceReader:match(reader, "}") { limits_closed = 1 }
                else {
                    let key = LanguageKit:SliceReader:take_identifier(reader)
                    if !key { HttpSyntax:error(state, "http limits expects name = value"); return }
                    if !LanguageKit:SliceReader:expect(reader, "=", "http limits expects =") { free(key); return }

                    var value = -1
                    if Http:text_equal(key, "request_line") {
                        if request_line >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: request_line"); return }
                        value = HttpSyntax:take_scaled(state, reader, 1)
                        if value < 256 || value > 1048576 { free(key); HttpSyntax:error(state, "request_line must be 256 B..1 MiB"); return }
                        request_line = value
                    } else if Http:text_equal(key, "headers_total") {
                        if headers_total >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: headers_total"); return }
                        value = HttpSyntax:take_scaled(state, reader, 1)
                        if value < 1024 || value > 8388608 { free(key); HttpSyntax:error(state, "headers_total must be 1 KiB..8 MiB"); return }
                        headers_total = value
                    } else if Http:text_equal(key, "header_count") {
                        if header_count >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: header_count"); return }
                        value = HttpSyntax:take_scaled(state, reader, 0)
                        if value < 1 || value > 4096 { free(key); HttpSyntax:error(state, "header_count must be 1..4096"); return }
                        header_count = value
                    } else if Http:text_equal(key, "body") {
                        if body >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: body"); return }
                        value = HttpSyntax:take_scaled(state, reader, 1)
                        if value < 0 || value > 1073741824 { free(key); HttpSyntax:error(state, "body must be 0 B..1 GiB"); return }
                        body = value
                    } else if Http:text_equal(key, "header_timeout") {
                        if header_timeout_ms >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: header_timeout"); return }
                        value = HttpSyntax:take_scaled(state, reader, 2)
                        if value < 100 || value > 300000 { free(key); HttpSyntax:error(state, "header_timeout must be 100 ms..300 s"); return }
                        header_timeout_ms = value
                    } else if Http:text_equal(key, "body_timeout") {
                        if body_timeout_ms >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: body_timeout"); return }
                        value = HttpSyntax:take_scaled(state, reader, 2)
                        if value < 100 || value > 300000 { free(key); HttpSyntax:error(state, "body_timeout must be 100 ms..300 s"); return }
                        body_timeout_ms = value
                    } else if Http:text_equal(key, "write_timeout") {
                        if write_timeout_ms >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: write_timeout"); return }
                        value = HttpSyntax:take_scaled(state, reader, 2)
                        if value < 100 || value > 300000 { free(key); HttpSyntax:error(state, "write_timeout must be 100 ms..300 s"); return }
                        write_timeout_ms = value
                    } else if Http:text_equal(key, "workers") {
                        if workers >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: workers"); return }
                        value = HttpSyntax:take_scaled(state, reader, 0)
                        if value < 0 || value > 1024 { free(key); HttpSyntax:error(state, "workers must be 0..1024 (0 = CPU count)"); return }
                        workers = value
                    } else if Http:text_equal(key, "queue_capacity") {
                        if queue_capacity >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: queue_capacity"); return }
                        value = HttpSyntax:take_scaled(state, reader, 0)
                        if value < 0 || value > 65536 { free(key); HttpSyntax:error(state, "queue_capacity must be 0..65536 (0 = auto)"); return }
                        queue_capacity = value
                    } else if Http:text_equal(key, "listen_backlog") {
                        if listen_backlog >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: listen_backlog"); return }
                        value = HttpSyntax:take_scaled(state, reader, 0)
                        if value < 1 || value > 65535 { free(key); HttpSyntax:error(state, "listen_backlog must be 1..65535"); return }
                        listen_backlog = value
                    } else if Http:text_equal(key, "chunk_line") {
                        if chunk_line >= 0 { free(key); HttpSyntax:error(state, "duplicate http limit: chunk_line"); return }
                        value = HttpSyntax:take_scaled(state, reader, 1)
                        if value < 64 || value > 65536 { free(key); HttpSyntax:error(state, "chunk_line must be 64 B..64 KiB"); return }
                        chunk_line = value
                    } else {
                        free(key)
                        HttpSyntax:error(state, "unknown http limit")
                        return
                    }
                    free(key)
                    LanguageKit:SliceReader:match(reader, ",")
                }
            }
            if !limits_closed { HttpSyntax:error(state, "http limits block is not closed"); return }
        }

        if !LanguageKit:SliceReader:expect(reader, "{", "http expects a route block") { return }

        context:syntax:emit(state, "if 1 {\n")
        context:syntax:emit(state, "let __http_limits = Http:Limits:defaults()\n")
        context:syntax:emit(state, "if __http_limits {\n")
        HttpSyntax:emit_limit(state, "request_line", request_line)
        HttpSyntax:emit_limit(state, "headers_total", headers_total)
        HttpSyntax:emit_limit(state, "header_count", header_count)
        HttpSyntax:emit_limit(state, "body", body)
        HttpSyntax:emit_limit(state, "header_timeout_ms", header_timeout_ms)
        HttpSyntax:emit_limit(state, "body_timeout_ms", body_timeout_ms)
        HttpSyntax:emit_limit(state, "write_timeout_ms", write_timeout_ms)
        HttpSyntax:emit_limit(state, "workers", workers)
        HttpSyntax:emit_limit(state, "queue_capacity", queue_capacity)
        HttpSyntax:emit_limit(state, "listen_backlog", listen_backlog)
        HttpSyntax:emit_limit(state, "chunk_line", chunk_line)

        context:syntax:emit(state, "let __http_server = Http:Server:new_on_with_limits(")
        HttpSyntax:emit_number(state, port)
        context:syntax:emit(state, ", ")
        if address_start >= 0 { HttpSyntax:emit_raw(state, source, address_start, address_end) }
        else { context:syntax:emit(state, "\"0.0.0.0\"") }
        context:syntax:emit(state, ", __http_limits)\n")
        context:syntax:emit(state, "if __http_server {\n")
        context:syntax:emit(state, "defer Http:Server:destroy(__http_server)\n")

        var closed = 0
        while !closed && LanguageKit:SliceReader:kind_of(reader) != 0 {
            if LanguageKit:SliceReader:match(reader, "}") { closed = 1 }
            else {
                let method = LanguageKit:SliceReader:take_identifier(reader)
                if !method {
                    HttpSyntax:error(state, "http route expects METHOD \"/path\" -> handler")
                    return
                }
                defer free(method)

                LanguageKit:SliceReader:skip_trivia(reader)
                let path_start = reader.position
                if LanguageKit:SliceReader:kind_of(reader) != 3 {
                    HttpSyntax:error(state, "http route path must be a quoted string")
                    return
                }
                let path_end = reader.position
                let path_value = LanguageKit:SliceReader:take_text(reader)
                if path_value { free(path_value) }

                if !LanguageKit:SliceReader:expect(reader, "->", "http route expects -> before the handler") { return }
                LanguageKit:SliceReader:skip_trivia(reader)
                let handler_start = reader.position
                let handler_end = HttpSyntax:handler_end(reader)
                if handler_end <= handler_start {
                    HttpSyntax:error(state, "http route needs a handler name or inline function")
                    return
                }
                HttpSyntax:emit_route(state, method, source, path_start, path_end, handler_start, handler_end)
            }
        }
        if !closed { HttpSyntax:error(state, "http route block is not closed"); return }

        if once { context:syntax:emit(state, "__http_server.serve_once()\n") }
        else { context:syntax:emit(state, "__http_server.run()\n") }
        context:syntax:emit(state, "}\n")
        context:syntax:emit(state, "}\n")
        context:syntax:emit(state, "}\n")
        context:syntax:advance(state, reader.position)
    }
}


languagekit_native_end
engine export "/tmp/recurloop-http-library.rli"
