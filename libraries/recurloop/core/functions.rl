// Function grammar and intrinsic behavior.

phrase fn_grammar = "\0fn-grammar" in root {
  dictionary
  type phrase_types_data
}

phrase fn = "fn" in root {
  kind "keyword"
  color "#569CD6"
  docs "```recurloop\nfn name(parameter:type, ...) -> result { ... }\nlet name = fn (parameter:type, ...) -> result { ... }\n```\n\nCompiles a typed function. Call it with `name(arguments)`. Parameters may be empty; use `void` when no value is returned.\n\nWithout a body, `let Signature = fn (...) -> result` defines a reusable signature. Here `...` stands for more parameters or body statements.\n\n**Example**\n\n```recurloop\nlet add = fn (a:i64, b:i64) -> i64 {\n    return a + b\n}\nprint add(20, 22)\n```"
  type phrase_types_data
}

phrase fn_cc83a0 = "fn" in root {
  prototype fn
  type phrase_types_elaborate
  action host "fn.define"
  language compiler
}

phrase forward = "forward" in root {
  kind "keyword"
  color "#569CD6"
  docs "```recurloop\nforward name(parameter:type, ...) -> result\n```\n\nDeclares a function before its definition. The later `fn` must match the signature.\n\n**Example**\n\n```recurloop\nforward odd(n:i64) -> i64\n```"
  type phrase_types_elaborate
  action host "fn.forward"
  language compiler
}

phrase function = "function" in root {
  kind "keyword"
  color "#569CD6"
  docs "```recurloop\nfunction name(parameter:type, ...) -> result abi convention\n```\n\nAttaches a typed call signature to an existing invokable phrase with a native module, such as one defined by `asm`. Use `fn` to write a new function."
  type phrase_types_elaborate
  action host "typed.function"
  language compiler
}

phrase method = "method" in root {
  kind "keyword"
  color "#569CD6"
  docs "```recurloop\nmethod Record name(self:Record*, ...) -> result abi convention\n```\n\nDeclares a typed method contract on a record. The first parameter is the receiver; invoke it as `instance.name(arguments)`."
  type phrase_types_elaborate
  action host "typed.method"
  language compiler
}

phrase fn_grammar_intrinsics = "intrinsics" in fn_grammar {
  dictionary
  type phrase_types_data
}

phrase fn_grammar_postfix = "postfix" in fn_grammar {
  dictionary
  type phrase_types_data
}

phrase fn_grammar_primary = "primary" in fn_grammar {
  dictionary
  type phrase_types_data
}

phrase fn_grammar_statements = "statements" in fn_grammar {
  dictionary
  type phrase_types_data
}

phrase fn_grammar_symbols = "symbols" in fn_grammar {
  dictionary
  type phrase_types_data
}

phrase fn_grammar_intrinsics_ampersand = "&" in fn_grammar_intrinsics {
  docs "```recurloop\n&target\n```\n\nReturns the address of an addressable native value."
  dictionary
  prototype ampersand
  type phrase_types_data
  intrinsic address
}

phrase fn_grammar_intrinsics_star = "*" in fn_grammar_intrinsics {
  docs "```recurloop\n*pointer\n```\n\nReads the pointed-to native value; use `*pointer = value` to write it."
  dictionary
  prototype star
  type phrase_types_data
  intrinsic dereference
}

phrase fn_grammar_intrinsics_cast = "cast" in fn_grammar_intrinsics {
  dictionary
  prototype cast
  type phrase_types_data
  intrinsic cast
}

phrase fn_grammar_intrinsics_alloc = "alloc" in fn_grammar_intrinsics {
  dictionary
  prototype alloc
  type phrase_types_data
  intrinsic allocate
}

phrase fn_grammar_intrinsics_sizeof = "sizeof" in fn_grammar_intrinsics {
  dictionary
  prototype sizeof
  type phrase_types_data
  intrinsic size-of
}

phrase fn_grammar_postfix_lparen = "(" in fn_grammar_postfix {
  docs "```recurloop\nfunction(arguments)\n```\n\nCalls a native function or function value with matching typed arguments."
  prototype lparen
  type phrase_types_callable
  action host "fn.postfix.call"
}

phrase fn_grammar_postfix_dot = "." in fn_grammar_postfix {
  docs "```recurloop\ninstance.field\ninstance.method(arguments)\n```\n\nAccesses a record field or invokes its method."
  prototype dot
  type phrase_types_callable
  action host "fn.postfix.member"
}

phrase fn_grammar_postfix_question = "?" in fn_grammar_postfix {
  docs "```recurloop\npointer_expression?\n```\n\nPropagates a null pointer by returning null from the current pointer-returning function."
  prototype question
  type phrase_types_callable
  action host "fn.postfix.propagate"
}

phrase fn_grammar_postfix_colon = ":" in fn_grammar_postfix {
  prototype colon
  type phrase_types_callable
  action host "fn.postfix.qualify"
}

