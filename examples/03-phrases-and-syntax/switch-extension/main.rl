// =============================================================================
// RecurLoop - source-defined switch / case / default / finally
//
// This example adds a complete switch-family syntax to `fn` entirely from .rl.
// No C++ parser support for switch/case/default/finally is required.
//
// Syntax:
//
//   switch expression {
//       case value {
//           ...
//           break
//       }
//       case other {
//           ...
//           continue
//       }
//       default {
//           ...
//           break
//       }
//       finally {
//           ...
//       }
//   }
//
// Semantics used by this language extension:
//   - the switch expression is evaluated exactly once;
//   - case expressions are evaluated for matching before any case body runs;
//   - execution starts at the first matching case;
//   - default is the start point when no case matches;
//   - no break means C/C++-style fallthrough;
//   - `break` exits the switch, not an enclosing loop;
//   - `continue` continues the nearest enclosing real while loop;
//   - `finally` runs once after normal completion, break, or continue;
//   - case/default/finally are parsed by the .rl rewrite and never reach the
//     ordinary fn parser as keywords.
//
// The current base language image does not expose `break` / `continue` spellings,
// but their fn compiler behaviors are still present. This example re-exposes the
// statement spellings below, then uses a one-iteration internal loop so native
// break has proper switch semantics. Switch-level continue is rewritten to exit
// that internal loop, run finally, and then continue the enclosing real loop.
// =============================================================================

link shared "c"
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

let SwitchSyntax = []

let SwitchSyntax:is_space = fn (byte:u8) -> i64 {
    if byte == 32 || byte == 9 || byte == 10 || byte == 13 {
        return 1
    }
    return 0
}

let SwitchSyntax:is_ident = fn (byte:u8) -> i64 {
    if byte >= 48 && byte <= 57 { return 1 }
    if byte >= 65 && byte <= 90 { return 1 }
    if byte >= 97 && byte <= 122 { return 1 }
    if byte == 95 { return 1 }
    return 0
}

let SwitchSyntax:word_at = fn (source:u8*, position:i64, limit:i64, word:u8*, length:i64) -> i64 {
    if position < 0 || position + length > limit {
        return 0
    }
    if position > 0 && SwitchSyntax:is_ident(source[position - 1]) {
        return 0
    }
    var i = 0
    while i < length {
        if source[position + i] != word[i] {
            return 0
        }
        i += 1
    }
    if position + length < limit && SwitchSyntax:is_ident(source[position + length]) {
        return 0
    }
    return 1
}

let SwitchSyntax:skip_string = fn (source:u8*, position:i64, limit:i64, quote:u8) -> i64 {
    var i = position + 1
    while i < limit {
        if source[i] == 92 {
            i += 2
        } else {
            if source[i] == quote {
                return i + 1
            }
            i += 1
        }
    }
    return limit
}

let SwitchSyntax:skip_line_comment = fn (source:u8*, position:i64, limit:i64) -> i64 {
    var i = position + 2
    while i < limit && source[i] != 10 {
        i += 1
    }
    return i
}

let SwitchSyntax:skip_block_comment = fn (source:u8*, position:i64, limit:i64) -> i64 {
    var i = position + 2
    while i + 1 < limit {
        if source[i] == 42 && source[i + 1] == 47 {
            return i + 2
        }
        i += 1
    }
    return limit
}

let SwitchSyntax:skip_trivia = fn (source:u8*, position:i64, limit:i64) -> i64 {
    var i = position
    var again = 1
    while again {
        again = 0
        while i < limit && SwitchSyntax:is_space(source[i]) {
            i += 1
        }
        if i + 1 < limit && source[i] == 47 && source[i + 1] == 47 {
            i = SwitchSyntax:skip_line_comment(source, i, limit)
            again = 1
        } else {
            if i + 1 < limit && source[i] == 47 && source[i + 1] == 42 {
                i = SwitchSyntax:skip_block_comment(source, i, limit)
                again = 1
            }
        }
    }
    return i
}

let SwitchSyntax:trim_left = fn (source:u8*, start:i64, finish:i64) -> i64 {
    var i = start
    while i < finish && SwitchSyntax:is_space(source[i]) {
        i += 1
    }
    return i
}

let SwitchSyntax:trim_right = fn (source:u8*, start:i64, finish:i64) -> i64 {
    var i = finish
    while i > start && SwitchSyntax:is_space(source[i - 1]) {
        i -= 1
    }
    return i
}

