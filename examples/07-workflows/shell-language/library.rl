// ============================================================================
// RecurLoop shell DSL - native process pipelines as a library-defined syntax
//
// This example demonstrates a Bash-like system scripting layer implemented in
// RecurLoop itself. The compiler has no built-in knowledge of `run`, `capture`,
// `directory`, `environment`, or `parallel`.
//
// Supported syntax:
//
//   echo "hello directly"
//   cd /tmp
//   pwd
//
//   var name = "RecurLoop"
//   print name
//   run printf "hello {upper(name)}\n"
//   print status
//   capture printf "captured-{name}\n"
//   print captured
//
//   run printf "hello\n"
//   run printf "alpha\nbeta\n" | grep beta > "/tmp/result.txt"
//
//   let captured = capture printf "one\ntwo\n" | tail -n 1 // owned u8*
//   let job = spawn sh -c "sleep 1; printf ready"         // starts now
//   printf("%s (%ld)\n", job.stdout(), job.exit_code())   // waits here
//
//   directory "/tmp" {
//       run pwd > "recurloop-shell-pwd.txt"
//   }
//
//   var RECURLOOP_DEMO = "enabled"
//   environment "RECURLOOP_DEMO" {
//       run printenv RECURLOOP_DEMO
//   }
//
//   parallel {
//       run printf "job-a\n" > "/tmp/recurloop-shell-a.txt"
//       run printf "job-b\n" > "/tmp/recurloop-shell-b.txt"
//   }
//
// Runtime semantics:
//   - unknown top-level lines and explicit `run` enter a phrase graph whose
//     dictionaries represent grammar states;
//   - the phrase actions build argv/pipeline objects directly, without parsing
//     an intermediate command string and without invoking Bash or /bin/sh;
//   - pipelines use fork(2), pipe(2), dup2(2), execvp(3), and waitpid(2);
//   - `>` and `>>` are implemented with open(2), not shell redirection;
//   - quoted arguments and backslash escaping are decoded by this library;
//   - capture reads the last pipeline stdout through a native pipe;
//   - spawn returns an asynchronous Shell:Invocation whose accessors wait;
//   - typed RecurLoop callbacks can consume stdin and produce pipeline stdout;
//   - pipeline failure uses pipefail-like semantics (first non-zero status);
//   - directory/environment scopes restore state through `defer`;
//   - parallel runs each `run` line in its own supervisor process.
//   - `cd` is a parent-process builtin and maintains PWD/OLDPWD.
//
// Deliberately not implemented in this example library:
//   glob expansion, && / ||, heredocs, job control, signals, and arbitrary
//   Bash grammar. PS1 command substitution is handled by the interactive core.
//
// Build reusable language image:
//   Recurloop --file examples/07-workflows/shell-language/library.rl
//
// The build writes:
//   /tmp/recurloop-shell-library.rli
// ============================================================================

