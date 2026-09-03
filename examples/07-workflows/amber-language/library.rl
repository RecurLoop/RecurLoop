// ============================================================================
// RecurLoop Amber compatibility layer
//
// Source library that installs an Amber-oriented surface language on top of
// RecurLoop's phrase system and the native pipeline implementation from
// examples/07-workflows/shell-language/library.rl.
//
// Target: Amber 0.6.x command syntax and the subset of the language that can be
// represented faithfully by RecurLoop's current public phrase/Context APIs.
//
// Implemented closely to Amber:
//   - `$ program args $` native commands (no /bin/sh intermediate parser);
//   - command interpolation `{expression}`;
//   - native pipelines `|` and redirections `>` / `>>` inside `$ ... $`;
//   - `let name = $ ... $` captures stdout and updates `status()`;
//   - command outcome handlers `failed[(code)]`, `succeeded`,
//     `exited[(code)]`;
//   - command modifiers `trust`, `silent`, `suppress`, including scopes;
//   - Amber spellings `and`, `or`, `not`; `Int`/`Bool` in compatibility `fun`;
//   - Amber-style Text interpolation in `echo("...{expr}...")`;
//   - multiline Text array literals with comments and trailing commas;
//   - source-defined `for value in array { ... }`;
//   - Amber-style helpers including echo(), cd(), pid(), status();
//   - parent-process cd and native POSIX process execution;
//   - serialization as a reusable RecurLoop engine image (.rli).
//
// Current compatibility limits:
//   - Amber `fun name(...): Type` declarations are not exact yet. The
//     compatibility `fun` still uses RecurLoop's `->` result-type syntax;
//   - general interpolated Text literals are not rewritten in every expression
//     position yet; interpolation is implemented for echo calls and Text-array
//     elements;
//   - command expressions are not accepted in every expression position; the
//     common `let name = $ ... $` capture form is supported;
//   - `?` failure propagation and Amber's compile-time failable-command check
//     are not implemented yet;
//   - arrays currently cover Text elements and the basic `for ... in ...` form;
//     heterogeneous arrays, ranges and other loop variants remain to be added;
//   - `sudo`, imports/main/test syntax and the complete Amber standard library
//     are not implemented yet.
//
// The library deliberately does NOT install the original shell example's
// empty-key fallback. Ordinary unknown source is therefore not treated as a
// command: Amber commands must be explicitly delimited by `$ ... $`.
//
// Build reusable image with a RecurLoop executable:
//   build/Debug/bin/recurloop --file recurloop-amber-library.rl
//
// Output:
//   /tmp/recurloop-amber-library.rli
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
extern dup(oldfd:i32) -> i32 abi sysv-amd64
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
extern getpid() -> i32 abi sysv-amd64
extern sleep(seconds:i32) -> i32 abi sysv-amd64

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
// Amber compatibility runtime
// ============================================================================

let Amber = phrase { dictionary = true permanent = true }
let Amber:Internal = phrase { dictionary = true serializable = false }
let Amber:Symbols = phrase { dictionary = true permanent = true }
let Amber:Functions = phrase { dictionary = true permanent = true }
let Amber:Variables = phrase { dictionary = true permanent = true }
let Amber:Arrays = phrase { dictionary = true permanent = true }
let Amber:Types = phrase { dictionary = true permanent = true }
let Amber:Builtins = phrase { dictionary = true permanent = true }
let Amber:Grammar = phrase { dictionary = true permanent = true }

// Stable language vocabulary is serialized in the engine image. Dynamic user
// declarations are interned beneath the same dictionaries at elaboration time.
let Amber:Symbols:Int = phrase { permanent = true }
let Amber:Symbols:Bool = phrase { permanent = true }
let Amber:Types:Int = <Amber:Symbols:Int>
let Amber:Types:Bool = <Amber:Symbols:Bool>
let Amber:Symbols:echo = phrase { permanent = true }
let Amber:Symbols:cd = phrase { permanent = true }
let Amber:Symbols:pwd = phrase { permanent = true }
let Amber:Symbols:pid = phrase { permanent = true }
let Amber:Symbols:len = phrase { permanent = true }
let Amber:Symbols:status = phrase { permanent = true }
let Amber:Builtins:echo = <Amber:Symbols:echo>
let Amber:Builtins:cd = <Amber:Symbols:cd>
let Amber:Builtins:pwd = <Amber:Symbols:pwd>
let Amber:Builtins:pid = <Amber:Symbols:pid>
let Amber:Builtins:len = <Amber:Symbols:len>
let Amber:Builtins:status = <Amber:Symbols:status>
let Amber:Symbols:fun = phrase { permanent = true }
let Amber:Symbols:for = phrase { permanent = true }
let Amber:Symbols:and = phrase { permanent = true }
let Amber:Symbols:or = phrase { permanent = true }
let Amber:Symbols:not = phrase { permanent = true }
let Amber:Grammar:fun = <Amber:Symbols:fun>
let Amber:Grammar:for = <Amber:Symbols:for>
let Amber:Grammar:and = <Amber:Symbols:and>
let Amber:Grammar:or = <Amber:Symbols:or>
let Amber:Grammar:not = <Amber:Symbols:not>