// Find the next top-level '{'. Parentheses and brackets in an expression are
// balanced, and braces/quotes inside strings and comments are ignored.
let SwitchSyntax:find_header_block = fn (source:u8*, position:i64, limit:i64) -> i64 {
    var i = position
    var parens = 0
    var brackets = 0
    while i < limit {
        if source[i] == 34 || source[i] == 39 {
            i = SwitchSyntax:skip_string(source, i, limit, source[i])
        } else {
            if i + 1 < limit && source[i] == 47 && source[i + 1] == 47 {
                i = SwitchSyntax:skip_line_comment(source, i, limit)
            } else {
                if i + 1 < limit && source[i] == 47 && source[i + 1] == 42 {
                    i = SwitchSyntax:skip_block_comment(source, i, limit)
                } else {
                    if source[i] == 40 { parens += 1 }
                    else if source[i] == 41 { parens -= 1 }
                    else if source[i] == 91 { brackets += 1 }
                    else if source[i] == 93 { brackets -= 1 }
                    else if source[i] == 123 && parens == 0 && brackets == 0 {
                        return i
                    }
                    i += 1
                }
            }
        }
    }
    return -1
}

let SwitchSyntax:find_block_end = fn (source:u8*, open:i64, limit:i64) -> i64 {
    var i = open + 1
    var depth = 1
    while i < limit {
        if source[i] == 34 || source[i] == 39 {
            i = SwitchSyntax:skip_string(source, i, limit, source[i])
        } else {
            if i + 1 < limit && source[i] == 47 && source[i + 1] == 47 {
                i = SwitchSyntax:skip_line_comment(source, i, limit)
            } else {
                if i + 1 < limit && source[i] == 47 && source[i + 1] == 42 {
                    i = SwitchSyntax:skip_block_comment(source, i, limit)
                } else {
                    if source[i] == 123 {
                        depth += 1
                    } else if source[i] == 125 {
                        depth -= 1
                        if depth == 0 {
                            return i
                        }
                    }
                    i += 1
                }
            }
        }
    }
    return -1
}

// Clause parser. kind: 1=case, 2=default, 3=finally.
// Returns the position immediately after the clause block, or -1 on failure.
let SwitchSyntax:clause = fn (
    source:u8*, position:i64, limit:i64,
    kind:i64*, header_start:i64*, header_end:i64*, body_start:i64*, body_end:i64*
) -> i64 {
    var i = SwitchSyntax:skip_trivia(source, position, limit)
    if i >= limit {
        return limit
    }

    var word_bytes = 0
    if SwitchSyntax:word_at(source, i, limit, "case", 4) {
        kind[0] = 1
        word_bytes = 4
    } else if SwitchSyntax:word_at(source, i, limit, "default", 7) {
        kind[0] = 2
        word_bytes = 7
    } else if SwitchSyntax:word_at(source, i, limit, "finally", 7) {
        kind[0] = 3
        word_bytes = 7
    } else {
        return -1
    }

    i += word_bytes
    let open = SwitchSyntax:find_header_block(source, i, limit)
    if open < 0 {
        return -1
    }
    let close = SwitchSyntax:find_block_end(source, open, limit)
    if close < 0 {
        return -1
    }

    header_start[0] = SwitchSyntax:trim_left(source, i, open)
    header_end[0] = SwitchSyntax:trim_right(source, header_start[0], open)
    body_start[0] = open + 1
    body_end[0] = close

    if kind[0] == 1 {
        if header_start[0] >= header_end[0] {
            return -1
        }
    } else {
        if header_start[0] != header_end[0] {
            return -1
        }
    }

    return close + 1
}

