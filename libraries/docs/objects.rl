// Extended manuals are normal portable phrase objects, not a second document index.
let Docs:object_text = fn (state:Context*, object:u64, field:u8*, fallback:u8*) -> u8* {
    let member = context:phrase:find:exact(state, object, field)
    if !member { return Docs:copy(fallback) }
    let size = context:phrase:payload:bytes(state, member)
    if size > 500000 { return cast(u8*, 0) }
    let text = malloc(size + 1)
    if !text { return text }
    if size { context:phrase:read(state, member, 0, text, size) }; text[size] = 0; return text
}
let Docs:objects = fn (state:Context*, store:Docs:Store*) -> i64 {
    let namespace = context:phrase:find(state, "Docs")
    let pages = context:phrase:find:exact(state, namespace, "Pages")
    if !pages { store.error = 1; return 0 }
    var object = context:phrase:child:first(state, pages)
    while object {
        let size = context:phrase:key(state, object, cast(u8*, 0), 0)
        let key = malloc(size + 1)
        if !key { store.error = 1; return 0 }; context:phrase:key(state, object, key, size); key[size] = 0
        let symbol = Docs:object_text(state, object, "symbol", "")
        var id = Docs:object_text(state, object, "id", key)
        var title = Docs:object_text(state, object, "title", key)
        let section = Docs:object_text(state, object, "section", "Language")
        let scope = Docs:object_text(state, object, "scope", store.name)
        let body = Docs:object_text(state, object, "body", "")
        let source = Docs:object_text(state, object, "source", "")
        let home = Docs:object_text(state, object, "default", "false")
        let ordering = Docs:object_text(state, object, "order", "0")
        let order = Docs:parse_order(ordering)
        if !Docs:empty(symbol) { free(id); id = Docs:page_id(symbol); if strcmp(title, key) == 0 { free(title); title = Docs:copy(symbol) } }
        if order < 0 || !symbol || !title || !section || !scope || !body || !source || !home || !Docs:valid_id(id) || Docs:find(store, scope, id) { store.error = 1 }
        else {
            let entry = Docs:add(store, scope, id, title, section, body, source, source)
            if entry { free(entry.symbol); entry.symbol = Docs:copy(symbol); entry.home = strcmp(home, "true") == 0; entry.order = order; entry.authored = 1 }
        }
        free(key); free(symbol); free(id); free(title); free(section); free(scope); free(body); free(source); free(home); free(ordering)
        if store.error { return 0 }; object = context:phrase:child:next(state, pages, object)
    }
    Docs:sort(store); return Docs:build_index(store)
}
let Docs:from_context = fn (state:Context*, scope:u8*, version:u8*, repository:u8*) -> Docs:Store* {
    let store = Docs:new(scope, version, repository)
    if store { Docs:objects(state, store) }; return store
}
syntax Docs:source <path:string> action fn (state:Context*, called:Phrase*) -> void {
    let raw_path = context:syntax:capture(state, "path")
    let decoded = Docs:json_parse(raw_path)
    if !decoded || decoded.kind != 3 { Docs:json_destroy(decoded); context:diagnostic:error(state, "invalid documentation source path"); return }
    defer Docs:json_destroy(decoded); let path = decoded.text
    let namespace = context:phrase:find(state, "Docs")
    let pages = context:phrase:find:exact(state, namespace, "Pages")
    var object = context:phrase:child:first(state, pages)
    while object {
        if !context:phrase:find:exact(state, object, "source") {
            let field = context:phrase:define:data(state, object, "source")
            context:phrase:data(state, field, path, 0, strlen(path))
        }
        object = context:phrase:child:next(state, pages, object)
    }
}
let Docs:dump_objects = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        var index = state.exec.args.index
        if index < state.exec.args.count && strcmp(state.exec.args.values[index], "--") == 0 { index += 1 }
        if state.exec.args.count - index != 4 { context:diagnostic:error(state, "object export requires scope, version, repository and output"); return }
        let args = &state.exec.args.values[index]; state.exec.args.index = state.exec.args.count
        let store = Docs:from_context(state, args[0], args[1], args[2])
        if !store { context:diagnostic:error(state, "cannot allocate documentation catalog"); return }; defer Docs:destroy(store)
        if store.error || !Docs:export_file(store, args[3]) { context:diagnostic:error(state, "cannot export documentation objects") }
    }
}
set Docs:from_context.docs = "Reads extended documentation objects from the current context's Docs:Pages dictionary and builds their index. Returns an owned catalog."