link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern realloc(pointer:u8*, size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern memcpy(destination:u8*, source:u8*, bytes:u64) -> u8* abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64
extern fflush(stream:u8*) -> i32 abi sysv-amd64
extern fopen(path:u8*, mode:u8*) -> u8* abi sysv-amd64
extern fclose(stream:u8*) -> i64 abi sysv-amd64
extern fread(pointer:u8*, size:u64, count:u64, stream:u8*) -> u64 abi sysv-amd64

extern fork() -> i32 abi sysv-amd64
extern pipe(fds:i32*) -> i32 abi sysv-amd64
extern dup2(oldfd:i32, newfd:i32) -> i32 abi sysv-amd64
extern close(fd:i32) -> i32 abi sysv-amd64
extern open(path:u8*, flags:i32, ...) -> i32 abi sysv-amd64
extern execvp(file:u8*, argv:u8**) -> i32 abi sysv-amd64
extern perror(prefix:u8*) -> void abi sysv-amd64
extern waitpid(pid:i32, status:i32*, options:i32) -> i32 abi sysv-amd64
extern _exit(status:i32) -> void abi sysv-amd64
extern read(fd:i32, buffer:u8*, count:u64) -> i64 abi sysv-amd64
extern chdir(path:u8*) -> i32 abi sysv-amd64
extern getcwd(buffer:u8*, size:u64) -> u8* abi sysv-amd64
extern getenv(name:u8*) -> u8* abi sysv-amd64
extern setenv(name:u8*, value:u8*, overwrite:i32) -> i32 abi sysv-amd64
extern unsetenv(name:u8*) -> i32 abi sysv-amd64

let Shell = phrase { dictionary = true permanent = true }
let Shell:Internal = phrase { dictionary = true serializable = false }

// The core interactive reader prefers the process environment's PS1 and uses
// this language value as a fallback when the environment does not define it.
var PS1 = "$ "

// Linux/POSIX open(2) constants are used as literals in Shell:open_output.

// ============================================================================
// Small owned-string helpers
// ============================================================================

let Shell:strlen = fn (text:u8*) -> i64 {
    if !text { return 0 }
    var length = 0
    while text[length] != 0 {
        length += 1
    }
    return length
}

let Shell:copy_text = fn (text:u8*) -> u8* {
    if !text { return cast(u8*, 0) }
    let length = Shell:strlen(text)
    let copy = cast(u8*, malloc(length + 1))
    if !copy { return cast(u8*, 0) }
    if length > 0 {
        memcpy(copy, text, length)
    }
    copy[length] = 0
    return copy
}

let Shell:copy_slice = fn (source:u8*, start:i64, finish:i64) -> u8* {
    if !source || finish < start { return cast(u8*, 0) }
    let length = finish - start
    let result = cast(u8*, malloc(length + 1))
    if !result { return cast(u8*, 0) }
    if length > 0 { memcpy(result, &source[start], length) }
    result[length] = 0
    return result
}

let Shell:is_space = fn (byte:u8) -> i64 {
    return byte == 32 || byte == 9 || byte == 10 || byte == 13
}

let Shell:text_equal = fn (left:u8*, right:u8*) -> i64 {
    if !left || !right { return 0 }
    var index = 0
    while left[index] != 0 && right[index] != 0 {
        if left[index] != right[index] { return 0 }
        index += 1
    }
    return left[index] == right[index]
}

// ============================================================================
// Small mutable text builder + interpolation helpers
// ============================================================================

record Shell:Text {
    data:u8*
    length:i64
    capacity:i64
}

let Shell:Text:new = fn () -> Shell:Text* {
    let text = cast(Shell:Text*, malloc(24))
    if !text { return cast(Shell:Text*, 0) }
    text.data = cast(u8*, 0)
    text.length = 0
    text.capacity = 0
    return text
}

let Shell:Text:reserve = fn (self:Shell:Text*, requested:i64) -> i64 {
    if !self { return 0 }
    if requested + 1 <= self.capacity { return 1 }

    var next = self.capacity
    if next < 32 { next = 32 }
    while next < requested + 1 { next *= 2 }

    let grown = cast(u8*, realloc(self.data, next))
    if !grown { return 0 }
    self.data = grown
    self.capacity = next
    if self.length == 0 { self.data[0] = 0 }
    return 1
}

let Shell:Text:append_byte = fn (self:Shell:Text*, value:u8) -> i64 {
    if !self { return 0 }
    if !self.reserve(self.length + 1) { return 0 }
    self.data[self.length] = value
    self.length += 1
    self.data[self.length] = 0
    return 1
}

let Shell:Text:append_bytes = fn (self:Shell:Text*, data:u8*, bytes:i64) -> i64 {
    if !self { return 0 }
    if bytes <= 0 { return 1 }
    if !self.reserve(self.length + bytes) { return 0 }
    memcpy(&self.data[self.length], data, bytes)
    self.length += bytes
    self.data[self.length] = 0
    return 1
}

let Shell:Text:append_text = fn (self:Shell:Text*, text:u8*) -> i64 {
    if !text { return 1 }
    return self.append_bytes(text, Shell:strlen(text))
}

let Shell:Text:take = fn (self:Shell:Text*) -> u8* {
    if !self { return cast(u8*, 0) }
    if !self.data {
        let empty = cast(u8*, malloc(1))
        if !empty { return cast(u8*, 0) }
        empty[0] = 0
        return empty
    }
    let data = self.data
    self.data = cast(u8*, 0)
    self.length = 0
    self.capacity = 0
    return data
}

let Shell:Text:destroy = fn (self:Shell:Text*) -> void {
    if !self { return }
    if self.data { free(self.data) }
    free(cast(u8*, self))
}

let Shell:i64_to_text = fn (value:i64) -> u8* {
    let scratch = cast(u8*, malloc(64))
    if !scratch { return cast(u8*, 0) }
    scratch[63] = 0

    var current = value
    var index = 62
    var negative = 0
    if current < 0 { negative = 1 }

    while current <= -10 || current >= 10 {
        var digit = current % 10
        if digit < 0 { digit = 0 - digit }
        scratch[index] = cast(u8, 48 + digit)
        index -= 1
        current /= 10
    }

    var final_digit = current
    if final_digit < 0 { final_digit = 0 - final_digit }
    scratch[index] = cast(u8, 48 + final_digit)
    index -= 1
    if negative {
        scratch[index] = 45
        index -= 1
    }

    let result = Shell:copy_text(&scratch[index + 1])
    free(scratch)
    return result
}

let Shell:stringify = fn (value:i64) -> u8* {
    return Shell:i64_to_text(value)
}

let Shell:stringify = fn (value:i32) -> u8* {
    return Shell:i64_to_text(value)
}

let Shell:stringify = fn (value:u8*) -> u8* {
    return Shell:copy_text(value)
}

// ============================================================================
// Runtime command model
// ============================================================================

record Shell:Command {
    argv:u8**
    argc:i64
    capacity:i64
}

let Shell:Command:new = fn () -> Shell:Command* {
    let command = cast(Shell:Command*, malloc(24))
    if !command { return cast(Shell:Command*, 0) }
    command.argv = cast(u8**, 0)
    command.argc = 0
    command.capacity = 0
    return command
}

let Shell:Command:reserve = fn (self:Shell:Command*, requested:i64) -> i64 {
    if !self { return 0 }
    if requested + 1 <= self.capacity { return 1 }

    var next = self.capacity
    if next < 4 { next = 4 }
    while next < requested + 1 {
        next *= 2
    }

    let resized = cast(u8**, realloc(cast(u8*, self.argv), next * 8))
    if !resized { return 0 }
    self.argv = resized
    self.capacity = next
    return 1
}

let Shell:Command:add_owned = fn (self:Shell:Command*, value:u8*) -> i64 {
    if !self || !value { return 0 }
    if !self.reserve(self.argc + 1) { return 0 }
    self.argv[self.argc] = value
    self.argc += 1
    self.argv[self.argc] = cast(u8*, 0)
    return 1
}

let Shell:Command:add = fn (self:Shell:Command*, value:u8*) -> i64 {
    let copy = Shell:copy_text(value)
    if !copy { return 0 }
    if !self.add_owned(copy) {
        free(copy)
        return 0
    }
    return 1
}

let Shell:Command:destroy = fn (self:Shell:Command*) -> void {
    if !self { return }
    var i = 0
    while i < self.argc {
        if self.argv[i] { free(self.argv[i]) }
        i += 1
    }
    if self.argv { free(cast(u8*, self.argv)) }
    free(cast(u8*, self))
}

// A native RecurLoop transform consumes all bytes from the previous pipeline
// stage and returns the bytes written to the next stage. The returned pointer
// only needs to remain valid until the callback returns.
let Shell:FunctionPrototype = fn (input:u8*) -> u8*

record Shell:Function {
    callback:Shell:FunctionPrototype
}

let Shell:Function:new = fn (callback:Shell:FunctionPrototype) -> Shell:Function* {
    let function = cast(Shell:Function*, malloc(8))
    if !function { return cast(Shell:Function*, 0) }
    function.callback = callback
    return function
}

let Shell:Function:destroy = fn (self:Shell:Function*) -> void {
    if self { free(cast(u8*, self)) }
}

record Shell:Pipeline {
    commands:Shell:Command**
    functions:Shell:Function**
    count:i64
    capacity:i64
    output_path:u8*
    append:i64
}

let Shell:Pipeline:new = fn () -> Shell:Pipeline* {
    let pipeline = cast(Shell:Pipeline*, malloc(48))
    if !pipeline { return cast(Shell:Pipeline*, 0) }
    pipeline.commands = cast(Shell:Command**, 0)
    pipeline.functions = cast(Shell:Function**, 0)
    pipeline.count = 0
    pipeline.capacity = 0
    pipeline.output_path = cast(u8*, 0)
    pipeline.append = 0
    return pipeline
}

let Shell:Pipeline:reserve = fn (self:Shell:Pipeline*, requested:i64) -> i64 {
    if !self { return 0 }
    if requested <= self.capacity { return 1 }
    var next = self.capacity
    if next < 2 { next = 2 }
    while next < requested { next *= 2 }
    let commands = cast(Shell:Command**, realloc(cast(u8*, self.commands), next * 8))
    if !commands { return 0 }
    self.commands = commands
    let functions = cast(Shell:Function**, realloc(cast(u8*, self.functions), next * 8))
    if !functions { return 0 }
    self.functions = functions
    self.capacity = next
    return 1
}

let Shell:Pipeline:add = fn (self:Shell:Pipeline*, command:Shell:Command*) -> i64 {
    if !self || !command || !self.reserve(self.count + 1) { return 0 }
    self.commands[self.count] = command
    self.functions[self.count] = cast(Shell:Function*, 0)
    self.count += 1
    return 1
}

let Shell:Pipeline:add_function = fn (self:Shell:Pipeline*, function:Shell:Function*) -> i64 {
    if !self || !function || !self.reserve(self.count + 1) { return 0 }
    self.commands[self.count] = cast(Shell:Command*, 0)
    self.functions[self.count] = function
    self.count += 1
    return 1
}

let Shell:Pipeline:add_function = fn (self:Shell:Pipeline*, callback:Shell:FunctionPrototype) -> i64 {
    let function = Shell:Function:new(callback)
    if !function { return 0 }
    if !self.add_function(function) {
        Shell:Function:destroy(function)
        return 0
    }
    return 1
}

let Shell:Pipeline:add_command = fn (self:Shell:Pipeline*, program:u8*, argument:u8*) -> i64 {
    if !self || !program { return 0 }
    let command = Shell:Command:new()
    if !command { return 0 }
    if !command.add(program) || (argument && !command.add(argument)) || !self.add(command) {
        Shell:Command:destroy(command)
        return 0
    }
    return 1
}

let Shell:Pipeline:add_command = fn (self:Shell:Pipeline*, program:u8*) -> i64 {
    return self.add_command(program, cast(u8*, 0))
}

let Shell:Pipeline:destroy = fn (self:Shell:Pipeline*) -> void {
    if !self { return }
    var i = 0
    while i < self.count {
        if self.commands[i] { Shell:Command:destroy(self.commands[i]) }
        if self.functions[i] { Shell:Function:destroy(self.functions[i]) }
        i += 1
    }
    if self.commands { free(cast(u8*, self.commands)) }
    if self.functions { free(cast(u8*, self.functions)) }
    if self.output_path { free(self.output_path) }
    free(cast(u8*, self))
}

// A command is assembled by phrase actions while source is being consumed.
// There is intentionally no string tokenizer and no second shell parser.
record Shell:Build {
    pipeline:Shell:Pipeline*
    command:Shell:Command*
    word:Shell:Text*
    expression:Shell:Text*
    word_open:i64
    redirect:i64
    failed:i64
    capture:i64
}

let Shell:Build:new = fn () -> Shell:Build* {
    let build = cast(Shell:Build*, malloc(64))
    if !build { return cast(Shell:Build*, 0) }
    build.pipeline = Shell:Pipeline:new()
    build.command = Shell:Command:new()
    build.word = Shell:Text:new()
    build.expression = Shell:Text:new()
    build.word_open = 0
    build.redirect = 0
    build.failed = 0
    build.capture = 0
    if !build.pipeline || !build.command || !build.word || !build.expression {
        if build.pipeline { Shell:Pipeline:destroy(build.pipeline) }
        if build.command { Shell:Command:destroy(build.command) }
        if build.word { Shell:Text:destroy(build.word) }
        if build.expression { Shell:Text:destroy(build.expression) }
        free(cast(u8*, build))
        return cast(Shell:Build*, 0)
    }
    return build
}

let Shell:Build:destroy = fn (self:Shell:Build*) -> void {
    if !self { return }
    if self.pipeline { Shell:Pipeline:destroy(self.pipeline) }
    if self.command { Shell:Command:destroy(self.command) }
    if self.word { Shell:Text:destroy(self.word) }
    if self.expression { Shell:Text:destroy(self.expression) }
    free(cast(u8*, self))
}

let Shell:Build:open_word = fn (self:Shell:Build*) -> i64 {
    if !self || self.failed { return 0 }
    self.word_open = 1
    return 1
}

let Shell:Build:append_byte = fn (self:Shell:Build*, value:u8) -> i64 {
    if !self || self.failed { return 0 }
    self.word_open = 1
    if !self.word.append_byte(value) { self.failed = 1; return 0 }
    return 1
}

let Shell:Build:append_text = fn (self:Shell:Build*, value:u8*) -> i64 {
    if !self || self.failed { return 0 }
    self.word_open = 1
    if !self.word.append_text(value) { self.failed = 1; return 0 }
    return 1
}

let Shell:Build:finish_word = fn (self:Shell:Build*) -> i64 {
    if !self || self.failed { return 0 }
    if !self.word_open { return 1 }
    let value = self.word.take()
    if !value { self.failed = 1; return 0 }
    self.word_open = 0

    if self.redirect == 1 {
        self.pipeline.output_path = value
        self.redirect = 2
        return 1
    }
    if self.redirect == 2 {
        free(value)
        self.failed = 1
        return 0
    }
    if !self.command.add_owned(value) {
        free(value)
        self.failed = 1
        return 0
    }
    return 1
}

let Shell:Build:pipe = fn (self:Shell:Build*) -> i64 {
    if !self || !self.finish_word() || self.redirect != 0 || self.command.argc == 0 {
        if self { self.failed = 1 }
        return 0
    }
    if !self.pipeline.add(self.command) { self.failed = 1; return 0 }
    self.command = Shell:Command:new()
    if !self.command { self.failed = 1; return 0 }
    return 1
}

let Shell:Build:redirect_to = fn (self:Shell:Build*, append:i64) -> i64 {
    if !self || !self.finish_word() || self.redirect != 0 || self.command.argc == 0 {
        if self { self.failed = 1 }
        return 0
    }
    self.redirect = 1
    self.pipeline.append = append
    return 1
}

let Shell:Build:finish = fn (self:Shell:Build*) -> Shell:Pipeline* {
    if !self || !self.finish_word() || self.failed || self.redirect == 1 || self.command.argc == 0 {
        return cast(Shell:Pipeline*, 0)
    }
    if !self.pipeline.add(self.command) { self.failed = 1; return cast(Shell:Pipeline*, 0) }
    self.command = cast(Shell:Command*, 0)
    let result = self.pipeline
    self.pipeline = cast(Shell:Pipeline*, 0)
    return result
}

let Shell:Text:clear = fn (self:Shell:Text*) -> void {
    if !self { return }
    self.length = 0
    if self.data { self.data[0] = 0 }
}

// ============================================================================
// Native process execution
// ============================================================================

let Shell:decode_status = fn (status:i32) -> i64 {
    let numeric = cast(i64, status)
    if numeric % 128 != 0 {
        return 128 + numeric % 128
    }
    return numeric / 256 % 256
}

let Shell:open_output = fn (pipeline:Shell:Pipeline*) -> i32 {
    if !pipeline || !pipeline.output_path { return cast(i32, -1) }
    var flags = 65
    if pipeline.append {
        flags += 1024
    } else {
        flags += 512
    }
    return open(pipeline.output_path, cast(i32, flags), cast(i32, 420))
}

// A pipeline starts immediately and owns its child processes. Reading any
// result property is the synchronization point: it drains captured stdout,
// waits once, caches the result, and makes subsequent reads inexpensive.
record Shell:Invocation {
    pids:i32*
    count:i64
    capture_fd:i64
    output:u8*
    result:i64
    completed:i64
    spawn_failed:i64
}

let Shell:read_all = fn (fd:i32) -> u8* {
    let text = Shell:Text:new()
    let buffer = cast(u8*, malloc(4096))
    if !text || !buffer {
        if text { Shell:Text:destroy(text) }
        if buffer { free(buffer) }
        return cast(u8*, 0)
    }
    var reading = 1
    while reading {
        let got = read(fd, buffer, 4096)
        if got <= 0 { reading = 0 }
        else if !text.append_bytes(buffer, got) { reading = 0 }
    }
    free(buffer)
    let result = text.take()
    Shell:Text:destroy(text)
    return result
}

let Shell:Function:invoke = fn (self:Shell:Function*) -> i64 {
    if !self { return 126 }
    let callback = self.callback
    if !callback { return 126 }
    let input = Shell:read_all(cast(i32, 0))
    if !input { return 126 }
    let output = callback(input)
    if output { printf("%s", output) }
    fflush(cast(u8*, 0))
    free(input)
    return 0
}

// Builtins which must affect the RecurLoop process run before the fork/exec
// path. A negative result means that the command was not a builtin.
let Shell:run_builtin = fn (pipeline:Shell:Pipeline*) -> i64 {
    if !pipeline || pipeline.count != 1 || pipeline.output_path {
        return -1
    }
    let command = pipeline.commands[0]
    if !command || command.argc == 0 || !Shell:text_equal(command.argv[0], "cd") {
        return -1
    }
    if command.argc > 2 { return 2 }

    var requested = cast(u8*, 0)
    var expanded = cast(u8*, 0)
    var print_path = 0
    if command.argc == 1 {
        requested = getenv("HOME")
    } else {
        requested = command.argv[1]
        if requested[0] == 45 && requested[1] == 0 {
            requested = getenv("OLDPWD")
            print_path = 1
        } else if requested[0] == 126 && (requested[1] == 0 || requested[1] == 47) {
            let home = getenv("HOME")
            if home {
                let text = Shell:Text:new()
                if text {
                    text.append_text(home)
                    text.append_text(&requested[1])
                    expanded = text.take()
                    Shell:Text:destroy(text)
                    requested = expanded
                }
            }
        }
    }

    if !requested {
        if expanded { free(expanded) }
        return 1
    }

    let previous = cast(u8*, malloc(4096))
    if !previous {
        if expanded { free(expanded) }
        return 1
    }
    if !getcwd(previous, 4096) || chdir(requested) != 0 {
        perror("cd")
        free(previous)
        if expanded { free(expanded) }
        return 1
    }

    let current = cast(u8*, malloc(4096))
    if current && getcwd(current, 4096) {
        setenv("OLDPWD", previous, cast(i32, 1))
        setenv("PWD", current, cast(i32, 1))
        if print_path { printf("%s\n", current) }
    }
    if current { free(current) }
    free(previous)
    if expanded { free(expanded) }
    return 0
}

let Shell:Invocation:start = fn (
    pipeline:Shell:Pipeline*, capture:i64
) -> Shell:Invocation* {
    if !pipeline || pipeline.count <= 0 || (capture && pipeline.output_path) {
        return cast(Shell:Invocation*, 0)
    }

    let invocation = cast(Shell:Invocation*, malloc(56))
    if !invocation { return cast(Shell:Invocation*, 0) }
    invocation.pids = cast(i32*, 0)
    invocation.count = 0
    invocation.capture_fd = -1
    invocation.output = cast(u8*, 0)
    invocation.result = 0
    invocation.completed = 0
    invocation.spawn_failed = 0

    // Parent-process builtins (notably cd) must take effect synchronously.
    let builtin = Shell:run_builtin(pipeline)
    if builtin >= 0 {
        invocation.result = builtin
        invocation.completed = 1
        if capture { invocation.output = Shell:copy_text("") }
        return invocation
    }

    fflush(cast(u8*, 0))
    invocation.pids = cast(i32*, malloc(pipeline.count * 4))
    if !invocation.pids {
        free(cast(u8*, invocation))
        return cast(Shell:Invocation*, 0)
    }

    var capture_fds = cast(i32*, 0)
    if capture {
        capture_fds = cast(i32*, malloc(8))
        if !capture_fds || pipe(capture_fds) != 0 {
            if capture_fds { free(cast(u8*, capture_fds)) }
            free(cast(u8*, invocation.pids))
            free(cast(u8*, invocation))
            return cast(Shell:Invocation*, 0)
        }
    }

    var previous_read = -1
    var index = 0
    while index < pipeline.count && invocation.spawn_failed == 0 {
        var next_fds = cast(i32*, 0)
        if index + 1 < pipeline.count {
            next_fds = cast(i32*, malloc(8))
            if !next_fds || pipe(next_fds) != 0 {
                if next_fds { free(cast(u8*, next_fds)) }
                invocation.spawn_failed = 1
            }
        }

        if invocation.spawn_failed == 0 {
            let pid = fork()
            if pid < 0 {
                if next_fds {
                    close(next_fds[0])
                    close(next_fds[1])
                    free(cast(u8*, next_fds))
                }
                invocation.spawn_failed = 1
            } else if pid == 0 {
                if previous_read >= 0 { dup2(cast(i32, previous_read), cast(i32, 0)) }
                if next_fds {
                    dup2(next_fds[1], cast(i32, 1))
                } else if capture {
                    dup2(capture_fds[1], cast(i32, 1))
                } else if pipeline.output_path {
                    let output_fd = Shell:open_output(pipeline)
                    if output_fd < 0 { _exit(cast(i32, 126)) }
                    dup2(output_fd, cast(i32, 1))
                    close(output_fd)
                }

                if previous_read >= 0 { close(cast(i32, previous_read)) }
                if next_fds {
                    close(next_fds[0])
                    close(next_fds[1])
                }
                if capture_fds {
                    close(capture_fds[0])
                    close(capture_fds[1])
                }

                let function = pipeline.functions[index]
                if function { _exit(cast(i32, function.invoke())) }
                let command = pipeline.commands[index]
                execvp(command.argv[0], command.argv)
                perror(command.argv[0])
                _exit(cast(i32, 127))
            } else {
                invocation.pids[invocation.count] = pid
                invocation.count += 1
                if previous_read >= 0 { close(cast(i32, previous_read)) }
                if next_fds {
                    close(next_fds[1])
                    previous_read = cast(i64, next_fds[0])
                    free(cast(u8*, next_fds))
                } else {
                    previous_read = -1
                }
            }
        }
        index += 1
    }

    if previous_read >= 0 { close(cast(i32, previous_read)) }
    if capture_fds {
        close(capture_fds[1])
        invocation.capture_fd = capture_fds[0]
        free(cast(u8*, capture_fds))
    }
    return invocation
}

let Shell:Invocation:await = fn (self:Shell:Invocation*) -> i64 {
    if !self { return 126 }
    if self.completed { return self.result }

    if self.capture_fd >= 0 {
        self.output = Shell:read_all(cast(i32, self.capture_fd))
        close(cast(i32, self.capture_fd))
        self.capture_fd = -1
    }

    var first_failure = 0
    if self.spawn_failed { first_failure = 126 }
    var index = 0
    while index < self.count {
        let status = cast(i32*, malloc(4))
        if status {
            status[0] = 0
            if waitpid(self.pids[index], status, cast(i32, 0)) >= 0 {
                let code = Shell:decode_status(status[0])
                if code != 0 && first_failure == 0 { first_failure = code }
            } else if first_failure == 0 {
                first_failure = 255
            }
            free(cast(u8*, status))
        } else if first_failure == 0 {
            first_failure = 255
        }
        index += 1
    }
    if self.pids { free(cast(u8*, self.pids)) }
    self.pids = cast(i32*, 0)
    self.count = 0
    if !self.output { self.output = Shell:copy_text("") }
    self.result = first_failure
    self.completed = 1
    return self.result
}

let Shell:Invocation:exit_code = fn (self:Shell:Invocation*) -> i64 {
    return self.await()
}

let Shell:Invocation:wait = fn (self:Shell:Invocation*) -> i64 {
    return self.await()
}

let Shell:Invocation:stdout = fn (self:Shell:Invocation*) -> u8* {
    self.await()
    return self.output
}

let Shell:Invocation:destroy = fn (self:Shell:Invocation*) -> void {
    if !self { return }
    self.await()
    if self.output { free(self.output) }
    free(cast(u8*, self))
}

// Compatibility result used by the programmatic capture_pipeline API.
record Shell:Capture {
    output:u8*
    exit_code:i64
}

let Shell:Capture:destroy = fn (self:Shell:Capture*) -> void {
    if !self { return }
    if self.output { free(self.output) }
    free(cast(u8*, self))
}

let Shell:run_pipeline = fn (pipeline:Shell:Pipeline*) -> i64 {
    let invocation = Shell:Invocation:start(pipeline, 0)
    if !invocation { return 126 }
    let code = invocation.exit_code()
    invocation.destroy()
    return code
}

let Shell:capture_pipeline = fn (pipeline:Shell:Pipeline*) -> Shell:Capture* {
    let invocation = Shell:Invocation:start(pipeline, 1)
    if !invocation { return cast(Shell:Capture*, 0) }
    let result = cast(Shell:Capture*, malloc(16))
    if !result { invocation.destroy(); return cast(Shell:Capture*, 0) }
    result.output = Shell:copy_text(invocation.stdout())
    result.exit_code = invocation.exit_code()
    invocation.destroy()
    if !result.output {
        free(cast(u8*, result))
        return cast(Shell:Capture*, 0)
    }
    return result
}

// ============================================================================
// Scoped working directory and environment guards
// ============================================================================

record Shell:DirectoryGuard {
    previous:u8*
    active:i64
}

let Shell:cwd_enter = fn (path:u8*) -> Shell:DirectoryGuard* {
    if !path { return cast(Shell:DirectoryGuard*, 0) }
    let guard = cast(Shell:DirectoryGuard*, malloc(16))
    if !guard { return cast(Shell:DirectoryGuard*, 0) }
    guard.previous = cast(u8*, malloc(4096))
    guard.active = 0
    if !guard.previous {
        free(cast(u8*, guard))
        return cast(Shell:DirectoryGuard*, 0)
    }
    if !getcwd(guard.previous, 4096) {
        free(guard.previous)
        free(cast(u8*, guard))
        return cast(Shell:DirectoryGuard*, 0)
    }
    if chdir(path) != 0 {
        free(guard.previous)
        free(cast(u8*, guard))
        return cast(Shell:DirectoryGuard*, 0)
    }
    guard.active = 1
    return guard
}

let Shell:cwd_leave = fn (guard:Shell:DirectoryGuard*) -> void {
    if !guard { return }
    if guard.active && guard.previous {
        chdir(guard.previous)
    }
    if guard.previous { free(guard.previous) }
    free(cast(u8*, guard))
}

record Shell:EnvGuard {
    name:u8*
    previous:u8*
    had_previous:i64
}

let Shell:env_enter = fn (name:u8*, value:u8*) -> Shell:EnvGuard* {
    if !name || !value { return cast(Shell:EnvGuard*, 0) }
    let guard = cast(Shell:EnvGuard*, malloc(24))
    if !guard { return cast(Shell:EnvGuard*, 0) }
    guard.name = name
    let old = getenv(name)
    if old {
        guard.previous = Shell:copy_text(old)
        guard.had_previous = 1
    } else {
        guard.previous = cast(u8*, 0)
        guard.had_previous = 0
    }
    if setenv(name, value, cast(i32, 1)) != 0 {
        if guard.previous { free(guard.previous) }
        free(cast(u8*, guard))
        return cast(Shell:EnvGuard*, 0)
    }
    return guard
}

let Shell:env_leave = fn (guard:Shell:EnvGuard*) -> void {
    if !guard { return }
    if guard.had_previous {
        setenv(guard.name, guard.previous, cast(i32, 1))
    } else {
        unsetenv(guard.name)
    }
    if guard.previous { free(guard.previous) }
    free(cast(u8*, guard))
}

// ============================================================================
// Parallel jobs. Each job is a supervisor process running a native pipeline.
// ============================================================================

record Shell:Parallel {
    pids:i32*
    count:i64
    capacity:i64
}

let Shell:Parallel:new = fn () -> Shell:Parallel* {
    let jobs = cast(Shell:Parallel*, malloc(24))
    if !jobs { return cast(Shell:Parallel*, 0) }
    jobs.pids = cast(i32*, 0)
    jobs.count = 0
    jobs.capacity = 0
    return jobs
}

let Shell:Parallel:reserve = fn (self:Shell:Parallel*, requested:i64) -> i64 {
    if requested <= self.capacity { return 1 }
    var next = self.capacity
    if next < 4 { next = 4 }
    while next < requested { next *= 2 }
    let grown = cast(i32*, realloc(cast(u8*, self.pids), next * 4))
    if !grown { return 0 }
    self.pids = grown
    self.capacity = next
    return 1
}

let Shell:Parallel:spawn = fn (self:Shell:Parallel*, pipeline:Shell:Pipeline*) -> i64 {
    if !self || !pipeline { return 0 }
    if !self.reserve(self.count + 1) { return 0 }
    fflush(cast(u8*, 0))
    let pid = fork()
    if pid < 0 { return 0 }
    if pid == 0 {
        let code = Shell:run_pipeline(pipeline)
        _exit(cast(i32, code))
    }
    self.pids[self.count] = pid
    self.count += 1
    return 1
}

let Shell:Parallel:wait = fn (self:Shell:Parallel*) -> i64 {
    if !self { return 255 }
    var first_failure = 0
    var i = 0
    while i < self.count {
        let status = cast(i32*, malloc(4))
        if !status {
            if first_failure == 0 { first_failure = 255 }
        } else {
            status[0] = 0
            if waitpid(self.pids[i], status, cast(i32, 0)) >= 0 {
                let code = Shell:decode_status(status[0])
                if code != 0 && first_failure == 0 { first_failure = code }
            } else if first_failure == 0 {
                first_failure = 255
            }
            free(cast(u8*, status))
        }
        i += 1
    }
    self.count = 0
    return first_failure
}

let Shell:Parallel:destroy = fn (self:Shell:Parallel*) -> void {
    if !self { return }
    if self.count > 0 { self.wait() }
    if self.pids { free(cast(u8*, self.pids)) }
    free(cast(u8*, self))
}

let Shell:Parallel:spawn_command = fn (
    self:Shell:Parallel*, program:u8*, argument:u8*, output:u8*
) -> i64 {
    let build = Shell:Build:new()
    if !build { return 0 }
    defer Shell:Build:destroy(build)
    build.append_text(program)
    build.finish_word()
    build.append_text(argument)
    build.finish_word()
    if output {
        build.redirect_to(0)
        build.append_text(output)
    }
    let pipeline = build.finish()
    if !pipeline { return 0 }
    defer Shell:Pipeline:destroy(pipeline)
    return self.spawn(pipeline)
}

// Phrase state shared by the top-level shell grammar
// ============================================================================

let Shell:state_number = fn (text:u8*) -> i64 {
    if !text { return 0 }
    var value = 0
    var i = 0
    while text[i] >= 48 && text[i] <= 57 {
        value = value * 10 + text[i] - 48
        i += 1
    }
    return value
}

let Shell:state_set = fn (state:Context*, name:u8*, value:i64) -> i64 {
    let text = Shell:i64_to_text(value)
    if !text { return 0 }
    defer free(text)
    if context:value:contains(state, name) {
        return context:value:assign:text(state, name, text)
    }
    return context:value:define:text(state, name, text)
}

let Shell:state_get = fn (state:Context*, name:u8*) -> i64 {
    if !context:value:contains(state, name) { return 0 }
    let text = context:value:format(state, name)
    if !text { return 0 }
    defer free(text)
    return Shell:state_number(text)
}

let Shell:active_build = fn (state:Context*) -> Shell:Build* {
    return cast(Shell:Build*, Shell:state_get(state, "__shell_phrase_build"))
}

let Shell:active_parallel = fn (state:Context*) -> Shell:Parallel* {
    return cast(Shell:Parallel*, Shell:state_get(state, "__shell_phrase_parallel"))
}

let Shell:store_status = fn (state:Context*, value:i64) -> i64 {
    if context:value:contains(state, "status") {
        return context:value:assign:integer(state, "status", value)
    }
    return context:value:define:integer(state, "status", value)
}

let Shell:store_capture = fn (state:Context*, value:u8*) -> i64 {
    if context:value:contains(state, "captured") {
        return context:value:assign:text(state, "captured", value)
    }
    return context:value:define:text(state, "captured", value)
}

let Shell:state_set_text = fn (state:Context*, name:u8*, value:u8*) -> i64 {
    if context:value:contains(state, name) {
        return context:value:assign:text(state, name, value)
    }
    return context:value:define:text(state, name, value)
}

let Shell:source_line_end = fn (state:Context*, start:i64) -> i64 {
    var finish = start
    var quote = 0
    var done = 0
    while !done {
        let ch = context:source:peek(state, finish)
        if ch == 0 || ch == 10 || ch == 13 {
            done = 1
        } else if quote != 0 {
            if ch == 92 {
                finish += 1
                if context:source:peek(state, finish) != 0 { finish += 1 }
            } else if ch == quote {
                quote = 0
                finish += 1
            } else {
                finish += 1
            }
        } else if ch == 34 || ch == 39 {
            quote = ch
            finish += 1
        } else {
            finish += 1
        }
    }
    return finish
}

// ============================================================================
// Natural top-level grammar: every transition is a phrase transition
// ============================================================================

let Shell:Grammar = []

let Shell:natural_grammar = fn (state:Context*, name:u8*) -> i64 {
    let shell = context:phrase:find(state, "Shell")
    let grammar = context:phrase:find:exact(state, shell, "Grammar")
    return context:phrase:find:exact(state, grammar, name)
}

let Shell:Grammar:command = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
}