// Foreign names are interned as RecurLoop phrases. Runtime values still live in
// Context values / compiled locals; the phrase is the stable language-level
// identity that tooling and other RecurLoop extensions can inspect.
let Amber:category_owner = fn (state:Context*, category:u8*) -> i64 {
    let root = context:phrase:find(state, "Amber")
    if !root { return 0 }
    return context:phrase:find:exact(state, root, category)
}
let Amber:intern_symbol = fn (state:Context*, name:u8*) -> i64 {
    let owner = Amber:category_owner(state, "Symbols")
    if !owner || !name { return 0 }
    let existing = context:phrase:find:exact(state, owner, name)
    if existing { return existing }
    let created = context:phrase:define:data(state, owner, name)
    return created
}
let Amber:categorize_symbol = fn (state:Context*, category:u8*, name:u8*) -> i64 {
    let symbol = Amber:intern_symbol(state, name)
    if !symbol { return 0 }
    let owner = Amber:category_owner(state, category)
    if owner && !context:phrase:find:exact(state, owner, name) {
        let alias = context:phrase:define:from(state, owner, name, symbol)
    }
    return symbol
}
let Amber:symbol_in = fn (state:Context*, category:u8*, name:u8*) -> i64 {
    let owner = Amber:category_owner(state, category)
    if !owner { return 0 }
    return context:phrase:find:exact(state, owner, name)
}

// Amber status() is process-wide in this compatibility layer. A hidden
// environment variable avoids serializing process-local addresses in the .rli.
let Amber:set_status = fn (value:i64) -> i64 {
    let text = Shell:i64_to_text(value)
    if !text { return 0 }
    defer free(text)
    return setenv("__RECURLOOP_AMBER_STATUS", text, cast(i32, 1)) == 0
}

let Amber:get_status = fn () -> i64 {
    let text = getenv("__RECURLOOP_AMBER_STATUS")
    if !text { return 0 }
    return Shell:state_number(text)
}

let status = fn () -> i64 {
    return Amber:get_status()
}

// suppress $ ... $ redirects stderr only while children are forked. The parent
// restores fd 2 immediately afterwards.
let Amber:stderr_silence_enter = fn () -> i64 {
    let saved = dup(cast(i32, 2))
    if saved < 0 { return -1 }
    let sink = open("/dev/null", cast(i32, 1))
    if sink < 0 {
        close(saved)
        return -1
    }
    if dup2(sink, cast(i32, 2)) < 0 {
        close(sink)
        close(saved)
        return -1
    }
    close(sink)
    return saved
}

let Amber:stderr_silence_leave = fn (saved:i64) -> void {
    if saved < 0 { return }
    dup2(cast(i32, saved), cast(i32, 2))
    close(cast(i32, saved))
}

let Amber:stdout_silence_enter = fn () -> i64 {
    let saved = dup(cast(i32, 1))
    if saved < 0 { return -1 }
    let sink = open("/dev/null", cast(i32, 1))
    if sink < 0 {
        close(saved)
        return -1
    }
    if dup2(sink, cast(i32, 1)) < 0 {
        close(sink)
        close(saved)
        return -1
    }
    close(sink)
    return saved
}

let Amber:stdout_silence_leave = fn (saved:i64) -> void {
    if saved < 0 { return }
    dup2(cast(i32, saved), cast(i32, 1))
    close(cast(i32, saved))
}

// Amber 0.6 prefers function-call syntax for builtins.
let echo = fn () -> i64 {
    printf("\n")
    return 0
}

let echo = fn (text:u8*) -> i64 {
    if text { printf("%s\n", text) }
    else { printf("\n") }
    return 0
}

let echo = fn (value:i64) -> i64 {
    printf("%lld\n", value)
    return 0
}


let cd = fn (path:u8*) -> i64 {
    let pipeline = Shell:Pipeline:new()
    if !pipeline {
        Amber:set_status(126)
        return 126
    }
    defer Shell:Pipeline:destroy(pipeline)
    if !pipeline.add_command("cd", path) {
        Amber:set_status(126)
        return 126
    }
    let code = Shell:run_pipeline(pipeline)
    Amber:set_status(code)
    return code
}

// RecurLoop already has the executable function machinery. `fun` delegates to
// the native `fn` parselet, but first installs Amber's integer type spellings in
// the *current source context*. This matters for .rli imports: custom Context
// types are source-context state, while the `fun` phrase itself is serializable.
// RecurLoop currently still uses `->` for an explicitly written result type.
let fun = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:type:find(state, "Int") == 0 {
            context:type:integer:signed(state, "Int", 64)
        }
        if context:type:find(state, "Bool") == 0 {
            context:type:integer:signed(state, "Bool", 64)
        }
        Amber:categorize_symbol(state, "Types", "Int")
        Amber:categorize_symbol(state, "Types", "Bool")
        context:phrase:elaborate(state, context:phrase:find(state, "fn"))
    }
}

// Amber logical operators are ordinary phrase aliases.
let and = <&&>
let or = <||>
let not = <!>

// RecurLoop's fn type parser uses the Context type registry, not ordinary
// phrase lookup. Install the Amber integer spellings there so `Int` and `Bool`
// are accepted in compiled signatures and survive engine-image export.
//
// `Num` and `Text` are intentionally not advertised as signature aliases yet:
// the current public Context API can create a new floating type but the fn ABI
// path does not accept custom floating aliases, and it cannot assign a new
// public name to an existing pointer type. Use f64 and u8* in RecurLoop-native
// signatures until those host APIs exist.
let install_amber_scalar_types = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:type:find(state, "Int") == 0 {
            context:type:integer:signed(state, "Int", 64)
        }
        if context:type:find(state, "Bool") == 0 {
            context:type:integer:signed(state, "Bool", 64)
        }
        Amber:categorize_symbol(state, "Types", "Int")
        Amber:categorize_symbol(state, "Types", "Bool")
    }
}
install_amber_scalar_types

// Small Amber-style builtins that have direct POSIX/native equivalents.
let pwd = fn () -> u8* {
    let capacity = 4096
    let result = cast(u8*, malloc(capacity))
    if !result { return cast(u8*, 0) }
    if !getcwd(result, capacity) { free(result); return cast(u8*, 0) }
    return result
}

let pid = fn () -> i64 { return cast(i64, getpid()) }

let len = fn (text:u8*) -> i64 { return Shell:strlen(text) }

// Amber reports the shell used by generated scripts. RecurLoop executes the
// pipeline directly, so the closest meaningful equivalent is the execution host.
let shellname = fn () -> u8* { return "RecurLoop" }

