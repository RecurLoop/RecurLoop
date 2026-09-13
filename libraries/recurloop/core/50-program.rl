// Source-defined top-level program form and core image export.
proc RecurLoopLanguage:program_action (state:Context*, called:Phrase*) -> void {
    let block = context:source:block:capture(state)
    if !block { context:diagnostic:error(state, "recur expects a source block"); return }
    defer context:source:block:release(block)
    let header = context:source:block:header(block)
    let source = context:source:block:body(block)
    if !header || !source { context:diagnostic:error(state, "recur could not capture source"); return }
    let header_length = RecurLoopLanguage:text_length(header)
    if RecurLoopLanguage:trim_finish(header, 0, header_length) != 0 {
        context:diagnostic:error(state, "recur takes no header; put declarations inside its block")
        return
    }

    let limit = RecurLoopLanguage:text_length(source)
    var i = 0
    // Declarations are compiled in source order. Once executable top-level code
    // begins, the remainder is the synthetic file body.
    while 1 {
        i = RecurLoopLanguage:skip_trivia(source, i, limit)
        if i >= limit { return }
        if RecurLoopLanguage:word_at(source, i, limit, "record", 6) {
            var finish = 0
            if !RecurLoopLanguage:define_record(state, source, i, limit, &finish) { return }
            i = finish
            continue
        }
        if RecurLoopLanguage:word_at(source, i, limit, "fn", 2) {
            var finish = 0
            if !RecurLoopLanguage:define_function(state, source, i, limit, &finish) { return }
            i = finish
            continue
        }
        break
    }

    // Remaining source behaves like today's top-level executable statements,
    // but is compiled as a private native entry function.
    let translator = cast(RecurLoopLanguage:Translator*, RecurLoopLanguage:allocate_type(state, "RecurLoopLanguage:Translator"))
    if !translator { context:diagnostic:error(state, "top-level translator allocation failed"); return }
    defer free(cast(u8*, translator))
    if !RecurLoopLanguage:Translator:init(translator) { context:diagnostic:error(state, "top-level translator allocation failed"); return }
    defer RecurLoopLanguage:Translator:destroy(translator)
    if !RecurLoopLanguage:Translator:translate_block(translator, source, i, limit) {
        context:diagnostic:error(state, "top-level source could not be translated")
        return
    }
    RecurLoopLanguage:Buffer:append(&translator.out, "return 0\n")
    if !context:function:compile(state, "() -> i64", translator.out.data, "__recurloop_language_file_main") {
        context:diagnostic:error(state, "top-level native lowering failed")
        return
    }
    let address = context:function:address(state, "__recurloop_language_file_main")
    if !address { context:diagnostic:error(state, "top-level entry is unavailable"); return }
    let entry = cast(RecurLoopSeed:I64Call0, address)
    let result = entry()
    if result != 0 { state.exec.status = result }
}

proc RecurLoopLanguage:program_handler (state:Context*, called:Phrase*) -> void {
    RecurLoopLanguage:program_action(state, called)
}
form recur = RecurLoopLanguage:program_handler

engine export "/tmp/recurloop-core.rli"