let Shell:Grammar:double = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:command>
}

let Shell:Grammar:single = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:command>
}

let Shell:Grammar:escape = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:command>
}

let Shell:Grammar:double_escape = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:double>
}

let Shell:Grammar:single_escape = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:single>
}

let Shell:Grammar:interpolation = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:command>
}

let Shell:Grammar:double_interpolation = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:double>
}

let Shell:Grammar:nested = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:interpolation>
}

let Shell:Grammar:double_nested = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:double_interpolation>
}

let Shell:Grammar:expression_double = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:interpolation>
}

let Shell:Grammar:expression_single = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:interpolation>
}

let Shell:Grammar:double_expression_double = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:double_interpolation>
}

let Shell:Grammar:double_expression_single = phrase {
    dictionary = true
    type = <phrase-types:elaborate>
    action = <debug>
    successor = <Shell:Grammar:double_interpolation>
}

let Shell:emit = fn (state:Context*, text:u8*) -> void {
    context:syntax:emit(state, text)
}

let Shell:Internal:token_byte = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            let data = context:syntax:data(state)
            let value = Shell:i64_to_text(data[0])
            if !value { return }
            defer free(value)
            context:syntax:advance(state, 1)
            Shell:emit(state, "Shell:Build:append_byte(__shell_build, cast(u8, ")
            Shell:emit(state, value)
            Shell:emit(state, "))\n")
            return
        }
        let build = Shell:active_build(state)
        if !build {
            context:diagnostic:error(state, "shell phrase state is unavailable")
            return
        }
        let byte = cast(u8, context:source:peek(state, 0))
        context:source:advance(state, 1)
        build.append_byte(byte)
    }
}