let sleep_seconds = fn (seconds:i64) -> i64 {
    sleep(cast(i32, seconds))
    return 0
}


// ============================================================================
// Amber Text interpolation + lightweight runtime arrays
// ============================================================================

// Hidden array state is stored in ordinary Context values so it is scoped to
// the source execution context rather than in process-global C++ state.
let Amber:array_count_key = fn (name:u8*) -> u8* {
    let output = Shell:Text:new()
    if !output { return cast(u8*, 0) }
    defer output.destroy()
    output.append_text("__amber_array:")
    output.append_text(name)
    output.append_text(":count")
    return output.take()
}

let Amber:array_item_key = fn (name:u8*, index:i64) -> u8* {
    let output = Shell:Text:new()
    if !output { return cast(u8*, 0) }
    defer output.destroy()
    let number = Shell:i64_to_text(index)
    if !number { return cast(u8*, 0) }
    defer free(number)
    output.append_text("__amber_array:")
    output.append_text(name)
    output.append_text(":")
    output.append_text(number)
    return output.take()
}

let Amber:skip_space_and_comments = fn (source:u8*, start:i64) -> i64 {
    var cursor = start
    var again = 1
    while again {
        again = 0
        while source[cursor] == 32 || source[cursor] == 9 || source[cursor] == 10 || source[cursor] == 13 {
            cursor += 1
        }
        if source[cursor] == 47 && source[cursor + 1] == 47 {
            cursor += 2
            while source[cursor] != 0 && source[cursor] != 10 && source[cursor] != 13 {
                cursor += 1
            }
            again = 1
        }
    }
    return cursor
}

// Decode the contents of one Amber double-quoted Text literal. `start` points
// to the first byte after the opening quote. `finish` points at the closing
// quote. The caller is responsible for locating those boundaries.
let Amber:decode_text = fn (source:u8*, start:i64, finish:i64) -> u8* {
    let output = Shell:Text:new()
    if !output { return cast(u8*, 0) }
    defer output.destroy()
    var cursor = start
    while cursor < finish {
        let ch = source[cursor]
        if ch == 92 && cursor + 1 < finish {
            let escaped = source[cursor + 1]
            if escaped == 110 { output.append_byte(10) }
            else if escaped == 114 { output.append_byte(13) }
            else if escaped == 116 { output.append_byte(9) }
            else { output.append_byte(escaped) }
            cursor += 2
        } else {
            output.append_byte(ch)
            cursor += 1
        }
    }
    return output.take()
}

// Evaluate Amber `{ expression }` interpolation using RecurLoop's public
// expression formatter. Nested braces and quoted strings inside an expression
// are balanced here so expressions are not limited to a single identifier.
let Amber:interpolate_text = fn (state:Context*, text:u8*) -> u8* {
    let output = Shell:Text:new()
    if !output { return cast(u8*, 0) }
    defer output.destroy()

    var cursor = 0
    while text[cursor] != 0 {
        if text[cursor] != 123 {
            output.append_byte(text[cursor])
            cursor += 1
        } else {
            let open = cursor
            cursor += 1
            let expression_start = cursor
            var depth = 1
            var quote = 0
            while text[cursor] != 0 && depth > 0 {
                let ch = text[cursor]
                if quote != 0 {
                    if ch == 92 && text[cursor + 1] != 0 {
                        cursor += 2
                    } else if ch == quote {
                        quote = 0
                        cursor += 1
                    } else {
                        cursor += 1
                    }
                } else if ch == 34 || ch == 39 {
                    quote = ch
                    cursor += 1
                } else if ch == 123 {
                    depth += 1
                    cursor += 1
                } else if ch == 125 {
                    depth -= 1
                    if depth > 0 { cursor += 1 }
                } else {
                    cursor += 1
                }
            }

            if depth != 0 {
                // Keep unmatched `{` literal instead of silently discarding it.
                output.append_byte(text[open])
                cursor = open + 1
            } else {
                let expression = Shell:copy_slice(text, expression_start, cursor)
                if !expression { return cast(u8*, 0) }
                defer free(expression)
                let value = context:expression:format(state, expression)
                if !value { return cast(u8*, 0) }
                output.append_text(value)
                free(value)
                cursor += 1
            }
        }
    }
    return output.take()
}

let Amber:store_text_array = fn (state:Context*, name:u8*, source:u8*, start:i64) -> i64 {
    var cursor = start
    if source[cursor] != 91 { return -1 }
    cursor += 1

    let joined = Shell:Text:new()
    if !joined { return -1 }
    defer joined.destroy()

    var count = 0
    var done = 0
    while !done {
        cursor = Amber:skip_space_and_comments(source, cursor)
        if source[cursor] == 93 {
            cursor += 1
            done = 1
        } else {
            if source[cursor] != 34 {
                context:diagnostic:error(state, "Amber array compatibility currently expects Text elements")
                return -1
            }
            cursor += 1
            let content_start = cursor
            var closed = 0
            while source[cursor] != 0 && !closed {
                if source[cursor] == 92 && source[cursor + 1] != 0 {
                    cursor += 2
                } else if source[cursor] == 34 {
                    closed = 1
                } else {
                    cursor += 1
                }
            }
            if !closed {
                context:diagnostic:error(state, "unterminated Text literal in Amber array")
                return -1
            }

            let decoded = Amber:decode_text(source, content_start, cursor)
            if !decoded { return -1 }
            defer free(decoded)
            let value = Amber:interpolate_text(state, decoded)
            if !value { return -1 }
            defer free(value)

            let key = Amber:array_item_key(name, count)
            if !key { return -1 }
            defer free(key)
            if context:value:contains(state, key) {
                context:value:assign:text(state, key, value)
            } else {
                context:value:define:text(state, key, value)
            }

            if count > 0 { joined.append_byte(32) }
            joined.append_text(value)
            count += 1
            cursor += 1
            cursor = Amber:skip_space_and_comments(source, cursor)
            if source[cursor] == 44 {
                cursor += 1
            } else if source[cursor] != 93 {
                context:diagnostic:error(state, "Amber array expects ',' or ']' after an element")
                return -1
            }
        }
    }

    let count_key = Amber:array_count_key(name)
    if !count_key { return -1 }
    defer free(count_key)
    if context:value:contains(state, count_key) {
        context:value:assign:integer(state, count_key, count)
    } else {
        context:value:define:integer(state, count_key, count)
    }

    // Amber formats arrays as their elements separated by spaces. Keeping the
    // public value in this form also makes echo(array) useful in the subset.
    let joined_text = joined.take()
    if !joined_text { return -1 }
    defer free(joined_text)
    if context:value:contains(state, name) {
        context:value:assign:text(state, name, joined_text)
    } else {
        context:value:define:text(state, name, joined_text)
    }
    return cursor
}

