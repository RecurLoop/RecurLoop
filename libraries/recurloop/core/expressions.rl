// Expression and assignment grammar. Operator behavior is declared semantically.

phrase expressions = "\0expressions" in root {
  dictionary
  type phrase_types_data
}

phrase assert = "assert" in root {
  type phrase_types_elaborate
  action host "expressions.assert"
  language compiler
}

phrase const = "const" in root {
  type phrase_types_elaborate
  action host "expressions.constant"
  language compiler
}

phrase print = "print" in root {
  type phrase_types_elaborate
  action host "expressions.print"
  language compiler
}

phrase set = "set" in root {
  type phrase_types_elaborate
  action host "expressions.assign"
  language compiler
}

phrase var = "var" in root {
  type phrase_types_elaborate
  action host "expressions.variable"
  language compiler
}

phrase expressions_assignments = "assignments" in expressions {
  dictionary
  type phrase_types_data
}

phrase expressions_builtins = "builtins" in expressions {
  dictionary
  type phrase_types_data
}

phrase expressions_dynamic = "dynamic" in expressions {
  dictionary
  type phrase_types_data
}

phrase expressions_infix = "infix" in expressions {
  dictionary
  type phrase_types_data
}

phrase expressions_literals = "literals" in expressions {
  dictionary
  type phrase_types_data
}

phrase expressions_prefix = "prefix" in expressions {
  dictionary
  type phrase_types_data
}

phrase expressions_symbols = "symbols" in expressions {
  dictionary
  type phrase_types_data
}

phrase expressions_assignments_percent_equals = "%=" in expressions_assignments {
  dictionary
  prototype percent_equals
  type phrase_types_data
  assignment compound
}

phrase expressions_assignments_star_equals = "*=" in expressions_assignments {
  dictionary
  prototype star_equals
  type phrase_types_data
  assignment compound
}

phrase expressions_assignments_plus_equals = "+=" in expressions_assignments {
  dictionary
  prototype plus_equals
  type phrase_types_data
  assignment compound
}

phrase expressions_assignments_minus_equals = "-=" in expressions_assignments {
  dictionary
  prototype minus_equals
  type phrase_types_data
  assignment compound
}

phrase expressions_assignments_slash_equals = "/=" in expressions_assignments {
  dictionary
  prototype slash_equals
  type phrase_types_data
  assignment compound
}

phrase expressions_assignments_equals = "=" in expressions_assignments {
  dictionary
  prototype equals
  type phrase_types_data
  assignment direct
}

phrase expressions_builtins_contains = "contains" in expressions_builtins {
  prototype contains
  type phrase_types_callable
  action host "expressions.builtin.contains"
}

phrase expressions_builtins_ends_with = "ends_with" in expressions_builtins {
  prototype ends_with
  type phrase_types_callable
  action host "expressions.builtin.ends-with"
}

phrase expressions_builtins_len = "len" in expressions_builtins {
  prototype len
  type phrase_types_callable
  action host "expressions.builtin.len"
}

phrase expressions_builtins_lower = "lower" in expressions_builtins {
  prototype lower
  type phrase_types_callable
  action host "expressions.builtin.lower"
}

phrase expressions_builtins_replace = "replace" in expressions_builtins {
  prototype replace
  type phrase_types_callable
  action host "expressions.builtin.replace"
}

phrase expressions_builtins_starts_with = "starts_with" in expressions_builtins {
  prototype starts_with
  type phrase_types_callable
  action host "expressions.builtin.starts-with"
}

phrase expressions_builtins_str = "str" in expressions_builtins {
  prototype str
  type phrase_types_callable
  action host "expressions.builtin.str"
}

phrase expressions_builtins_substr = "substr" in expressions_builtins {
  prototype substr
  type phrase_types_callable
  action host "expressions.builtin.substr"
}

phrase expressions_builtins_trim = "trim" in expressions_builtins {
  prototype trim
  type phrase_types_callable
  action host "expressions.builtin.trim"
}