phrase fn_grammar_postfix_lbracket = "[" in fn_grammar_postfix {
  docs "```recurloop\narray_or_pointer[index]\n```\n\nAccesses a native element by zero-based index."
  prototype lbracket_862dc1
  type phrase_types_callable
  action host "fn.postfix.index"
}

phrase fn_grammar_primary_lparen = "(" in fn_grammar_primary {
  prototype lparen
  type phrase_types_callable
  action host "fn.primary.group"
}

phrase fn_grammar_primary_cast = "cast" in fn_grammar_primary {
  prototype cast
  type phrase_types_callable
  action host "fn.primary.cast"
}

phrase fn_grammar_primary_alloc = "alloc" in fn_grammar_primary {
  prototype alloc
  type phrase_types_callable
  action host "fn.primary.alloc"
}

phrase fn_grammar_primary_sizeof = "sizeof" in fn_grammar_primary {
  prototype sizeof
  type phrase_types_callable
  action host "fn.primary.sizeof"
}

phrase fn_grammar_primary_fn = "fn" in fn_grammar_primary {
  prototype fn_cc83a0
  type phrase_types_callable
  action host "fn.primary.function"
}

phrase fn_grammar_primary_if = "if" in fn_grammar_primary {
  prototype if
  type phrase_types_callable
  action host "fn.primary.conditional"
}

phrase fn_grammar_primary_lbrace = "{" in fn_grammar_primary {
  prototype lbrace_055f92
  type phrase_types_callable
  action host "fn.primary.block"
}

phrase fn_grammar_statements_assignment = "\0assignment" in fn_grammar_statements {
  dictionary
  type phrase_types_data
}

phrase fn_grammar_statements_expression = "\0expression" in fn_grammar_statements {
  dictionary
  type phrase_types_data
}

phrase fn_grammar_statements_break = "break" in fn_grammar_statements {
  dictionary
  prototype break
  type phrase_types_callable
  action host "fn.statement.parse-control"
}

phrase fn_grammar_statements_const = "const" in fn_grammar_statements {
  dictionary
  prototype const
  type phrase_types_callable
  action host "fn.statement.parse-variable"
  variable immutable
}

phrase fn_grammar_statements_continue = "continue" in fn_grammar_statements {
  dictionary
  prototype continue
  type phrase_types_callable
  action host "fn.statement.parse-control"
}

phrase fn_grammar_statements_defer = "defer" in fn_grammar_statements {
  dictionary
  prototype defer
  type phrase_types_callable
  action host "fn.statement.parse-defer"
}

phrase fn_grammar_statements_if = "if" in fn_grammar_statements {
  dictionary
  prototype if
  type phrase_types_callable
  action host "fn.statement.parse-conditional"
}

phrase fn_grammar_statements_let = "let" in fn_grammar_statements {
  dictionary
  prototype let
  type phrase_types_callable
  action host "fn.statement.parse-variable"
  variable immutable
}

phrase fn_grammar_statements_return = "return" in fn_grammar_statements {
  dictionary
  prototype return
  type phrase_types_callable
  action host "fn.statement.parse-return"
}

phrase fn_grammar_statements_set = "set" in fn_grammar_statements {
  dictionary
  prototype set
  type phrase_types_callable
  action host "fn.statement.parse-assignment"
}

phrase fn_grammar_statements_var = "var" in fn_grammar_statements {
  dictionary
  prototype var
  type phrase_types_callable
  action host "fn.statement.parse-variable"
  variable mutable
}

phrase fn_grammar_statements_while = "while" in fn_grammar_statements {
  dictionary
  prototype while
  type phrase_types_callable
  action host "fn.statement.parse-loop"
}

phrase fn_grammar_symbols_ampersand = "&" in fn_grammar_symbols {
  prototype ampersand
  type phrase_types_data
}

phrase fn_grammar_symbols_lparen = "(" in fn_grammar_symbols {
  prototype lparen
  type phrase_types_data
}

phrase fn_grammar_symbols_rparen = ")" in fn_grammar_symbols {
  prototype rparen
  type phrase_types_data
}

phrase fn_grammar_symbols_comma = "," in fn_grammar_symbols {
  prototype comma
  type phrase_types_data
}

phrase fn_grammar_symbols_arrow = "->" in fn_grammar_symbols {
  prototype arrow
  type phrase_types_data
}

phrase fn_grammar_symbols_dot = "." in fn_grammar_symbols {
  prototype dot
  type phrase_types_data
}

phrase fn_grammar_symbols_empty = "..." in fn_grammar_symbols {
  prototype empty_671187
  type phrase_types_data
}

phrase fn_grammar_symbols_colon = ":" in fn_grammar_symbols {
  prototype colon
  type phrase_types_data
}