let Shell:Internal:token_escape_byte = phrase {
    type = <phrase-types:scoped-callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            let data = context:syntax:data(state)
            let value = Shell:i64_to_text(data[0])
            if !value { return }
            defer free(value)
            context:syntax:advance(state, 1)
            Shell:emit(state, "Shell:Build:append_byte(__shell_build, cast(u8, ")
            Shell:emit(state, value)
            Shell:emit(state, "))\n")
            return
        }
        let build = Shell:active_build(state)
        if !build {
            context:diagnostic:error(state, "shell phrase state is unavailable")
            return
        }
        let byte = cast(u8, context:source:peek(state, 0))
        context:source:advance(state, 1)
        build.append_byte(byte)
    }
}

let Shell:Internal:token_expression_byte = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { context:syntax:copy(state, 1); return }
        let build = Shell:active_build(state)
        if !build { context:diagnostic:error(state, "shell interpolation state is unavailable"); return }
        let byte = cast(u8, context:source:peek(state, 0))
        context:source:advance(state, 1)
        build.expression.append_byte(byte)
    }
}

let Shell:Internal:token_word = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "Shell:Build:finish_word(__shell_build)\n"); return }
        let build = Shell:active_build(state)
        if build { build.finish_word() }
    }
}

let Shell:Internal:token_pipe = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "Shell:Build:pipe(__shell_build)\n"); return }
        let build = Shell:active_build(state)
        if !build || !build.pipe() {
            context:diagnostic:error(state, "shell pipe expects a command on both sides")
        }
    }
}

