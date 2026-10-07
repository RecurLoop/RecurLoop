// Typed-language grammar and ABI-facing phrases. C++ owns physical host layout; this file owns language phrases.

// Semantic metadata exposed to IDE/introspection clients. These are normal
// phrase fields; libraries can attach them to their own phrases without any
// editor-specific registration.
phrase docs = "docs" in root {
  type phrase_types_data
}

phrase kind = "kind" in root {
  type phrase_types_data
}

phrase color = "color" in root {
  type phrase_types_data
}

phrase phrase_fields = "\0phrase-fields" in root {
  dictionary
  type phrase_types_data
}

phrase phrase_names = "\0phrase-names" in root {
  dictionary
  type phrase_types_data
}

phrase type_syntax = "\0type-syntax" in root {
  dictionary
  type phrase_types_data
}

phrase typed_grammar = "\0typed-grammar" in root {
  dictionary
  type phrase_types_data
}

phrase abi = "abi" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nabi name(property(...), ...)\n```\n\nDefines a calling convention. Select it on a function declaration with `abi name`. Built-ins include `sysv-amd64`, `microsoft-x64`, `cdecl-x86`, `stdcall-x86` and `fastcall-x86`.\n\n**Example**\n\n```recurloop\nextern puts(text:u8*) -> i32 abi sysv-amd64\n```"
  dictionary
  type phrase_types_elaborate
  action host "typed.abi"
  language compiler
}

phrase extern = "extern" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nextern name(parameter:type, ...) -> result abi convention\n```\n\nDeclares a function supplied by native code. Configure its library with `link` before calling it. A final `...` parameter declares a variadic function.\n\n**Example**\n\n```recurloop\nlink shared \"c\"\nextern puts(text:u8*) -> i32 abi sysv-amd64\n```"
  type phrase_types_elaborate
  action host "typed.extern"
  language compiler
}

phrase link = "link" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nlink shared \"name\"\nlink object \"path.o\"\nlink archive \"path.a\"\nlink path \"directory\"\nlink library \"name\"\nlink clear\n```\n\nAdds native linker inputs or search paths. `shared` selects a shared library; `library` selects a static library by name. `clear` removes all configured inputs."
  dictionary
  type phrase_types_elaborate
  action host "typed.link"
  language compiler
}

phrase module = "module" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nmodule auto\nmodule manual\nmodule include symbol\nmodule exclude symbol\nmodule entry symbol\n```\n\nControls which native modules enter output. `auto` includes dependencies; `manual` uses explicit selections. `dynamic` is an alias of `exclude`. `clear` resets selections; `embed`/`strip` include/omit language metadata."
  dictionary
  type phrase_types_elaborate
  action host "typed.module"
  language compiler
}

phrase pointer = "pointer" in root {
  kind "type"
  color "#4EC9B0"
  docs "```recurloop\npointer Type* name\n```\n\nDeclares a zero-initialized native pointer instance. Use `Type*` in parameter and local type annotations.\n\n**Example**\n\n```recurloop\npointer u8* buffer\n```"
  type phrase_types_elaborate
  action host "typed.pointer"
  language compiler
}

phrase record = "record" in root {
  kind "keyword"
  color "#569CD6"
  docs "```recurloop\nrecord Name {\n    field:type\n    ...\n}\n```\n\nDefines a native record with calculated field offsets and alignment. Field types can be pointers, arrays or other records.\n\n**Example**\n\n```recurloop\nrecord Point { x:i64 y:i64 }\n```"
  type phrase_types_elaborate
  action host "typed.record"
  language compiler
}

phrase phrase_fields_action = "action" in phrase_fields {
  prototype action
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\naction = <implementation>\naction = fn (state:Context*, called:Phrase*) -> void { ... }\n```\n\nCopies a phrase action or compiles an inline action. Inline actions can only be assigned while creating the phrase."
  type phrase_types_callable
  action host "phrase.field.action"
}

phrase phrase_fields_color = "color" in phrase_fields {
  prototype color
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\ncolor = \"#RRGGBB\"\n```\n\nSets the semantic text color reported to editors. Example: `color = \"#569CD6\"`."
  type phrase_types_callable
  action host "phrase.field.color"
}

phrase phrase_fields_docs = "docs" in phrase_fields {
  prototype docs
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\ndocs = \"Markdown text\"\n```\n\nSets hover and completion documentation. Use a fenced `recurloop` code block for syntax highlighting and `\\n` for line breaks."
  type phrase_types_callable
  action host "phrase.field.docs"
}

phrase phrase_fields_kind = "kind" in phrase_fields {
  prototype kind
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\nkind = \"category\"\n```\n\nSets the semantic category reported to editors, such as `keyword`, `function`, `type` or `phrase field`."
  type phrase_types_callable
  action host "phrase.field.kind"
}