let Amber:array_count = fn (state:Context*, name:u8*) -> i64 {
    let key = Amber:array_count_key(name)
    if !key { return -1 }
    defer free(key)
    if !context:value:contains(state, key) { return -1 }
    let value = context:value:format(state, key)
    if !value { return -1 }
    defer free(value)
    return Shell:state_number(value)
}

let Amber:array_item = fn (state:Context*, name:u8*, index:i64) -> u8* {
    let key = Amber:array_item_key(name, index)
    if !key { return cast(u8*, 0) }
    defer free(key)
    if !context:value:contains(state, key) { return cast(u8*, 0) }
    return context:value:format(state, key)
}

// Top-level echo adapter. A longer `echo(` phrase wins over the typed `echo`
// overload dictionary. Non-literal arguments are still evaluated by the normal
// RecurLoop expression formatter; quoted Text additionally gains Amber
// interpolation semantics.
let Amber:echo_call = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = cast(u8*, context:source:data(state))
        var cursor = 0
        var depth = 0
        var quote = 0
        var close = -1
        while source[cursor] != 0 && close < 0 {
            let ch = source[cursor]
            if quote != 0 {
                if ch == 92 && source[cursor + 1] != 0 { cursor += 2 }
                else if ch == quote { quote = 0; cursor += 1 }
                else { cursor += 1 }
            } else if ch == 34 || ch == 39 {
                quote = ch
                cursor += 1
            } else if ch == 40 || ch == 91 || ch == 123 {
                depth += 1
                cursor += 1
            } else if ch == 41 {
                if depth == 0 { close = cursor }
                else { depth -= 1; cursor += 1 }
            } else if ch == 93 || ch == 125 {
                if depth > 0 { depth -= 1 }
                cursor += 1
            } else {
                cursor += 1
            }
        }
        if close < 0 {
            context:diagnostic:error(state, "echo call is missing ')'")
            return
        }

        var start = 0
        var finish = close
        while start < finish && (source[start] == 32 || source[start] == 9 || source[start] == 10 || source[start] == 13) { start += 1 }
        while finish > start && (source[finish - 1] == 32 || source[finish - 1] == 9 || source[finish - 1] == 10 || source[finish - 1] == 13) { finish -= 1 }

        var formatted = cast(u8*, 0)
        if finish > start + 1 && source[start] == 34 && source[finish - 1] == 34 {
            let decoded = Amber:decode_text(source, start + 1, finish - 1)
            if decoded {
                formatted = Amber:interpolate_text(state, decoded)
                free(decoded)
            }
        } else if finish == start {
            formatted = Shell:copy_text("")
        } else {
            let expression = Shell:copy_slice(source, start, finish)
            if expression {
                formatted = context:expression:format(state, expression)
                free(expression)
            }
        }

        if formatted {
            printf("%s\n", formatted)
            free(formatted)
        }
        context:source:advance(state, close + 1)
    }
}

let "echo(" = <Amber:echo_call>