// Emit a case/default body while rewriting only switch-level `continue`.
// A continue inside a nested while is left untouched and therefore continues
// that nested loop normally. Nested switch/fn blocks are also left for their
// own parser/rewrite pass. The function returns the number of rewritten
// switch-level continue statements.
let SwitchSyntax:emit_body = fn (state:Context*, source:u8*, start:i64, finish:i64) -> i64 {
    var i = start
    var segment = start
    var rewritten = 0

    while i < finish {
        if source[i] == 34 || source[i] == 39 {
            i = SwitchSyntax:skip_string(source, i, finish, source[i])
        } else {
            if i + 1 < finish && source[i] == 47 && source[i + 1] == 47 {
                i = SwitchSyntax:skip_line_comment(source, i, finish)
            } else {
                if i + 1 < finish && source[i] == 47 && source[i + 1] == 42 {
                    i = SwitchSyntax:skip_block_comment(source, i, finish)
                } else {
                    // Do not steal continue from a nested loop, nested switch,
                    // or nested function literal. Copy the entire construct.
                    var nested = 0
                    var word_bytes = 0
                    if SwitchSyntax:word_at(source, i, finish, "while", 5) {
                        nested = 1
                        word_bytes = 5
                    } else if SwitchSyntax:word_at(source, i, finish, "switch", 6) {
                        nested = 1
                        word_bytes = 6
                    } else if SwitchSyntax:word_at(source, i, finish, "fn", 2) {
                        nested = 1
                        word_bytes = 2
                    }

                    if nested {
                        let open = SwitchSyntax:find_header_block(source, i + word_bytes, finish)
                        if open >= 0 {
                            let close = SwitchSyntax:find_block_end(source, open, finish)
                            if close >= 0 {
                                i = close + 1
                            } else {
                                i += word_bytes
                            }
                        } else {
                            i += word_bytes
                        }
                    } else if SwitchSyntax:word_at(source, i, finish, "continue", 8) {
                        if i > segment {
                            context:syntax:emit(state, source, segment, i - segment)
                        }
                        context:syntax:emit(state, "__rl_switch_continue = 1\nbreak")
                        rewritten += 1
                        i += 8
                        segment = i
                    } else {
                        i += 1
                    }
                }
            }
        }
    }

    if finish > segment {
        context:syntax:emit(state, source, segment, finish - segment)
    }
    return rewritten
}

// Because the current language does not need a general string builder for
// syntax expansion, these helpers stream generated source directly into the
// syntax output buffer.
let SwitchSyntax:emit_slice = fn (state:Context*, source:u8*, start:i64, finish:i64) -> void {
    if finish > start {
        context:syntax:emit(state, source, start, finish - start)
    }
}

let SwitchSyntax:error = fn (state:Context*, message:u8*) -> void {
    context:diagnostic:error:at(
        state,
        context:syntax:path(state),
        context:syntax:line(state),
        context:syntax:position(state),
        message
    )
}

// Re-expose the fn statement spellings. The current compiler dispatches the
// statement behavior by spelling once a phrase with statement syntax exists.
// Inheriting from `return` supplies that statement-syntax phrase shape; inside
// compiled functions `break` and `continue` then select their native behaviors.
let break = <return>
let continue = <return>

