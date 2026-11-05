// Portable documentation export implemented in RecurLoop.
// Requires the standard Shell/LanguageKit vocabulary. No source-code parsing:
// API descriptions come from the runtime's versioned P/G/H/J trace facts.

link shared "c"
extern calloc(count:u64, size:u64) -> u8* abi sysv-amd64
extern fseek(stream:u8*, offset:i64, origin:i32) -> i32 abi sysv-amd64
extern ftell(stream:u8*) -> i64 abi sysv-amd64
extern fwrite(data:u8*, size:u64, count:u64, stream:u8*) -> u64 abi sysv-amd64
extern snprintf(buffer:u8*, size:u64, format:u8*, ...) -> i32 abi sysv-amd64
extern access(path:u8*, mode:i32) -> i32 abi sysv-amd64

let Docs = []

let Docs:copy = fn (text:u8*) -> u8* { return LanguageKit:copy_text(text) }
let Docs:empty = fn (text:u8*) -> i64 { return !text || text[0] == 0 }
let Docs:trim = fn (text:u8*) -> u8* {
    if !text { return text }
    var size = cast(i64, strlen(text))
    while size > 0 && (text[size - 1] == 10 || text[size - 1] == 13 || text[size - 1] == 32) { size -= 1 }
    text[size] = 0
    return text
}
let Docs:join = fn (left:u8*, right:u8*) -> u8* {
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    defer out.destroy()
    if !out.append(left) || !out.append("/") || !out.append(right) { return cast(u8*, 0) }
    return out.take()
}
let Docs:read_file = fn (path:u8*) -> u8* {
    let stream = fopen(path, "rb")
    if !stream { return cast(u8*, 0) }
    defer fclose(stream)
    if fseek(stream, 0, 2) != 0 { return cast(u8*, 0) }
    let size = ftell(stream)
    if size < 0 || size > 16777216 || fseek(stream, 0, 0) != 0 { return cast(u8*, 0) }
    let out = malloc(cast(u64, size + 1))
    if !out { return out }
    if size > 0 && fread(out, 1, cast(u64, size), stream) != cast(u64, size) { free(out); return cast(u8*, 0) }
    out[size] = 0
    return out
}
let Docs:write_file = fn (path:u8*, text:u8*) -> i64 {
    let stream = fopen(path, "wb")
    if !stream { return 0 }
    let size = strlen(text)
    let written = fwrite(text, 1, size, stream)
    let closed = fclose(stream)
    return written == size && closed == 0
}
let Docs:nibble = fn (value:u8) -> i64 {
    if value >= 48 && value <= 57 { return value - 48 }
    if value >= 97 && value <= 102 { return value - 87 }
    if value >= 65 && value <= 70 { return value - 55 }
    return -1
}
let Docs:decode = fn (hex:u8*) -> u8* {
    let size = cast(i64, strlen(hex))
    if size % 2 != 0 { return cast(u8*, 0) }
    let out = malloc(cast(u64, size / 2 + 1))
    if !out { return out }
    var i = 0
    while i < size {
        let high = Docs:nibble(hex[i])
        let low = Docs:nibble(hex[i + 1])
        if high < 0 || low < 0 { free(out); return cast(u8*, 0) }
        out[i / 2] = cast(u8, high * 16 + low)
        i += 2
    }
    out[size / 2] = 0
    return out
}
let Docs:json = fn (out:LanguageKit:Text*, value:u8*) -> i64 {
    if !value { return out.append("null") }
    if !out.append("\"") { return 0 }
    let digits = "0123456789abcdef"
    var i = 0
    while value[i] != 0 {
        let ch = value[i]
        if ch == 34 { if !out.append("\\\"") { return 0 } }
        else if ch == 92 { if !out.append("\\\\") { return 0 } }
        else if ch == 10 { if !out.append("\\n") { return 0 } }
        else if ch == 13 { if !out.append("\\r") { return 0 } }
        else if ch == 9 { if !out.append("\\t") { return 0 } }
        else if ch < 32 {
            if !out.append("\\u00") || !out.append_byte(digits[ch / 16]) || !out.append_byte(digits[ch % 16]) { return 0 }
        } else { if !out.append_byte(ch) { return 0 } }
        i += 1
    }
    return out.append("\"")
}
let Docs:basename = fn (path:u8*) -> u8* {
    if !path { return cast(u8*, 0) }
    var result = path
    var i = 0
    while path[i] != 0 { if path[i] == 47 { result = &path[i + 1] }; i += 1 }
    return result
}
let Docs:page_id = fn (name:u8*) -> u8* {
    var hash = cast(u64, 5381)
    var i = 0
    while name[i] != 0 { hash = hash * 131 + cast(u64, name[i]); i += 1 }
    let out = malloc(32)
    if out { snprintf(out, 32, "api-%016llx", hash) }
    return out
}

