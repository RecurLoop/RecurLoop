let ReaderGrammar = phrase { dictionary = true }
let setup_reader_grammar = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let grammar = context:phrase:find(state, "ReaderGrammar")
        LanguageKit:define_token(state, grammar, "{", 5)
        LanguageKit:define_token(state, grammar, "}", 5)
        LanguageKit:define_token(state, grammar, "+", 4)
        LanguageKit:define_token(state, grammar, "//", 4)
        LanguageKit:define_token(state, grammar, "/*", 4)
        LanguageKit:define_token(state, grammar, "*/", 4)
    }
}
setup_reader_grammar
let ReaderGrammar:begin = <ReaderGrammar:"{">
let ReaderGrammar:end = <ReaderGrammar:"}">
let ReaderGrammar:plus = <ReaderGrammar:"+">
let ReaderGrammar:"⊕" = <ReaderGrammar:"+">
let ReaderGrammar:"//token" = <ReaderGrammar:"+">
let ReaderGrammar:"  add" = <ReaderGrammar:"+">
let ReaderGrammar:"\"plus" = <ReaderGrammar:"+">
let ReaderGrammar:"#" = <ReaderGrammar:"//">
let ReaderGrammar:comment = <ReaderGrammar:"/*">
let ReaderGrammar:stop = <ReaderGrammar:"*/">

let check_reader = fn (state:Context*, source:u8*, expected:u8*) -> void {
    let grammar = context:phrase:find(state, "ReaderGrammar")
    let reader = LanguageKit:SliceReader:new_phrases(state, grammar, source, strlen(source), 392)
    if !reader { context:diagnostic:error(state, "could not allocate phrase reader"); return }
    defer reader.destroy()
    if !reader.is(expected) { context:diagnostic:error(state, "phrase identity or longest match failed"); return }
    let canonical = reader.take_canonical()
    if !canonical || strcmp(canonical, expected) != 0 { context:diagnostic:error(state, "canonical alias text failed") }
    if canonical { free(canonical) }
    if reader.kind_of() != 0 { context:diagnostic:error(state, "phrase reader left unexpected source") }
}
let bounded_readers = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        check_reader(state, "//token", "+")
        check_reader(state, "⊕", "+")
        check_reader(state, "  add", "+")
        check_reader(state, "\"plus", "+")
        check_reader(state, "# end\ncomment fake } stop begin", "{")
        let grammar = context:phrase:find(state, "ReaderGrammar")
        let reader = LanguageKit:SliceReader:new_phrases(state, grammar, "\"}\"", 3, 128)
        if !reader { return }
        if reader.is("}") || reader.kind_of() != 3 { context:diagnostic:error(state, "quoted data became syntax") }
        reader.destroy()
        let word = LanguageKit:SliceReader:new_phrases(state, grammar, "weekend", 7, 0)
        if !word { return }
        if word.is("}") || word.kind_of() != 1 { context:diagnostic:error(state, "word suffix became syntax") }
        word.destroy()
    }
}
bounded_readers

let streamed_reader = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let reader = LanguageKit:Reader:new_phrases(state, context:phrase:find(state, "ReaderGrammar"), 392)
        if !reader { return }
        defer reader.destroy()
        if !reader.match("{") { context:diagnostic:error(state, "streamed opening alias failed"); return }
        if reader.number_of() != 20 { context:diagnostic:error(state, "streamed number failed"); return }
        reader.consume()
        if !reader.match("+") { context:diagnostic:error(state, "streamed longest token failed"); return }
        if reader.number_of() != 22 { context:diagnostic:error(state, "streamed second number failed"); return }
        reader.consume()
        if !reader.match("}") { context:diagnostic:error(state, "streamed closing alias failed"); return }
        context:source:root(state)
    }
}
streamed_reader begin 20 //token 22 end
streamed_reader begin 20 ⊕ 22 end
print 42