let Shell:Internal:token_redirect = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "Shell:Build:redirect_to(__shell_build, 0)\n"); return }
        let build = Shell:active_build(state)
        if !build || !build.redirect_to(0) {
            context:diagnostic:error(state, "shell redirection expects a command and one output path")
        }
    }
}

let Shell:Internal:token_append = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "Shell:Build:redirect_to(__shell_build, 1)\n"); return }
        let build = Shell:active_build(state)
        if !build || !build.redirect_to(1) {
            context:diagnostic:error(state, "shell redirection expects a command and one output path")
        }
    }
}

let Shell:Internal:token_double = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "Shell:Build:open_word(__shell_build)\n"); return }
        let build = Shell:active_build(state)
        if build { build.open_word() }
        context:phrase:elaborate(state, Shell:natural_grammar(state, "double"))
    }
}

let Shell:Internal:token_single = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "Shell:Build:open_word(__shell_build)\n"); return }
        let build = Shell:active_build(state)
        if build { build.open_word() }
        context:phrase:elaborate(state, Shell:natural_grammar(state, "single"))
    }
}

let Shell:Internal:token_escape = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { return }
        context:phrase:elaborate(state, Shell:natural_grammar(state, "escape"))
    }
}

let Shell:Internal:token_double_escape = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { return }
        context:phrase:elaborate(state, Shell:natural_grammar(state, "double_escape"))
    }
}