phrase expressions_builtins_type = "type" in expressions_builtins {
  prototype type
  type phrase_types_callable
  action host "expressions.builtin.type"
}

phrase expressions_builtins_upper = "upper" in expressions_builtins {
  prototype upper
  type phrase_types_callable
  action host "expressions.builtin.upper"
}

phrase expressions_builtins_value = "value" in expressions_builtins {
  prototype value
  type phrase_types_callable
  action host "expressions.builtin.value"
}

phrase expressions_infix_not_equal = "!=" in expressions_infix {
  dictionary
  prototype not_equal
  type phrase_types_callable
  action host "expressions.operator.infix-not-equal"
  operator infix precedence 3
}

phrase expressions_infix_percent = "%" in expressions_infix {
  dictionary
  prototype percent
  type phrase_types_callable
  action host "expressions.operator.infix-modulo"
  operator infix precedence 6
}

phrase expressions_infix_and_and = "&&" in expressions_infix {
  dictionary
  prototype and_and
  type phrase_types_callable
  action host "expressions.operator.infix-and"
  operator infix precedence 2 short-circuit false
}

phrase expressions_infix_star = "*" in expressions_infix {
  dictionary
  prototype star
  type phrase_types_callable
  action host "expressions.operator.infix-multiply"
  operator infix precedence 6
}

phrase expressions_infix_plus = "+" in expressions_infix {
  dictionary
  prototype plus
  type phrase_types_callable
  action host "expressions.operator.infix-add"
  operator infix precedence 5
}

phrase expressions_infix_minus = "-" in expressions_infix {
  dictionary
  prototype minus
  type phrase_types_callable
  action host "expressions.operator.infix-subtract"
  operator infix precedence 5
}

phrase expressions_infix_slash = "/" in expressions_infix {
  dictionary
  prototype slash
  type phrase_types_callable
  action host "expressions.operator.infix-divide"
  operator infix precedence 6
}

phrase expressions_infix_less = "<" in expressions_infix {
  dictionary
  prototype less
  type phrase_types_callable
  action host "expressions.operator.infix-less"
  operator infix precedence 4
}

phrase expressions_infix_less_equal = "<=" in expressions_infix {
  dictionary
  prototype less_equal
  type phrase_types_callable
  action host "expressions.operator.infix-less-equal"
  operator infix precedence 4
}

phrase expressions_infix_equal_equal = "==" in expressions_infix {
  dictionary
  prototype equal_equal
  type phrase_types_callable
  action host "expressions.operator.infix-equal"
  operator infix precedence 3
}

phrase expressions_infix_greater = ">" in expressions_infix {
  dictionary
  prototype greater
  type phrase_types_callable
  action host "expressions.operator.infix-greater"
  operator infix precedence 4
}

phrase expressions_infix_greater_equal = ">=" in expressions_infix {
  dictionary
  prototype greater_equal
  type phrase_types_callable
  action host "expressions.operator.infix-greater-equal"
  operator infix precedence 4
}

phrase expressions_infix_or_or = "||" in expressions_infix {
  dictionary
  prototype or_or
  type phrase_types_callable
  action host "expressions.operator.infix-or"
  operator infix precedence 1 short-circuit true
}

phrase expressions_literals_false = "false" in expressions_literals {
  prototype false
  type phrase_types_callable
  action host "expressions.literal.false"
}

phrase expressions_literals_null = "null" in expressions_literals {
  prototype null
  type phrase_types_callable
  action host "expressions.literal.null"
}

phrase expressions_literals_true = "true" in expressions_literals {
  prototype true
  type phrase_types_callable
  action host "expressions.literal.true"
}

phrase expressions_prefix_not = "!" in expressions_prefix {
  dictionary
  prototype not
  type phrase_types_callable
  action host "expressions.operator.prefix-not"
  operator prefix precedence 7
}