// `for value in array { ... }` is a source-defined Amber loop. The block can be
// executed repeatedly just like RecurLoop's source-defined `repeat` example.
let Amber:for_loop = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let block = state.source_block_capture()
        if !block { return }
        defer block.release()
        let header = block.header()
        var cursor = 0
        while header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13 { cursor += 1 }
        let variable_start = cursor
        let first = header[cursor]
        if !((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95) {
            context:diagnostic:error(state, "Amber for expects an iteration variable")
            return
        }
        cursor += 1
        var scanning = 1
        while scanning {
            let ch = header[cursor]
            if (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch == 95 { cursor += 1 }
            else { scanning = 0 }
        }
        let variable_end = cursor
        while header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13 { cursor += 1 }
        if header[cursor] != 105 || header[cursor + 1] != 110 {
            context:diagnostic:error(state, "Amber for expects 'in'")
            return
        }
        cursor += 2
        if !(header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13) {
            context:diagnostic:error(state, "Amber for expects whitespace after 'in'")
            return
        }
        while header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13 { cursor += 1 }
        let array_start = cursor
        let array_first = header[cursor]
        if !((array_first >= 65 && array_first <= 90) || (array_first >= 97 && array_first <= 122) || array_first == 95) {
            context:diagnostic:error(state, "Amber for expects an array name after 'in'")
            return
        }
        cursor += 1
        scanning = 1
        while scanning {
            let ch = header[cursor]
            if (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch == 95 { cursor += 1 }
            else { scanning = 0 }
        }
        let array_end = cursor
        while header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13 { cursor += 1 }
        if header[cursor] != 0 {
            context:diagnostic:error(state, "unexpected input after Amber for array")
            return
        }

        let variable = Shell:copy_slice(header, variable_start, variable_end)
        let array = Shell:copy_slice(header, array_start, array_end)
        if !variable || !array {
            if variable { free(variable) }
            if array { free(array) }
            return
        }
        defer free(variable)
        defer free(array)
        Amber:categorize_symbol(state, "Variables", variable)
        Amber:categorize_symbol(state, "Arrays", array)

        let count = Amber:array_count(state, array)
        if count < 0 {
            context:diagnostic:error(state, "Amber for source is not an array")
            return
        }

        var index = 0
        while index < count {
            let value = Amber:array_item(state, array, index)
            if !value { return }
            if context:value:contains(state, variable) {
                context:value:assign:text(state, variable, value)
            } else {
                context:value:define:text(state, variable, value)
            }
            free(value)
            if state.source_block_execute_current(block) == 0 { return }
            index += 1
        }
    }
}

let "for " = <Amber:for_loop>

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
    var amber_saved_stdout = -1
    var amber_saved_stderr = -1
    if Shell:state_get(state, "__amber_silent") {
        amber_saved_stdout = Amber:stdout_silence_enter()
    }
    if Shell:state_get(state, "__amber_suppress") {
        amber_saved_stderr = Amber:stderr_silence_enter()
    }
    defer Amber:stdout_silence_leave(amber_saved_stdout)
    defer Amber:stderr_silence_leave(amber_saved_stderr)
    defer Shell:state_set(state, "__amber_silent", 0)
    defer Shell:state_set(state, "__amber_suppress", 0)
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
    Amber:set_status(state.exec.status)
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

// Handles `name = run ...`, `name = capture ...`, and Amber-style `name = $ ... $`. All other forms are
// delegated back to the canonical RecurLoop declaration/assignment phrase.
let Shell:top_level_assignment = fn (
    state:Context*, canonical:u8*, define_value:i64
) -> void {
    // Array literals may span physical input lines. Ask the Context source
    // reader to make the remaining source available before scanning.
    context:source:ensure(state, 65536)
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
        } else if source[cursor] == 36 {
            // Amber command expression: let value = $ command $
            mode = 2
            cursor += 1
        } else if source[cursor] == 91 {
            // Amber array literal. The compatibility layer currently stores
            // Text elements as runtime Context values for `for ... in ...`.
            mode = 3
        }
    }

    var declared_name = cast(u8*, 0)
    if name_end > name_start { declared_name = Shell:copy_slice(source, name_start, name_end) }
    defer free(declared_name)

    if mode == 0 {
        // Amber `let` is mutable for ordinary values, but RecurLoop function
        // literals still need the canonical immutable declaration path so the
        // compiler can install their typed phrase. Preserve that path for an
        // RHS beginning with `fn` or the compatibility `fun` phrase.
        if Shell:text_equal(canonical, "var") {
            let fn_rhs = source[cursor] == 102 && source[cursor + 1] == 110 && Shell:is_space(source[cursor + 2])
            let fun_rhs = source[cursor] == 102 && source[cursor + 1] == 117 && source[cursor + 2] == 110 && Shell:is_space(source[cursor + 3])
            if fn_rhs || fun_rhs {
                if declared_name { Amber:categorize_symbol(state, "Functions", declared_name) }
                context:phrase:elaborate(state, context:phrase:find(state, "let"))
                return
            }
        }
        if define_value && declared_name { Amber:categorize_symbol(state, "Variables", declared_name) }
        context:phrase:elaborate(state, context:phrase:find(state, canonical))
        return
    }
    let name = Shell:copy_slice(source, name_start, name_end)
    if !name { context:diagnostic:error(state, "assignment could not copy its name"); return }
    defer free(name)
    if define_value { Amber:categorize_symbol(state, "Variables", name) }

    if mode == 3 {
        Amber:categorize_symbol(state, "Arrays", name)
        let finish = Amber:store_text_array(state, name, source, cursor)
        if finish >= 0 { context:source:advance(state, finish) }
        return
    }

    while source[cursor] == 32 || source[cursor] == 9 { cursor += 1 }
    if cursor >= Shell:source_line_end(state, cursor) {
        context:diagnostic:error(state, "shell assignment expects a command")
        return
    }

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
        Shell:emit(state, "var __shell_status = 126\n")
        Shell:emit(state, "if __shell_invocation { free(__shell_result); __shell_result = Shell:copy_text(__shell_invocation.stdout()); __shell_status = __shell_invocation.exit_code(); __shell_invocation.destroy() }\n")
        Shell:emit(state, "Amber:set_status(__shell_status)\n")
        Shell:emit(state, "Shell:Pipeline:destroy(__shell_pipeline)\n__shell_result\n}")
    } else {
        Shell:emit(state, "let __shell_invocation = Shell:Invocation:start(__shell_pipeline, 0)\n")
        Shell:emit(state, "var __shell_result = 126\n")
        Shell:emit(state, "if __shell_invocation { __shell_result = __shell_invocation.exit_code(); __shell_invocation.destroy() }\n")
        Shell:emit(state, "Amber:set_status(__shell_result)\n")
        Shell:emit(state, "Shell:Pipeline:destroy(__shell_pipeline)\n__shell_result\n}")
    }
    if delimiter == 125 { Shell:emit(state, "}") }
    else { Shell:emit(state, "\n") }
}