let Shell:Internal:token_single_escape = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { return }
        context:phrase:elaborate(state, Shell:natural_grammar(state, "single_escape"))
    }
}

let Shell:Internal:token_close = phrase {
    type = <phrase-types:scoped-callable>
    action = fn (state:Context*, called:Phrase*) -> void {}
}

let Shell:Internal:token_interpolation = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            Shell:emit(state, "{\nlet __shell_piece = Shell:stringify(")
            return
        }
        let build = Shell:active_build(state)
        if !build { context:diagnostic:error(state, "shell interpolation state is unavailable"); return }
        build.expression.clear()
        context:phrase:elaborate(state, Shell:natural_grammar(state, "interpolation"))
    }
}

let Shell:Internal:token_double_interpolation = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            Shell:emit(state, "{\nlet __shell_piece = Shell:stringify(")
            return
        }
        let build = Shell:active_build(state)
        if !build { context:diagnostic:error(state, "shell interpolation state is unavailable"); return }
        build.expression.clear()
        context:phrase:elaborate(state, Shell:natural_grammar(state, "double_interpolation"))
    }
}

let Shell:finish_interpolation = fn (state:Context*) -> void {
    let build = Shell:active_build(state)
    if !build || !build.expression.data {
        context:diagnostic:error(state, "shell interpolation expects a RecurLoop expression")
        return
    }
    let value = context:expression:format(state, build.expression.data)
    if !value { return }
    build.append_text(value)
    free(value)
}

let Shell:Internal:token_interpolation_close = phrase {
    type = <phrase-types:scoped-callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            Shell:emit(state, ")\nShell:Build:append_text(__shell_build, __shell_piece)\nfree(__shell_piece)\n}\n")
            return
        }
        Shell:finish_interpolation(state)
    }
}

let Shell:enter_expression_quote = fn (state:Context*, owner:u8*, quote:u8) -> void {
    let build = Shell:active_build(state)
    if build { build.expression.append_byte(quote) }
    context:phrase:elaborate(state, Shell:natural_grammar(state, owner))
}

let Shell:Internal:token_expression_double = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "\""); return }
        Shell:enter_expression_quote(state, "expression_double", cast(u8, 34))
    }
}

let Shell:Internal:token_expression_single = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "'"); return }
        Shell:enter_expression_quote(state, "expression_single", cast(u8, 39))
    }
}

let Shell:Internal:token_double_expression_double = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "\""); return }
        Shell:enter_expression_quote(state, "double_expression_double", cast(u8, 34))
    }
}

let Shell:Internal:token_double_expression_single = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "'"); return }
        Shell:enter_expression_quote(state, "double_expression_single", cast(u8, 39))
    }
}

let Shell:Internal:token_expression_quote_close = phrase {
    type = <phrase-types:scoped-callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            let key = cast(u8*, malloc(2))
            if !key { return }
            defer free(key)
            context:phrase:key(state, cast(i64, called), key, 1)
            if key[0] == 34 { Shell:emit(state, "\"") } else { Shell:emit(state, "'") }
            return
        }
        let build = Shell:active_build(state)
        let key = cast(u8*, malloc(2))
        if !build || !key { return }
        defer free(key)
        context:phrase:key(state, cast(i64, called), key, 1)
        build.expression.append_byte(key[0])
    }
}

let Shell:Internal:token_nested = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "{"); return }
        let build = Shell:active_build(state)
        if build { build.expression.append_byte(cast(u8, 123)) }
        context:phrase:elaborate(state, Shell:natural_grammar(state, "nested"))
    }
}

let Shell:Internal:token_double_nested = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "{"); return }
        let build = Shell:active_build(state)
        if build { build.expression.append_byte(cast(u8, 123)) }
        context:phrase:elaborate(state, Shell:natural_grammar(state, "double_nested"))
    }
}

let Shell:Internal:token_nested_close = phrase {
    type = <phrase-types:scoped-callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:emit(state, "}"); return }
        let build = Shell:active_build(state)
        if build { build.expression.append_byte(cast(u8, 125)) }
    }
}

let Shell:finish_top_command = fn (state:Context*) -> void {
    let build = Shell:active_build(state)
    if !build { context:diagnostic:error(state, "shell phrase state is unavailable"); return }
    let pipeline = build.finish()
    if !pipeline {
        Shell:Build:destroy(build)
        Shell:state_set(state, "__shell_phrase_build", 0)
        context:diagnostic:error(state, "shell command is incomplete")
        return
    }
    defer Shell:Pipeline:destroy(pipeline)
    let assignment_kind = Shell:state_get(state, "__shell_assignment_kind")
    var assignment_name = cast(u8*, 0)
    if assignment_kind != 0 {
        assignment_name = context:value:format(state, "__shell_assignment_name")
    }

    if build.capture {
        if Shell:active_parallel(state) {
            context:diagnostic:error(state, "capture is not available inside parallel")
        } else {
            let result = Shell:capture_pipeline(pipeline)
            if !result {
                context:diagnostic:error(state, "shell capture could not start the pipeline")
            } else {
                Shell:store_capture(state, result.output)
                Shell:store_status(state, result.exit_code)
                state.exec.status = result.exit_code
                if assignment_name {
                    if assignment_kind == 2 {
                        context:value:define:text(state, assignment_name, result.output)
                    } else if assignment_kind == 4 {
                        context:value:assign:text(state, assignment_name, result.output)
                    }
                }
                Shell:Capture:destroy(result)
            }
        }
    } else {
        let jobs = Shell:active_parallel(state)
        var status = 0
        if jobs {
            if !jobs.spawn(pipeline) {
                context:diagnostic:error(state, "parallel could not spawn a shell pipeline")
            }
        } else {
            status = Shell:run_pipeline(pipeline)
        }
        Shell:store_status(state, status)
        state.exec.status = status
        if assignment_name {
            if assignment_kind == 1 {
                context:value:define:integer(state, assignment_name, status)
            } else if assignment_kind == 3 {
                context:value:assign:integer(state, assignment_name, status)
            }
        }
    }

    if assignment_name { free(assignment_name) }
    Shell:state_set(state, "__shell_assignment_kind", 0)
    Shell:state_set_text(state, "__shell_assignment_name", "")
    Shell:Build:destroy(build)
    Shell:state_set(state, "__shell_phrase_build", 0)
}

