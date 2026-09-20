// =============================================================================
// RecurLoop native IDE runtime.
//
// This library contains the stable project runner, inotify watching, hot-reload
// lifecycle and persistent terminal models.  UI primitives come from gui.rli;
// concrete application composition lives in examples/07-workflows/ide/*.rl.
// The C++ host remains unaware of both GUI and IDE policy.
// =============================================================================

languagekit_native_begin

link shared "c"
link shared "dl"
link shared "gtk-3"

let IDE = phrase { dictionary = true permanent = true }

// libc / Linux filesystem. Common declarations come from language-kit.rli.
extern realpath(path:u8*, resolved:u8*) -> u8* abi sysv-amd64
extern fopen(path:u8*, mode:u8*) -> u8* abi sysv-amd64
extern fclose(stream:u8*) -> i32 abi sysv-amd64
extern fseek(stream:u8*, offset:i64, origin:i32) -> i32 abi sysv-amd64
extern ftell(stream:u8*) -> i64 abi sysv-amd64
extern fread(target:u8*, size:u64, count:u64, stream:u8*) -> u64 abi sysv-amd64
extern fwrite(source:u8*, size:u64, count:u64, stream:u8*) -> u64 abi sysv-amd64
extern opendir(path:u8*) -> u8* abi sysv-amd64
extern readdir(directory:u8*) -> u8* abi sysv-amd64
extern closedir(directory:u8*) -> i32 abi sysv-amd64
extern inotify_init1(flags:i32) -> i32 abi sysv-amd64
extern inotify_add_watch(fd:i32, path:u8*, mask:u32) -> i32 abi sysv-amd64
extern read(fd:i32, target:u8*, bytes:u64) -> i64 abi sysv-amd64
extern clock_gettime(clock:i32, time:u8*) -> i32 abi sysv-amd64
extern snprintf(buffer:u8*, size:u64, format:u8*, ...) -> i32 abi sysv-amd64
extern fork() -> i32 abi sysv-amd64
extern execvp(file:u8*, argv:u8**) -> i32 abi sysv-amd64
extern waitpid(pid:i32, status:i32*, options:i32) -> i32 abi sysv-amd64
extern _exit(status:i32) -> void abi sysv-amd64
extern kill(pid:i32, signal:i32) -> i32 abi sysv-amd64
extern unlink(path:u8*) -> i32 abi sysv-amd64
extern getpid() -> i32 abi sysv-amd64
extern getenv(name:u8*) -> u8* abi sysv-amd64
extern setenv(name:u8*, value:u8*, overwrite:i32) -> i32 abi sysv-amd64
extern unsetenv(name:u8*) -> i32 abi sysv-amd64
extern usleep(microseconds:u32) -> i32 abi sysv-amd64
extern socket(domain:i32, kind:i32, protocol:i32) -> i32 abi sysv-amd64
extern connect(fd:i32, address:u8*, length:u32) -> i32 abi sysv-amd64
extern recv(fd:i32, buffer:u8*, length:u64, flags:i32) -> i64 abi sysv-amd64
extern send(fd:i32, buffer:u8*, length:u64, flags:i32) -> i64 abi sysv-amd64
extern shutdown(fd:i32, how:i32) -> i32 abi sysv-amd64
extern dlopen(path:u8*, flags:i32) -> u8* abi sysv-amd64
extern dlsym(handle:u8*, symbol:u8*) -> u8* abi sysv-amd64
extern dlclose(handle:u8*) -> i32 abi sysv-amd64
extern dlerror() -> u8* abi sysv-amd64

// GUI widgets are provided by gui.rli.  This library owns only the stable
// project/runtime/hot-reload state and never talks to GTK directly.
let IDE:Lifecycle = fn (action:i64, host:u8*) -> void

record IDE:Timespec {
    seconds:i64
    nanoseconds:i64
}

record IDE:WatchDir {
    wd:i32
    path:u8*
    next:IDE:WatchDir*
}

record IDE:Watcher {
    fd:i32
    root:u8*
    directories:IDE:WatchDir*
}

record IDE:RetiredGeneration {
    pid:i32
    handle:u8*
    socket_path:u8*
    object_path:u8*
    module_path:u8*
    next:IDE:RetiredGeneration*
}

record IDE:Runner {
    program:u8*
    root:u8*
    socket_path:u8*
    object_path:u8*
    module_path:u8*
    pid:i32
    last_status:i32
    generation:u64
    revision:u64
    last_output:u8*
    last_error:u8*
    module:u8*
    lifecycle:IDE:Lifecycle
    retired:IDE:RetiredGeneration*
}

