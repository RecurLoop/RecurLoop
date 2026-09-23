// =============================================================================
// RecurLoop native IDE runtime.
//
// This library contains the stable project runner, filesystem/workspace API,
// hot-reload lifecycle, one shared project runtime and persistent terminal
// models. Concrete IDE views are project source: ide.rli owns the window and
// runtime, but not explorer/editor/terminal widgets or their composition. The
// C++ host remains unaware of GUI/IDE policy.
// =============================================================================

languagekit_native_begin

link shared "c"
link shared "dl"
link shared "gtk-3"
link shared "glib-2.0"

let IDE = phrase { dictionary = true permanent = true }

// libc / Linux filesystem. Common declarations come from language-kit.rli.
extern realpath(path:u8*, resolved:u8*) -> u8* abi sysv-amd64
extern readlink(path:u8*, target:u8*, size:u64) -> i64 abi sysv-amd64
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
extern inotify_rm_watch(fd:i32, wd:i32) -> i32 abi sysv-amd64
extern read(fd:i32, target:u8*, bytes:u64) -> i64 abi sysv-amd64
extern clock_gettime(clock:i32, time:u8*) -> i32 abi sysv-amd64
extern snprintf(buffer:u8*, size:u64, format:u8*, ...) -> i32 abi sysv-amd64
extern fork() -> i32 abi sysv-amd64
extern execvp(file:u8*, argv:u8**) -> i32 abi sysv-amd64
extern waitpid(pid:i32, status:i32*, options:i32) -> i32 abi sysv-amd64
extern _exit(status:i32) -> void abi sysv-amd64
extern kill(pid:i32, signal:i32) -> i32 abi sysv-amd64
extern unlink(path:u8*) -> i32 abi sysv-amd64
extern rmdir(path:u8*) -> i32 abi sysv-amd64
extern mkdir(path:u8*, mode:u32) -> i32 abi sysv-amd64
extern rename(old_path:u8*, new_path:u8*) -> i32 abi sysv-amd64
extern access(path:u8*, mode:i32) -> i32 abi sysv-amd64
extern getpid() -> i32 abi sysv-amd64
extern chdir(path:u8*) -> i32 abi sysv-amd64
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

// Event sources used by the Linux IDE backend. Hot reload correctness is event
// driven: inotify wakes the main loop and worker completion is delivered by
// GLib's child watcher. No polling/debounce interval participates in deciding
// which source generation may become visible.
let IDE:ChildWatch = fn (pid:i32, status:i32, data:u8*) -> void
let IDE:FdWatch = fn (fd:i32, condition:i32, data:u8*) -> i32
extern g_child_watch_add(pid:i32, callback:IDE:ChildWatch, data:u8*) -> u32 abi sysv-amd64
extern g_unix_fd_add(fd:i32, condition:i32, callback:IDE:FdWatch, data:u8*) -> u32 abi sysv-amd64

// GUI widgets are provided by gui.rli.  This library owns only the stable
// project/runtime/hot-reload state and never talks to GTK directly.
let IDE:Lifecycle = fn (action:i64, host:u8*) -> void
let IDE:ShellLifecycle = fn (action:i64, host:u8*) -> void

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
    application:u8*
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
    cache_directory:u8*
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

// Blocking project compilation/publication never runs on GTK's main thread.
// `epoch` is the exact source generation observed when the worker was spawned.
// A result from an older epoch is never allowed to become visible.
record IDE:Job {
    pid:i32
    kind:i32
    revision:u64
    epoch:u64
    source_path:u8*
    result_path:u8*
}

// Stable application host. The native window and render surface outlive every
// project generation. A replacement view is first built into candidate_* while
// the current content remains visible, then selected on the stack in one main-
// loop turn. retiring_* lets the old lifecycle free its own state only after
// its widgets have been detached and destroyed.
record IDE:Host {
    root:u8*
    entry:u8*
    runner:IDE:Runner*
    window:u8*
    surface:u8*
    content:u8*
    user_data:u8*
    candidate_content:u8*
    candidate_user_data:u8*
    retiring_content:u8*
    retiring_user_data:u8*
    candidate_title:u8*
    terminals:IDE:Terminal*
    watcher:IDE:Watcher*
    selected:u8*
    pending_since:i64
    terminal_number:i64
    shell_lifecycle:IDE:ShellLifecycle
    initial_module:u8*
    startup_phase:i64
    watch_root:u8*
    config_source:u8*
    watch_sources:u8*
    reload_mode:i64
    candidate_reload_mode:i64
    reload_pending:i64
    view_phase:i64
    candidate_config_ready:i64
    source_epoch:u64
    job:IDE:Job*
    job_watch:IDE:ChildWatch
    window_title:u8*
    window_width:i64
    window_height:i64
    candidate_window_width:i64
    candidate_window_height:i64
}

// Per-instance application configuration. A project supplies one lifecycle
// callback with app.view(...). That callback belongs to the project generation;
// the Host/window/project runtime remain stable across view replacement.
record IDE:Config {
    workspace_path:u8*
    source_path:u8*
    cache_path:u8*
    watch_path:u8*
    reload_mode:i64
    title_text:u8*
    window_width:i64
    window_height:i64
    view_lifecycle:IDE:Lifecycle
}

let IDE:Reload = phrase { dictionary = true permanent = true }
let IDE:Reload:Off = fn () -> i64 { return 0 }
let IDE:Reload:Hot = fn () -> i64 { return 1 }
let IDE:Reload:Manual = fn () -> i64 { return 2 }

// View access is generation-aware. Project code must use these helpers instead
// of reading/writing Host.user_data directly so candidate and retiring views can
// coexist safely during a transactional replacement.
let IDE:view_data = fn (host:IDE:Host*) -> u8* {
    if !host { return cast(u8*, 0) }
    if host.view_phase == 1 { return host.candidate_user_data }
    if host.view_phase == 2 { return host.retiring_user_data }
    return host.user_data
}

let IDE:view_reload_mode = fn (host:IDE:Host*) -> i64 {
    if !host { return IDE:Reload:Off() }
    if host.view_phase == 1 { return host.candidate_reload_mode }
    return host.reload_mode
}

// The view is fully constructed offscreen before it is attached here. During a
// reload the stack still displays Host.content; adding a candidate does not make
// it current. A lifecycle that never attaches a root is rejected.
let IDE:view_attach = fn (host:IDE:Host*, content:u8*, data:u8*) -> i64 {
    if !host || host.view_phase != 1 || !host.surface || !content || !data { return 0 }
    if host.candidate_content || host.candidate_user_data { return 0 }
    host.candidate_content = content
    host.candidate_user_data = data
    Gui:stack_add(host.surface, content)
    return 1
}

// Project UI never needs to know the native directory-entry layout. Platform
// backends can replace this implementation without changing explorer.rl.
let IDE:DirectoryVisitor = fn (path:u8*, name:u8*, directory:i64, data:u8*) -> void

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
    let ts = alloc(IDE:Timespec)
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