let switch = phrase {
    type = <phrase-types:elaborate>
    rewrite = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let source = context:syntax:data(state)
        let bytes = context:syntax:bytes(state)

        let switch_open = SwitchSyntax:find_header_block(source, 0, bytes)
        if switch_open < 0 {
            SwitchSyntax:error(state, "switch expects an expression followed by a block")
            return
        }
        let switch_close = SwitchSyntax:find_block_end(source, switch_open, bytes)
        if switch_close < 0 {
            SwitchSyntax:error(state, "switch block is not closed")
            return
        }

        let expr_start = SwitchSyntax:trim_left(source, 0, switch_open)
        let expr_end = SwitchSyntax:trim_right(source, expr_start, switch_open)
        if expr_start >= expr_end {
            SwitchSyntax:error(state, "switch expects a non-empty expression")
            return
        }

        // Validate the whole clause list first. This prevents partially emitted
        // syntax when an invalid clause is encountered.
        var position = switch_open + 1
        var default_count = 0
        var finally_count = 0
        var finally_body_start = 0
        var finally_body_end = 0
        var clauses = 0
        while SwitchSyntax:skip_trivia(source, position, switch_close) < switch_close {
            var kind = 0
            var hs = 0
            var he = 0
            var bs = 0
            var be = 0
            let next = SwitchSyntax:clause(source, position, switch_close, &kind, &hs, &he, &bs, &be)
            if next < 0 {
                SwitchSyntax:error(state, "switch expects case/default/finally clauses")
                return
            }
            if kind == 2 {
                default_count += 1
                if default_count > 1 {
                    SwitchSyntax:error(state, "switch allows only one default clause")
                    return
                }
            }
            if kind == 3 {
                finally_count += 1
                finally_body_start = bs
                finally_body_end = be
                if finally_count > 1 {
                    SwitchSyntax:error(state, "switch allows only one finally clause")
                    return
                }
                // finally is intentionally required to be the final clause.
                if SwitchSyntax:skip_trivia(source, next, switch_close) != switch_close {
                    SwitchSyntax:error(state, "finally must be the last switch clause")
                    return
                }
            }
            clauses += 1
            position = next
        }

        if clauses == 0 {
            SwitchSyntax:error(state, "switch requires at least one case or default clause")
            return
        }

        // A lexical `if 1` is used only to give generated locals their own scope.
        context:syntax:emit(state, "if 1 {\n")
        context:syntax:emit(state, "var __rl_switch_continue = 0\n")
        context:syntax:emit(state, "while 1 {\n")
        context:syntax:emit(state, "let __rl_switch_value = (")
        SwitchSyntax:emit_slice(state, source, expr_start, expr_end)
        context:syntax:emit(state, ")\n")
        context:syntax:emit(state, "var __rl_switch_matched = 0\n")
        context:syntax:emit(state, "var __rl_switch_active = 0\n")

        // Pass 1: determine whether any case matches. This makes default work
        // correctly even when it appears before a later matching case.
        position = switch_open + 1
        while SwitchSyntax:skip_trivia(source, position, switch_close) < switch_close {
            var kind = 0
            var hs = 0
            var he = 0
            var bs = 0
            var be = 0
            let next = SwitchSyntax:clause(source, position, switch_close, &kind, &hs, &he, &bs, &be)
            if kind == 1 {
                context:syntax:emit(state, "if __rl_switch_value == (")
                SwitchSyntax:emit_slice(state, source, hs, he)
                context:syntax:emit(state, ") { __rl_switch_matched = 1 }\n")
            }
            position = next
        }

        // Pass 2: execute from the matching label onward. The generated
        // one-iteration while gives native `break` the same target a C/C++
        // switch would have. A switch-level continue is rewritten by emit_body
        // into a flag + break, then propagated after finally.
        var has_continue = 0
        position = switch_open + 1
        while SwitchSyntax:skip_trivia(source, position, switch_close) < switch_close {
            var kind = 0
            var hs = 0
            var he = 0
            var bs = 0
            var be = 0
            let next = SwitchSyntax:clause(source, position, switch_close, &kind, &hs, &he, &bs, &be)

            if kind == 1 {
                context:syntax:emit(state, "if __rl_switch_active || __rl_switch_value == (")
                SwitchSyntax:emit_slice(state, source, hs, he)
                context:syntax:emit(state, ") {\n")
                context:syntax:emit(state, "__rl_switch_active = 1\n")
                if SwitchSyntax:emit_body(state, source, bs, be) > 0 {
                    has_continue = 1
                }
                context:syntax:emit(state, "\n}\n")
            } else if kind == 2 {
                context:syntax:emit(state, "if __rl_switch_active || __rl_switch_matched == 0 {\n")
                context:syntax:emit(state, "__rl_switch_active = 1\n")
                if SwitchSyntax:emit_body(state, source, bs, be) > 0 {
                    has_continue = 1
                }
                context:syntax:emit(state, "\n}\n")
            }
            position = next
        }

        // No case break was taken: leave the internal one-iteration loop.
        context:syntax:emit(state, "break\n}\n")

        if finally_count == 1 {
            SwitchSyntax:emit_slice(state, source, finally_body_start, finally_body_end)
            context:syntax:emit(state, "\n")
        }
        if has_continue {
            context:syntax:emit(state, "if __rl_switch_continue { continue }\n")
        }
        context:syntax:emit(state, "}\n")

        // Consume the complete original switch spelling from the syntax input.
        context:syntax:advance(state, switch_close + 1)
    }
}

// =============================================================================
// Usage tests
// =============================================================================

let direct_switch = fn (value:i64, finalized:i64*) -> i64 {
    var result = 0
    switch value {
        case 1 {
            result = 10
            break
        }
        case 2 {
            result = 20
            break
        }
        case 3 {
            result = 30
            break
        }
        default {
            result = -1
            break
        }
        finally {
            finalized[0] += 1
        }
    }
    return result
}

// C/C++-style fallthrough: case 10 has no break, so case 20 runs too.
let fallthrough_switch = fn (value:i64, finalized:i64*) -> i64 {
    var result = 0
    switch value {
        case 10 {
            result += 10
        }
        case 20 {
            result += 20
            break
        }
        case 30 {
            result += 30
        }
        case 40 {
            result += 40
            break
        }
        default {
            result = -1
            break
        }
        finally {
            result += 1000
            finalized[0] += 1
        }
    }
    return result
}

// Real C++-style continue: it skips the remainder of the enclosing while
// iteration, while finally still executes first.
let continue_outer_loop = fn (finalized:i64*) -> i64 {
    var i = 0
    var result = 0
    while i < 5 {
        i += 1
        switch i {
            case 2 {
                result += 20
                continue
            }
            case 4 {
                result += 40
                break
            }
            default {
                result += i
                break
            }
            finally {
                finalized[0] += 1
            }
        }
        result += 100
    }
    return result
}