record IDE:RuntimeSession {
    runner:IDE:Runner*
    fd:i32
    last_status:i32
    last_output:u8*
    last_error:u8*
}

// Runtime/transcript survive view hot reload.  GTK widgets never live here;
// every generation creates fresh widgets and callback pointers.
record IDE:Terminal {
    runtime:IDE:RuntimeSession*
    transcript:u8*
    number:i64
    next:IDE:Terminal*
}

// Stable application host.  `content` and `user_data` belong to the currently
// mounted generation; everything else survives rebuilds.
record IDE:Host {
    root:u8*
    entry:u8*
    runner:IDE:Runner*
    window:u8*
    content:u8*
    user_data:u8*
    terminals:IDE:Terminal*
    watcher:IDE:Watcher*
    pending_path:u8*
    selected:u8*
    pending_since:i64
    terminal_number:i64
}

let IDE:copy = fn (text:u8*) -> u8* {
    if !text { return cast(u8*, 0) }
    let bytes = strlen(text)
    let result = cast(u8*, malloc(bytes + 1))
    if !result { return cast(u8*, 0) }
    memcpy(result, text, bytes + 1)
    return result
}

let IDE:join = fn (left:u8*, right:u8*) -> u8* {
    if !left || !right { return cast(u8*, 0) }
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    defer out.destroy()
    if !out.append(left) { return cast(u8*, 0) }
    let bytes = cast(i64, strlen(left))
    if bytes > 0 && left[bytes - 1] != 47 { if !out.append("/") { return cast(u8*, 0) } }
    var start = right
    if right[0] == 47 { start = &right[1] }
    if !out.append(start) { return cast(u8*, 0) }
    return out.take()
}

let IDE:relative = fn (root:u8*, path:u8*) -> u8* {
    if !root || !path { return IDE:copy(path) }
    var i = 0
    while root[i] != 0 && path[i] == root[i] { i += 1 }
    if root[i] == 0 {
        if path[i] == 47 { i += 1 }
        return IDE:copy(&path[i])
    }
    return IDE:copy(path)
}

let IDE:now_ms = fn () -> i64 {
    let ts = cast(IDE:Timespec*, malloc(16))
    if !ts { return 0 }
    defer free(cast(u8*, ts))
    if clock_gettime(1, cast(u8*, ts)) != 0 { return 0 }
    return ts.seconds * 1000 + ts.nanoseconds / 1000000
}

let IDE:read_file = fn (path:u8*) -> u8* {
    if !path { return cast(u8*, 0) }
    let stream = fopen(path, "rb")
    if !stream { return cast(u8*, 0) }
    defer fclose(stream)
    if fseek(stream, 0, 2) != 0 { return cast(u8*, 0) }
    let bytes = ftell(stream)
    if bytes < 0 || bytes > 16777216 { return cast(u8*, 0) }
    if fseek(stream, 0, 0) != 0 { return cast(u8*, 0) }
    let data = cast(u8*, malloc(bytes + 1))
    if !data { return cast(u8*, 0) }
    if bytes > 0 && cast(i64, fread(data, 1, cast(u64, bytes), stream)) != bytes {
        free(data)
        return cast(u8*, 0)
    }
    data[bytes] = 0
    return data
}

let IDE:write_file = fn (path:u8*, data:u8*) -> i64 {
    if !path || !data { return 0 }
    let stream = fopen(path, "wb")
    if !stream { return 0 }
    defer fclose(stream)
    let bytes = strlen(data)
    if bytes == 0 { return 1 }
    return cast(u64, fwrite(data, 1, bytes, stream)) == bytes
}

let IDE:skip_directory = fn (name:u8*) -> i64 {
    if !name { return 1 }
    return strcmp(name, ".") == 0 || strcmp(name, "..") == 0 || strcmp(name, ".git") == 0 ||
           strcmp(name, "build") == 0 || strcmp(name, ".cache") == 0 || strcmp(name, "node_modules") == 0
}

let IDE:is_directory = fn (path:u8*) -> i64 {
    if !path { return 0 }
    let directory = opendir(path)
    if !directory { return 0 }
    closedir(directory)
    return 1
}

let IDE:append_u64 = fn (text:LanguageKit:Text*, input:u64) -> i64 {
    if !text { return 0 }
    let digits = cast(u8*, malloc(32))
    if !digits { return 0 }
    defer free(digits)
    var value = input
    var count = 0
    if value == 0 { digits[0] = 48; count = 1 }
    while value > 0 {
        digits[count] = cast(u8, 48 + value % 10)
        value = value / 10
        count += 1
    }
    var i = 0
    while i < count / 2 {
        let temporary = digits[i]
        digits[i] = digits[count - i - 1]
        digits[count - i - 1] = temporary
        i += 1
    }
    digits[count] = 0
    return text.append(digits)
}