let IDE:file_exists = fn (path:u8*) -> i64 {
    if !path { return 0 }
    let stream = fopen(path, "rb")
    if !stream { return 0 }
    fclose(stream)
    return 1
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

// Enumerate exactly one directory without exposing libc/dirent details to the
// source-defined view. Call once with directories=1 and once with 0 when a UI
// wants the conventional folders-first presentation.
let IDE:visit_directory = fn (path:u8*, directories:i64, visitor:IDE:DirectoryVisitor, data:u8*) -> i64 {
    if !path || !visitor { return 0 }
    let handle = opendir(path)
    if !handle { return 0 }
    defer closedir(handle)

    var entry = readdir(handle)
    while entry {
        let kind = entry[18]
        let name = &entry[19]
        if !IDE:skip_directory(name) {
            let child = IDE:join(path, name)
            if child {
                let is_dir = kind == 4 || (kind == 0 && IDE:is_directory(child))
                if (directories != 0 && is_dir) || (directories == 0 && !is_dir) {
                    visitor(child, name, is_dir, data)
                }
                free(child)
            }
        }
        entry = readdir(handle)
    }
    return 1
}

let IDE:path_exists = fn (path:u8*) -> i64 {
    if !path { return 0 }
    return access(path, 0) == 0
}

let IDE:ensure_directory = fn (path:u8*) -> i64 {
    if !path { return 0 }
    if IDE:is_directory(path) { return 1 }
    if IDE:path_exists(path) { return 0 }
    return mkdir(path, cast(u32, 493)) == 0
}


let IDE:project_cache_directory = fn (root:u8*) -> u8* {
    if !root { return cast(u8*, 0) }
    let cache = IDE:join(root, ".cache")
    if !cache { return cast(u8*, 0) }
    if !IDE:ensure_directory(cache) { free(cache); return cast(u8*, 0) }
    let recurloop = IDE:join(cache, "recurloop")
    free(cache)
    if !recurloop { return cast(u8*, 0) }
    if !IDE:ensure_directory(recurloop) { free(recurloop); return cast(u8*, 0) }
    return recurloop
}

let IDE:leaf_name = fn (path:u8*) -> u8* {
    if !path { return cast(u8*, 0) }
    let bytes = cast(i64, strlen(path))
    var start = 0
    var i = 0
    while i < bytes {
        if path[i] == 47 { start = i + 1 }
        i += 1
    }
    return IDE:copy(&path[start])
}

let IDE:parent_path = fn (path:u8*) -> u8* {
    if !path { return cast(u8*, 0) }
    let bytes = cast(i64, strlen(path))
    if bytes == 0 { return IDE:copy(".") }
    var i = bytes
    while i > 0 && path[i - 1] != 47 { i -= 1 }
    if i == 0 { return IDE:copy(".") }
    if i == 1 { return IDE:copy("/") }
    let result = cast(u8*, malloc(i))
    if !result { return cast(u8*, 0) }
    memcpy(result, path, i - 1)
    result[i - 1] = 0
    return result
}

let IDE:ensure_directory_tree = fn (path:u8*) -> i64 {
    if !path || path[0] == 0 { return 0 }
    if IDE:is_directory(path) { return 1 }
    if IDE:path_exists(path) { return 0 }
    let parent = IDE:parent_path(path)
    if parent {
        let different = strcmp(parent, path) != 0
        let trivial = strcmp(parent, ".") == 0
        if different && !trivial && !IDE:is_directory(parent) && !IDE:ensure_directory_tree(parent) {
            free(parent)
            return 0
        }
        free(parent)
    }
    return mkdir(path, cast(u32, 493)) == 0 || IDE:is_directory(path)
}


// Resolve runtime assets from the running executable instead of embedding the
// build machine's source/build paths.  This keeps the native IDE relocatable:
// build trees use build/Release/{bin,libraries}, installed trees use
// {bin,share/recurloop/{libraries,ide}}, and explicit environment overrides
// remain available for development/package testing.
let IDE:self_executable = fn () -> u8* {
    let result = cast(u8*, malloc(4096))
    if !result { return cast(u8*, 0) }
    let bytes = readlink("/proc/self/exe", result, 4095)
    if bytes <= 0 || bytes >= 4095 { free(result); return cast(u8*, 0) }
    result[bytes] = 0
    return result
}

let IDE:resolve_file = fn (path:u8*) -> u8* {
    if !path || path[0] == 0 { return cast(u8*, 0) }
    return realpath(path, cast(u8*, 0))
}

let IDE:resolve_host = fn () -> u8* {
    let override = getenv("RECURLOOP_HOST")
    if override && override[0] != 0 {
        let resolved = IDE:resolve_file(override)
        if resolved { return resolved }
    }

    let self = IDE:self_executable()
    if !self { return cast(u8*, 0) }
    defer free(self)
    let directory = IDE:parent_path(self)
    if !directory { return cast(u8*, 0) }
    defer free(directory)
    let candidate = IDE:join(directory, "recurloop")
    if !candidate { return cast(u8*, 0) }
    defer free(candidate)
    return IDE:resolve_file(candidate)
}


let IDE:resolve_library_directory = fn (program:u8*) -> u8* {
    if !program { return cast(u8*, 0) }
    let directory = IDE:parent_path(program)
    if !directory { return cast(u8*, 0) }
    defer free(directory)
    let prefix = IDE:parent_path(directory)
    if !prefix { return cast(u8*, 0) }
    defer free(prefix)

    var candidate = IDE:join(prefix, "libraries")
    if candidate {
        let directory_handle = opendir(candidate)
        if directory_handle { closedir(directory_handle); return candidate }
        free(candidate)
    }
    candidate = IDE:join(prefix, "share/recurloop/libraries")
    if candidate {
        let directory_handle = opendir(candidate)
        if directory_handle { closedir(directory_handle); return candidate }
        free(candidate)
    }
    return cast(u8*, 0)
}

let IDE:has_suffix = fn (text:u8*, suffix:u8*) -> i64 {
    if !text || !suffix { return 0 }
    let text_bytes = cast(i64, strlen(text))
    let suffix_bytes = cast(i64, strlen(suffix))
    if suffix_bytes > text_bytes { return 0 }
    return strcmp(&text[text_bytes - suffix_bytes], suffix) == 0
}

let IDE:path_is_inside = fn (path:u8*, prefix:u8*) -> i64 {
    if !path || !prefix { return 0 }
    var i = 0
    while prefix[i] != 0 && path[i] == prefix[i] { i += 1 }
    if prefix[i] != 0 { return 0 }
    return path[i] == 0 || path[i] == 47
}

let IDE:valid_leaf_name = fn (name:u8*) -> i64 {
    if !name || name[0] == 0 { return 0 }
    if strcmp(name, ".") == 0 || strcmp(name, "..") == 0 { return 0 }
    var i = 0
    while name[i] != 0 {
        if name[i] == 47 || name[i] == 92 { return 0 }
        i += 1
    }
    return 1
}

let IDE:create_empty_file = fn (path:u8*) -> i64 {
    if !path || IDE:path_exists(path) { return 0 }
    let stream = fopen(path, "wb")
    if !stream { return 0 }
    fclose(stream)
    return 1
}

let IDE:create_directory = fn (path:u8*) -> i64 {
    if !path || IDE:path_exists(path) { return 0 }
    return mkdir(path, cast(u32, 493)) == 0
}

let IDE:rename_path = fn (old_path:u8*, new_path:u8*) -> i64 {
    if !old_path || !new_path || IDE:path_exists(new_path) { return 0 }
    return rename(old_path, new_path) == 0
}

let IDE:remove_path = fn (path:u8*) -> i64 {
    if !path { return 0 }
    if !IDE:is_directory(path) { return unlink(path) == 0 }

    let directory = opendir(path)
    if !directory { return 0 }
    var ok:i64 = 1
    var entry = readdir(directory)
    while entry {
        let name = &entry[19]
        if strcmp(name, ".") != 0 && strcmp(name, "..") != 0 {
            let child = IDE:join(path, name)
            if child {
                let kind = entry[18]
                let is_dir = kind == 4 || (kind == 0 && IDE:is_directory(child))
                if is_dir {
                    if !IDE:remove_path(child) { ok = 0 }
                } else {
                    if unlink(child) != 0 { ok = 0 }
                }
                free(child)
            } else {
                ok = 0
            }
        }
        entry = readdir(directory)
    }
    closedir(directory)
    if !ok { return 0 }
    return rmdir(path) == 0
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
// One ordinary `recurloop --serve` process owns the project for the whole IDE
// lifetime. Candidate builds use short-lived sessions on that same project.
// A candidate is published only after source compilation and native linking
// succeed, so failed builds never replace the shared project generation.
// Existing terminal sessions can then use ordinary `:refresh` to attach to the
// newly published generation; no terminal is stranded on an old server.
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
    let bytes = snprintf(path, 256, "/tmp/recurloop-ide-module-%d-%llu%s", process, revision, ending)
    if bytes < 0 || bytes >= 256 { free(path); return cast(u8*, 0) }
    return path
}

// Native hot-reload artifacts belong to the configured IDE cache.  The Unix
// socket remains in /tmp because it is runtime state, not a compiled artifact.
let IDE:Runner:cache_artifact = fn (self:IDE:Runner*, revision:u64, ending:u8*) -> u8* {
    if !self || !ending || !self.cache_directory { return IDE:artifact(revision, ending) }
    let directory = IDE:join(self.cache_directory, "ide")
    if !directory { return cast(u8*, 0) }
    defer free(directory)
    if !IDE:ensure_directory_tree(directory) { return cast(u8*, 0) }

    let path = cast(u8*, malloc(512))
    if !path { return cast(u8*, 0) }
    let bytes = snprintf(path, 512, "%s/generation-%d-%llu%s", directory, getpid(), revision, ending)
    if bytes < 0 || bytes >= 512 { free(path); return cast(u8*, 0) }
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

let IDE:RuntimeSession:load_file = fn (self:IDE:RuntimeSession*, path:u8*) -> i32 {
    if !self || !path { return 1 }
    // Internal server transport command. Unlike the language-level `:load`
    // phrase, this reaches Session::executeFile(), which is the cache boundary
    // for project source and therefore restores/writes step .rli images.
    let command = LanguageKit:Text:new()
    if !command { return 1 }
    defer command.destroy()
    command.append(":load-file\t")
    command.append(path)
    return self.request(command.data)
}

// Generated build drivers are unique to one revision and are deleted as soon
// as the native module has been linked. Evaluate them as ordinary included
// source instead of advancing the persistent step cache and serializing a full
// checkpoint that can never be reused.
let IDE:RuntimeSession:load_transient_file = fn (self:IDE:RuntimeSession*, path:u8*) -> i32 {
    if !self || !path { return 1 }
    let command = LanguageKit:Text:new()
    if !command { return 1 }
    defer command.destroy()
    command.append("include ")
    if !IDE:append_source_string(command, path) { return 1 }
    return self.request(command.data)
}

let IDE:RuntimeSession:load_optional_file = fn (self:IDE:RuntimeSession*, path:u8*) -> i32 {
    if !path || !IDE:file_exists(path) { return 0 }
    return self.load_file(path)
}


let IDE:RuntimeSession:load_project_file = fn (self:IDE:RuntimeSession*, runner:IDE:Runner*) -> i32 {
    if !self || !runner || !runner.root { return 1 }
    let project = IDE:join(runner.root, "project.rl")
    if !project { return 1 }
    let status = self.load_optional_file(project)
    free(project)
    return status
}

let IDE:RuntimeSession:load_entry = fn (self:IDE:RuntimeSession*, runner:IDE:Runner*) -> i32 {
    if !self || !runner || !runner.application { return 1 }
    if self.request(":baseline") != 0 { return 1 }
    if self.request(":cache") != 0 { return 1 }
    if self.load_file(runner.application) != 0 { return 1 }
    return self.load_project_file(runner)
}

let IDE:RuntimeSession:load_environment = fn (self:IDE:RuntimeSession*, runner:IDE:Runner*) -> i32 {
    return self.load_entry(runner)
}

let IDE:RuntimeSession:load_view_environment = fn (self:IDE:RuntimeSession*, runner:IDE:Runner*) -> i32 {
    return self.load_entry(runner)
}

let IDE:RuntimeSession:cache_dependencies = fn (self:IDE:RuntimeSession*) -> u8* {
    if !self || self.request(":cache-dependencies") != 0 || !self.last_output { return cast(u8*, 0) }
    return IDE:copy(self.last_output)
}

let IDE:RuntimeSession:new = fn (runner:IDE:Runner*) -> IDE:RuntimeSession* {
    if !runner || !runner.socket_path { return cast(IDE:RuntimeSession*, 0) }
    let fd = IDE:connect_socket(runner.socket_path)
    if fd < 0 { return cast(IDE:RuntimeSession*, 0) }
    let greeting = IDE:receive_response(fd)
    if !greeting { close(fd); return cast(IDE:RuntimeSession*, 0) }
    free(greeting)
    let self = alloc(IDE:RuntimeSession)
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
    let status = alloc(i32)
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
        let status = alloc(i32)
        if status { waitpid(self.pid, status, 0); free(cast(u8*, status)) }
        self.pid = -1
    }
    if self.socket_path { unlink(self.socket_path) }
}

let IDE:Runner:start_server = fn (self:IDE:Runner*) -> i64 {
    if !self || !self.program || !self.root || !self.socket_path { return 0 }
    unlink(self.socket_path)
    let library_path = IDE:resolve_library_directory(self.program)
    var cache_directory = IDE:copy(self.cache_directory)
    if !cache_directory { cache_directory = IDE:project_cache_directory(self.root) }
    let args = cast(u8**, malloc(18 * sizeof(u8*)))
    if !args {
        if library_path { free(library_path) }
        if cache_directory { free(cache_directory) }
        return 0
    }
    var at = 0
    args[at] = self.program; at += 1
    if library_path {
        args[at] = "--library-path"; at += 1
        args[at] = library_path; at += 1
    }
    // project.rli is the immutable shared baseline. No workspace source is
    // parsed before the server socket is ready; the local overlay is published
    // later as one transaction from the GTK event loop.
    args[at] = "--library"; at += 1
    args[at] = "project"; at += 1
    if cache_directory {
        args[at] = "--project-cache"; at += 1
        args[at] = cache_directory; at += 1
    }
    args[at] = "--serve"; at += 1
    args[at] = "--unix"; at += 1
    args[at] = self.socket_path; at += 1
    args[at] = "--no-stdio"; at += 1
    args[at] = cast(u8*, 0)
    setenv("RECURLOOP_IDE_PROJECT_BUILD", "1", 1)
    let pid = fork()
    if pid < 0 {
        unsetenv("RECURLOOP_IDE_PROJECT_BUILD")
        free(cast(u8*, args))
        if library_path { free(library_path) }
        if cache_directory { free(cache_directory) }
        return 0
    }
    if pid == 0 {
        // Keep the launcher's working directory: replaying the same source must
        // resolve explicit engine imports exactly as the foreground process did.
        // Workspace-aware code uses RECURLOOP_PROJECT_ROOT instead.
        setenv("RECURLOOP_PROJECT_ROOT", self.root, 1)
        execvp(self.program, args)
        _exit(127)
    }
    unsetenv("RECURLOOP_IDE_PROJECT_BUILD")
    free(cast(u8*, args))
    if library_path { free(library_path) }
    if cache_directory { free(cache_directory) }
    self.pid = pid
    return 1
}

let IDE:Runner:server_ready = fn (self:IDE:Runner*) -> i64 {
    if !self || self.pid <= 0 || !self.socket_path { return 0 }
    let fd = IDE:connect_socket(self.socket_path)
    if fd < 0 { return 0 }
    close(fd)
    return 1
}

let IDE:Runner:wait_server = fn (self:IDE:Runner*) -> i64 {
    if !self { return 0 }
    var attempt = 0
    while attempt < 300 {
        if self.server_ready() { return 1 }
        usleep(10000)
        attempt += 1
    }
    return 0
}

let IDE:Runner:spawn_server = fn (self:IDE:Runner*) -> i64 {
    if !self.start_server() { return 0 }
    if self.wait_server() { return 1 }
    self.stop()
    return 0
}

let IDE:Runner:driver_source = fn (self:IDE:Runner*, driver:u8*) -> i64 {
    if !self || !driver || !self.object_path { return 0 }
    let source = LanguageKit:Text:new()
    if !source { return 0 }
    defer source.destroy()
    source.append("emit object ")
    if !IDE:append_source_string(source, self.object_path) { return 0 }
    source.append(" recurloop_ide_lifecycle = fn (action:i64, host:u8*) -> void {\n")
    source.append("  let app = IDE:Config:new()\n")
    source.append("  if app {\n")
    source.append("    IDE:App:configure(app)\n")
    source.append("    if action == 5 { app.apply(cast(IDE:Host*, host)) }\n")
    source.append("    else { app.dispatch(action, cast(IDE:Host*, host)) }\n")
    source.append("    app.destroy()\n")
    source.append("  }\n")
    source.append("}\n")
    return IDE:write_file(driver, source.data)
}

let IDE:Runner:load_module = fn (self:IDE:Runner*, path:u8*) -> i64 {
    if !self || !path { return 0 }
    let handle = dlopen(path, 2)
    if !handle { return 0 }
    let symbol = dlsym(handle, "recurloop_ide_lifecycle")
    if !symbol {
        dlclose(handle)
        return 0
    }
    self.module = handle
    self.lifecycle = cast(IDE:Lifecycle, symbol)
    return 1
}

let IDE:Runner:link_module = fn (self:IDE:Runner*) -> i64 {
    if !self || !self.object_path || !self.module_path { return 0 }

    // The generation is built in a short-lived worker process. Do not rely on
    // GTK having already been touched (and therefore dlopen()ed) by that worker:
    // make the module carry its own runtime dependencies. Use versioned SONAMEs
    // so a normal GTK runtime installation is sufficient; development linker
    // symlinks such as libgtk-3.so are intentionally not required.
    let args = cast(u8**, malloc(10 * sizeof(u8*)))
    if !args { return 0 }
    args[0] = "clang"
    args[1] = "-shared"
    args[2] = self.object_path
    args[3] = "-l:libgtk-3.so.0"
    args[4] = "-l:libgdk-3.so.0"
    args[5] = "-l:libgobject-2.0.so.0"
    args[6] = "-l:libglib-2.0.so.0"
    args[7] = "-o"
    args[8] = self.module_path
    args[9] = cast(u8*, 0)
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
    if !symbol {
        dlclose(self.module)
        self.module = cast(u8*, 0)
        return 0
    }
    self.lifecycle = cast(IDE:Lifecycle, symbol)
    return 1
}

let IDE:Runner:candidate = fn (self:IDE:Runner*) -> IDE:Runner* {
    if !self || self.pid <= 0 || !self.socket_path { return cast(IDE:Runner*, 0) }
    let next = alloc(IDE:Runner)
    if !next { return cast(IDE:Runner*, 0) }
    next.program = IDE:copy(self.program)
    next.root = IDE:copy(self.root)
    next.application = IDE:copy(self.application)
    next.revision = self.revision + 1
    next.generation = self.generation + 1
    next.socket_path = cast(u8*, 0)
    next.object_path = self.cache_artifact(next.revision, ".o")
    next.module_path = self.cache_artifact(next.revision, ".so")
    next.pid = -1
    next.last_status = 1
    next.last_output = cast(u8*, 0)
    next.last_error = cast(u8*, 0)
    next.module = cast(u8*, 0)
    next.lifecycle = cast(IDE:Lifecycle, 0)
    next.retired = cast(IDE:RetiredGeneration*, 0)
    next.cache_directory = IDE:copy(self.cache_directory)
    if !next.program || !next.root || !next.application || !next.object_path || !next.module_path {
        next.last_error = IDE:copy("cannot allocate project generation")
        return next
    }

    let driver = self.cache_artifact(next.revision, ".driver.rl")
    if !driver || !next.driver_source(driver) {
        if !next.last_error { next.last_error = IDE:copy("cannot create project build driver") }
        if driver { unlink(driver); free(driver) }
        return next
    }

    // Rebuild from the immutable project.rli baseline, not from the previous
    // publication.  Deleted syntax/IDE/build definitions therefore disappear
    // deterministically instead of leaking across hot reload generations.
    let build = IDE:RuntimeSession:new(self)
    if !build {
        next.last_error = IDE:copy("cannot connect build session to project runtime")
        unlink(driver); free(driver)
        return next
    }

    if build.load_view_environment(self) != 0 {
        next.last_error = IDE:copy(build.last_error)
    } else {
        next.last_output = build.cache_dependencies()
    }
    if !next.last_error && !next.last_output {
        next.last_error = IDE:copy("project dependency graph is unavailable")
    } else if !next.last_error && (build.request(":publish-prepare") != 0 || !build.last_output || !IDE:text_contains(build.last_output, "prepared project=")) {
        next.last_error = IDE:copy(build.last_error)
        if !next.last_error { next.last_error = IDE:copy("project publication could not be prepared") }
    } else if !next.last_error && build.load_transient_file(driver) != 0 {
        next.last_error = IDE:copy(build.last_error)
    } else if !next.last_error && !next.link_module() {
        let error = dlerror()
        next.last_error = IDE:copy(error)
        if !next.last_error { next.last_error = IDE:copy("native lifecycle link failed") }
    } else if !next.last_error && (build.request(":publish-commit") != 0 || !build.last_output || !IDE:text_contains(build.last_output, "published project=")) {
        next.last_error = IDE:copy(build.last_error)
        if !next.last_error { next.last_error = IDE:copy("project publication failed") }
    } else if !next.last_error {
        next.last_status = 0
    }
    build.destroy()
    unlink(driver)
    free(driver)
    return next
}

// Publish the launcher/project environment without rebuilding the native view.
// Startup uses this path after the server socket becomes ready.
let IDE:Runner:publish_environment = fn (self:IDE:Runner*) -> i64 {
    if !self || self.pid <= 0 { return 0 }
    let publish = IDE:RuntimeSession:new(self)
    if !publish {
        if self.last_error { free(self.last_error) }
        self.last_error = IDE:copy("cannot connect environment publication session")
        self.last_status = 1
        return 0
    }
    let loaded = publish.load_environment(self) == 0
    let published = loaded && publish.request(":publish") == 0 && publish.last_output && IDE:text_contains(publish.last_output, "published project=")
    if self.last_output { free(self.last_output); self.last_output = cast(u8*, 0) }
    if self.last_error { free(self.last_error); self.last_error = cast(u8*, 0) }
    self.revision += 1
    if published {
        self.generation += 1
        self.last_status = 0
        self.last_output = IDE:copy(publish.last_output)
    } else {
        self.last_status = 1
        self.last_error = IDE:copy(publish.last_error)
        if !self.last_error { self.last_error = IDE:copy("project environment publication failed") }
    }
    publish.destroy()
    return published
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
            let status = alloc(i32)
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
    if self.application { free(self.application) }
    if self.cache_directory { free(self.cache_directory) }
    if self.socket_path { free(self.socket_path) }
    if self.object_path { unlink(self.object_path); free(self.object_path) }
    if self.module_path { unlink(self.module_path); free(self.module_path) }
    if self.last_output { free(self.last_output) }
    if self.last_error { free(self.last_error) }
    free(cast(u8*, self))
}

let IDE:Runner:adopt = fn (self:IDE:Runner*, next:IDE:Runner*) -> i64 {
    if !self || !next || next.last_status != 0 || !next.lifecycle { return 0 }

    // Only native lifecycle modules are retired. The project server/socket are
    // stable for the whole IDE lifetime so all terminal sessions share one
    // publication graph and ordinary :refresh always sees the latest publish.
    if self.module || self.object_path || self.module_path {
        let retired = alloc(IDE:RetiredGeneration)
        if !retired { return 0 }
        retired.pid = -1
        retired.handle = self.module
        retired.socket_path = cast(u8*, 0)
        retired.object_path = self.object_path
        retired.module_path = self.module_path
        retired.next = self.retired
        self.retired = retired
        self.module = cast(u8*, 0)
        self.object_path = cast(u8*, 0)
        self.module_path = cast(u8*, 0)
    }

    if self.last_output { free(self.last_output) }
    if self.last_error { free(self.last_error) }
    self.object_path = next.object_path; next.object_path = cast(u8*, 0)
    self.module_path = next.module_path; next.module_path = cast(u8*, 0)
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

let IDE:Runner:allocate = fn (program:u8*, root:u8*, application:u8*) -> IDE:Runner* {
    let self = alloc(IDE:Runner)
    if !self { return cast(IDE:Runner*, 0) }
    self.program = IDE:copy(program)
    self.root = IDE:copy(root)
    self.application = IDE:copy(application)
    self.socket_path = IDE:artifact(0, ".sock")
    self.object_path = cast(u8*, 0)
    self.module_path = cast(u8*, 0)
    self.pid = -1
    self.last_status = 0
    self.generation = 0
    self.revision = 0
    self.last_output = cast(u8*, 0)
    self.last_error = cast(u8*, 0)
    self.module = cast(u8*, 0)
    self.lifecycle = cast(IDE:Lifecycle, 0)
    self.retired = cast(IDE:RetiredGeneration*, 0)
    self.cache_directory = cast(u8*, 0)
    if !self.program || !self.root || !self.application || !self.socket_path {
        self.destroy()
        return cast(IDE:Runner*, 0)
    }
    return self
}

let IDE:Runner:set_cache = fn (self:IDE:Runner*, path:u8*) -> i64 {
    if !self { return 0 }
    if self.cache_directory { free(self.cache_directory); self.cache_directory = cast(u8*, 0) }
    if path { self.cache_directory = IDE:copy(path) }
    return !path || self.cache_directory
}

let IDE:Runner:attach = fn (program:u8*, root:u8*, application:u8*, socket_path:u8*, cache:u8*, revision:u64) -> IDE:Runner* {
    if !program || !root || !application || !socket_path { return cast(IDE:Runner*, 0) }
    let self = IDE:Runner:allocate(program, root, application)
    if !self { return cast(IDE:Runner*, 0) }
    if self.socket_path { free(self.socket_path) }
    self.socket_path = IDE:copy(socket_path)
    if !self.socket_path || !self.set_cache(cache) { self.pid = -1; self.destroy(); return cast(IDE:Runner*, 0) }
    // RuntimeSession only needs a positive marker plus the inherited socket.
    // The worker must never stop/kill the real project-server PID.
    self.pid = 1
    if revision > 0 { self.revision = revision - 1 }
    return self
}

// Entry used by the short-lived helper process generated below.  Keeping the
// expensive :load-file/:publish/native-module work outside the GTK process
// keeps the UI event loop responsive while the cache warms or a reload builds.
let IDE:worker_main = fn (kind:i64, program:u8*, root:u8*, application:u8*, socket_path:u8*, cache:u8*, revision:u64, result_path:u8*) -> i64 {
    let runner = IDE:Runner:attach(program, root, application, socket_path, cache, revision)
    if !runner {
        if result_path { IDE:write_file(result_path, "cannot attach IDE build worker to project runtime") }
        _exit(1)
        return 1
    }

    // Startup already executes the launcher in the foreground process, so the
    // visible IDE does not need to be compiled into a .so again.  The first
    // worker only warms/restores the step cache and publishes the launcher into
    // the shared Project used by terminals.  This is substantially cheaper than
    // building an identical native view before the user can interact with it.
    if kind == 1 {
        let publish = IDE:RuntimeSession:new(runner)
        if !publish {
            if result_path { IDE:write_file(result_path, "cannot connect initial IDE publication session") }
            _exit(1)
            return 1
        }
        var dependencies = cast(u8*, 0)
        if publish.load_environment(runner) == 0 { dependencies = publish.cache_dependencies() }
        if dependencies && publish.request(":publish") == 0 && publish.last_output && IDE:text_contains(publish.last_output, "published project=") && result_path && IDE:write_file(result_path, dependencies) {
            free(dependencies)
            _exit(0)
            return 0
        }
        if dependencies { free(dependencies) }
        if result_path {
            if publish.last_error { IDE:write_file(result_path, publish.last_error) }
            else { IDE:write_file(result_path, "initial IDE project publication failed") }
        }
        _exit(1)
        return 1
    }

    // Reloads compile a replacement lifecycle module and publish the same
    // source generation into the persistent Project before the foreground
    // process adopts it.
    if kind == 2 {
        let candidate = runner.candidate()
        let response = LanguageKit:Text:new()
        if candidate && candidate.last_status == 0 && candidate.module_path && candidate.last_output && response &&
           response.append(candidate.module_path) && response.append("\n") && response.append(candidate.last_output) &&
           result_path && IDE:write_file(result_path, response.data) {
            response.destroy()
            if candidate.object_path { unlink(candidate.object_path) }
            // Do not destroy a successful candidate: its destroy path unlinks
            // the .so that the GTK process is about to dlopen. Process exit
            // releases the worker-only allocations and dlopen handle.
            _exit(0)
            return 0
        }
        if response { response.destroy() }
        if result_path {
            if candidate && candidate.last_error { IDE:write_file(result_path, candidate.last_error) }
            else { IDE:write_file(result_path, "IDE generation build failed") }
        }
        // A failed candidate owns no generation that the foreground process
        // needs. Clean its temporary .o/.so instead of leaking failed builds
        // into the configured cache.
        if candidate { candidate.destroy() }
        _exit(1)
        return 1
    }

    if result_path { IDE:write_file(result_path, "unknown IDE worker job") }
    _exit(1)
    return 1
}

let IDE:job_destroy = fn (job:IDE:Job*) -> void {
    if !job { return }
    if job.source_path { unlink(job.source_path); free(job.source_path) }
    if job.result_path { unlink(job.result_path); free(job.result_path) }
    free(cast(u8*, job))
}

let IDE:write_worker_source = fn (host:IDE:Host*, kind:i64, revision:u64, source_path:u8*, result_path:u8*) -> i64 {
    if !host || !host.runner || !source_path || !result_path { return 0 }
    let library_directory = IDE:resolve_library_directory(host.runner.program)
    if !library_directory { return 0 }
    defer free(library_directory)
    let ide_image = IDE:join(library_directory, "ide.rli")
    if !ide_image { return 0 }
    defer free(ide_image)

    let source = LanguageKit:Text:new()
    if !source { return 0 }
    defer source.destroy()
    source.append("engine import ")
    if !IDE:append_source_string(source, ide_image) { return 0 }
    source.append("\nvar IDE_Worker_status = IDE:worker_main(")
    IDE:append_u64(source, cast(u64, kind))
    source.append(", ")
    if !IDE:append_source_string(source, host.runner.program) { return 0 }
    source.append(", ")
    if !IDE:append_source_string(source, host.runner.root) { return 0 }
    source.append(", ")
    if !IDE:append_source_string(source, host.runner.application) { return 0 }
    source.append(", ")
    if !IDE:append_source_string(source, host.runner.socket_path) { return 0 }
    source.append(", ")
    if !IDE:append_source_string(source, host.runner.cache_directory) { return 0 }
    source.append(", ")
    IDE:append_u64(source, revision)
    source.append(", ")
    if !IDE:append_source_string(source, result_path) { return 0 }
    source.append(")\n")
    return IDE:write_file(source_path, source.data)
}

let IDE:spawn_job = fn (host:IDE:Host*, kind:i64) -> i64 {
    if !host || !host.runner || host.job || !host.runner.cache_directory { return 0 }
    let revision = host.runner.revision + 1
    let source_path = host.runner.cache_artifact(revision, ".worker.rl")
    let result_path = host.runner.cache_artifact(revision, ".worker.result")
    if !source_path || !result_path {
        if source_path { free(source_path) }
        if result_path { free(result_path) }
        return 0
    }
    unlink(result_path)
    if !IDE:write_worker_source(host, kind, revision, source_path, result_path) {
        unlink(source_path); free(source_path); free(result_path)
        return 0
    }

    let args = cast(u8**, malloc(4 * sizeof(u8*)))
    if !args { unlink(source_path); free(source_path); free(result_path); return 0 }
    args[0] = host.runner.program
    args[1] = "--file"
    args[2] = source_path
    args[3] = cast(u8*, 0)
    let pid = fork()
    if pid < 0 {
        free(cast(u8*, args)); unlink(source_path); free(source_path); free(result_path)
        return 0
    }
    if pid == 0 {
        setenv("RECURLOOP_IDE_PROJECT_BUILD", "1", 1)
        execvp(host.runner.program, args)
        _exit(127)
    }
    free(cast(u8*, args))

    let job = alloc(IDE:Job)
    if !job {
        kill(pid, 15)
        let raw = alloc(i32)
        if raw { waitpid(pid, raw, 0); free(cast(u8*, raw)) }
        unlink(source_path); free(source_path); free(result_path)
        return 0
    }
    job.pid = pid
    job.kind = cast(i32, kind)
    job.revision = revision
    job.epoch = host.source_epoch
    job.source_path = source_path
    job.result_path = result_path
    host.job = job
    let watch = host.job_watch
    if !watch || g_child_watch_add(pid, watch, cast(u8*, host)) == 0 {
        host.job = cast(IDE:Job*, 0)
        kill(pid, 15)
        let raw = alloc(i32)
        if raw { waitpid(pid, raw, 0); free(cast(u8*, raw)) }
        IDE:job_destroy(job)
        return 0
    }
    return 1
}

let IDE:Runner:new_async = fn (program:u8*, root:u8*, application:u8*) -> IDE:Runner* {
    let self = IDE:Runner:allocate(program, root, application)
    if !self { return cast(IDE:Runner*, 0) }
    if !self.start_server() { self.destroy(); return cast(IDE:Runner*, 0) }
    return self
}

let IDE:Runner:new = fn (program:u8*, root:u8*, application:u8*) -> IDE:Runner* {
    let self = IDE:Runner:allocate(program, root, application)
    if !self { return cast(IDE:Runner*, 0) }
    if !self.spawn_server() { self.destroy(); return cast(IDE:Runner*, 0) }
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
    let terminal = alloc(IDE:Terminal)
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
    let existing = self.find(wd)
    if existing {
        if !existing.path || strcmp(existing.path, path) != 0 {
            let replacement = IDE:copy(path)
            if replacement {
                if existing.path { free(existing.path) }
                existing.path = replacement
            }
        }
        return
    }
    let item = alloc(IDE:WatchDir)
    if !item { return }
    item.wd = wd
    item.path = IDE:copy(path)
    item.next = self.directories
    if !item.path { free(cast(u8*, item)); return }
    self.directories = item
}

let IDE:Watcher:forget = fn (self:IDE:Watcher*, wd:i32) -> void {
    if !self || wd < 0 { return }
    var previous = cast(IDE:WatchDir*, 0)
    var item = self.directories
    while item {
        if item.wd == wd {
            if previous { previous.next = item.next }
            else { self.directories = item.next }
            if item.path { free(item.path) }
            free(cast(u8*, item))
            return
        }
        previous = item
        item = item.next
    }
}

// inotify watches the configured source tree. Heavy/generated directories are
// skipped and newly created directories are attached incrementally.
let IDE:Watcher:add_directory = fn (self:IDE:Watcher*, path:u8*) -> void {
    if !self || !path || !IDE:is_directory(path) { return }
    // MODIFY invalidates an in-flight build immediately. CLOSE_WRITE/rename/delete
    // are the stable boundaries that are allowed to schedule the next generation.
    // No timeout or debounce participates in correctness.
    let wd = inotify_add_watch(self.fd, path, cast(u32, 2 + 8 + 64 + 128 + 256 + 512 + 1024 + 2048))
    if wd >= 0 { self.remember(wd, path) }
}

let IDE:Watcher:add_tree = fn (self:IDE:Watcher*, path:u8*) -> void {
    if !self || !path || !IDE:is_directory(path) { return }
    self.add_directory(path)
    let directory = opendir(path)
    if !directory { return }
    var entry = readdir(directory)
    while entry {
        let name = &entry[19]
        if !IDE:skip_directory(name) {
            let child = IDE:join(path, name)
            if child {
                let kind = entry[18]
                if kind == 4 || (kind == 0 && IDE:is_directory(child)) { self.add_tree(child) }
                free(child)
            }
        }
        entry = readdir(directory)
    }
    closedir(directory)
}

let IDE:Watcher:new = fn (root:u8*) -> IDE:Watcher* {
    let fd = inotify_init1(526336)
    if fd < 0 { return cast(IDE:Watcher*, 0) }
    let self = alloc(IDE:Watcher)
    if !self { close(fd); return cast(IDE:Watcher*, 0) }
    self.fd = fd
    self.root = IDE:copy(root)
    self.directories = cast(IDE:WatchDir*, 0)
    if !self.root { close(fd); free(cast(u8*, self)); return cast(IDE:Watcher*, 0) }
    self.add_directory(root)
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

let IDE:clear_candidate_config = fn (host:IDE:Host*) -> void {
    if !host { return }
    if host.candidate_title { free(host.candidate_title); host.candidate_title = cast(u8*, 0) }
    host.candidate_window_width = host.window_width
    host.candidate_window_height = host.window_height
    host.candidate_reload_mode = host.reload_mode
    host.candidate_config_ready = 0
}

let IDE:prepare_candidate_config = fn (host:IDE:Host*) -> i64 {
    if !host { return 0 }
    IDE:clear_candidate_config(host)
    host.candidate_title = IDE:copy(host.window_title)
    if host.window_title && !host.candidate_title { return 0 }
    host.candidate_window_width = host.window_width
    host.candidate_window_height = host.window_height
    host.candidate_reload_mode = host.reload_mode
    return 1
}

// Build a generation into the hidden side of Host.surface. `configure` is 0
// for the launcher view (its Config already initialized Host) and 1 for a
// compiled generation whose action 5 supplies a fresh project Config.
let IDE:stage_view = fn (host:IDE:Host*, lifecycle:IDE:Lifecycle, configure:i64) -> i64 {
    if !host || !lifecycle || !host.surface || host.candidate_content || host.candidate_user_data { return 0 }
    if !IDE:prepare_candidate_config(host) { return 0 }

    host.view_phase = 1
    if configure != 0 {
        lifecycle(5, cast(u8*, host))
        if host.candidate_config_ready == 0 {
            host.view_phase = 0
            IDE:clear_candidate_config(host)
            return 0
        }
    } else {
        host.candidate_config_ready = 1
    }

    lifecycle(1, cast(u8*, host))
    host.view_phase = 0
    if !host.candidate_content || !host.candidate_user_data {
        IDE:clear_candidate_config(host)
        return 0
    }
    // Show the candidate subtree while GtkStack keeps the current child
    // selected. This realizes every widget without exposing a partial layout.
    Gui:show(host.candidate_content)
    return 1
}

let IDE:discard_staged_view = fn (host:IDE:Host*, lifecycle:IDE:Lifecycle) -> void {
    if !host { return }
    let content = host.candidate_content
    let data = host.candidate_user_data
    host.view_phase = 1
    if content { Gui:destroy(content) }
    if data && lifecycle { lifecycle(2, cast(u8*, host)) }
    host.view_phase = 0
    host.candidate_content = cast(u8*, 0)
    host.candidate_user_data = cast(u8*, 0)
    IDE:clear_candidate_config(host)
}

// One main-loop transaction makes the fully realized candidate visible and
// only then tears down the previous generation. There is never a frame where
// Host.surface contains no selected IDE view.
let IDE:commit_staged_view = fn (host:IDE:Host*, lifecycle:IDE:Lifecycle, previous:IDE:Lifecycle) -> i64 {
    if !host || !lifecycle || !host.surface || !host.candidate_content || !host.candidate_user_data { return 0 }

    let old_content = host.content
    let old_data = host.user_data
    let next_content = host.candidate_content
    let next_data = host.candidate_user_data

    Gui:stack_select(host.surface, next_content)
    host.content = next_content
    host.user_data = next_data
    host.candidate_content = cast(u8*, 0)
    host.candidate_user_data = cast(u8*, 0)
    host.shell_lifecycle = cast(IDE:ShellLifecycle, lifecycle)

    if host.candidate_title {
        if host.window_title { free(host.window_title) }
        host.window_title = host.candidate_title
        host.candidate_title = cast(u8*, 0)
        if host.window { Gui:window_title(host.window, host.window_title) }
    }
    if host.candidate_window_width != host.window_width || host.candidate_window_height != host.window_height {
        host.window_width = host.candidate_window_width
        host.window_height = host.candidate_window_height
        if host.window { Gui:window_size(host.window, cast(i32, host.window_width), cast(i32, host.window_height)) }
    }
    host.reload_mode = host.candidate_reload_mode
    host.candidate_config_ready = 0

    if old_content || old_data {
        host.retiring_content = old_content
        host.retiring_user_data = old_data
        host.view_phase = 2
        if old_content { Gui:destroy(old_content) }
        if old_data && previous { previous(2, cast(u8*, host)) }
        host.view_phase = 0
        host.retiring_content = cast(u8*, 0)
        host.retiring_user_data = cast(u8*, 0)
    }

    return 1
}

let IDE:is_reloadable_path = fn (host:IDE:Host*, path:u8*) -> i64 {
    if !host || !path || !IDE:has_suffix(path, ".rl") { return 0 }
    if !host.watch_sources { return host.config_source && strcmp(host.config_source, path) == 0 }
    let bytes = cast(i64, strlen(path))
    var offset = 0
    while host.watch_sources[offset] != 0 {
        var line = 0
        while host.watch_sources[offset + line] != 0 && host.watch_sources[offset + line] != 10 { line += 1 }
        var equal = line == bytes
        var index = 0
        while equal && index < bytes {
            if host.watch_sources[offset + index] != path[index] { equal = 0 }
            index += 1
        }
        if equal { return 1 }
        offset += line
        if host.watch_sources[offset] == 10 { offset += 1 }
    }
    return 0
}

let IDE:set_watch_sources = fn (host:IDE:Host*, sources:u8*) -> i64 {
    if !host || !sources { return 0 }
    let next = IDE:copy(sources)
    if !next { return 0 }
    if host.watch_sources { free(host.watch_sources) }
    host.watch_sources = next
    return 1
}

let IDE:notify_reload_failure = fn (host:IDE:Host*) -> void {
    if !host { return }
    if host.runner && host.runner.lifecycle {
        let lifecycle = host.runner.lifecycle
        lifecycle(3, cast(u8*, host))
    } else if host.shell_lifecycle {
        let lifecycle = host.shell_lifecycle
        lifecycle(3, cast(u8*, host))
    }
}

let IDE:notify_runtime_ready = fn (host:IDE:Host*) -> void {
    if !host { return }
    if host.runner && host.runner.lifecycle {
        let lifecycle = host.runner.lifecycle
        lifecycle(4, cast(u8*, host))
    } else if host.shell_lifecycle {
        let lifecycle = host.shell_lifecycle
        lifecycle(4, cast(u8*, host))
    }
}

// Return values: 0 = activation failure, 1 = committed, 2 = source epoch
// changed while the candidate was being built/staged and the candidate was
// discarded without disturbing the visible generation.
let IDE:mark_source_change = fn (host:IDE:Host*) -> void {
    if !host { return }
    host.source_epoch += 1
    host.reload_pending = 1
}

// Drain every currently queued inotify event into one exact source epoch.
// MODIFY invalidates an in-flight candidate immediately, while only stable
// filesystem boundaries (close-write, rename, delete) schedule a replacement.
// Correctness therefore never depends on guessing how long an editor needs to save.
let IDE:drain_watcher = fn (host:IDE:Host*) -> i64 {
    if !host || !host.watcher { return 0 }
    let watcher = host.watcher
    let buffer = malloc(16384)
    if !buffer { return 0 }
    defer free(buffer)
    var changes = 0

    while 1 {
        let bytes = read(watcher.fd, buffer, 16384)
        if bytes <= 0 { break }
        var offset = 0
        while offset + 16 <= bytes {
            let wd = cast(i32*, &buffer[offset])[0]
            let mask = cast(u32*, &buffer[offset + 4])[0]
            let name_bytes = cast(u32*, &buffer[offset + 12])[0]
            // IN_Q_OVERFLOW means at least one source event was lost. Treat the
            // whole watched tree as changed: invalidate every in-flight epoch
            // and schedule one fresh rebuild from the current filesystem state.
            let overflow = (mask / cast(u32, 16384)) % 2 != 0
            if overflow { IDE:mark_source_change(host); changes += 1 }
            let directory = watcher.find(wd)
            if directory {
                let ignored = (mask / cast(u32, 32768)) % 2 != 0
                let deleted_self = (mask / cast(u32, 1024)) % 2 != 0
                let moved_self = (mask / cast(u32, 2048)) % 2 != 0
                if !ignored {
                    var changed = IDE:copy(directory.path)
                    if name_bytes > 0 && buffer[offset + 16] != 0 {
                        if changed { free(changed) }
                        changed = IDE:join(directory.path, &buffer[offset + 16])
                    }
                    if changed {
                        let directory_event = (mask / cast(u32, 1073741824)) % 2 != 0
                        let created = (mask / cast(u32, 256)) % 2 != 0 || (mask / cast(u32, 128)) % 2 != 0
                        if directory_event && created && name_bytes > 0 && !IDE:skip_directory(&buffer[offset + 16]) {
                            watcher.add_tree(changed)
                        }

                        let modified = (mask / cast(u32, 2)) % 2 != 0
                        let close_write = (mask / cast(u32, 8)) % 2 != 0
                        let moved_from = (mask / cast(u32, 64)) % 2 != 0
                        let moved_to = (mask / cast(u32, 128)) % 2 != 0
                        let deleted = (mask / cast(u32, 512)) % 2 != 0
                        let stable = close_write || moved_from || moved_to || deleted
                        if !directory_event && IDE:is_reloadable_path(host, changed) {
                            // A write that is still in progress may never become a visible
                            // generation: bump the epoch without scheduling a build. The
                            // matching stable boundary below is what makes the source ready.
                            if modified { host.source_epoch += 1 }
                            if stable {
                                IDE:mark_source_change(host)
                                changes += 1
                            }
                        }
                        free(changed)
                    }
                }
                if ignored || deleted_self {
                    if deleted_self && !ignored { inotify_rm_watch(watcher.fd, wd) }
                    watcher.forget(wd)
                } else if moved_self && !IDE:is_directory(directory.path) {
                    inotify_rm_watch(watcher.fd, wd)
                    watcher.forget(wd)
                }
            }
            offset += 16 + name_bytes
        }
    }

    return changes
}

let IDE:finish_reload = fn (host:IDE:Host*, module_path:u8*, revision:u64, epoch:u64) -> i64 {
    if !host || !host.runner || !module_path { return 0 }
    let handle = dlopen(module_path, 2)
    if !handle {
        let error = dlerror()
        if host.runner.last_error { free(host.runner.last_error) }
        host.runner.last_error = IDE:copy(error)
        if !host.runner.last_error { host.runner.last_error = IDE:copy("cannot load IDE generation module") }
        unlink(module_path)
        return 0
    }
    let symbol = dlsym(handle, "recurloop_ide_lifecycle")
    if !symbol {
        let error = dlerror()
        if host.runner.last_error { free(host.runner.last_error) }
        host.runner.last_error = IDE:copy(error)
        if !host.runner.last_error { host.runner.last_error = IDE:copy("IDE generation has no lifecycle symbol") }
        dlclose(handle)
        unlink(module_path)
        return 0
    }
    let next_lifecycle = cast(IDE:Lifecycle, symbol)
    let owned_module_path = IDE:copy(module_path)
    if !owned_module_path {
        if host.runner.last_error { free(host.runner.last_error) }
        host.runner.last_error = IDE:copy("cannot retain IDE generation module path")
        dlclose(handle)
        unlink(module_path)
        return 0
    }

    var previous = cast(IDE:Lifecycle, 0)
    if host.runner.lifecycle { previous = host.runner.lifecycle }
    else if host.shell_lifecycle { previous = cast(IDE:Lifecycle, host.shell_lifecycle) }

    // Candidate construction happens while the previous GtkStack child remains
    // selected. A source-defined lifecycle must explicitly attach one complete
    // root through IDE:view_attach; otherwise this generation is rejected.
    if !IDE:stage_view(host, next_lifecycle, 1) {
        if host.runner.last_error { free(host.runner.last_error) }
        host.runner.last_error = IDE:copy("IDE generation did not produce a complete staged view")
        dlclose(handle)
        unlink(module_path)
        free(owned_module_path)
        return 0
    }

    // Drain the kernel queue immediately before the commit boundary. If any
    // stable write/rename/delete arrived since this worker started, its epoch is
    // obsolete even if compilation/linking succeeded.
    IDE:drain_watcher(host)
    if epoch != host.source_epoch {
        IDE:discard_staged_view(host, next_lifecycle)
        dlclose(handle)
        unlink(module_path)
        free(owned_module_path)
        return 2
    }

    if !IDE:commit_staged_view(host, next_lifecycle, previous) {
        IDE:discard_staged_view(host, next_lifecycle)
        dlclose(handle)
        unlink(module_path)
        free(owned_module_path)
        if host.runner.last_error { free(host.runner.last_error) }
        host.runner.last_error = IDE:copy("IDE staged view could not be committed")
        return 0
    }

    // The old callbacks/widgets are gone before their native generation is
    // retired. Keep old modules until Runner teardown as an additional guard
    // against toolkit-delayed callback destruction.
    if host.runner.module || host.runner.object_path || host.runner.module_path {
        let retired = alloc(IDE:RetiredGeneration)
        if retired {
            retired.pid = -1
            retired.handle = host.runner.module
            retired.socket_path = cast(u8*, 0)
            retired.object_path = host.runner.object_path
            retired.module_path = host.runner.module_path
            retired.next = host.runner.retired
            host.runner.retired = retired
        } else {
            if host.runner.module { dlclose(host.runner.module) }
            if host.runner.object_path { unlink(host.runner.object_path); free(host.runner.object_path) }
            if host.runner.module_path { unlink(host.runner.module_path); free(host.runner.module_path) }
        }
    }

    host.runner.module = handle
    host.runner.lifecycle = next_lifecycle
    host.runner.object_path = cast(u8*, 0)
    host.runner.module_path = owned_module_path
    host.runner.revision = revision
    host.runner.generation += 1
    host.runner.last_status = 0
    if host.runner.last_output { free(host.runner.last_output); host.runner.last_output = cast(u8*, 0) }
    if host.runner.last_error { free(host.runner.last_error); host.runner.last_error = cast(u8*, 0) }

    return 1
}

let IDE:start_reload = fn (host:IDE:Host*) -> i64 {
    if !host || !host.runner || host.job { return 0 }
    if !IDE:spawn_job(host, 2) {
        host.runner.last_status = 1
        if host.runner.last_error { free(host.runner.last_error) }
        host.runner.last_error = IDE:copy("cannot start IDE reload worker")
        IDE:notify_reload_failure(host)
        return 0
    }
    host.reload_pending = 0
    IDE:notify_runtime_ready(host)
    return 1
}

let IDE:continue_pending_reload = fn (host:IDE:Host*) -> void {
    if !host || host.job || host.startup_phase != 2 || host.reload_mode != IDE:Reload:Hot() || host.reload_pending == 0 { return }
    IDE:start_reload(host)
}

// GLib delivers child completion exactly once; no waitpid polling interval is
// involved. The callback keeps Host.job installed until all queued inotify
// events have been drained, closing the race between worker completion and a
// save that reached the kernel just before it.
let IDE:job_done = fn (pid:i32, status:i32, data:u8*) -> void {
    let host = cast(IDE:Host*, data)
    if !host || !host.job || host.job.pid != pid { return }
    let job = host.job
    let success = status == 0
    let kind = job.kind
    let revision = job.revision
    let epoch = job.epoch
    let result = IDE:read_file(job.result_path)

    IDE:drain_watcher(host)

    if kind == 1 {
        host.runner.revision = revision
        if success && result && epoch == host.source_epoch {
            host.runner.generation += 1
            host.runner.last_status = 0
            if host.runner.last_output { free(host.runner.last_output) }
            if host.runner.last_error { free(host.runner.last_error); host.runner.last_error = cast(u8*, 0) }
            host.runner.last_output = IDE:copy(result)
            IDE:set_watch_sources(host, result)
        } else if !success {
            host.runner.last_status = 1
            if host.runner.last_error { free(host.runner.last_error) }
            if result { host.runner.last_error = IDE:copy(result) }
            else { host.runner.last_error = IDE:copy("initial IDE project publication failed") }
            IDE:notify_reload_failure(host)
        }
        host.startup_phase = 2
        host.job = cast(IDE:Job*, 0)
        IDE:job_destroy(job)
        if result { free(result) }
        IDE:notify_runtime_ready(host)
        IDE:continue_pending_reload(host)
        return
    }

    if kind == 2 {
        var outcome = 0
        var dependencies = cast(u8*, 0)
        if success && result {
            var line = 0
            while result[line] != 0 && result[line] != 10 { line += 1 }
            if result[line] == 10 { result[line] = 0; dependencies = &result[line + 1] }
            if epoch == host.source_epoch && dependencies { outcome = IDE:finish_reload(host, result, revision, epoch) }
            else { unlink(result); outcome = 2 }
        }

        host.runner.revision = revision
        if outcome == 0 {
            host.runner.last_status = 1
            if !success {
                if host.runner.last_error { free(host.runner.last_error) }
                if result { host.runner.last_error = IDE:copy(result) }
                else { host.runner.last_error = IDE:copy("IDE reload build failed") }
            } else if !host.runner.last_error {
                host.runner.last_error = IDE:copy("IDE reload module could not be activated")
            }
            IDE:notify_reload_failure(host)
        }

        host.job = cast(IDE:Job*, 0)
        IDE:job_destroy(job)
        if result { free(result) }
        // The replacement view was mounted while Host.job still identified the
        // in-flight worker, so its first status render said "reloading". Notify
        // it after clearing the job to render the committed ready state. This
        // also remounts persistent terminal models into generic project views.
        if outcome == 1 {
            IDE:set_watch_sources(host, dependencies)
            IDE:notify_runtime_ready(host)
        }
        IDE:continue_pending_reload(host)
        return
    }

    host.job = cast(IDE:Job*, 0)
    IDE:job_destroy(job)
    if result { free(result) }
    IDE:continue_pending_reload(host)
}

let IDE:reload = fn (host:IDE:Host*, path:u8*) -> void {
    if !host || !host.runner || !path { return }
    if host.job { host.reload_pending = 1; return }
    IDE:start_reload(host)
}

let IDE:manual_reload = fn (host:IDE:Host*) -> void {
    if !host || host.reload_mode != IDE:Reload:Manual() { return }
    var source = host.config_source
    if !source { source = host.root }
    host.reload_pending = 0
    IDE:reload(host, source)
}

let IDE:watch_ready = fn (fd:i32, condition:i32, data:u8*) -> i32 {
    let host = cast(IDE:Host*, data)
    if !host || !host.watcher || host.watcher.fd != fd { return 0 }
    let changes = IDE:drain_watcher(host)
    if changes > 0 {
        if host.reload_mode == IDE:Reload:Hot() { IDE:continue_pending_reload(host) }
        else if host.reload_mode == IDE:Reload:Manual() { IDE:notify_runtime_ready(host) }
    }
    return 1
}

let IDE:on_destroy = fn (widget:u8*, data:u8*) -> void { Gui:quit() }

let IDE:free_host = fn (host:IDE:Host*) -> void {
    if !host { return }
    if host.job {
        kill(host.job.pid, 15)
        let raw = alloc(i32)
        if raw { waitpid(host.job.pid, raw, 0); free(cast(u8*, raw)) }
        let job = host.job
        host.job = cast(IDE:Job*, 0)
        IDE:job_destroy(job)
    }
    IDE:free_terminals(host)
    if host.watcher { host.watcher.destroy() }
    if host.candidate_title { free(host.candidate_title) }
    if host.selected { free(host.selected) }
    if host.runner { host.runner.destroy() }
    if host.entry { free(host.entry) }
    if host.initial_module { free(host.initial_module) }
    if host.watch_root { free(host.watch_root) }
    if host.config_source { free(host.config_source) }
    if host.watch_sources { free(host.watch_sources) }
    if host.window_title { free(host.window_title) }
    if host.root { free(host.root) }
    free(cast(u8*, host))
}


let IDE:activate_watcher = fn (host:IDE:Host*) -> void {
    if !host || host.watcher || host.reload_mode == IDE:Reload:Off() { return }
    var root = host.watch_root
    if !root { root = host.root }
    if !root { return }
    host.watcher = IDE:Watcher:new(root)
    if !host.watcher { return }
    host.watcher.add_tree(root)
    if host.config_source {
        let source_directory = IDE:parent_path(host.config_source)
        if source_directory { host.watcher.add_tree(source_directory); free(source_directory) }
    }
    // G_IO_IN | G_IO_ERR | G_IO_HUP | G_IO_NVAL. inotify is nonblocking, so
    // one callback drains the complete kernel queue without a polling timer.
    if g_unix_fd_add(host.watcher.fd, 57, IDE:watch_ready, cast(u8*, host)) == 0 {
        host.watcher.destroy()
        host.watcher = cast(IDE:Watcher*, 0)
    }
}

// Source-defined startup.  The current .rl process paints the default/overridden
// view immediately; the persistent Project server starts on the GTK timer and
// is then populated from the same configuration source through the step cache.
let IDE:startup_tick = fn (data:u8*) -> i32 {
    let host = cast(IDE:Host*, data)
    if !host || !host.runner { return 0 }

    if host.startup_phase == 2 && !host.job {
        IDE:activate_watcher(host)
        return 0
    }
    if host.job { return 1 }

    if host.runner.pid <= 0 {
        if !host.runner.start_server() {
            host.runner.last_status = 1
            if host.runner.last_error { free(host.runner.last_error) }
            host.runner.last_error = IDE:copy("project runtime failed to start")
            IDE:notify_reload_failure(host)
            return 0
        }
        host.pending_since = IDE:now_ms()
        return 1
    }

    if host.runner.server_ready() {
        host.pending_since = 0
        // Start watching as soon as the shared Project is reachable. Saves that
        // happen while the first publication worker is warming the cache are
        // then queued instead of being silently missed.
        IDE:activate_watcher(host)
        // :baseline/:cache/:load-file/:publish may compile many steps. Keep
        // that work in a short-lived helper using the same Project socket/cache
        // while GTK continues dispatching the already-mounted IDE.
        if !IDE:spawn_job(host, 1) {
            host.runner.last_status = 1
            if host.runner.last_error { free(host.runner.last_error) }
            host.runner.last_error = IDE:copy("cannot start initial IDE publication worker")
            IDE:notify_runtime_ready(host)
            IDE:notify_reload_failure(host)
            return 0
        }
        return 1
    }
    if host.pending_since == 0 { host.pending_since = IDE:now_ms() }
    if IDE:now_ms() - host.pending_since < 5000 { return 1 }
    host.runner.last_status = 1
    if host.runner.last_error { free(host.runner.last_error) }
    host.runner.last_error = IDE:copy("project runtime failed to start")
    IDE:notify_reload_failure(host)
    return 0
}

let IDE:Config:new = fn () -> IDE:Config* {
    let self = alloc(IDE:Config)
    if !self { return cast(IDE:Config*, 0) }
    self.workspace_path = cast(u8*, 0)
    self.source_path = cast(u8*, 0)
    self.cache_path = cast(u8*, 0)
    self.watch_path = cast(u8*, 0)
    self.reload_mode = IDE:Reload:Hot()
    self.title_text = IDE:copy("RecurLoop IDE")
    self.window_width = 1360
    self.window_height = 860
    self.view_lifecycle = cast(IDE:Lifecycle, 0)
    if !self.title_text {
        free(cast(u8*, self))
        return cast(IDE:Config*, 0)
    }
    return self
}

let IDE:Config:title = fn (self:IDE:Config*, title:u8*) -> IDE:Config* {
    if !self { return self }
    let next = IDE:copy(title)
    if !next { return self }
    if self.title_text { free(self.title_text) }
    self.title_text = next
    return self
}

let IDE:Config:size = fn (self:IDE:Config*, width:i64, height:i64) -> IDE:Config* {
    if !self { return self }
    if width <= 0 || height <= 0 || width > 2147483647 || height > 2147483647 { return self }
    self.window_width = width
    self.window_height = height
    return self
}

let IDE:Config:workspace = fn (self:IDE:Config*, path:u8*) -> IDE:Config* {
    if !self { return self }
    if self.workspace_path { free(self.workspace_path); self.workspace_path = cast(u8*, 0) }
    if path { self.workspace_path = IDE:copy(path) }
    return self
}

let IDE:Config:source = fn (self:IDE:Config*, path:u8*) -> IDE:Config* {
    if !self { return self }
    if self.source_path { free(self.source_path); self.source_path = cast(u8*, 0) }
    if path { self.source_path = IDE:copy(path) }
    return self
}

let IDE:Config:cache = fn (self:IDE:Config*, path:u8*) -> IDE:Config* {
    if !self { return self }
    if self.cache_path { free(self.cache_path); self.cache_path = cast(u8*, 0) }
    if path { self.cache_path = IDE:copy(path) }
    return self
}

let IDE:Config:watch = fn (self:IDE:Config*, path:u8*) -> IDE:Config* {
    if !self { return self }
    if self.watch_path { free(self.watch_path); self.watch_path = cast(u8*, 0) }
    if path { self.watch_path = IDE:copy(path) }
    return self
}

let IDE:Config:reload = fn (self:IDE:Config*, mode:u8*) -> IDE:Config* {
    if !self || !mode { return self }
    if strcmp(mode, "hot") == 0 || strcmp(mode, "hot-reload") == 0 { self.reload_mode = IDE:Reload:Hot() }
    else if strcmp(mode, "manual") == 0 || strcmp(mode, "manually") == 0 { self.reload_mode = IDE:Reload:Manual() }
    else if strcmp(mode, "off") == 0 || strcmp(mode, "none") == 0 || strcmp(mode, "no-reload") == 0 { self.reload_mode = IDE:Reload:Off() }
    return self
}

let IDE:Config:view = fn (self:IDE:Config*, lifecycle:IDE:Lifecycle) -> IDE:Config* {
    if !self { return self }
    self.view_lifecycle = lifecycle
    return self
}

let IDE:Config:dispatch = fn (self:IDE:Config*, action:i64, host:IDE:Host*) -> void {
    if !self || !self.view_lifecycle || !host { return }
    let lifecycle = self.view_lifecycle
    lifecycle(action, cast(u8*, host))
}

let IDE:Config:destroy = fn (self:IDE:Config*) -> void {
    if !self { return }
    if self.workspace_path { free(self.workspace_path) }
    if self.source_path { free(self.source_path) }
    if self.cache_path { free(self.cache_path) }
    if self.watch_path { free(self.watch_path) }
    if self.title_text { free(self.title_text) }
    free(cast(u8*, self))
}

let IDE:resolve_workspace_path = fn (root:u8*, path:u8*) -> u8* {
    if !path || path[0] == 0 { return cast(u8*, 0) }
    if path[0] == 47 { return IDE:copy(path) }
    return IDE:join(root, path)
}

let IDE:Config:apply = fn (self:IDE:Config*, host:IDE:Host*) -> i64 {
    if !self || !host || !self.view_lifecycle { return 0 }

    // A compiled generation is configured while view_phase==1. Keep all of its
    // window/reload policy in candidate slots; nothing visible or persistent is
    // mutated until the staged view itself is committed.
    if host.view_phase == 1 {
        let title = IDE:copy(self.title_text)
        if self.title_text && !title { return 0 }
        if host.candidate_title { free(host.candidate_title) }
        host.candidate_title = title
        host.candidate_window_width = self.window_width
        host.candidate_window_height = self.window_height
        host.candidate_reload_mode = self.reload_mode
        host.candidate_config_ready = 1
        return 1
    }

    // Non-staged application of configuration is kept for the launcher and for
    // explicit runtime use. Native generation replacement normally goes through
    // the transactional candidate path above.
    host.shell_lifecycle = cast(IDE:ShellLifecycle, self.view_lifecycle)
    if self.title_text && (!host.window_title || strcmp(self.title_text, host.window_title) != 0) {
        let title = IDE:copy(self.title_text)
        if !title { return 0 }
        if host.window_title { free(host.window_title) }
        host.window_title = title
        if host.window { Gui:window_title(host.window, host.window_title) }
    }
    if self.window_width != host.window_width || self.window_height != host.window_height {
        host.window_width = self.window_width
        host.window_height = self.window_height
        if host.window { Gui:window_size(host.window, cast(i32, host.window_width), cast(i32, host.window_height)) }
    }
    if host.reload_mode != self.reload_mode {
        host.reload_mode = self.reload_mode
        host.reload_pending = 0
    }
    if host.reload_mode != IDE:Reload:Off() && !host.watcher { IDE:activate_watcher(host) }
    return 1
}

let IDE:Config:open = fn (self:IDE:Config*) -> i64 {
    if !self { return 1 }
    // The same launcher is replayed inside the project build server.  Its
    // declarations/configuration must compile there, but it must never open a
    // second GTK loop.
    if getenv("RECURLOOP_IDE_PROJECT_BUILD") { return 0 }
    if !self.workspace_path || !self.source_path || !self.view_lifecycle { return 1 }

    let root = realpath(self.workspace_path, cast(u8*, 0))
    if !root { return 1 }
    defer free(root)
    let source = realpath(self.source_path, cast(u8*, 0))
    if !source { return 1 }
    defer free(source)

    var cache = cast(u8*, 0)
    if self.cache_path { cache = IDE:resolve_workspace_path(root, self.cache_path) }
    else { cache = IDE:join(root, ".cache/recurloop") }
    if !cache { return 1 }
    defer free(cache)
    if !IDE:ensure_directory_tree(cache) { return 1 }

    var watch_candidate = cast(u8*, 0)
    if self.watch_path { watch_candidate = IDE:resolve_workspace_path(root, self.watch_path) }
    else { watch_candidate = IDE:copy(root) }
    if !watch_candidate { return 1 }
    let watch = realpath(watch_candidate, cast(u8*, 0))
    free(watch_candidate)
    if !watch || !IDE:is_directory(watch) {
        if watch { free(watch) }
        return 1
    }
    defer free(watch)

    let program = IDE:resolve_host()
    if !program { return 1 }
    defer free(program)
    if !Gui:initialize() { return 1 }

    let host = alloc(IDE:Host)
    if !host { return 1 }
    host.root = IDE:copy(root)
    host.entry = IDE:copy(source)
    host.runner = cast(IDE:Runner*, 0)
    host.window = cast(u8*, 0)
    host.surface = cast(u8*, 0)
    host.content = cast(u8*, 0)
    host.user_data = cast(u8*, 0)
    host.candidate_content = cast(u8*, 0)
    host.candidate_user_data = cast(u8*, 0)
    host.retiring_content = cast(u8*, 0)
    host.retiring_user_data = cast(u8*, 0)
    host.candidate_title = cast(u8*, 0)
    host.terminals = cast(IDE:Terminal*, 0)
    host.watcher = cast(IDE:Watcher*, 0)
    host.selected = cast(u8*, 0)
    host.pending_since = 0
    host.terminal_number = 0
    host.shell_lifecycle = cast(IDE:ShellLifecycle, self.view_lifecycle)
    host.initial_module = cast(u8*, 0)
    host.startup_phase = 0
    host.watch_root = IDE:copy(watch)
    host.config_source = IDE:copy(source)
    host.watch_sources = cast(u8*, 0)
    host.reload_mode = self.reload_mode
    host.candidate_reload_mode = self.reload_mode
    host.reload_pending = 0
    host.view_phase = 0
    host.candidate_config_ready = 0
    host.source_epoch = 0
    host.job = cast(IDE:Job*, 0)
    host.job_watch = IDE:job_done
    host.window_title = IDE:copy(self.title_text)
    host.window_width = self.window_width
    host.window_height = self.window_height
    host.candidate_window_width = self.window_width
    host.candidate_window_height = self.window_height
    if !host.root || !host.entry || !host.watch_root || !host.config_source || !host.window_title { IDE:free_host(host); return 1 }

    host.window = Gui:window(host.window_title, cast(i32, host.window_width), cast(i32, host.window_height))
    if !host.window { IDE:free_host(host); return 1 }
    host.surface = Gui:stack()
    if !host.surface { IDE:free_host(host); return 1 }
    Gui:add(host.window, host.surface)
    Gui:on_destroy(host.window, IDE:on_destroy, cast(u8*, host))

    host.runner = IDE:Runner:allocate(program, host.root, host.config_source)
    if !host.runner || !host.runner.set_cache(cache) { IDE:free_host(host); return 1 }

    // Paint immediately, but use the same staging/commit path as every later
    // generation. Project code never owns the native window child directly.
    let initial_lifecycle = cast(IDE:Lifecycle, host.shell_lifecycle)
    if !IDE:stage_view(host, initial_lifecycle, 0) || !IDE:commit_staged_view(host, initial_lifecycle, cast(IDE:Lifecycle, 0)) {
        IDE:discard_staged_view(host, initial_lifecycle)
        IDE:free_host(host)
        return 1
    }
    Gui:show(host.window)
    host.pending_since = IDE:now_ms()
    Gui:timer(20, IDE:startup_tick, cast(u8*, host))
    Gui:run()

    if host.runner && host.runner.lifecycle {
        let lifecycle = host.runner.lifecycle
        lifecycle(2, cast(u8*, host))
    } else {
        if host.shell_lifecycle {
            let lifecycle = host.shell_lifecycle
            lifecycle(2, cast(u8*, host))
        }
    }
    IDE:free_host(host)
    return 0
}

// Small ownership wrapper for launcher code. The project provides the
// configuration callback; each run owns a fresh Config object.
let IDE:run = fn (configure:fn (IDE:Config*) -> void) -> i64 {
    if !configure { return 1 }
    let app = IDE:Config:new()
    if !app { return 1 }
    defer app.destroy()
    configure(app)
    return app.open()
}

languagekit_native_end
include "build/export.rl"
__recurloop_export_library
