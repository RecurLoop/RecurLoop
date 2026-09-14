// Typed-language grammar and ABI-facing phrases. C++ owns physical host layout; this file owns language phrases.

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
  dictionary
  type phrase_types_elaborate
  action host "typed.abi"
  language compiler
}

phrase extern = "extern" in root {
  type phrase_types_elaborate
  action host "typed.extern"
  language compiler
}

phrase link = "link" in root {
  dictionary
  type phrase_types_elaborate
  action host "typed.link"
  language compiler
}

phrase module = "module" in root {
  dictionary
  type phrase_types_elaborate
  action host "typed.module"
  language compiler
}

phrase pointer = "pointer" in root {
  type phrase_types_elaborate
  action host "typed.pointer"
  language compiler
}

phrase record = "record" in root {
  type phrase_types_elaborate
  action host "typed.record"
  language compiler
}

phrase phrase_fields_action = "action" in phrase_fields {
  prototype action
  type phrase_types_callable
  action host "phrase.field.action"
}

phrase phrase_fields_dictionary = "dictionary" in phrase_fields {
  prototype dictionary
  type phrase_types_callable
  action host "phrase.field.dictionary"
}

phrase phrase_fields_parent = "parent" in phrase_fields {
  prototype parent
  type phrase_types_callable
  action host "phrase.field.parent"
}

phrase phrase_fields_payload = "payload" in phrase_fields {
  prototype payload
  type phrase_types_callable
  action host "phrase.field.payload"
}

phrase phrase_fields_permanent = "permanent" in phrase_fields {
  prototype permanent
  type phrase_types_callable
  action host "phrase.field.permanent"
}

phrase phrase_fields_prototype = "prototype" in phrase_fields {
  prototype prototype
  type phrase_types_callable
  action host "phrase.field.prototype"
}

phrase phrase_fields_rewrite = "rewrite" in phrase_fields {
  prototype rewrite
  type phrase_types_callable
  action host "phrase.field.rewrite"
}

phrase phrase_fields_serializable = "serializable" in phrase_fields {
  prototype serializable
  type phrase_types_callable
  action host "phrase.field.serializable"
}

phrase phrase_fields_successor = "successor" in phrase_fields {
  prototype successor
  type phrase_types_callable
  action host "phrase.field.successor"
}

phrase phrase_fields_type = "type" in phrase_fields {
  prototype type
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
  prototype align
  type phrase_types_callable
  action host "typed.abi.align"
}

phrase abi_cleanup = "cleanup" in abi {
  dictionary
  prototype cleanup
  type phrase_types_callable
  action host "typed.abi.cleanup"
}

phrase abi_floating = "floating" in abi {
  prototype floating
  type phrase_types_callable
  action host "typed.abi.floating"
}

phrase abi_floating_result = "floating-result" in abi {
  prototype floating_result
  type phrase_types_callable
  action host "typed.abi.floating-result"
}

phrase abi_integer = "integer" in abi {
  prototype integer
  type phrase_types_callable
  action host "typed.abi.integer"
}

phrase abi_result = "result" in abi {
  prototype result
  type phrase_types_callable
  action host "typed.abi.result"
}

phrase abi_shadow = "shadow" in abi {
  prototype shadow
  type phrase_types_callable
  action host "typed.abi.shadow"
}

phrase abi_stack = "stack" in abi {
  dictionary
  prototype stack
  type phrase_types_callable
  action host "typed.abi.stack"
}

phrase link_archive = "archive" in link {
  prototype archive
  type phrase_types_callable
  action host "typed.link.archive"
}

phrase link_clear = "clear" in link {
  prototype clear
  type phrase_types_callable
  action host "typed.link.clear"
}

phrase link_library = "library" in link {
  prototype library
  type phrase_types_callable
  action host "typed.link.library"
}

phrase link_object = "object" in link {
  prototype object
  type phrase_types_callable
  action host "typed.link.object"
}

phrase link_path = "path" in link {
  prototype path
  type phrase_types_callable
  action host "typed.link.path"
}

phrase link_shared = "shared" in link {
  prototype shared
  type phrase_types_callable
  action host "typed.link.shared"
}

phrase module_auto = "auto" in module {
  prototype auto
  type phrase_types_callable
  action host "typed.module.auto"
}

phrase module_clear = "clear" in module {
  prototype clear
  type phrase_types_callable
  action host "typed.module.clear"
}

phrase module_dynamic = "dynamic" in module {
  prototype dynamic
  type phrase_types_callable
  action host "typed.module.exclude"
}

phrase module_embed = "embed" in module {
  prototype embed
  type phrase_types_callable
  action host "typed.module.embed"
}

phrase module_entry = "entry" in module {
  prototype entry
  type phrase_types_callable
  action host "typed.module.entry"
}

phrase module_exclude = "exclude" in module {
  prototype exclude
  type phrase_types_callable
  action host "typed.module.exclude"
}

phrase module_include = "include" in module {
  prototype include
  type phrase_types_callable
  action host "typed.module.include"
}

phrase module_manual = "manual" in module {
  prototype manual
  type phrase_types_callable
  action host "typed.module.manual"
}

phrase module_strip = "strip" in module {
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