let Shell:Internal:token_finish = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { return }
        Shell:finish_top_command(state)
        context:source:root(state)
    }
}

let Shell:begin_top_command = fn (state:Context*, capture:i64) -> void {
    if Shell:active_build(state) {
        context:diagnostic:error(state, "a shell command is already being assembled")
        return
    }
    let build = Shell:Build:new()
    if !build { context:diagnostic:error(state, "shell could not allocate a command builder"); return }
    build.capture = capture
    if !Shell:state_set(state, "__shell_phrase_build", cast(i64, build)) {
        Shell:Build:destroy(build)
        return
    }
    context:phrase:elaborate(state, Shell:natural_grammar(state, "command"))
}

// Handles only `name = run ...` and `name = capture ...`. All other forms are
// delegated back to the canonical RecurLoop declaration/assignment phrase.
let Shell:top_level_assignment = fn (
    state:Context*, canonical:u8*, define_value:i64
) -> void {
    let source = cast(u8*, context:source:data(state))
    var cursor = 0
    while source[cursor] == 32 || source[cursor] == 9 { cursor += 1 }
    let name_start = cursor
    let first = source[cursor]
    if (first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95 {
        cursor += 1
        var scanning = 1
        while scanning {
            let ch = source[cursor]
            if (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) ||
                (ch >= 48 && ch <= 57) || ch == 95 {
                cursor += 1
            } else {
                scanning = 0
            }
        }
    }
    let name_end = cursor
    while source[cursor] == 32 || source[cursor] == 9 { cursor += 1 }

    var mode = 0
    if name_end > name_start && source[cursor] == 61 {
        cursor += 1
        while source[cursor] == 32 || source[cursor] == 9 { cursor += 1 }
        if source[cursor] == 114 && source[cursor + 1] == 117 && source[cursor + 2] == 110 &&
            Shell:is_space(source[cursor + 3]) {
            mode = 1
            cursor += 3
        } else if source[cursor] == 99 && source[cursor + 1] == 97 && source[cursor + 2] == 112 &&
            source[cursor + 3] == 116 && source[cursor + 4] == 117 && source[cursor + 5] == 114 &&
            source[cursor + 6] == 101 && Shell:is_space(source[cursor + 7]) {
            mode = 2
            cursor += 7
        }
    }

    if mode == 0 {
        context:phrase:elaborate(state, context:phrase:find(state, canonical))
        return
    }
    while source[cursor] == 32 || source[cursor] == 9 { cursor += 1 }
    if cursor >= Shell:source_line_end(state, cursor) {
        context:diagnostic:error(state, "shell assignment expects a command")
        return
    }

    let name = Shell:copy_slice(source, name_start, name_end)
    if !name { context:diagnostic:error(state, "shell assignment could not copy its name"); return }
    defer free(name)
    Shell:state_set_text(state, "__shell_assignment_name", name)
    if define_value { Shell:state_set(state, "__shell_assignment_kind", mode) }
    else { Shell:state_set(state, "__shell_assignment_kind", mode + 2) }
    context:source:advance(state, cursor)
    Shell:begin_top_command(state, mode == 2)
}

let shell_top_level_var = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        Shell:top_level_assignment(state, "var", 1)
    }
}

let shell_top_level_let = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        Shell:top_level_assignment(state, "let", 1)
    }
}

let shell_top_level_set = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        Shell:top_level_assignment(state, "set", 0)
    }
}

// mode: 0 = exit code, 1 = owned stdout text, 2 = asynchronous Invocation.
let Shell:rewrite_command = fn (state:Context*, mode:i64) -> void {
    Shell:emit(state, "{\nlet __shell_build = Shell:Build:new()\ndefer Shell:Build:destroy(__shell_build)\n")
    let delimiter = context:syntax:elaborate(state, Shell:natural_grammar(state, "command"))

    Shell:emit(state, "let __shell_pipeline = Shell:Build:finish(__shell_build)\n")
    if mode == 2 {
        Shell:emit(state, "let __shell_result = Shell:Invocation:start(__shell_pipeline, 1)\n")
        Shell:emit(state, "Shell:Pipeline:destroy(__shell_pipeline)\n__shell_result\n}")
    } else if mode == 1 {
        Shell:emit(state, "let __shell_invocation = Shell:Invocation:start(__shell_pipeline, 1)\n")
        Shell:emit(state, "var __shell_result = Shell:copy_text(\"\")\n")
        Shell:emit(state, "if __shell_invocation { free(__shell_result); __shell_result = Shell:copy_text(__shell_invocation.stdout()); __shell_invocation.destroy() }\n")
        Shell:emit(state, "Shell:Pipeline:destroy(__shell_pipeline)\n__shell_result\n}")
    } else {
        Shell:emit(state, "let __shell_invocation = Shell:Invocation:start(__shell_pipeline, 0)\n")
        Shell:emit(state, "var __shell_result = 126\n")
        Shell:emit(state, "if __shell_invocation { __shell_result = __shell_invocation.exit_code(); __shell_invocation.destroy() }\n")
        Shell:emit(state, "Shell:Pipeline:destroy(__shell_pipeline)\n__shell_result\n}")
    }
    if delimiter == 125 { Shell:emit(state, "}") }
    else { Shell:emit(state, "\n") }
}

let run = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:rewrite_command(state, 0) }
        else { Shell:begin_top_command(state, 0) }
    }
}

// Empty-key fallback: ordinary RecurLoop phrases win longest-prefix lookup;
// any otherwise unknown line enters the exact same phrase graph as `run`.
let Shell:top_command = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        Shell:begin_top_command(state, 0)
    }
}

let install_shell_fallback = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let shell = context:phrase:find(state, "Shell")
        let top_command = context:phrase:find:exact(state, shell, "top_command")
        let fallback = context:phrase:define:alias(
            state, "", top_command
        )
        if !fallback {
            context:diagnostic:error(state, "could not install the shell command fallback")
        }
    }
}
install_shell_fallback

let capture = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:rewrite_command(state, 1) }
        else { Shell:begin_top_command(state, 1) }
    }
}

let spawn = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Shell:rewrite_command(state, 2) }
        else {
            context:diagnostic:error(state, "spawn is an expression and must be used in compiled code")
        }
    }
}


// The command grammar is the phrase graph itself. Every alias carries both
// behavior and its next state, so top-level elaboration and fn rewriting walk
// exactly the same graph.
let Shell:Grammar:command:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_byte> successor = <Shell:Grammar:command> }
let Shell:Grammar:command:" " = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_word> successor = <Shell:Grammar:command> }
let Shell:Grammar:command:"\t" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_word> successor = <Shell:Grammar:command> }
let Shell:Grammar:command:"|" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_pipe> successor = <Shell:Grammar:command> }
let Shell:Grammar:command:">>" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_append> successor = <Shell:Grammar:command> }
let Shell:Grammar:command:">" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_redirect> successor = <Shell:Grammar:command> }
let Shell:Grammar:command:"\"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_double> successor = <Shell:Grammar:double> }
let Shell:Grammar:command:"'" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_single> successor = <Shell:Grammar:single> }
let Shell:Grammar:command:"\\" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_escape> successor = <Shell:Grammar:escape> }
let Shell:Grammar:command:"{" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_interpolation> successor = <Shell:Grammar:interpolation> }
let Shell:Grammar:command:"\n" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_finish> successor = none }
let Shell:Grammar:command:"\r\n" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_finish> successor = none }
let Shell:Grammar:command:"\r" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_finish> successor = none }
let Shell:Grammar:command:"}" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_finish> successor = none }