phrase phrase_fields_dictionary = "dictionary" in phrase_fields {
  prototype dictionary
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\ndictionary = true\n```\n\nCreates a child dictionary owned by this phrase. Set it during creation; it cannot be changed later."
  type phrase_types_callable
  action host "phrase.field.dictionary"
}

phrase phrase_fields_parent = "parent" in phrase_fields {
  prototype parent
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\nlet Namespace:name = definition\n```\n\nRead-only dictionary owner used for lexical lookup. Assigning `parent` is rejected; create the phrase at the desired qualified path."
  type phrase_types_callable
  action host "phrase.field.parent"
}

phrase phrase_fields_payload = "payload" in phrase_fields {
  prototype payload
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\npayload = \"bytes\"\n```\n\nSets payload bytes while creating a phrase. String escapes include `\\n`, `\\t` and `\\0`; payload cannot be assigned later."
  type phrase_types_callable
  action host "phrase.field.payload"
}

phrase phrase_fields_permanent = "permanent" in phrase_fields {
  prototype permanent
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\npermanent = true\n```\n\nProtects the committed phrase from redefinition and modification. Apply after setting its other fields."
  type phrase_types_callable
  action host "phrase.field.permanent"
}

phrase phrase_fields_prototype = "prototype" in phrase_fields {
  prototype prototype
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\nprototype = <phrase>\n```\n\nInherits behavior, structure and semantic metadata from another phrase. Use `none` to clear the prototype."
  type phrase_types_callable
  action host "phrase.field.prototype"
}

phrase phrase_fields_rewrite = "rewrite" in phrase_fields {
  prototype rewrite
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\nrewrite = true\n```\n\nMakes a root phrase available during compiled-function expansion as well as top-level elaboration."
  type phrase_types_callable
  action host "phrase.field.rewrite"
}

phrase phrase_fields_serializable = "serializable" in phrase_fields {
  prototype serializable
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\nserializable = false\n```\n\nExcludes this phrase from engine images. Use for process-local state; `true` enables serialization."
  type phrase_types_callable
  action host "phrase.field.serializable"
}

phrase phrase_fields_successor = "successor" in phrase_fields {
  prototype successor
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\nsuccessor = <dictionary>\n```\n\nSelects the lookup dictionary used after this phrase matches. Use `none` to clear it."
  type phrase_types_callable
  action host "phrase.field.successor"
}

phrase phrase_fields_type = "type" in phrase_fields {
  prototype type
  kind "phrase field"
  color "#9CDCFE"
  docs "```recurloop\ntype = <phrase-types:elaborate>\n```\n\nSelects phrase execution behavior. Use `data` for storage, `elaborate` for source parsing, `callable` for invocation or `scoped-callable` for invocation followed by a return to the parent dictionary."
  type phrase_types_callable
  action host "phrase.field.type"
}

phrase phrase_names_double = "double" in phrase_names {
  dictionary
  type phrase_types_data
}

phrase phrase_names_plain = "plain" in phrase_names {
  dictionary
  type phrase_types_data
}

phrase phrase_names_single = "single" in phrase_names {
  dictionary
  type phrase_types_data
}

phrase type_syntax_prefix = "prefix" in type_syntax {
  dictionary
  type phrase_types_data
}

phrase type_syntax_suffix = "suffix" in type_syntax {
  dictionary
  type phrase_types_data
}

phrase typed_grammar_symbols = "symbols" in typed_grammar {
  dictionary
  type phrase_types_data
}

phrase abi_align = "align" in abi {
  docs "```recurloop\nalign(16)\n```\n\nSets stack alignment in bytes inside an ABI declaration."
  prototype align
  type phrase_types_callable
  action host "typed.abi.align"
}

phrase abi_cleanup = "cleanup" in abi {
  docs "```recurloop\ncleanup(caller)\ncleanup(callee)\n```\n\nSelects who removes stack arguments inside an ABI declaration."
  dictionary
  prototype cleanup
  type phrase_types_callable
  action host "typed.abi.cleanup"
}

phrase abi_floating = "floating" in abi {
  docs "```recurloop\nfloating(xmm0, xmm1, ...)\n```\n\nLists floating-point argument registers in order, inside an ABI declaration."
  prototype floating
  type phrase_types_callable
  action host "typed.abi.floating"
}

phrase abi_floating_result = "floating-result" in abi {
  docs "```recurloop\nfloating-result(xmm0)\n```\n\nSelects the floating-point return register inside an ABI declaration."
  prototype floating_result
  type phrase_types_callable
  action host "typed.abi.floating-result"
}

phrase abi_integer = "integer" in abi {
  docs "```recurloop\ninteger(rdi, rsi, ...)\n```\n\nLists integer/pointer argument registers in order, inside `abi name(...)`."
  prototype integer
  type phrase_types_callable
  action host "typed.abi.integer"
}

phrase abi_result = "result" in abi {
  docs "```recurloop\nresult(rax)\n```\n\nSelects the integer/pointer return register inside an ABI declaration."
  prototype result
  type phrase_types_callable
  action host "typed.abi.result"
}

phrase abi_shadow = "shadow" in abi {
  docs "```recurloop\nshadow(32)\n```\n\nSets reserved caller shadow space in bytes inside an ABI declaration."
  prototype shadow
  type phrase_types_callable
  action host "typed.abi.shadow"
}

phrase abi_stack = "stack" in abi {
  docs "```recurloop\nstack(down)\nstack(up)\n```\n\nSelects stack growth direction inside an ABI declaration."
  dictionary
  prototype stack
  type phrase_types_callable
  action host "typed.abi.stack"
}

phrase link_archive = "archive" in link {
  docs "```recurloop\nlink archive \"path.a\"\n```\n\nAdds a native static archive."
  prototype archive
  type phrase_types_callable
  action host "typed.link.archive"
}