// =============================================================================
// Source-defined project runtime.
//
// Each candidate generation is built in a fresh ordinary `recurloop --serve`
// process. The source-defined runner talks to the existing line protocol over
// a Unix socket, emits one PIC object containing the application lifecycle,
// links a versioned module and loads it into the GTK process. Failed candidates
// are discarded without touching the mounted generation.
// =============================================================================

let IDE:text_contains = fn (text:u8*, needle:u8*) -> i64 {
    if !text || !needle { return 0 }
    let text_bytes = cast(i64, strlen(text))
    let needle_bytes = cast(i64, strlen(needle))
    if needle_bytes == 0 { return 1 }
    var offset = 0
    while offset + needle_bytes <= text_bytes {
        var equal = 1
        var index = 0
        while index < needle_bytes && equal {
            if text[offset + index] != needle[index] { equal = 0 }
            index += 1
        }
        if equal { return 1 }
        offset += 1
    }
    return 0
}

let IDE:append_bytes = fn (text:LanguageKit:Text*, data:u8*, bytes:i64) -> i64 {
    if !text || !data || bytes < 0 || !text.reserve(text.length + bytes + 1) { return 0 }
    if bytes > 0 { memcpy(&text.data[text.length], data, cast(u64, bytes)) }
    text.length += bytes
    text.data[text.length] = 0
    return 1
}

let IDE:append_source_string = fn (text:LanguageKit:Text*, value:u8*) -> i64 {
    if !text || !value || !text.append("\"") { return 0 }
    var index = 0
    while value[index] != 0 {
        if value[index] == 34 || value[index] == 92 {
            if !text.append_byte(92) { return 0 }
        }
        if !text.append_byte(value[index]) { return 0 }
        index += 1
    }
    return text.append("\"")
}

let IDE:artifact = fn (revision:u64, ending:u8*) -> u8* {
    let path = cast(u8*, malloc(256))
    if !path { return cast(u8*, 0) }
    let process = getpid()
    let bytes = snprintf(path, 256, "/tmp/recurloop-ide-%d-%llu%s", process, revision, ending)
    if bytes < 0 || bytes >= 256 { free(path); return cast(u8*, 0) }
    return path
}

let IDE:connect_socket = fn (path:u8*) -> i32 {
    if !path || strlen(path) >= 108 { return -1 }
    let fd = socket(1, 524289, 0)
    if fd < 0 { return -1 }
    let address = cast(u8*, malloc(110))
    if !address { close(fd); return -1 }
    var i = 0
    while i < 110 { address[i] = 0; i += 1 }
    cast(u16*, address)[0] = cast(u16, 1)
    memcpy(&address[2], path, strlen(path) + 1)
    let result = connect(fd, address, 110)
    free(address)
    if result != 0 { close(fd); return -1 }
    return fd
}

let IDE:send_all = fn (fd:i32, data:u8*, bytes:i64) -> i64 {
    if fd < 0 || !data || bytes < 0 { return 0 }
    var offset = 0
    while offset < bytes {
        let written = send(fd, &data[offset], cast(u64, bytes - offset), 16384)
        if written <= 0 { return 0 }
        offset += written
    }
    return 1
}

let IDE:receive_response = fn (fd:i32) -> u8* {
    if fd < 0 { return cast(u8*, 0) }
    let text = LanguageKit:Text:new()
    let buffer = cast(u8*, malloc(4096))
    if !text || !buffer {
        if text { text.destroy() }
        if buffer { free(buffer) }
        return cast(u8*, 0)
    }
    defer text.destroy()
    defer free(buffer)
    while 1 {
        let bytes = recv(fd, buffer, 4096, 0)
        if bytes <= 0 { return cast(u8*, 0) }
        if !IDE:append_bytes(text, buffer, bytes) { return cast(u8*, 0) }
        if text.length >= 2 && text.data[text.length - 2] == 62 && text.data[text.length - 1] == 32 {
            text.length -= 2
            text.data[text.length] = 0
            return text.take()
        }
    }
    return cast(u8*, 0)
}

let IDE:RuntimeSession:clear = fn (self:IDE:RuntimeSession*) -> void {
    if !self { return }
    if self.last_output { free(self.last_output) }
    if self.last_error { free(self.last_error) }
    self.last_output = cast(u8*, 0)
    self.last_error = cast(u8*, 0)
    self.last_status = 0
}

