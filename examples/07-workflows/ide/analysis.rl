// IDE runtime adapter for the shared LanguageKit analysis engine.
let IDE:Analysis = phrase { dictionary = true permanent = true }

let IDE:Analysis:trace = fn (host:IDE:Host*, path:u8*, source:u8*) -> u8* {
    return IDE:intelligence_inspect(host, path, source, 1)
}

let IDE:Analysis:update_file = fn (index:LanguageKit:Analysis:Index*, host:IDE:Host*, path:u8*, source:u8*) -> LanguageKit:Analysis:File* {
    let file = LanguageKit:Analysis:find_file(index, path)
    if file && LanguageKit:Analysis:equal(file.source, source) { return file }
    let trace = IDE:Analysis:trace(host, path, source)
    let updated = LanguageKit:Analysis:update_file(index, path, source, trace)
    if trace { free(trace) }
    return updated
}

let IDE:Analysis:index = fn (state:IDE:App:State*, path:u8*, source:u8*) -> LanguageKit:Analysis:File* {
    if !state || !state.host || !state.host.runner { return cast(LanguageKit:Analysis:File*, 0) }
    var index = cast(LanguageKit:Analysis:Index*, state.intelligence_index)
    let application_root = IDE:App:application_root(state)
    defer free(application_root)
    let standalone = application_root && IDE:path_is_inside(path, application_root)
    if index && (index.revision != state.host.runner.revision || index.standalone != standalone) {
        LanguageKit:Analysis:destroy(index); index = cast(LanguageKit:Analysis:Index*, 0); state.intelligence_index = cast(u8*, 0)
    }
    if !index {
        index = LanguageKit:Analysis:new()
        if !index { return cast(LanguageKit:Analysis:File*, 0) }
        index.revision = state.host.runner.revision; index.standalone = standalone
        state.intelligence_index = cast(u8*, index)
    }
    let paths = state.host.watch_sources
    if paths {
        var at:i64 = 0
        while paths[at] != 0 {
            let end = IDE:App:find_byte(paths, at, 10)
            let file_path = LanguageKit:copy_bytes(&paths[at], end - at)
            if file_path {
                let application_file = application_root && IDE:path_is_inside(file_path, application_root)
                if application_file == standalone && !LanguageKit:Analysis:equal(file_path, path) {
                    let disk = IDE:read_file(file_path)
                    if disk { IDE:Analysis:update_file(index, state.host, file_path, disk); free(disk) }
                }
                free(file_path)
            }
            at = end; if paths[at] == 10 { at += 1 }
        }
    }
    return IDE:Analysis:update_file(index, state.host, path, source)
}

let IDE:Analysis:query = fn (state:IDE:App:State*, operation:u8*, path:u8*, source:u8*, position:u64, argument:u8*) -> u8* {
    let current = IDE:Analysis:index(state, path, source)
    if !current { return cast(u8*, 0) }
    return LanguageKit:Analysis:query_index(cast(LanguageKit:Analysis:Index*, state.intelligence_index), current, operation, position, argument)
}