// A continue in a nested while must remain owned by that nested loop, not by
// the switch rewrite.
let nested_loop_control = fn () -> i64 {
    var result = 0
    switch 7 {
        case 7 {
            var i = 0
            while i < 4 {
                i += 1
                if i == 2 {
                    continue
                }
                result += i
            }
            break
        }
        default {
            result = -1
            break
        }
    }
    return result
}

// default may occur before a later case. A later match must win over default.
let default_in_middle = fn (value:i64) -> i64 {
    var result = 0
    switch value {
        case 1 {
            result = 10
            break
        }
        default {
            result = 50
        }
        case 9 {
            result += 9
            break
        }
        finally {
            result += 100
        }
    }
    return result
}

// Nested switch proves that generated locals are lexically scoped and that the
// emitted inner switch is expanded on a later syntax pass.
let nested_switch = fn (group:i64, value:i64, finalized:i64*) -> i64 {
    var result = 0
    switch group {
        case 1 {
            switch value {
                case 10 {
                    result = 110
                    break
                }
                case 20 {
                    result = 120
                    break
                }
                default {
                    result = 199
                    break
                }
                finally {
                    finalized[0] += 10
                }
            }
            break
        }
        case 2 {
            result = 200 + value
            break
        }
        default {
            result = -1
            break
        }
        finally {
            finalized[0] += 1
        }
    }
    return result
}

let verify_switch_extension = fn () -> i64 {
    var finalized = 0
    if direct_switch(1, &finalized) != 10 { return 0 }
    if direct_switch(3, &finalized) != 30 { return 0 }
    if direct_switch(99, &finalized) != -1 { return 0 }
    if finalized != 3 { return 0 }

    finalized = 0
    if fallthrough_switch(10, &finalized) != 1030 { return 0 }
    if fallthrough_switch(20, &finalized) != 1020 { return 0 }
    if fallthrough_switch(30, &finalized) != 1070 { return 0 }
    if fallthrough_switch(40, &finalized) != 1040 { return 0 }
    if fallthrough_switch(99, &finalized) != 999 { return 0 }
    if finalized != 5 { return 0 }

    finalized = 0
    if continue_outer_loop(&finalized) != 469 { return 0 }
    if finalized != 5 { return 0 }
    if nested_loop_control() != 8 { return 0 }

    if default_in_middle(1) != 110 { return 0 }
    if default_in_middle(9) != 109 { return 0 }
    if default_in_middle(77) != 159 { return 0 }

    finalized = 0
    if nested_switch(1, 20, &finalized) != 120 { return 0 }
    if finalized != 11 { return 0 }
    finalized = 0
    if nested_switch(2, 7, &finalized) != 207 { return 0 }
    if finalized != 1 { return 0 }
    finalized = 0
    if nested_switch(9, 7, &finalized) != -1 { return 0 }
    if finalized != 1 { return 0 }
    return 1
}

assert verify_switch_extension() == 1

emit executable "/tmp/recurloop-switch-case-full" switch_case_main = fn (argc:i64, argv:u8**) -> i64 {
    var final_count = 0

    let direct = direct_switch(2, &final_count)
    let fallthrough = fallthrough_switch(10, &final_count)
    let implicit_second = fallthrough_switch(30, &final_count)
    let continued_loop = continue_outer_loop(&final_count)
    let nested_loop = nested_loop_control()
    let fallback = default_in_middle(77)
    let nested = nested_switch(1, 20, &final_count)

    printf("RecurLoop source-defined switch/case example\n")
    printf("direct case:              %lld\n", direct)
    printf("implicit fallthrough:      %lld\n", fallthrough)
    printf("second fallthrough:        %lld\n", implicit_second)
    printf("continue outer loop:       %lld\n", continued_loop)
    printf("nested-loop continue:      %lld\n", nested_loop)
    printf("default in middle:         %lld\n", fallback)
    printf("nested switch:             %lld\n", nested)
    printf("finally executions:        %lld\n", final_count)

    if direct != 20 { return 1 }
    if fallthrough != 1030 { return 2 }
    if implicit_second != 1070 { return 3 }
    if continued_loop != 469 { return 4 }
    if nested_loop != 8 { return 5 }
    if fallback != 159 { return 6 }
    if nested != 120 { return 7 }
    if final_count != 19 { return 8 }

    printf("all switch/case/default/finally/break/continue checks passed\n")
    return 0
}
debug:stats