let IDE:RuntimeSession:request = fn (self:IDE:RuntimeSession*, command:u8*) -> i32 {
    if !self || self.fd < 0 || !command { return 1 }
    self.clear()
    if !IDE:send_all(self.fd, command, cast(i64, strlen(command))) || !IDE:send_all(self.fd, "\n", 1) {
        self.last_status = 1
        self.last_error = IDE:copy("runtime connection failed")
        return 1
    }
    let response = IDE:receive_response(self.fd)
    if !response {
        self.last_status = 1
        self.last_error = IDE:copy("runtime connection closed")
        return 1
    }
    let response_bytes = strlen(response)
    let status_line = response_bytes >= 7 && response[0] == 115 && response[1] == 116 && response[2] == 97 &&
                      response[3] == 116 && response[4] == 117 && response[5] == 115 && response[6] == 61
    if status_line || IDE:text_contains(response, "\nstatus=") {
        self.last_status = 1
        self.last_error = response
    } else {
        self.last_output = response
    }
    return self.last_status
}

let IDE:RuntimeSession:new = fn (runner:IDE:Runner*) -> IDE:RuntimeSession* {
    if !runner || !runner.socket_path { return cast(IDE:RuntimeSession*, 0) }
    let fd = IDE:connect_socket(runner.socket_path)
    if fd < 0 { return cast(IDE:RuntimeSession*, 0) }
    let greeting = IDE:receive_response(fd)
    if !greeting { close(fd); return cast(IDE:RuntimeSession*, 0) }
    free(greeting)
    let self = cast(IDE:RuntimeSession*, malloc(32))
    if !self { close(fd); return cast(IDE:RuntimeSession*, 0) }
    self.runner = runner
    self.fd = fd
    self.last_status = 0
    self.last_output = cast(u8*, 0)
    self.last_error = cast(u8*, 0)
    return self
}

let IDE:RuntimeSession:destroy = fn (self:IDE:RuntimeSession*) -> void {
    if !self { return }
    self.clear()
    if self.fd >= 0 { shutdown(self.fd, 2); close(self.fd) }
    free(cast(u8*, self))
}

let IDE:process_success = fn (pid:i32) -> i64 {
    if pid <= 0 { return 0 }
    let status = cast(i32*, malloc(4))
    if !status { return 0 }
    defer free(cast(u8*, status))
    status[0] = 0
    if waitpid(pid, status, 0) != pid { return 0 }
    return status[0] == 0
}

let IDE:Runner:stop = fn (self:IDE:Runner*) -> void {
    if !self { return }
    if self.pid > 0 {
        kill(self.pid, 15)
        let status = cast(i32*, malloc(4))
        if status { waitpid(self.pid, status, 0); free(cast(u8*, status)) }
        self.pid = -1
    }
    if self.socket_path { unlink(self.socket_path) }
}

let IDE:Runner:spawn_server = fn (self:IDE:Runner*) -> i64 {
    if !self || !self.program || !self.socket_path { return 0 }
    unlink(self.socket_path)
    let args = cast(u8**, malloc(48))
    if !args { return 0 }
    args[0] = self.program
    args[1] = "--serve"
    args[2] = "--unix"
    args[3] = self.socket_path
    args[4] = "--no-stdio"
    args[5] = cast(u8*, 0)
    setenv("RECURLOOP_IDE_PROJECT_BUILD", "1", 1)
    let pid = fork()
    if pid < 0 { unsetenv("RECURLOOP_IDE_PROJECT_BUILD"); free(cast(u8*, args)); return 0 }
    if pid == 0 {
        execvp(self.program, args)
        _exit(127)
    }
    unsetenv("RECURLOOP_IDE_PROJECT_BUILD")
    free(cast(u8*, args))
    self.pid = pid
    var attempt = 0
    while attempt < 300 {
        let fd = IDE:connect_socket(self.socket_path)
        if fd >= 0 { close(fd); return 1 }
        usleep(10000)
        attempt += 1
    }
    self.stop()
    return 0
}

let IDE:Runner:driver_source = fn (self:IDE:Runner*, driver:u8*) -> i64 {
    if !self || !driver || !self.root || !self.object_path { return 0 }
    let source = LanguageKit:Text:new()
    if !source { return 0 }
    defer source.destroy()
    source.append("include ")
    if !IDE:append_source_string(source, self.root) { return 0 }
    source.append("\nemit object ")
    if !IDE:append_source_string(source, self.object_path) { return 0 }
    source.append(" recurloop_ide_lifecycle = fn (action:i64, host:u8*) -> void {\n")
    source.append("  if action == 1 { IDE_App:mount(cast(IDE:Host*, host)) }\n")
    source.append("  else if action == 2 { IDE_App:unmount(cast(IDE:Host*, host)) }\n")
    source.append("  else if action == 3 { IDE_App:reload_failed(cast(IDE:Host*, host)) }\n")
    source.append("}\n")
    return IDE:write_file(driver, source.data)
}