// Amber's `let` is mutable, unlike a normal RecurLoop compiled `let` local.
// At top level the assignment adapter already delegates ordinary declarations
// to `var`. During fn compilation this rewrite emits `var` as well. It also
// recognizes the Amber command-expression form `let name = $ ... $` and emits
// a native capturing pipeline instead of an exit-code command statement.
let Amber:rewrite_let = fn (state:Context*) -> void {
    let source = context:syntax:data(state)
    let bytes = context:syntax:bytes(state)
    var cursor = 0
    while cursor < bytes && (source[cursor] == 32 || source[cursor] == 9) { cursor += 1 }
    let name_start = cursor
    if cursor < bytes {
        let first = source[cursor]
        if (first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95 {
            cursor += 1
            var scanning = 1
            while scanning && cursor < bytes {
                let ch = source[cursor]
                if (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) ||
                    (ch >= 48 && ch <= 57) || ch == 95 { cursor += 1 }
                else { scanning = 0 }
            }
        }
    }
    let name_end = cursor
    while cursor < bytes && (source[cursor] == 32 || source[cursor] == 9) { cursor += 1 }
    if name_end <= name_start || cursor >= bytes || source[cursor] != 61 {
        context:syntax:emit(state, "var ")
        return
    }
    cursor += 1
    while cursor < bytes && (source[cursor] == 32 || source[cursor] == 9) { cursor += 1 }
    if cursor >= bytes || source[cursor] != 36 {
        context:syntax:emit(state, "var ")
        return
    }

    context:syntax:emit(state, "var ")
    context:syntax:emit(state, source, name_start, name_end - name_start)
    context:syntax:emit(state, " = ")
    context:syntax:advance(state, cursor + 1)
    Shell:rewrite_command(state, 1)
}

let shell_top_level_let = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Amber:rewrite_let(state) }
        else { Shell:top_level_assignment(state, "var", 1) }
    }
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
// Amber requires explicit $ ... $ commands; do not install the implicit shell fallback.

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
let Shell:Grammar:command:"$" = phrase { type = <phrase-types:elaborate> action = <Shell:Internal:token_finish> successor = none }

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

// ============================================================================
// Amber command syntax
// ============================================================================

let Amber:command = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            Shell:rewrite_command(state, 0)
        } else {
            Shell:state_set(state, "__amber_silent", 0)
            Shell:state_set(state, "__amber_suppress", 0)
            Shell:begin_top_command(state, 0)
        }
    }
}

let Amber:silent_command = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            Shell:emit(state, "{\nlet __amber_saved_stdout = Amber:stdout_silence_enter()\ndefer Amber:stdout_silence_leave(__amber_saved_stdout)\n")
            Shell:rewrite_command(state, 0)
            Shell:emit(state, "\n}")
        } else {
            Shell:state_set(state, "__amber_silent", 1)
            Shell:state_set(state, "__amber_suppress", 0)
            Shell:begin_top_command(state, 0)
        }
    }
}

let Amber:suppress_command = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            Shell:emit(state, "{\nlet __amber_saved_stderr = Amber:stderr_silence_enter()\ndefer Amber:stderr_silence_leave(__amber_saved_stderr)\n")
            Shell:rewrite_command(state, 0)
            Shell:emit(state, "\n}")
        } else {
            Shell:state_set(state, "__amber_silent", 0)
            Shell:state_set(state, "__amber_suppress", 1)
            Shell:begin_top_command(state, 0)
        }
    }
}

let Amber:silent_suppress_command = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) {
            Shell:emit(state, "{\nlet __amber_saved_stdout = Amber:stdout_silence_enter()\nlet __amber_saved_stderr = Amber:stderr_silence_enter()\ndefer Amber:stdout_silence_leave(__amber_saved_stdout)\ndefer Amber:stderr_silence_leave(__amber_saved_stderr)\n")
            Shell:rewrite_command(state, 0)
            Shell:emit(state, "\n}")
        } else {
            Shell:state_set(state, "__amber_silent", 1)
            Shell:state_set(state, "__amber_suppress", 1)
            Shell:begin_top_command(state, 0)
        }
    }
}

// `trust` is syntactically accepted. RecurLoop currently does not impose
// Amber's compile-time rule that every failable command must be handled.
// Define aliases directly in source so they are part of the serializable lexicon.
let "$" = <Amber:command>
let "trust $" = <Amber:command>
let "silent $" = <Amber:silent_command>
let "silent trust $" = <Amber:silent_command>
let "trust silent $" = <Amber:silent_command>
let "suppress $" = <Amber:suppress_command>
let "suppress trust $" = <Amber:suppress_command>
let "trust suppress $" = <Amber:suppress_command>
let "silent suppress $" = <Amber:silent_suppress_command>
let "suppress silent $" = <Amber:silent_suppress_command>
let "silent suppress trust $" = <Amber:silent_suppress_command>
let "silent trust suppress $" = <Amber:silent_suppress_command>
let "suppress silent trust $" = <Amber:silent_suppress_command>
let "suppress trust silent $" = <Amber:silent_suppress_command>
let "trust silent suppress $" = <Amber:silent_suppress_command>
let "trust suppress silent $" = <Amber:silent_suppress_command>