phrase expressions_prefix_plus = "+" in expressions_prefix {
  dictionary
  prototype plus
  type phrase_types_callable
  action host "expressions.operator.prefix-positive"
  operator prefix precedence 7
}

phrase expressions_prefix_minus = "-" in expressions_prefix {
  dictionary
  prototype minus
  type phrase_types_callable
  action host "expressions.operator.prefix-negative"
  operator prefix precedence 7
}

phrase expressions_symbols_lparen = "(" in expressions_symbols {
  prototype lparen
  type phrase_types_data
}

phrase expressions_symbols_rparen = ")" in expressions_symbols {
  prototype rparen
  type phrase_types_data
}

phrase expressions_symbols_comma = "," in expressions_symbols {
  prototype comma
  type phrase_types_data
}

phrase expressions_symbols_dot = "." in expressions_symbols {
  prototype dot
  type phrase_types_data
}

phrase expressions_assignments_percent_equals_fn_assign = "\0fn-assign" in expressions_assignments_percent_equals {
  type phrase_types_callable
  action host "fn.assignment.emit-modulo"
}

phrase expressions_assignments_star_equals_fn_assign = "\0fn-assign" in expressions_assignments_star_equals {
  type phrase_types_callable
  action host "fn.assignment.emit-multiply"
}

phrase expressions_assignments_plus_equals_fn_assign = "\0fn-assign" in expressions_assignments_plus_equals {
  type phrase_types_callable
  action host "fn.assignment.emit-add"
}

phrase expressions_assignments_minus_equals_fn_assign = "\0fn-assign" in expressions_assignments_minus_equals {
  type phrase_types_callable
  action host "fn.assignment.emit-subtract"
}

phrase expressions_assignments_slash_equals_fn_assign = "\0fn-assign" in expressions_assignments_slash_equals {
  type phrase_types_callable
  action host "fn.assignment.emit-divide"
}

phrase expressions_assignments_equals_fn_assign = "\0fn-assign" in expressions_assignments_equals {
  type phrase_types_callable
  action host "fn.assignment.emit-move"
}

phrase expressions_infix_not_equal_fn_emit = "\0fn-emit" in expressions_infix_not_equal {
  type phrase_types_callable
  action host "fn.operator.emit-not-equal"
}

phrase expressions_infix_not_equal_fn_infer = "\0fn-infer" in expressions_infix_not_equal {
  type phrase_types_callable
  action host "fn.operator.infer-integer"
}

phrase expressions_infix_percent_fn_emit = "\0fn-emit" in expressions_infix_percent {
  type phrase_types_callable
  action host "fn.operator.emit-modulo"
}

phrase expressions_infix_percent_fn_infer = "\0fn-infer" in expressions_infix_percent {
  type phrase_types_callable
  action host "fn.operator.infer-left"
}

phrase expressions_infix_and_and_fn_emit = "\0fn-emit" in expressions_infix_and_and {
  type phrase_types_callable
  action host "fn.operator.emit-and"
}

phrase expressions_infix_and_and_fn_infer = "\0fn-infer" in expressions_infix_and_and {
  type phrase_types_callable
  action host "fn.operator.infer-integer"
}

phrase expressions_infix_star_fn_emit = "\0fn-emit" in expressions_infix_star {
  type phrase_types_callable
  action host "fn.operator.emit-multiply"
}

phrase expressions_infix_star_fn_infer = "\0fn-infer" in expressions_infix_star {
  type phrase_types_callable
  action host "fn.operator.infer-left"
}

phrase expressions_infix_plus_fn_emit = "\0fn-emit" in expressions_infix_plus {
  type phrase_types_callable
  action host "fn.operator.emit-add"
}

phrase expressions_infix_plus_fn_infer = "\0fn-infer" in expressions_infix_plus {
  type phrase_types_callable
  action host "fn.operator.infer-left"
}