record Docs:Symbol {
    version:u8*
    name:u8*
    description:u8*
    image:u8*
    signature:u8*
    pattern:u8*
    example:u8*
    summary:u8*
    arguments:LanguageKit:Text*
    next:Docs:Symbol*
}
record Docs:Catalog { first:Docs:Symbol* last:Docs:Symbol* error:i64 }
let Docs:symbol = fn (catalog:Docs:Catalog*, version:u8*, name:u8*) -> Docs:Symbol* {
    var item = catalog.first
    while item {
        if strcmp(item.version, version) == 0 && strcmp(item.name, name) == 0 { return item }
        item = item.next
    }
    item = cast(Docs:Symbol*, calloc(1, sizeof(Docs:Symbol)))
    if !item { catalog.error = 1; return item }
    item.version = Docs:copy(version)
    item.name = Docs:copy(name)
    item.arguments = LanguageKit:Text:new()
    if catalog.last { catalog.last.next = item }
    else { catalog.first = item }
    catalog.last = item
    return item
}
let Docs:parse_trace = fn (trace:u8*) -> Docs:Catalog* {
    let catalog = cast(Docs:Catalog*, calloc(1, sizeof(Docs:Catalog)))
    if !catalog { return catalog }
    let fields = cast(u8**, calloc(16, sizeof(u8*)))
    if !fields { catalog.error = 1; return catalog }
    defer free(cast(u8*, fields))
    var line = trace
    while line && line[0] != 0 {
        var end = 0
        while line[end] != 0 && line[end] != 10 { end += 1 }
        var next = cast(u8*, 0)
        if line[end] == 10 { line[end] = 0; next = &line[end + 1] }
        var count = 1
        fields[0] = line
        var at = 0
        while at < end {
            if line[at] == 9 { line[at] = 0; if count < 16 { fields[count] = &line[at + 1]; count += 1 } }
            at += 1
        }
        if fields[0][0] == 69 { catalog.error = 1; return catalog }
        if count >= 5 && (fields[0][0] == 80 || fields[0][0] == 71 || fields[0][0] == 72 || fields[0][0] == 74) {
            let name = Docs:decode(fields[2])
            if !name { catalog.error = 1; return catalog }
            let item = Docs:symbol(catalog, fields[1], name)
            free(name)
            if !item { return catalog }
            if fields[0][0] == 80 && count >= 8 { item.description = Docs:decode(fields[4]); item.signature = Docs:decode(fields[7]) }
            else if fields[0][0] == 71 { item.image = Docs:decode(fields[4]) }
            else if fields[0][0] == 72 && count >= 8 { item.pattern = Docs:decode(fields[3]); item.example = Docs:decode(fields[5]); item.summary = Docs:decode(fields[6]) }
            else if fields[0][0] == 74 && count >= 8 {
                let argument = Docs:decode(fields[3])
                let description = Docs:decode(fields[4])
                if argument && description { item.arguments.append("\n- **"); item.arguments.append(argument); item.arguments.append("** — "); item.arguments.append(description) }
                if argument { free(argument) }; if description { free(description) }
            }
        }
        line = next
    }
    return catalog
}
let Docs:destroy_catalog = fn (catalog:Docs:Catalog*) -> void {
    if !catalog { return }
    var item = catalog.first
    while item {
        let next = item.next
        free(item.version); free(item.name); free(item.description); free(item.image)
        free(item.signature); free(item.pattern); free(item.example); free(item.summary)
        if item.arguments { item.arguments.destroy() }
        free(cast(u8*, item)); item = next
    }
    free(cast(u8*, catalog))
}
let Docs:documented = fn (item:Docs:Symbol*, image:u8*) -> i64 {
    if Docs:empty(item.name) || Docs:empty(item.image) || strcmp(Docs:basename(item.image), image) != 0 { return 0 }
    var i = 0
    while item.name[i] != 0 { if item.name[i] < 32 { return 0 }; i += 1 }
    return !Docs:empty(item.description) || !Docs:empty(item.summary)
}
let Docs:body = fn (item:Docs:Symbol*) -> u8* {
    let out = LanguageKit:Text:new()
    if !out { return cast(u8*, 0) }
    defer out.destroy()
    if !Docs:empty(item.summary) { out.append(item.summary); out.append("\n\n") }
    if !Docs:empty(item.description) { out.append(item.description); out.append("\n\n") }
    if !Docs:empty(item.signature) { out.append("## Signature\n\n```recurloop\n"); out.append(item.signature); out.append("\n```\n\n") }
    if !Docs:empty(item.pattern) { out.append("## Syntax\n\n```recurloop\n"); out.append(item.pattern); out.append("\n```\n\n") }
    if !Docs:empty(item.example) { out.append("## Example\n\n```recurloop\n"); out.append(item.example); out.append("\n```\n\n") }
    if item.arguments.length { out.append("## Arguments\n"); out.append(item.arguments.data) }
    return out.take()
}
let Docs:page = fn (out:LanguageKit:Text*, navigation:LanguageKit:Text*, id:u8*, title:u8*, section:u8*, body:u8*, source:u8*) -> void {
    if navigation.length > 0 { out.append(",\n"); navigation.append(",\n") }
    let header = LanguageKit:Text:new()
    header.append("{\"id\":"); Docs:json(header, id)
    header.append(",\"title\":"); Docs:json(header, title)
    header.append(",\"section\":"); Docs:json(header, section)
    header.append(",\"source_path\":"); Docs:json(header, source)
    navigation.append(header.data); navigation.append("}")
    out.append(header.data); out.append(",\"body\":"); Docs:json(out, body); out.append("}")
    header.destroy()
}
let Docs:markdown_page = fn (out:LanguageKit:Text*, navigation:LanguageKit:Text*, path:u8*, section:u8*, id:u8*) -> i64 {
    let body = Docs:read_file(path)
    if !body { return 0 }
    defer free(body)
    var title = Docs:copy(id)
    var at = 0
    while body[at] != 0 {
        if (at == 0 || body[at - 1] == 10) && body[at] == 35 && body[at + 1] == 32 {
            var end = at + 2
            while body[end] != 0 && body[end] != 10 && body[end] != 13 { end += 1 }
            free(title); title = LanguageKit:copy_bytes(&body[at + 2], end - at - 2); break
        }
        at += 1
    }
    Docs:page(out, navigation, id, title, section, body, path)
    free(title)
    return 1
}
let Docs:core_guides = fn (out:LanguageKit:Text*, navigation:LanguageKit:Text*) -> i64 {
    if !Docs:markdown_page(out, navigation, "README.md", "Getting started", "overview") { return 0 }
    let paths = capture find docs -maxdepth 1 -name "*.md" -type f | sort
    if !paths { return 0 }
    defer free(paths)
    var path = paths
    while path[0] != 0 {
        var end = 0
        while path[end] != 0 && path[end] != 10 { end += 1 }
        let more = path[end] == 10
        path[end] = 0
        let name = Docs:copy(Docs:basename(path))
        name[strlen(name) - 3] = 0
        let written = Docs:markdown_page(out, navigation, path, "Guides", name)
        free(name)
        if !written { return 0 }
        if !more { break }; path = &path[end + 1]
    }
    if !Docs:markdown_page(out, navigation, "libraries/README.md", "Libraries", "standard-libraries") { return 0 }
    return Docs:markdown_page(out, navigation, "tools/vscode-recurloop/README.md", "Tools", "vscode")
}
let Docs:bundle = fn (root:u8*, output:u8*, scope:u8*, version:u8*, revision:u8*, manifest:LanguageKit:Text*, first:i64) -> i64 {
    let executable = Docs:join(root, "build/Release/bin/recurloop")
    let libraries = Docs:join(root, "build/Release/libraries")
    let entry = Docs:join(root, ".cache/docs-export/recurloop.project.rl")
    defer free(executable); defer free(libraries); defer free(entry)
    var library = scope
    if strcmp(scope, "core") == 0 { library = "project" }
    let command = spawn "{executable}" --library-path "{libraries}" --library "{library}" --project "{entry}" --trace "{entry}"
    if !command { return 0 }
    defer command.destroy()
    if command.exit_code() != 0 { return 0 }
    let trace = Docs:copy(command.stdout())
    if !trace || trace[0] == 0 { if trace { free(trace) }; return 0 }
    defer free(trace)
    let catalog = Docs:parse_trace(trace)
    if !catalog { return 0 }
    defer Docs:destroy_catalog(catalog)
    if catalog.error { return 0 }
    let out = LanguageKit:Text:new()
    let navigation = LanguageKit:Text:new()
    defer out.destroy(); defer navigation.destroy()
    out.append("{\"schema_version\":1,\"package\":{\"name\":"); Docs:json(out, scope)
    out.append(",\"version\":"); Docs:json(out, version)
    out.append(",\"kind\":\"standard\",\"repository_url\":\"https://github.com/RecurLoop/RecurLoop\"},\"source_revision\":"); Docs:json(out, revision)
    out.append(",\"pages\":[\n")
    if strcmp(scope, "core") == 0 { if !Docs:core_guides(out, navigation) { return 0 } }
    else {
        let readme = LanguageKit:Text:new()
        readme.append("libraries/"); readme.append(scope); readme.append("/README.md")
        if access(readme.data, 4) == 0 { if !Docs:markdown_page(out, navigation, readme.data, "Overview", "overview") { readme.destroy(); return 0 } }
        readme.destroy()
    }
    let image = LanguageKit:Text:new()
    image.append(scope); image.append(".rli")
    defer image.destroy()
    var item = catalog.first
    var count = 0
    while item {
        if Docs:documented(item, image.data) {
            let id = Docs:page_id(item.name)
            let body = Docs:body(item)
            if !id || !body { return 0 }
            Docs:page(out, navigation, id, item.name, "API", body, cast(u8*, 0))
            free(id); free(body); count += 1
        }
        item = item.next
    }
    if navigation.length == 0 { return 0 }
    out.append("\n]}\n")
    let filename = LanguageKit:Text:new()
    filename.append(scope); filename.append(".json")
    let destination = Docs:join(output, filename.data)
    defer free(destination); defer filename.destroy()
    if !Docs:write_file(destination, out.data) { return 0 }
    if !first { manifest.append(",\n") }
    manifest.append("{\"id\":"); Docs:json(manifest, scope)
    manifest.append(",\"title\":")
    var title = scope
    if strcmp(scope, "core") == 0 { title = "RecurLoop" }
    Docs:json(manifest, title)
    manifest.append(",\"version\":"); Docs:json(manifest, version)
    manifest.append(",\"url\":\"/docs-data/"); manifest.append(scope); manifest.append(".json\",\"pages\":[\n"); manifest.append(navigation.data); manifest.append("\n]}")
    printf("[docs] %s: %ld documented phrases\n", scope, count)
    return 1
}
let Docs:export = fn (output:u8*) -> i64 {
    if Docs:empty(output) { return 1 }
    let directory_status = run mkdir -p "{output}" .cache/docs-export
    if directory_status != 0 { return 2 }
    if !Docs:write_file(".cache/docs-export/recurloop.project.rl", "") { return 3 }
    let root = capture pwd
    let revision = capture git rev-parse HEAD
    let release = capture ./build/Release/bin/recurloop --version
    if !root || !revision || !release { return 4 }
    defer free(root); defer free(revision); defer free(release)
    Docs:trim(root); Docs:trim(revision); Docs:trim(release)
    var version = release
    while version[0] != 0 && version[0] != 118 { version = &version[1] }
    if version[0] == 0 { return 4 }; version = &version[1]
    let manifest = LanguageKit:Text:new()
    defer manifest.destroy()
    manifest.append("{\"schema_version\":1,\"version\":"); Docs:json(manifest, version)
    manifest.append(",\"source_revision\":"); Docs:json(manifest, revision)
    manifest.append(",\"repository_url\":\"https://github.com/RecurLoop/RecurLoop\",\"bundles\":[\n")
    if !Docs:bundle(root, output, "core", version, revision, manifest, 1) { return 5 }
    let scopes = Docs:read_file("libraries/standard.txt")
    if !scopes { return 6 }
    defer free(scopes)
    var scope = scopes
    while scope[0] != 0 {
        var end = 0
        while scope[end] != 0 && scope[end] != 10 { end += 1 }
        let more = scope[end] == 10
        scope[end] = 0
        if scope[0] != 0 && scope[0] != 35 { if !Docs:bundle(root, output, scope, version, revision, manifest, 0) { return 7 } }
        if !more { break }; scope = &scope[end + 1]
    }
    manifest.append("\n]}\n")
    let path = Docs:join(output, "manifest.json")
    defer free(path)
    if !Docs:write_file(path, manifest.data) { return 8 }
    return 0
}
let Docs:export_from_environment = fn () -> i64 {
    var output = getenv("RECURLOOP_DOCS_OUTPUT")
    if !output || output[0] == 0 { output = "build/documentation" }
    return Docs:export(output)
}