phrase fn_grammar_symbols_semicolon = ";" in fn_grammar_symbols {
  prototype semicolon
  type phrase_types_data
}

phrase fn_grammar_symbols_question = "?" in fn_grammar_symbols {
  prototype question
  type phrase_types_data
}

phrase fn_grammar_symbols_rbracket = "]" in fn_grammar_symbols {
  prototype rbracket
  type phrase_types_data
}

phrase fn_grammar_symbols_lbrace = "{" in fn_grammar_symbols {
  prototype lbrace
  type phrase_types_data
}

phrase fn_grammar_symbols_rbrace = "}" in fn_grammar_symbols {
  prototype rbrace
  type phrase_types_data
}

phrase fn_grammar_intrinsics_ampersand_fn_emit = "\0fn-emit" in fn_grammar_intrinsics_ampersand {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior address emit
}

phrase fn_grammar_intrinsics_ampersand_fn_infer = "\0fn-infer" in fn_grammar_intrinsics_ampersand {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior address infer
}

phrase fn_grammar_intrinsics_star_fn_emit = "\0fn-emit" in fn_grammar_intrinsics_star {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior dereference emit
}

phrase fn_grammar_intrinsics_star_fn_infer = "\0fn-infer" in fn_grammar_intrinsics_star {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior dereference infer
}

phrase fn_grammar_intrinsics_star_fn_lvalue = "\0fn-lvalue" in fn_grammar_intrinsics_star {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior dereference lvalue
}

phrase fn_grammar_intrinsics_cast_fn_emit = "\0fn-emit" in fn_grammar_intrinsics_cast {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior cast emit
}

phrase fn_grammar_intrinsics_cast_fn_infer = "\0fn-infer" in fn_grammar_intrinsics_cast {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior cast infer
}

phrase fn_grammar_intrinsics_alloc_fn_emit = "\0fn-emit" in fn_grammar_intrinsics_alloc {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior allocate emit
}

phrase fn_grammar_intrinsics_alloc_fn_infer = "\0fn-infer" in fn_grammar_intrinsics_alloc {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior allocate infer
}

phrase fn_grammar_intrinsics_sizeof_fn_emit = "\0fn-emit" in fn_grammar_intrinsics_sizeof {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior size-of emit
}

phrase fn_grammar_intrinsics_sizeof_fn_infer = "\0fn-infer" in fn_grammar_intrinsics_sizeof {
  type phrase_types_callable
  action host "fn.intrinsic.compile"
  intrinsic-behavior size-of infer
}

phrase fn_grammar_statements_assignment_fn_emit = "\0fn-emit" in fn_grammar_statements_assignment {
  type phrase_types_callable
  action host "fn.statement.emit-assignment"
}

phrase fn_grammar_statements_expression_fn_emit = "\0fn-emit" in fn_grammar_statements_expression {
  type phrase_types_callable
  action host "fn.statement.emit-expression"
}

phrase fn_grammar_statements_expression_fn_value = "\0fn-value" in fn_grammar_statements_expression {
  type phrase_types_data
}

phrase fn_grammar_statements_break_fn_emit = "\0fn-emit" in fn_grammar_statements_break {
  type phrase_types_callable
  action host "fn.statement.emit-break"
}

phrase fn_grammar_statements_const_fn_emit = "\0fn-emit" in fn_grammar_statements_const {
  type phrase_types_callable
  action host "fn.statement.emit-variable"
}

phrase fn_grammar_statements_continue_fn_emit = "\0fn-emit" in fn_grammar_statements_continue {
  type phrase_types_callable
  action host "fn.statement.emit-continue"
}

phrase fn_grammar_statements_defer_fn_emit = "\0fn-emit" in fn_grammar_statements_defer {
  type phrase_types_callable
  action host "fn.statement.emit-defer"
}

phrase fn_grammar_statements_if_fn_emit = "\0fn-emit" in fn_grammar_statements_if {
  type phrase_types_callable
  action host "fn.statement.emit-conditional"
}

phrase fn_grammar_statements_let_fn_emit = "\0fn-emit" in fn_grammar_statements_let {
  type phrase_types_callable
  action host "fn.statement.emit-variable"
}

phrase fn_grammar_statements_return_fn_emit = "\0fn-emit" in fn_grammar_statements_return {
  type phrase_types_callable
  action host "fn.statement.emit-return"
}

phrase fn_grammar_statements_set_fn_emit = "\0fn-emit" in fn_grammar_statements_set {
  type phrase_types_callable
  action host "fn.statement.emit-assignment"
}

phrase fn_grammar_statements_var_fn_emit = "\0fn-emit" in fn_grammar_statements_var {
  type phrase_types_callable
  action host "fn.statement.emit-variable"
}

phrase fn_grammar_statements_while_fn_emit = "\0fn-emit" in fn_grammar_statements_while {
  type phrase_types_callable
  action host "fn.statement.emit-loop"
}