let IDE:Runner:link_module = fn (self:IDE:Runner*) -> i64 {
    if !self || !self.object_path || !self.module_path { return 0 }
    let args = cast(u8**, malloc(64))
    if !args { return 0 }
    args[0] = "clang"
    args[1] = "-shared"
    args[2] = self.object_path
    args[3] = "-o"
    args[4] = self.module_path
    args[5] = "-lgtk-3"
    args[6] = "-lc"
    args[7] = cast(u8*, 0)
    let pid = fork()
    if pid < 0 { free(cast(u8*, args)); return 0 }
    if pid == 0 {
        execvp("clang", args)
        _exit(127)
    }
    free(cast(u8*, args))
    if !IDE:process_success(pid) { return 0 }
    self.module = dlopen(self.module_path, 2)
    if !self.module { return 0 }
    let symbol = dlsym(self.module, "recurloop_ide_lifecycle")
    if !symbol { return 0 }
    self.lifecycle = cast(IDE:Lifecycle, symbol)
    return 1
}

let IDE:Runner:candidate = fn (self:IDE:Runner*) -> IDE:Runner* {
    if !self { return cast(IDE:Runner*, 0) }
    let next = cast(IDE:Runner*, malloc(104))
    if !next { return cast(IDE:Runner*, 0) }
    next.program = IDE:copy(self.program)
    next.root = IDE:copy(self.root)
    next.revision = self.revision + 1
    next.generation = self.generation + 1
    next.socket_path = IDE:artifact(next.revision, ".sock")
    next.object_path = IDE:artifact(next.revision, ".o")
    next.module_path = IDE:artifact(next.revision, ".so")
    next.pid = -1
    next.last_status = 1
    next.last_output = cast(u8*, 0)
    next.last_error = cast(u8*, 0)
    next.module = cast(u8*, 0)
    next.lifecycle = cast(IDE:Lifecycle, 0)
    next.retired = cast(IDE:RetiredGeneration*, 0)
    if !next.program || !next.root || !next.socket_path || !next.object_path || !next.module_path {
        next.last_error = IDE:copy("cannot allocate project generation")
        return next
    }

    let driver = IDE:artifact(next.revision, ".rl")
    if !driver || !next.driver_source(driver) || !next.spawn_server() {
        if !next.last_error { next.last_error = IDE:copy("cannot start clean project runtime") }
        if driver { unlink(driver); free(driver) }
        return next
    }

    var build = cast(IDE:RuntimeSession*, 0)
    var attempt = 0
    while !build && attempt < 100 {
        build = IDE:RuntimeSession:new(next)
        if !build { usleep(10000) }
        attempt += 1
    }
    if !build {
        next.last_error = IDE:copy("cannot connect to project runtime")
        unlink(driver); free(driver)
        return next
    }

    var command = LanguageKit:Text:new()
    if command {
        command.append(":load ")
        if !IDE:append_source_string(command, driver) { command.destroy(); command = cast(LanguageKit:Text*, 0) }
    }
    if !command || build.request(command.data) != 0 {
        next.last_error = IDE:copy(build.last_error)
    } else if build.request(":publish") != 0 || !build.last_output || !IDE:text_contains(build.last_output, "published project=") {
        next.last_error = IDE:copy(build.last_error)
        if !next.last_error { next.last_error = IDE:copy("project publication failed") }
    } else if !next.link_module() {
        let error = dlerror()
        next.last_error = IDE:copy(error)
        if !next.last_error { next.last_error = IDE:copy("native lifecycle link failed") }
    } else {
        next.last_status = 0
        next.last_output = IDE:copy("project generation built")
    }
    if command { command.destroy() }
    build.destroy()
    unlink(driver)
    free(driver)
    return next
}

let IDE:Runner:destroy = fn (self:IDE:Runner*) -> void {
    if !self { return }
    self.stop()
    if self.module { dlclose(self.module) }
    var retired = self.retired
    while retired {
        let next = retired.next
        if retired.pid > 0 {
            kill(retired.pid, 15)
            let status = cast(i32*, malloc(4))
            if status { waitpid(retired.pid, status, 0); free(cast(u8*, status)) }
        }
        if retired.handle { dlclose(retired.handle) }
        if retired.socket_path { unlink(retired.socket_path); free(retired.socket_path) }
        if retired.object_path { unlink(retired.object_path); free(retired.object_path) }
        if retired.module_path { unlink(retired.module_path); free(retired.module_path) }
        free(cast(u8*, retired))
        retired = next
    }
    if self.program { free(self.program) }
    if self.root { free(self.root) }
    if self.socket_path { free(self.socket_path) }
    if self.object_path { unlink(self.object_path); free(self.object_path) }
    if self.module_path { unlink(self.module_path); free(self.module_path) }
    if self.last_output { free(self.last_output) }
    if self.last_error { free(self.last_error) }
    free(cast(u8*, self))
}

