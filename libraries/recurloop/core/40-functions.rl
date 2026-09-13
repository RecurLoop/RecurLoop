// Source-defined function declaration shell and lowering bridge.
// -----------------------------------------------------------------------------
// fn: parse declaration shell + parse/normalize the body ourselves.
// -----------------------------------------------------------------------------
proc RecurLoopLanguage:define_function (state:Context*, text:u8*, start:i64, limit:i64, finish_out:i64*) -> i64 {
    var i = RecurLoopLanguage:skip_trivia(text, start + 2, limit)
    let name_start = i
    while i < limit && RecurLoopLanguage:is_name(text[i]) { i += 1 }
    if i == name_start { context:diagnostic:error(state, "fn expects a name"); return 0 }
    let name = RecurLoopLanguage:copy_slice(text, name_start, i)
    if !name { return 0 }
    defer free(name)

    i = RecurLoopLanguage:skip_trivia(text, i, limit)
    if i >= limit || text[i] != 40 { context:diagnostic:error(state, "fn expects parameter list"); return 0 }
    let signature_start = i
    let params_close = RecurLoopLanguage:matching(text, i, limit, 40, 41)
    if params_close < 0 { context:diagnostic:error(state, "fn parameter list is not closed"); return 0 }
    i = RecurLoopLanguage:skip_trivia(text, params_close + 1, limit)
    if i + 1 >= limit || text[i] != 45 || text[i + 1] != 62 { context:diagnostic:error(state, "fn expects '-> return-type'"); return 0 }
    i += 2
    let open = RecurLoopLanguage:find_top(text, i, limit, 123)
    if open < 0 { context:diagnostic:error(state, "fn expects a body"); return 0 }
    let body_close = RecurLoopLanguage:matching(text, open, limit, 123, 125)
    if body_close < 0 { context:diagnostic:error(state, "fn body is not closed"); return 0 }
    let signature_finish = RecurLoopLanguage:trim_finish(text, signature_start, open)
    let signature = RecurLoopLanguage:copy_slice(text, signature_start, signature_finish)
    if !signature { return 0 }
    defer free(signature)

    let translator = cast(RecurLoopLanguage:Translator*, RecurLoopLanguage:allocate_type(state, "RecurLoopLanguage:Translator"))
    if !translator { context:diagnostic:error(state, "fn translator allocation failed"); return 0 }
    defer free(cast(u8*, translator))
    if !RecurLoopLanguage:Translator:init(translator) { context:diagnostic:error(state, "fn translator allocation failed"); return 0 }
    defer RecurLoopLanguage:Translator:destroy(translator)
    if !RecurLoopLanguage:Translator:translate_block(translator, text, open + 1, body_close) {
        context:diagnostic:error(state, "fn body could not be translated")
        return 0
    }
    if !context:function:compile(state, signature, translator.out.data, name) {
        context:diagnostic:error(state, "fn native lowering failed")
        return 0
    }
    finish_out[0] = body_close + 1
    return 1
}