let Shell:Grammar:double:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_byte> successor = <Shell:Grammar:double> }
let Shell:Grammar:double:"\"" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_close> successor = <Shell:Grammar:command> }
let Shell:Grammar:double:"\\" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_double_escape> successor = <Shell:Grammar:double_escape> }
let Shell:Grammar:double:"{" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_double_interpolation> successor = <Shell:Grammar:double_interpolation> }

let Shell:Grammar:single:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_byte> successor = <Shell:Grammar:single> }
let Shell:Grammar:single:"'" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_close> successor = <Shell:Grammar:command> }
let Shell:Grammar:single:"\\" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_single_escape> successor = <Shell:Grammar:single_escape> }

let Shell:Grammar:escape:"" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_escape_byte> successor = <Shell:Grammar:command> }
let Shell:Grammar:double_escape:"" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_escape_byte> successor = <Shell:Grammar:double> }
let Shell:Grammar:single_escape:"" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_escape_byte> successor = <Shell:Grammar:single> }

let Shell:Grammar:interpolation:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_byte> successor = <Shell:Grammar:interpolation> }
let Shell:Grammar:interpolation:"}" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_interpolation_close> successor = <Shell:Grammar:command> }
let Shell:Grammar:interpolation:"{" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_nested> successor = <Shell:Grammar:nested> }
let Shell:Grammar:interpolation:"\"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_double> successor = <Shell:Grammar:expression_double> }
let Shell:Grammar:interpolation:"'" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_single> successor = <Shell:Grammar:expression_single> }

let Shell:Grammar:double_interpolation:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_byte> successor = <Shell:Grammar:double_interpolation> }
let Shell:Grammar:double_interpolation:"}" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_interpolation_close> successor = <Shell:Grammar:double> }
let Shell:Grammar:double_interpolation:"{" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_double_nested> successor = <Shell:Grammar:double_nested> }
let Shell:Grammar:double_interpolation:"\"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_double_expression_double> successor = <Shell:Grammar:double_expression_double> }
let Shell:Grammar:double_interpolation:"'" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_double_expression_single> successor = <Shell:Grammar:double_expression_single> }

let Shell:Grammar:nested:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_byte> successor = <Shell:Grammar:nested> }
let Shell:Grammar:nested:"}" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_nested_close> successor = <Shell:Grammar:interpolation> }
let Shell:Grammar:nested:"{" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_nested> successor = <Shell:Grammar:nested> }
let Shell:Grammar:double_nested:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_byte> successor = <Shell:Grammar:double_nested> }
let Shell:Grammar:double_nested:"}" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_nested_close> successor = <Shell:Grammar:double_interpolation> }
let Shell:Grammar:double_nested:"{" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_double_nested> successor = <Shell:Grammar:double_nested> }

let Shell:Grammar:expression_double:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_byte> successor = <Shell:Grammar:expression_double> }
let Shell:Grammar:expression_double:"\"" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_expression_quote_close> successor = <Shell:Grammar:interpolation> }
let Shell:Grammar:expression_single:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_byte> successor = <Shell:Grammar:expression_single> }
let Shell:Grammar:expression_single:"'" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_expression_quote_close> successor = <Shell:Grammar:interpolation> }
let Shell:Grammar:double_expression_double:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_byte> successor = <Shell:Grammar:double_expression_double> }
let Shell:Grammar:double_expression_double:"\"" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_expression_quote_close> successor = <Shell:Grammar:double_interpolation> }
let Shell:Grammar:double_expression_single:"" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_expression_byte> successor = <Shell:Grammar:double_expression_single> }
let Shell:Grammar:double_expression_single:"'" = phrase { type = <phrase-types:scoped-callable> action = <Shell:Internal:token_expression_quote_close> successor = <Shell:Grammar:double_interpolation> }

// Generic block capture remains a core RecurLoop phrase facility. Headers are
// evaluated by the ordinary expression engine; these actions do no scanning.
let directory = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let block = state.source_block_capture()
        if !block { return }
        defer block.release()
        let header = block.header()
        let path = context:expression:format:at(
            state, header, 0, Shell:strlen(header),
            block.path(), block.header_line(), block.header_position()
        )
        if !path { return }
        defer free(path)
        let guard = Shell:cwd_enter(path)
        if !guard { context:diagnostic:error(state, "directory could not enter the requested path"); return }
        defer Shell:cwd_leave(guard)
        state.source_block_execute_current(block)
    }
}

// The header evaluates to the name of a RecurLoop value. Its formatted value
// becomes the environment value for the duration of the ordinary phrase block.
let environment = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let block = state.source_block_capture()
        if !block { return }
        defer block.release()
        let header = block.header()
        let name = context:expression:format:at(
            state, header, 0, Shell:strlen(header),
            block.path(), block.header_line(), block.header_position()
        )
        if !name { return }
        defer free(name)
        let value = context:value:format(state, name)
        if !value { return }
        defer free(value)
        let guard = Shell:env_enter(name, value)
        if !guard { context:diagnostic:error(state, "environment could not set the variable"); return }
        defer Shell:env_leave(guard)
        state.source_block_execute_current(block)
    }
}

// The block body is executed normally. The only state is the active supervisor;
// each ordinary run phrase therefore spawns its already-built pipeline.
let parallel = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let block = state.source_block_capture()
        if !block { return }
        defer block.release()
        let jobs = Shell:Parallel:new()
        if !jobs { context:diagnostic:error(state, "parallel could not allocate its job list"); return }
        defer Shell:Parallel:destroy(jobs)
        Shell:state_set(state, "__shell_phrase_parallel", cast(i64, jobs))
        state.source_block_execute_current(block)
        Shell:state_set(state, "__shell_phrase_parallel", 0)
        let status = jobs.wait()
        Shell:store_status(state, status)
        state.exec.status = status
    }
}

// Longest-prefix aliases add shell-result assignments without changing the
// ordinary meanings of var/let/set for every other right-hand side.
let install_shell_assignments = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let var_action = context:phrase:find(state, "shell_top_level_var")
        let let_action = context:phrase:find(state, "shell_top_level_let")
        let set_action = context:phrase:find(state, "shell_top_level_set")
        let var_space = context:phrase:define:alias(state, "var ", var_action)
        let var_tab = context:phrase:define:alias(state, "var\t", var_action)
        let let_space = context:phrase:define:alias(state, "let ", let_action)
        let let_tab = context:phrase:define:alias(state, "let\t", let_action)
        let set_space = context:phrase:define:alias(state, "set ", set_action)
        let set_tab = context:phrase:define:alias(state, "set\t", set_action)
        if !var_space || !var_tab || !let_space || !let_tab || !set_space || !set_tab {
            context:diagnostic:error(state, "could not install shell assignment phrases")
        }
    }
}
install_shell_assignments

// The image contains only phrase graphs, compiled actions and stable native
// symbol names. No parser state or process-local pointer is exported.
set malloc.serializable = false
set realloc.serializable = false
set free.serializable = false
set memcpy.serializable = false
set printf.serializable = false
set fflush.serializable = false
set fopen.serializable = false
set fclose.serializable = false
set fread.serializable = false
set fork.serializable = false
set pipe.serializable = false
set dup2.serializable = false
set close.serializable = false
set open.serializable = false
set execvp.serializable = false
set perror.serializable = false
set waitpid.serializable = false
set _exit.serializable = false
set read.serializable = false
set chdir.serializable = false
set getcwd.serializable = false
set getenv.serializable = false
set setenv.serializable = false
set unsetenv.serializable = false
set install_shell_fallback.serializable = false
set install_shell_assignments.serializable = false
engine export "/tmp/recurloop-shell-library.rli"