phrase expressions_infix_minus_fn_emit = "\0fn-emit" in expressions_infix_minus {
  type phrase_types_callable
  action host "fn.operator.emit-subtract"
}

phrase expressions_infix_minus_fn_infer = "\0fn-infer" in expressions_infix_minus {
  type phrase_types_callable
  action host "fn.operator.infer-left"
}

phrase expressions_infix_slash_fn_emit = "\0fn-emit" in expressions_infix_slash {
  type phrase_types_callable
  action host "fn.operator.emit-divide"
}

phrase expressions_infix_slash_fn_infer = "\0fn-infer" in expressions_infix_slash {
  type phrase_types_callable
  action host "fn.operator.infer-left"
}

phrase expressions_infix_less_fn_emit = "\0fn-emit" in expressions_infix_less {
  type phrase_types_callable
  action host "fn.operator.emit-less"
}

phrase expressions_infix_less_fn_infer = "\0fn-infer" in expressions_infix_less {
  type phrase_types_callable
  action host "fn.operator.infer-integer"
}

phrase expressions_infix_less_equal_fn_emit = "\0fn-emit" in expressions_infix_less_equal {
  type phrase_types_callable
  action host "fn.operator.emit-less-equal"
}

phrase expressions_infix_less_equal_fn_infer = "\0fn-infer" in expressions_infix_less_equal {
  type phrase_types_callable
  action host "fn.operator.infer-integer"
}

phrase expressions_infix_equal_equal_fn_emit = "\0fn-emit" in expressions_infix_equal_equal {
  type phrase_types_callable
  action host "fn.operator.emit-equal"
}

phrase expressions_infix_equal_equal_fn_infer = "\0fn-infer" in expressions_infix_equal_equal {
  type phrase_types_callable
  action host "fn.operator.infer-integer"
}

phrase expressions_infix_greater_fn_emit = "\0fn-emit" in expressions_infix_greater {
  type phrase_types_callable
  action host "fn.operator.emit-greater"
}

phrase expressions_infix_greater_fn_infer = "\0fn-infer" in expressions_infix_greater {
  type phrase_types_callable
  action host "fn.operator.infer-integer"
}

phrase expressions_infix_greater_equal_fn_emit = "\0fn-emit" in expressions_infix_greater_equal {
  type phrase_types_callable
  action host "fn.operator.emit-greater-equal"
}

phrase expressions_infix_greater_equal_fn_infer = "\0fn-infer" in expressions_infix_greater_equal {
  type phrase_types_callable
  action host "fn.operator.infer-integer"
}

phrase expressions_infix_or_or_fn_emit = "\0fn-emit" in expressions_infix_or_or {
  type phrase_types_callable
  action host "fn.operator.emit-or"
}

phrase expressions_infix_or_or_fn_infer = "\0fn-infer" in expressions_infix_or_or {
  type phrase_types_callable
  action host "fn.operator.infer-integer"
}

phrase expressions_prefix_not_fn_emit = "\0fn-emit" in expressions_prefix_not {
  type phrase_types_callable
  action host "fn.operator.emit-not"
}

phrase expressions_prefix_not_fn_infer = "\0fn-infer" in expressions_prefix_not {
  type phrase_types_callable
  action host "fn.operator.infer-integer"
}

phrase expressions_prefix_plus_fn_emit = "\0fn-emit" in expressions_prefix_plus {
  type phrase_types_callable
  action host "fn.operator.emit-positive"
}

phrase expressions_prefix_plus_fn_infer = "\0fn-infer" in expressions_prefix_plus {
  type phrase_types_callable
  action host "fn.operator.infer-left"
}

phrase expressions_prefix_minus_fn_emit = "\0fn-emit" in expressions_prefix_minus {
  type phrase_types_callable
  action host "fn.operator.emit-negative"
}

phrase expressions_prefix_minus_fn_infer = "\0fn-infer" in expressions_prefix_minus {
  type phrase_types_callable
  action host "fn.operator.infer-left"
}