phrase link_clear = "clear" in link {
  docs "```recurloop\nlink clear\n```\n\nClears configured native linker inputs and search paths."
  prototype clear
  type phrase_types_callable
  action host "typed.link.clear"
}

phrase link_library = "library" in link {
  docs "```recurloop\nlink library \"name\"\n```\n\nLinks a static library by name."
  prototype library
  type phrase_types_callable
  action host "typed.link.library"
}

phrase link_object = "object" in link {
  docs "```recurloop\nlink object \"path.o\"\n```\n\nAdds a native object file."
  prototype object
  type phrase_types_callable
  action host "typed.link.object"
}

phrase link_path = "path" in link {
  docs "```recurloop\nlink path \"directory\"\n```\n\nAdds a directory to library lookup."
  prototype path
  type phrase_types_callable
  action host "typed.link.path"
}

phrase link_shared = "shared" in link {
  docs "```recurloop\nlink shared \"name\"\n```\n\nLinks a shared library by name. Example: `link shared \"c\"`."
  prototype shared
  type phrase_types_callable
  action host "typed.link.shared"
}

phrase module_auto = "auto" in module {
  docs "```recurloop\nmodule auto\n```\n\nAutomatically includes reachable native dependencies."
  prototype auto
  type phrase_types_callable
  action host "typed.module.auto"
}

phrase module_clear = "clear" in module {
  docs "```recurloop\nmodule clear\n```\n\nResets native module selections."
  prototype clear
  type phrase_types_callable
  action host "typed.module.clear"
}

phrase module_dynamic = "dynamic" in module {
  docs "```recurloop\nmodule dynamic symbol\n```\n\nAlias of `module exclude`: leaves the symbol outside the selected native modules."
  prototype dynamic
  type phrase_types_callable
  action host "typed.module.exclude"
}

phrase module_embed = "embed" in module {
  docs "```recurloop\nmodule embed\n```\n\nIncludes language metadata in native output."
  prototype embed
  type phrase_types_callable
  action host "typed.module.embed"
}

phrase module_entry = "entry" in module {
  docs "```recurloop\nmodule entry symbol\n```\n\nSelects the native entry symbol."
  prototype entry
  type phrase_types_callable
  action host "typed.module.entry"
}

phrase module_exclude = "exclude" in module {
  docs "```recurloop\nmodule exclude symbol\n```\n\nExcludes a native module from output."
  prototype exclude
  type phrase_types_callable
  action host "typed.module.exclude"
}

phrase module_include = "include" in module {
  docs "```recurloop\nmodule include symbol\n```\n\nAdds a native module to output."
  prototype include
  type phrase_types_callable
  action host "typed.module.include"
}

phrase module_manual = "manual" in module {
  docs "```recurloop\nmodule manual\n```\n\nUses explicit native module selections."
  prototype manual
  type phrase_types_callable
  action host "typed.module.manual"
}

phrase module_strip = "strip" in module {
  docs "```recurloop\nmodule strip\n```\n\nOmits language metadata from native output. This does not control executable debug symbols."
  prototype strip
  type phrase_types_callable
  action host "typed.module.strip"
}

phrase phrase_names_double_empty = "" in phrase_names_double {
  type phrase_types_callable
  action host "phrase-name.byte"
}

phrase phrase_names_double_quote = "\"" in phrase_names_double {
  type phrase_types_callable
  action host "phrase-name.end-quote"
}

phrase phrase_names_double_empty_c6de19 = "${" in phrase_names_double {
  type phrase_types_callable
  action host "phrase-name.interpolate"
}