let Amber:bind_handler_status = fn (state:Context*, header:u8*, value:i64) -> i64 {
    if !header { return 1 }
    var cursor = 0
    while header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13 { cursor += 1 }
    if header[cursor] == 0 { return 1 }
    if header[cursor] != 40 { return 0 }
    cursor += 1
    while header[cursor] == 32 || header[cursor] == 9 { cursor += 1 }
    let start = cursor
    let first = header[cursor]
    if !((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95) { return 0 }
    cursor += 1
    var scanning = 1
    while scanning {
        let ch = header[cursor]
        if (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch == 95 { cursor += 1 }
        else { scanning = 0 }
    }
    let name = Shell:copy_slice(header, start, cursor)
    if !name { return 0 }
    defer free(name)
    while header[cursor] == 32 || header[cursor] == 9 { cursor += 1 }
    if header[cursor] != 41 { return 0 }
    cursor += 1
    while header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13 { cursor += 1 }
    if header[cursor] != 0 { return 0 }
    if context:value:contains(state, name) {
        return context:value:assign:integer(state, name, value)
    }
    return context:value:define:integer(state, name, value)
}

let Amber:run_handler = fn (state:Context*, kind:i64) -> void {
    let block = state.source_block_capture()
    if !block { return }
    defer block.release()
    let code = Amber:get_status()
    let handler_header = block.header()
    if kind == 2 {
        var cursor = 0
        while handler_header[cursor] == 32 || handler_header[cursor] == 9 || handler_header[cursor] == 10 || handler_header[cursor] == 13 { cursor += 1 }
        if handler_header[cursor] != 0 {
            context:diagnostic:error(state, "Amber succeeded does not accept an exit-code binding")
            return
        }
    } else if !Amber:bind_handler_status(state, handler_header, code) {
        context:diagnostic:error(state, "Amber handler expects failed[(name)]/succeeded/exited[(name)] followed by a block")
        return
    }
    if kind == 1 && code == 0 { return }
    if kind == 2 && code != 0 { return }
    state.source_block_execute_current(block)
}

let Amber:syntax_skip_string = fn (source:u8*, position:i64, limit:i64, quote:u8) -> i64 {
    var cursor = position + 1
    while cursor < limit {
        if source[cursor] == 92 {
            cursor += 2
        } else if source[cursor] == quote {
            return cursor + 1
        } else {
            cursor += 1
        }
    }
    return limit
}

let Amber:syntax_block_open = fn (source:u8*, limit:i64) -> i64 {
    var cursor = 0
    var parens = 0
    while cursor < limit {
        let ch = source[cursor]
        if ch == 34 || ch == 39 {
            cursor = Amber:syntax_skip_string(source, cursor, limit, ch)
        } else {
            if ch == 40 { parens += 1 }
            else if ch == 41 { parens -= 1 }
            else if ch == 123 && parens == 0 { return cursor }
            cursor += 1
        }
    }
    return -1
}

let Amber:syntax_block_close = fn (source:u8*, open:i64, limit:i64) -> i64 {
    var cursor = open + 1
    var depth = 1
    while cursor < limit {
        let ch = source[cursor]
        if ch == 34 || ch == 39 {
            cursor = Amber:syntax_skip_string(source, cursor, limit, ch)
        } else {
            if ch == 123 { depth += 1 }
            else if ch == 125 {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
    }
    return -1
}

// Rewrite Amber outcome handlers inside compiled functions. The command itself
// has already updated Amber status(), so the handler becomes ordinary RecurLoop
// control flow around the original body.
let Amber:rewrite_handler = fn (state:Context*, kind:i64) -> void {
    let source = context:syntax:data(state)
    let bytes = context:syntax:bytes(state)
    let open = Amber:syntax_block_open(source, bytes)
    if open < 0 {
        context:diagnostic:error(state, "Amber outcome handler expects a block")
        return
    }
    let close = Amber:syntax_block_close(source, open, bytes)
    if close < 0 {
        context:diagnostic:error(state, "Amber outcome handler block is not closed")
        return
    }

    var start = 0
    while start < open && (source[start] == 32 || source[start] == 9 || source[start] == 10 || source[start] == 13) { start += 1 }
    var name_start = -1
    var name_end = -1
    if start < open {
        if source[start] != 40 {
            context:diagnostic:error(state, "Amber outcome status binding expects (name)")
            return
        }
        start += 1
        while start < open && (source[start] == 32 || source[start] == 9) { start += 1 }
        name_start = start
        if start >= open { context:diagnostic:error(state, "Amber outcome status binding is empty"); return }
        let first = source[start]
        if !((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95) {
            context:diagnostic:error(state, "Amber outcome status binding expects an identifier")
            return
        }
        start += 1
        var scanning = 1
        while scanning && start < open {
            let ch = source[start]
            if (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch == 95 { start += 1 }
            else { scanning = 0 }
        }
        name_end = start
        while start < open && (source[start] == 32 || source[start] == 9) { start += 1 }
        if start >= open || source[start] != 41 {
            context:diagnostic:error(state, "Amber outcome status binding expects a closing parenthesis")
            return
        }
        start += 1
        while start < open && (source[start] == 32 || source[start] == 9 || source[start] == 10 || source[start] == 13) { start += 1 }
        if start != open {
            context:diagnostic:error(state, "unexpected text before Amber outcome block")
            return
        }
    }

    if kind == 2 && name_start >= 0 {
        context:diagnostic:error(state, "Amber succeeded does not accept an exit-code binding")
        return
    }

    if kind == 1 { context:syntax:emit(state, "if status() != 0 {\n") }
    else if kind == 2 { context:syntax:emit(state, "if status() == 0 {\n") }
    else { context:syntax:emit(state, "if 1 {\n") }

    if name_start >= 0 {
        context:syntax:emit(state, "var ")
        context:syntax:emit(state, source, name_start, name_end - name_start)
        context:syntax:emit(state, " = status()\n")
    }
    if close > open + 1 {
        context:syntax:emit(state, source, open + 1, close - open - 1)
    }
    context:syntax:emit(state, "\n}\n")
    context:syntax:advance(state, close + 1)
}

let failed = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Amber:rewrite_handler(state, 1) }
        else { Amber:run_handler(state, 1) }
    }
}

let succeeded = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Amber:rewrite_handler(state, 2) }
        else { Amber:run_handler(state, 2) }
    }
}

let exited = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Amber:rewrite_handler(state, 3) }
        else { Amber:run_handler(state, 3) }
    }
}

// Amber command modifiers can also be used as scopes, for example:
//   silent trust {
//       $ first command $
//       $ second command $
//   }
// `trust` is a semantic no-op here because this compatibility layer does not
// implement Amber's compile-time failable-command checker.
let Amber:run_modifier_scope = fn (state:Context*, silence_stdout:i64, suppress_stderr:i64) -> void {
    let block = state.source_block_capture()
    if !block { return }
    defer block.release()
    let header = block.header()
    var cursor = 0
    while header[cursor] == 32 || header[cursor] == 9 || header[cursor] == 10 || header[cursor] == 13 { cursor += 1 }
    if header[cursor] != 0 {
        context:diagnostic:error(state, "Amber command modifier scope expects a block with no header")
        return
    }

    var saved_stdout = -1
    var saved_stderr = -1
    if silence_stdout { saved_stdout = Amber:stdout_silence_enter() }
    if suppress_stderr { saved_stderr = Amber:stderr_silence_enter() }
    defer Amber:stdout_silence_leave(saved_stdout)
    defer Amber:stderr_silence_leave(saved_stderr)
    state.source_block_execute_current(block)
}

