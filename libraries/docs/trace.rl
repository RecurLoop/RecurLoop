record Docs:Symbol {
    version:u8*
    name:u8*
    description:u8*
    image:u8*
    source:u8*
    project_source:i64
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
        if fields[0][0] == 69 && fields[0][1] == 0 && count >= 2 { let message = Docs:decode(fields[1]); if message { Docs:diagnostic("source diagnostic", message); free(message) }; catalog.error = 1; return catalog }
        if count >= 5 && fields[0][1] == 0 && (fields[0][0] == 80 || fields[0][0] == 71 || fields[0][0] == 72 || fields[0][0] == 74 || fields[0][0] == 70) {
            let name = Docs:decode(fields[2])
            if !name { catalog.error = 1; return catalog }
            let item = Docs:symbol(catalog, fields[1], name)
            free(name)
            if !item { return catalog }
            if fields[0][0] == 80 && count >= 8 { item.description = Docs:decode(fields[4]); item.signature = Docs:decode(fields[7]) }
            else if fields[0][0] == 71 {
                item.image = Docs:decode(fields[4])
                let origin = Docs:decode(fields[3])
                if !Docs:empty(origin) && (Docs:empty(item.image) || strstr(item.image, "/.cache/recurloop/modules/")) {
                    item.project_source = 1; free(item.source); item.source = origin
                } else if !item.source { item.source = origin } else { free(origin) }
            }
            else if fields[0][0] == 70 && count >= 4 { if item.source { free(item.source) }; item.source = Docs:decode(fields[3]) }
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
        free(item.source); free(item.signature); free(item.pattern); free(item.example); free(item.summary)
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