let IDE:Runner:adopt = fn (self:IDE:Runner*, next:IDE:Runner*) -> i64 {
    if !self || !next || next.last_status != 0 || !next.lifecycle { return 0 }
    if self.pid > 0 || self.module || self.socket_path {
        let retired = cast(IDE:RetiredGeneration*, malloc(48))
        if !retired { return 0 }
        retired.pid = self.pid
        retired.handle = self.module
        retired.socket_path = self.socket_path
        retired.object_path = self.object_path
        retired.module_path = self.module_path
        retired.next = self.retired
        self.retired = retired
        self.pid = -1
        self.module = cast(u8*, 0)
        self.socket_path = cast(u8*, 0)
        self.object_path = cast(u8*, 0)
        self.module_path = cast(u8*, 0)
    }
    if self.last_output { free(self.last_output) }
    if self.last_error { free(self.last_error) }
    self.socket_path = next.socket_path; next.socket_path = cast(u8*, 0)
    self.object_path = next.object_path; next.object_path = cast(u8*, 0)
    self.module_path = next.module_path; next.module_path = cast(u8*, 0)
    self.pid = next.pid; next.pid = -1
    self.generation = next.generation
    self.revision = next.revision
    self.last_status = 0
    self.last_output = next.last_output; next.last_output = cast(u8*, 0)
    self.last_error = next.last_error; next.last_error = cast(u8*, 0)
    self.module = next.module; next.module = cast(u8*, 0)
    self.lifecycle = next.lifecycle; next.lifecycle = cast(IDE:Lifecycle, 0)
    next.destroy()
    return 1
}

let IDE:Runner:remember_failure = fn (self:IDE:Runner*, failed:IDE:Runner*) -> void {
    if !self || !failed { return }
    if self.last_output { free(self.last_output) }
    if self.last_error { free(self.last_error) }
    self.last_status = failed.last_status
    self.revision = failed.revision
    self.last_output = IDE:copy(failed.last_output)
    self.last_error = IDE:copy(failed.last_error)
    failed.destroy()
}

let IDE:Runner:new = fn (program:u8*, root:u8*) -> IDE:Runner* {
    let self = cast(IDE:Runner*, malloc(104))
    if !self { return cast(IDE:Runner*, 0) }
    self.program = IDE:copy(program)
    self.root = IDE:copy(root)
    self.socket_path = cast(u8*, 0)
    self.object_path = cast(u8*, 0)
    self.module_path = cast(u8*, 0)
    self.pid = -1
    self.last_status = 1
    self.generation = 0
    self.revision = 0
    self.last_output = cast(u8*, 0)
    self.last_error = cast(u8*, 0)
    self.module = cast(u8*, 0)
    self.lifecycle = cast(IDE:Lifecycle, 0)
    self.retired = cast(IDE:RetiredGeneration*, 0)
    if !self.program || !self.root { self.destroy(); return cast(IDE:Runner*, 0) }
    return self
}

let IDE:Terminal:append = fn (self:IDE:Terminal*, text:u8*) -> void {
    if !self || !text { return }
    let out = LanguageKit:Text:new()
    if !out { return }
    defer out.destroy()
    if self.transcript { out.append(self.transcript) }
    out.append(text)
    let next = out.take()
    if !next { return }
    if self.transcript { free(self.transcript) }
    self.transcript = next
}

let IDE:terminal_new = fn (host:IDE:Host*) -> IDE:Terminal* {
    if !host || !host.runner { return cast(IDE:Terminal*, 0) }
    let runtime = IDE:RuntimeSession:new(host.runner)
    if !runtime { return cast(IDE:Terminal*, 0) }
    let terminal = cast(IDE:Terminal*, malloc(32))
    if !terminal { runtime.destroy(); return cast(IDE:Terminal*, 0) }
    host.terminal_number += 1
    terminal.runtime = runtime
    terminal.transcript = IDE:copy("")
    terminal.number = host.terminal_number
    terminal.next = host.terminals
    host.terminals = terminal
    return terminal
}

let IDE:free_terminals = fn (host:IDE:Host*) -> void {
    if !host { return }
    var terminal = host.terminals
    while terminal {
        let next = terminal.next
        if terminal.runtime { terminal.runtime.destroy() }
        if terminal.transcript { free(terminal.transcript) }
        free(cast(u8*, terminal))
        terminal = next
    }
    host.terminals = cast(IDE:Terminal*, 0)
}

