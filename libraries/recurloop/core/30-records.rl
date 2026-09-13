// Source-defined record declaration parser and layout construction.
// -----------------------------------------------------------------------------
// record: direct type/layout construction. No host `record` is emitted.
// -----------------------------------------------------------------------------
proc RecurLoopLanguage:define_record (state:Context*, text:u8*, start:i64, limit:i64, finish_out:i64*) -> i64 {
    var i = RecurLoopLanguage:skip_trivia(text, start + 6, limit)
    let name_start = i
    while i < limit && RecurLoopLanguage:is_name(text[i]) { i += 1 }
    if i == name_start { context:diagnostic:error(state, "record expects a name"); return 0 }
    let name = RecurLoopLanguage:copy_slice(text, name_start, i)
    if !name { return 0 }
    defer free(name)

    i = RecurLoopLanguage:skip_trivia(text, i, limit)
    if i >= limit || text[i] != 123 { context:diagnostic:error(state, "record expects a field block"); return 0 }
    let close = RecurLoopLanguage:matching(text, i, limit, 123, 125)
    if close < 0 { context:diagnostic:error(state, "record block is not closed"); return 0 }

    let structure = context:type:structure:declare(state, name)
    if !structure { context:diagnostic:error(state, "record could not declare type"); return 0 }

    let owner_name = cast(RecurLoopLanguage:Buffer*, RecurLoopLanguage:allocate_type(state, "RecurLoopLanguage:Buffer"))
    if !owner_name { return 0 }
    defer free(cast(u8*, owner_name))
    if !RecurLoopLanguage:Buffer:init(owner_name, 64) { return 0 }
    defer RecurLoopLanguage:Buffer:destroy(owner_name)
    RecurLoopLanguage:Buffer:append(owner_name, "__recurloop_language_fields_")
    RecurLoopLanguage:Buffer:append(owner_name, name)
    let owner = context:phrase:define:dictionary(state, owner_name.data)
    if !owner { context:diagnostic:error(state, "record could not create field dictionary"); return 0 }

    var p = i + 1
    var last_field = 0
    var fields = 0
    while 1 {
        p = RecurLoopLanguage:skip_trivia(text, p, close)
        while p < close && (text[p] == 44 || text[p] == 59) { p += 1; p = RecurLoopLanguage:skip_trivia(text, p, close) }
        if p >= close { break }
        let field_start = p
        while p < close && ((text[p] >= 65 && text[p] <= 90) || (text[p] >= 97 && text[p] <= 122) || (text[p] >= 48 && text[p] <= 57) || text[p] == 95 || text[p] == 45) { p += 1 }
        if p == field_start { context:diagnostic:error(state, "record expected a field name"); return 0 }
        let field_name = RecurLoopLanguage:copy_slice(text, field_start, p)
        if !field_name { return 0 }
        defer free(field_name)
        p = RecurLoopLanguage:skip_trivia(text, p, close)
        if p >= close || text[p] != 58 { context:diagnostic:error(state, "record field expects ':'"); return 0 }
        p += 1
        p = RecurLoopLanguage:skip_trivia(text, p, close)
        let type_start = p
        var bracket = 0
        while p < close {
            if text[p] == 91 { bracket += 1; p += 1; continue }
            if text[p] == 93 { if bracket > 0 { bracket -= 1 }; p += 1; continue }
            if bracket == 0 && (text[p] == 44 || text[p] == 59 || text[p] == 10 || text[p] == 13) { break }
            if bracket == 0 && (text[p] == 32 || text[p] == 9) {
                var probe = p
                while probe < close && (text[probe] == 32 || text[probe] == 9) { probe += 1 }
                var q = probe
                while q < close && ((text[q] >= 65 && text[q] <= 90) || (text[q] >= 97 && text[q] <= 122) || (text[q] >= 48 && text[q] <= 57) || text[q] == 95 || text[q] == 45) { q += 1 }
                var r = q
                while r < close && (text[r] == 32 || text[r] == 9) { r += 1 }
                if q > probe && r < close && text[r] == 58 { break }
            }
            p += 1
        }
        let type_finish = RecurLoopLanguage:trim_finish(text, type_start, p)
        let field_type = RecurLoopSeed:resolve_type(state, text, type_start, type_finish)
        if !field_type { context:diagnostic:error(state, "record could not resolve field type"); return 0 }
        var field = 0
        if last_field { field = context:phrase:define:successor(state, owner, field_name, last_field) }
        else { field = context:phrase:define:data(state, owner, field_name) }
        if !field { context:diagnostic:error(state, "record could not define field metadata"); return 0 }
        context:phrase:data(state, field, &field_type, 0, 8)
        last_field = field
        fields += 1
    }
    if fields <= 0 || !context:type:structure:complete:natural(state, structure, last_field) {
        context:diagnostic:error(state, "record could not complete layout")
        return 0
    }
    finish_out[0] = close + 1
    return 1
}