let Amber:rewrite_modifier_scope = fn (state:Context*, silence_stdout:i64, suppress_stderr:i64) -> void {
    let source = context:syntax:data(state)
    let bytes = context:syntax:bytes(state)
    let open = Amber:syntax_block_open(source, bytes)
    if open < 0 {
        context:diagnostic:error(state, "Amber command modifier scope expects a block")
        return
    }
    var cursor = 0
    while cursor < open && (source[cursor] == 32 || source[cursor] == 9 || source[cursor] == 10 || source[cursor] == 13) { cursor += 1 }
    if cursor != open {
        context:diagnostic:error(state, "Amber command modifier scope expects a block with no header")
        return
    }
    let close = Amber:syntax_block_close(source, open, bytes)
    if close < 0 {
        context:diagnostic:error(state, "Amber command modifier scope block is not closed")
        return
    }

    context:syntax:emit(state, "{\n")
    if silence_stdout {
        context:syntax:emit(state, "let __amber_scope_stdout = Amber:stdout_silence_enter()\ndefer Amber:stdout_silence_leave(__amber_scope_stdout)\n")
    }
    if suppress_stderr {
        context:syntax:emit(state, "let __amber_scope_stderr = Amber:stderr_silence_enter()\ndefer Amber:stderr_silence_leave(__amber_scope_stderr)\n")
    }
    if close > open + 1 {
        context:syntax:emit(state, source, open + 1, close - open - 1)
    }
    context:syntax:emit(state, "\n}\n")
    context:syntax:advance(state, close + 1)
}

let Amber:trust_scope = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Amber:rewrite_modifier_scope(state, 0, 0) }
        else { Amber:run_modifier_scope(state, 0, 0) }
    }
}

let Amber:silent_scope = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Amber:rewrite_modifier_scope(state, 1, 0) }
        else { Amber:run_modifier_scope(state, 1, 0) }
    }
}

let Amber:suppress_scope = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Amber:rewrite_modifier_scope(state, 0, 1) }
        else { Amber:run_modifier_scope(state, 0, 1) }
    }
}

let Amber:silent_suppress_scope = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:syntax:active(state) { Amber:rewrite_modifier_scope(state, 1, 1) }
        else { Amber:run_modifier_scope(state, 1, 1) }
    }
}

// Modifier scopes are source aliases too, so they survive engine-image export.
let trust = <Amber:trust_scope>
let silent = <Amber:silent_scope>
let suppress = <Amber:suppress_scope>
let "silent trust" = <Amber:silent_scope>
let "trust silent" = <Amber:silent_scope>
let "suppress trust" = <Amber:suppress_scope>
let "trust suppress" = <Amber:suppress_scope>
let "silent suppress" = <Amber:silent_suppress_scope>
let "suppress silent" = <Amber:silent_suppress_scope>
let "silent suppress trust" = <Amber:silent_suppress_scope>
let "silent trust suppress" = <Amber:silent_suppress_scope>
let "suppress silent trust" = <Amber:silent_suppress_scope>
let "suppress trust silent" = <Amber:silent_suppress_scope>
let "trust silent suppress" = <Amber:silent_suppress_scope>
let "trust suppress silent" = <Amber:silent_suppress_scope>

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

// RecurLoop-side introspection. This checks phrase dictionaries only; it does
// not consult Context values, the shell runtime, or array storage.
let Amber:assert_symbol_phrase = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        context:source:ensure(state, 4096)
        let source = cast(u8*, context:source:data(state))
        let bytes = context:source:bytes(state)
        var i = 0
        while i < bytes && Shell:is_space(source[i]) { i += 1 }
        let category_start = i
        while i < bytes && !Shell:is_space(source[i]) { i += 1 }
        let category_end = i
        while i < bytes && Shell:is_space(source[i]) { i += 1 }
        let name_start = i
        while i < bytes && !Shell:is_space(source[i]) { i += 1 }
        let name_end = i
        let category = Shell:copy_slice(source, category_start, category_end)
        let name = Shell:copy_slice(source, name_start, name_end)
        if !category || !name { context:diagnostic:error(state, "amber_assert expects CATEGORY NAME") }
        else {
            var owner_name = cast(u8*, 0)
            if Shell:text_equal(category, "function") { owner_name = "Functions" }
            else if Shell:text_equal(category, "variable") { owner_name = "Variables" }
            else if Shell:text_equal(category, "array") { owner_name = "Arrays" }
            else if Shell:text_equal(category, "type") { owner_name = "Types" }
            else if Shell:text_equal(category, "builtin") { owner_name = "Builtins" }
            else if Shell:text_equal(category, "grammar") { owner_name = "Grammar" }
            else if Shell:text_equal(category, "symbol") { owner_name = "Symbols" }
            if !owner_name || !Amber:symbol_in(state, owner_name, name) {
                context:diagnostic:error(state, "Amber: expected phrase-backed symbol is missing")
            }
        }
        if category { free(category) }
        if name { free(name) }
        context:source:advance(state, name_end)
        context:source:root(state)
    }
}
let amber_assert = <Amber:assert_symbol_phrase>

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
set dup.serializable = false
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
set getpid.serializable = false
set sleep.serializable = false
set install_shell_fallback.serializable = false
set install_shell_assignments.serializable = false
set install_amber_scalar_types.serializable = false
engine export "/tmp/recurloop-amber-library.rli"