let IDE:Watcher:find = fn (self:IDE:Watcher*, wd:i32) -> IDE:WatchDir* {
    if !self { return cast(IDE:WatchDir*, 0) }
    var item = self.directories
    while item {
        if item.wd == wd { return item }
        item = item.next
    }
    return cast(IDE:WatchDir*, 0)
}

let IDE:Watcher:remember = fn (self:IDE:Watcher*, wd:i32, path:u8*) -> void {
    if !self || wd < 0 || !path { return }
    let item = cast(IDE:WatchDir*, malloc(24))
    if !item { return }
    item.wd = wd
    item.path = IDE:copy(path)
    item.next = self.directories
    if !item.path { free(cast(u8*, item)); return }
    self.directories = item
}

let IDE:Watcher:add_tree = fn (self:IDE:Watcher*, path:u8*) -> void {
    if !self || !path { return }
    // CLOSE_WRITE | MOVED_FROM | MOVED_TO | CREATE | DELETE | DELETE_SELF | MOVE_SELF
    let wd = inotify_add_watch(self.fd, path, cast(u32, 8 + 64 + 128 + 256 + 512 + 1024 + 2048))
    if wd >= 0 { self.remember(wd, path) }
    let directory = opendir(path)
    if !directory { return }
    defer closedir(directory)
    while 1 {
        let entry = readdir(directory)
        if !entry { return }
        let kind = entry[18]
        let name = &entry[19]
        if !IDE:skip_directory(name) {
            let child = IDE:join(path, name)
            if child {
                if kind == 4 || (kind == 0 && IDE:is_directory(child)) { self.add_tree(child) }
                free(child)
            }
        }
    }
}

let IDE:Watcher:new = fn (root:u8*) -> IDE:Watcher* {
    let fd = inotify_init1(526336)
    if fd < 0 { return cast(IDE:Watcher*, 0) }
    let self = cast(IDE:Watcher*, malloc(24))
    if !self { close(fd); return cast(IDE:Watcher*, 0) }
    self.fd = fd
    self.root = IDE:copy(root)
    self.directories = cast(IDE:WatchDir*, 0)
    if !self.root { close(fd); free(cast(u8*, self)); return cast(IDE:Watcher*, 0) }
    self.add_tree(root)
    return self
}

let IDE:Watcher:destroy = fn (self:IDE:Watcher*) -> void {
    if !self { return }
    var directory = self.directories
    while directory {
        let next = directory.next
        if directory.path { free(directory.path) }
        free(cast(u8*, directory))
        directory = next
    }
    close(self.fd)
    if self.root { free(self.root) }
    free(cast(u8*, self))
}

let IDE:mount_current = fn (host:IDE:Host*) -> i32 {
    if !host || !host.runner || !host.runner.lifecycle { return 1 }
    let lifecycle = host.runner.lifecycle
    lifecycle(1, cast(u8*, host))
    if host.window { Gui:show(host.window) }
    return 0
}

let IDE:reload = fn (host:IDE:Host*, path:u8*) -> void {
    if !host || !host.runner || !path { return }
    let candidate = host.runner.candidate()
    if !candidate || candidate.last_status != 0 {
        if candidate { host.runner.remember_failure(candidate) }
        if host.runner.lifecycle { let lifecycle = host.runner.lifecycle; lifecycle(3, cast(u8*, host)) }
        return
    }

    // The old native module stays mapped until shutdown, so queued foreign
    // callbacks can never jump into unmapped code after the view is destroyed.
    if host.runner.lifecycle { let lifecycle = host.runner.lifecycle; lifecycle(2, cast(u8*, host)) }
    if host.content {
        Gui:destroy(host.content)
        host.content = cast(u8*, 0)
    }
    host.user_data = cast(u8*, 0)
    if !host.runner.adopt(candidate) { candidate.destroy(); return }
    IDE:mount_current(host)
}