phrase phrase_names_double_backslash = "\\" in phrase_names_double {
  type phrase_types_callable
  action host "phrase-name.escaped-byte"
}

phrase phrase_names_double_n = "\\n" in phrase_names_double {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character newline
}

phrase phrase_names_double_r = "\\r" in phrase_names_double {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character carriage-return
}

phrase phrase_names_double_t = "\\t" in phrase_names_double {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character tab
}

phrase phrase_names_double_v = "\\v" in phrase_names_double {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character vertical-tab
}

phrase phrase_names_plain_empty = "" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.byte"
}

phrase phrase_names_plain_tab = "\t" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.whitespace"
}

phrase phrase_names_plain_newline = "\n" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.whitespace"
}

phrase phrase_names_plain_vertical_tab = "\x0b" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.whitespace"
}

phrase phrase_names_plain_carriage_return = "\r" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.whitespace"
}

phrase phrase_names_plain_empty_a0f5ee = " " in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.whitespace"
}

phrase phrase_names_plain_quote = "\"" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.begin-double"
}

phrase phrase_names_plain_empty_3ecd09 = "${" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.interpolate"
}

phrase phrase_names_plain_apostrophe = "'" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.begin-single"
}

phrase phrase_names_plain_colon = ":" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.segment"
}

phrase phrase_names_plain_backslash = "\\" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.escaped-byte"
}

phrase phrase_names_plain_n = "\\n" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character newline
}

phrase phrase_names_plain_r = "\\r" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character carriage-return
}

phrase phrase_names_plain_t = "\\t" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character tab
}

phrase phrase_names_plain_v = "\\v" in phrase_names_plain {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character vertical-tab
}

phrase phrase_names_single_empty = "" in phrase_names_single {
  type phrase_types_callable
  action host "phrase-name.byte"
}

phrase phrase_names_single_empty_126cec = "${" in phrase_names_single {
  type phrase_types_callable
  action host "phrase-name.interpolate"
}

phrase phrase_names_single_apostrophe = "'" in phrase_names_single {
  type phrase_types_callable
  action host "phrase-name.end-quote"
}

phrase phrase_names_single_backslash = "\\" in phrase_names_single {
  type phrase_types_callable
  action host "phrase-name.escaped-byte"
}

phrase phrase_names_single_n = "\\n" in phrase_names_single {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character newline
}

phrase phrase_names_single_r = "\\r" in phrase_names_single {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character carriage-return
}

phrase phrase_names_single_t = "\\t" in phrase_names_single {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character tab
}

phrase phrase_names_single_v = "\\v" in phrase_names_single {
  type phrase_types_callable
  action host "phrase-name.escaped"
  character vertical-tab
}

phrase type_syntax_prefix_fn = "fn" in type_syntax_prefix {
  prototype fn
  type phrase_types_callable
  action host "type-syntax.function"
}

phrase type_syntax_suffix_star = "*" in type_syntax_suffix {
  prototype star
  type phrase_types_callable
  action host "type-syntax.pointer"
}

phrase type_syntax_suffix_lbracket = "[" in type_syntax_suffix {
  prototype lbracket
  type phrase_types_callable
  action host "type-syntax.array"
}

phrase typed_grammar_symbols_lparen = "(" in typed_grammar_symbols {
  prototype lparen
  type phrase_types_data
}

phrase typed_grammar_symbols_rparen = ")" in typed_grammar_symbols {
  prototype rparen
  type phrase_types_data
}

phrase typed_grammar_symbols_comma = "," in typed_grammar_symbols {
  prototype comma
  type phrase_types_data
}

phrase typed_grammar_symbols_arrow = "->" in typed_grammar_symbols {
  prototype arrow
  type phrase_types_data
}

phrase typed_grammar_symbols_empty = "..." in typed_grammar_symbols {
  prototype empty_671187
  type phrase_types_data
}

phrase typed_grammar_symbols_colon = ":" in typed_grammar_symbols {
  prototype colon
  type phrase_types_data
}

phrase typed_grammar_symbols_equals = "=" in typed_grammar_symbols {
  prototype equals
  type phrase_types_data
}

phrase typed_grammar_symbols_rbracket = "]" in typed_grammar_symbols {
  prototype rbracket
  type phrase_types_data
}

phrase abi_cleanup_callee = "callee" in abi_cleanup {
  prototype callee
  type phrase_types_data
  abi-cleanup callee
}

phrase abi_cleanup_caller = "caller" in abi_cleanup {
  prototype caller
  type phrase_types_data
  abi-cleanup caller
}

phrase abi_stack_down = "down" in abi_stack {
  prototype down
  type phrase_types_data
  abi-stack down
}

phrase abi_stack_up = "up" in abi_stack {
  prototype up
  type phrase_types_data
  abi-stack up
}