let IDE:watch_tick = fn (data:u8*) -> i32 {
    let host = cast(IDE:Host*, data)
    if !host || !host.watcher { return 1 }
    let watcher = host.watcher
    let buffer = malloc(16384)
    if !buffer { return 1 }
    defer free(buffer)

    while 1 {
        let bytes = read(watcher.fd, buffer, 16384)
        if bytes <= 0 { break }
        var offset = 0
        while offset + 16 <= bytes {
            let wd = cast(i32*, &buffer[offset])[0]
            let mask = cast(u32*, &buffer[offset + 4])[0]
            let name_bytes = cast(u32*, &buffer[offset + 12])[0]
            if wd < 0 && (mask / cast(u32, 16384)) % 2 != 0 {
                if host.pending_path { free(host.pending_path) }
                host.pending_path = IDE:copy(host.entry)
                host.pending_since = IDE:now_ms()
            } else {
                let directory = watcher.find(wd)
                if directory {
                    var changed = IDE:copy(directory.path)
                    if name_bytes > 0 && buffer[offset + 16] != 0 {
                        if changed { free(changed) }
                        changed = IDE:join(directory.path, &buffer[offset + 16])
                    }
                    if changed {
                        if host.pending_path { free(host.pending_path) }
                        host.pending_path = changed
                        host.pending_since = IDE:now_ms()
                        let directory_event = (mask / cast(u32, 1073741824)) % 2 != 0
                        let created = (mask / cast(u32, 256)) % 2 != 0 || (mask / cast(u32, 128)) % 2 != 0
                        if directory_event && created { watcher.add_tree(changed) }
                    }
                }
            }
            offset += 16 + name_bytes
        }
    }

    if host.pending_path && IDE:now_ms() - host.pending_since >= 100 {
        let changed = host.pending_path
        host.pending_path = cast(u8*, 0)
        IDE:reload(host, changed)
        free(changed)
    }
    return 1
}

let IDE:on_destroy = fn (widget:u8*, data:u8*) -> void { Gui:quit() }

let IDE:free_host = fn (host:IDE:Host*) -> void {
    if !host { return }
    IDE:free_terminals(host)
    if host.watcher { host.watcher.destroy() }
    if host.pending_path { free(host.pending_path) }
    if host.selected { free(host.selected) }
    if host.runner { host.runner.destroy() }
    if host.entry { free(host.entry) }
    if host.root { free(host.root) }
    free(cast(u8*, host))
}

let IDE:run = fn (program:u8*, root:u8*) -> i64 {
    if !program || !root { return 1 }
    let resolved = realpath(root, cast(u8*, 0))
    if !resolved { return 1 }
    defer free(resolved)
    if !Gui:initialize() { return 1 }

    let host = cast(IDE:Host*, malloc(96))
    if !host { return 1 }
    host.root = IDE:copy(resolved)
    host.entry = IDE:join(resolved, "main.rl")
    host.runner = cast(IDE:Runner*, 0)
    host.window = cast(u8*, 0)
    host.content = cast(u8*, 0)
    host.user_data = cast(u8*, 0)
    host.terminals = cast(IDE:Terminal*, 0)
    host.watcher = cast(IDE:Watcher*, 0)
    host.pending_path = cast(u8*, 0)
    host.selected = cast(u8*, 0)
    host.pending_since = 0
    host.terminal_number = 0
    if !host.root || !host.entry { IDE:free_host(host); return 1 }

    host.window = Gui:window("RecurLoop application", 1280, 820)
    if !host.window { IDE:free_host(host); return 1 }
    Gui:on_destroy(host.window, IDE:on_destroy, cast(u8*, host))

    host.runner = IDE:Runner:new(program, host.entry)
    if !host.runner { IDE:free_host(host); return 1 }
    let candidate = host.runner.candidate()
    if candidate && candidate.last_status == 0 { host.runner.adopt(candidate); IDE:mount_current(host) }
    else if candidate { host.runner.remember_failure(candidate) }

    host.watcher = IDE:Watcher:new(host.root)
    if host.watcher { Gui:timer(50, IDE:watch_tick, cast(u8*, host)) }
    Gui:show(host.window)
    Gui:run()

    if host.runner && host.runner.lifecycle {
        let lifecycle = host.runner.lifecycle
        lifecycle(2, cast(u8*, host))
    }
    IDE:free_host(host)
    return 0
}

// Source-level launch marker. Candidate runtimes receive an explicit build
// argument, so replaying main.rl never starts another GTK event loop.
let ide = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if getenv("RECURLOOP_IDE_PROJECT_BUILD") { return }
        var index = state.exec.args.index
        if index >= state.exec.args.count || !state.exec.args.values[index] || strcmp(state.exec.args.values[index], "--") != 0 {
            context:diagnostic:error(state, "ide requires: -- <application-directory>")
            return
        }
        index += 1
        if index >= state.exec.args.count || index + 1 != state.exec.args.count {
            context:diagnostic:error(state, "ide accepts exactly one application directory after --")
            return
        }
        let root = state.exec.args.values[index]
        state.exec.args.index = state.exec.args.count
        if IDE:run(state.exec.args.values[0], root) != 0 { context:diagnostic:error(state, "IDE failed to start") }
    }
}

languagekit_native_end
include "build/export.rl"
__recurloop_export_library
