// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:logical_not = [
    symbol = phrase { payload = "!" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
!expression
```

Negates a truth value."
    }
]

let Docs:Pages:not_equal = [
    symbol = phrase { payload = "!=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left != right
```

Tests inequality."
    }
]

let Docs:Pages:remainder = [
    symbol = phrase { payload = "%" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left % right
```

Computes the remainder."
    }
]

let Docs:Pages:assign_remainder = [
    symbol = phrase { payload = "%=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target %= expression
```

Applies `%` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:address_and = [
    symbol = phrase { payload = "&" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
&target
left & right
```

In a compiled function, `&target` takes an address. Between integers, `&` combines bits with AND."
    }
]

let Docs:Pages:logical_and = [
    symbol = phrase { payload = "&&" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left && right
```

Logical AND; skips the right operand when the left is false."
    }
]

let Docs:Pages:phrase = [
    symbol = phrase { payload = "&=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target &= expression
```

Applies `&` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:multiply = [
    symbol = phrase { payload = "*" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left * right
*pointer
Type*
```

Multiplies numbers, dereferences a native pointer, or forms a pointer type, depending on position."
    }
]

let Docs:Pages:assign_multiply = [
    symbol = phrase { payload = "*=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target *= expression
```

Applies `*` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:add = [
    symbol = phrase { payload = "+" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left + right
+expression
```

Adds numbers or concatenates runtime strings. Prefix `+` leaves a number unchanged."
    }
]

let Docs:Pages:assign_add = [
    symbol = phrase { payload = "+=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target += expression
```

Applies `+` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:subtract = [
    symbol = phrase { payload = "-" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left - right
-expression
```

Subtracts numbers. Prefix `-` negates a number."
    }
]

let Docs:Pages:assign_subtract = [
    symbol = phrase { payload = "-=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target -= expression
```

Applies `-` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:bss = [
    symbol = phrase { payload = ".bss" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
.bss
```

Selects the uninitialized data section in an `asm` block."
    }
]

let Docs:Pages:data = [
    symbol = phrase { payload = ".data" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
.data
```

Selects the writable initialized data section in an `asm` block."
    }
]

let Docs:Pages:rodata = [
    symbol = phrase { payload = ".rodata" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
.rodata
```

Selects the read-only data section in an `asm` block."
    }
]

let Docs:Pages:text = [
    symbol = phrase { payload = ".text" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
.text
```

Selects the executable instruction section in an `asm` block."
    }
]

let Docs:Pages:divide = [
    symbol = phrase { payload = "/" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left / right
```

Divides numeric operands."
    }
]

let Docs:Pages:assign_divide = [
    symbol = phrase { payload = "/=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target /= expression
```

Applies `/` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:baseline = [
    symbol = phrase { payload = ":baseline" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:baseline
```

Resets the session to the project baseline generation."
    }
]

let Docs:Pages:cache = [
    symbol = phrase { payload = ":cache" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:cache
```

Enables linked per-source project image caching for this session."
    }
]

let Docs:Pages:cache_dependencies = [
    symbol = phrase { payload = ":cache-dependencies" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:cache-dependencies
```

Lists dependencies recorded by the project module cache."
    }
]

let Docs:Pages:cache_exact = [
    symbol = phrase { payload = ":cache-exact" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:cache-exact
```

Starts the compatibility exact-cache mode used by older build clients; follows the project cache setting."
    }
]

let Docs:Pages:cache_status = [
    symbol = phrase { payload = ":cache-status" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:cache-status
```

Reports project module cache hit, miss and write counts."
    }
]

let Docs:Pages:exit = [
    symbol = phrase { payload = ":exit" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:exit
```

Alias of `:quit`; closes the current managed session."
    }
]

let Docs:Pages:generations = [
    symbol = phrase { payload = ":generations" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:generations
```

Shows project and session generation information."
    }
]

let Docs:Pages:help = [
    symbol = phrase { payload = ":help" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:help
```

Lists commands available in a managed session."
    }
]

let Docs:Pages:load = [
    symbol = phrase { payload = ":load" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:load \"path.rl\"
```

Executes a source file in the current session."
    }
]

let Docs:Pages:publish = [
    symbol = phrase { payload = ":publish" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:publish
```

Publishes the current session environment as a new project generation."
    }
]

let Docs:Pages:publish_commit = [
    symbol = phrase { payload = ":publish-commit" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:publish-commit
```

Publishes the generation prepared with `:publish-prepare`."
    }
]

let Docs:Pages:publish_prepare = [
    symbol = phrase { payload = ":publish-prepare" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:publish-prepare
```

Prepares a project generation for later publication with `:publish-commit`."
    }
]

let Docs:Pages:quit = [
    symbol = phrase { payload = ":quit" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:quit
```

Closes the current managed session."
    }
]

let Docs:Pages:refresh = [
    symbol = phrase { payload = ":refresh" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
:refresh
```

Adopts the latest published project environment in this session."
    }
]

let Docs:Pages:less_than = [
    symbol = phrase { payload = "<" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
<Namespace:phrase>
```

References an existing phrase. Use references for aliases, prototypes, actions or lexicons."
    }
]

let Docs:Pages:phrase_05812b1d = [
    symbol = phrase { payload = "<<" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left << right
```

Shifts integer bits left, discarding bits past the width."
    }
]

let Docs:Pages:phrase_d1191014 = [
    symbol = phrase { payload = "<<=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target <<= expression
```

Applies `<<` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:less_equal = [
    symbol = phrase { payload = "<=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left <= right
```

Tests whether the left operand is smaller or equal."
    }
]

let Docs:Pages:phrase_000ac1cc = [
    symbol = phrase { payload = "=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target = expression
```

Assigns a value to a mutable target."
    }
]

let Docs:Pages:equal = [
    symbol = phrase { payload = "==" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left == right
```

Tests equality."
    }
]

let Docs:Pages:greater_than = [
    symbol = phrase { payload = ">" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left > right
```

Tests whether the left operand is larger."
    }
]

let Docs:Pages:greater_equal = [
    symbol = phrase { payload = ">=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left >= right
```

Tests whether the left operand is larger or equal."
    }
]

let Docs:Pages:phrase_05812c25 = [
    symbol = phrase { payload = ">>" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left >> right
```

Shifts right arithmetically for signed types and logically for unsigned types."
    }
]

let Docs:Pages:phrase_d119972c = [
    symbol = phrase { payload = ">>=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target >>= expression
```

Applies `>>` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:phrase_000ac1ce = [
    symbol = phrase { payload = "?" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
pointer_expression?
```

Inside a pointer-returning compiled function, propagates a null pointer by returning null."
    }
]

let Docs:Pages:RecurLoopCompatibility_if_marker = [
    symbol = phrase { payload = "RecurLoopCompatibility:if_marker" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
if condition { ... } else { ... }
```

Runs the first block when the condition is true, otherwise the optional `else` block. Inside compiled functions, `else if` chains further conditions.

**Example**

```recurloop
if count > 0 { print \"ready\" } else { print \"empty\" }
```"
    }
]

let Docs:Pages:RecurLoopCompatibility_while_marker = [
    symbol = phrase { payload = "RecurLoopCompatibility:while_marker" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
while condition { ... }
```

Repeats the block while the condition is true. The condition is checked before each iteration.

**Example**

```recurloop
var n = 0
while n < 3 {
    print n
    n += 1
}
```"
    }
]

let Docs:Pages:RecurLoopHelp_assert_arguments_condition = [
    symbol = phrase { payload = "RecurLoopHelp:assert:arguments:condition" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "True means success; false stops execution with a diagnostic."
    }
]

let Docs:Pages:RecurLoopHelp_const_arguments_type = [
    symbol = phrase { payload = "RecurLoopHelp:const:arguments:type" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Optional native type."
    }
]

let Docs:Pages:RecurLoopHelp_const_arguments_value = [
    symbol = phrase { payload = "RecurLoopHelp:const:arguments:value" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Constant expression; the value cannot be reassigned."
    }
]

let Docs:Pages:RecurLoopHelp_emit_arguments_definition = [
    symbol = phrase { payload = "RecurLoopHelp:emit:arguments:definition" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "name = fn (...) -> type {...}; raw uses = hex {...}."
    }
]

let Docs:Pages:RecurLoopHelp_emit_arguments_path = [
    symbol = phrase { payload = "RecurLoopHelp:emit:arguments:path" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Destination file."
    }
]

let Docs:Pages:RecurLoopHelp_engine_arguments_path = [
    symbol = phrase { payload = "RecurLoopHelp:engine:arguments:path" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "An engine image (.rli). Export keeps phrases, docs and help."
    }
]

let Docs:Pages:RecurLoopHelp_fn_arguments_body = [
    symbol = phrase { payload = "RecurLoopHelp:fn:arguments:body" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Statements in braces. return supplies the result."
    }
]

let Docs:Pages:RecurLoopHelp_fn_arguments_parameters = [
    symbol = phrase { payload = "RecurLoopHelp:fn:arguments:parameters" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Comma-separated name:type pairs; leave empty for no parameters."
    }
]

let Docs:Pages:RecurLoopHelp_fn_arguments_result = [
    symbol = phrase { payload = "RecurLoopHelp:fn:arguments:result" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Return type; use void when no value is returned."
    }
]

let Docs:Pages:RecurLoopHelp_if_arguments_accepted = [
    symbol = phrase { payload = "RecurLoopHelp:if:arguments:accepted" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Code executed when the condition is true."
    }
]

let Docs:Pages:RecurLoopHelp_if_arguments_condition = [
    symbol = phrase { payload = "RecurLoopHelp:if:arguments:condition" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "An expression interpreted as true or false."
    }
]

let Docs:Pages:RecurLoopHelp_if_arguments_rejected = [
    symbol = phrase { payload = "RecurLoopHelp:if:arguments:rejected" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Optional else block executed when the condition is false."
    }
]

let Docs:Pages:RecurLoopHelp_include_arguments_path = [
    symbol = phrase { payload = "RecurLoopHelp:include:arguments:path" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Quoted path, relative to the including file."
    }
]

let Docs:Pages:RecurLoopHelp_let_arguments_definition = [
    symbol = phrase { payload = "RecurLoopHelp:let:arguments:definition" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "fn, phrase, a reference <name> or a dictionary [...]. Inside fn, let also binds expression values."
    }
]

let Docs:Pages:RecurLoopHelp_let_arguments_name = [
    symbol = phrase { payload = "RecurLoopHelp:let:arguments:name" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "New name; qualify it with a dictionary, e.g. Tools:say."
    }
]

let Docs:Pages:RecurLoopHelp_link_arguments_path = [
    symbol = phrase { payload = "RecurLoopHelp:link:arguments:path" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Library name for shared/library; filesystem path for object/archive/path."
    }
]

let Docs:Pages:RecurLoopHelp_module_arguments_symbol = [
    symbol = phrase { payload = "RecurLoopHelp:module:arguments:symbol" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "A native function or module name."
    }
]

let Docs:Pages:RecurLoopHelp_print_arguments_value = [
    symbol = phrase { payload = "RecurLoopHelp:print:arguments:value" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "An expression to display."
    }
]

let Docs:Pages:RecurLoopHelp_record_arguments_fields = [
    symbol = phrase { payload = "RecurLoopHelp:record:arguments:fields" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Fields as name:type pairs. Layout and alignment are calculated."
    }
]

let Docs:Pages:RecurLoopHelp_record_arguments_name = [
    symbol = phrase { payload = "RecurLoopHelp:record:arguments:name" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Name of the new type."
    }
]

let Docs:Pages:RecurLoopHelp_syntax_arguments_definition = [
    symbol = phrase { payload = "RecurLoopHelp:syntax:arguments:definition" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Captures <name:matcher>, [optional], (a | b); finish with => replacement, as <phrase> or action fn."
    }
]

let Docs:Pages:RecurLoopHelp_syntax_arguments_name = [
    symbol = phrase { payload = "RecurLoopHelp:syntax:arguments:name" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "New phrase name; extend preserves the previous syntax as fallback."
    }
]

let Docs:Pages:RecurLoopHelp_var_arguments_name = [
    symbol = phrase { payload = "RecurLoopHelp:var:arguments:name" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Name of the new variable."
    }
]

let Docs:Pages:RecurLoopHelp_var_arguments_type = [
    symbol = phrase { payload = "RecurLoopHelp:var:arguments:type" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Optional native type; inferred when omitted."
    }
]

let Docs:Pages:RecurLoopHelp_var_arguments_value = [
    symbol = phrase { payload = "RecurLoopHelp:var:arguments:value" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Initial value. Assignment may change it later."
    }
]

let Docs:Pages:RecurLoopHelp_while_arguments_body = [
    symbol = phrase { payload = "RecurLoopHelp:while:arguments:body" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Update the condition or use break to end the loop."
    }
]

let Docs:Pages:RecurLoopHelp_while_arguments_condition = [
    symbol = phrase { payload = "RecurLoopHelp:while:arguments:condition" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Checked before each iteration."
    }
]

let Docs:Pages:phrase_000ac1ea = [
    symbol = phrase { payload = "[" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
let Name = [ key = definition ... ]
```

Creates a nested phrase dictionary. Access a child with `Name:key`."
    }
]

let Docs:Pages:bit_xor = [
    symbol = phrase { payload = "^" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left ^ right
```

Combines integer bits with XOR."
    }
]

let Docs:Pages:phrase_05813c84 = [
    symbol = phrase { payload = "^=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target ^= expression
```

Applies `^` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:abi = [
    symbol = phrase { payload = "abi" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
abi name(property(...), ...)
```

Defines a calling convention. Select it on a function declaration with `abi name`. Built-ins include `sysv-amd64`, `microsoft-x64`, `cdecl-x86`, `stdcall-x86` and `fastcall-x86`.

**Example**

```recurloop
extern puts(text:u8*) -> i32 abi sysv-amd64
```"
    }
]

let Docs:Pages:abi_align = [
    symbol = phrase { payload = "abi:align" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
align(16)
```

Sets stack alignment in bytes inside an ABI declaration."
    }
]

let Docs:Pages:abi_cleanup = [
    symbol = phrase { payload = "abi:cleanup" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
cleanup(caller)
cleanup(callee)
```

Selects who removes stack arguments inside an ABI declaration."
    }
]

let Docs:Pages:abi_floating = [
    symbol = phrase { payload = "abi:floating" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
floating(xmm0, xmm1, ...)
```

Lists floating-point argument registers in order, inside an ABI declaration."
    }
]

let Docs:Pages:abi_floating_result = [
    symbol = phrase { payload = "abi:floating-result" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
floating-result(xmm0)
```

Selects the floating-point return register inside an ABI declaration."
    }
]

let Docs:Pages:abi_integer = [
    symbol = phrase { payload = "abi:integer" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
integer(rdi, rsi, ...)
```

Lists integer/pointer argument registers in order, inside `abi name(...)`."
    }
]

let Docs:Pages:abi_result = [
    symbol = phrase { payload = "abi:result" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
result(rax)
```

Selects the integer/pointer return register inside an ABI declaration."
    }
]

let Docs:Pages:abi_shadow = [
    symbol = phrase { payload = "abi:shadow" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
shadow(32)
```

Sets reserved caller shadow space in bytes inside an ABI declaration."
    }
]

let Docs:Pages:abi_stack = [
    symbol = phrase { payload = "abi:stack" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
stack(down)
stack(up)
```

Selects stack growth direction inside an ABI declaration."
    }
]

let Docs:Pages:alloc = [
    symbol = phrase { payload = "alloc" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
alloc(Type)
```

In a compiled function, allocates an object with `malloc` and returns `Type*`. Storage is uninitialized; check for a null pointer and release it with `free`.

**Example (inside fn)**

```recurloop
let point = alloc(Point)
if !point { return 1 }
defer free(cast(u8*, point))
```"
    }
]

let Docs:Pages:asm = [
    symbol = phrase { payload = "asm" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
asm {
    instruction operands
    ...
}
```

Assembles native instructions and labels. Use it as a `let` definition or after an `emit` directive.

**Example**

```recurloop
let answer = asm {
    mov rax, 42
    ret
}
```"
    }
]

let Docs:Pages:asm_bss = [
    symbol = phrase { payload = "asm:{:.bss" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
.bss
```

Selects the uninitialized data section in an `asm` block."
    }
]

let Docs:Pages:asm_data = [
    symbol = phrase { payload = "asm:{:.data" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
.data
```

Selects the writable initialized data section in an `asm` block."
    }
]

let Docs:Pages:asm_rodata = [
    symbol = phrase { payload = "asm:{:.rodata" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
.rodata
```

Selects the read-only data section in an `asm` block."
    }
]

let Docs:Pages:asm_section_alloc = [
    symbol = phrase { payload = "asm:{:.section:alloc" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
alloc(Type)
```

In a compiled function, allocates an object with `malloc` and returns `Type*`. Storage is uninitialized; check for a null pointer and release it with `free`.

**Example (inside fn)**

```recurloop
let point = alloc(Point)
if !point { return 1 }
defer free(cast(u8*, point))
```"
    }
]

let Docs:Pages:asm_section_merge = [
    symbol = phrase { payload = "asm:{:.section:merge" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
merge <lexicon>
merge \"fragment.rli\"
```

Merges a captured lexicon or exported lexicon fragment into the current dictionary."
    }
]

let Docs:Pages:asm_text = [
    symbol = phrase { payload = "asm:{:.text" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
.text
```

Selects the executable instruction section in an `asm` block."
    }
]

let Docs:Pages:asm_assembler_memory_expect = [
    symbol = phrase { payload = "asm:{:assembler-memory-expect:*" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left * right
*pointer
Type*
```

Multiplies numbers, dereferences a native pointer, or forms a pointer type, depending on position."
    }
]

let Docs:Pages:asm_assembler_memory_expect_a948f0b2 = [
    symbol = phrase { payload = "asm:{:assembler-memory-expect:+" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left + right
+expression
```

Adds numbers or concatenates runtime strings. Prefix `+` leaves a number unchanged."
    }
]

let Docs:Pages:asm_assembler_memory_expect_a948f0b4 = [
    symbol = phrase { payload = "asm:{:assembler-memory-expect:-" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left - right
-expression
```

Subtracts numbers. Prefix `-` negates a number."
    }
]

let Docs:Pages:asm_assembler_memory_register = [
    symbol = phrase { payload = "asm:{:assembler-memory-register:*" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left * right
*pointer
Type*
```

Multiplies numbers, dereferences a native pointer, or forms a pointer type, depending on position."
    }
]

let Docs:Pages:asm_assembler_memory_register_4e7e37e8 = [
    symbol = phrase { payload = "asm:{:assembler-memory-register:+" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left + right
+expression
```

Adds numbers or concatenates runtime strings. Prefix `+` leaves a number unchanged."
    }
]

let Docs:Pages:asm_assembler_memory_register_4e7e37ea = [
    symbol = phrase { payload = "asm:{:assembler-memory-register:-" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left - right
-expression
```

Subtracts numbers. Prefix `-` negates a number."
    }
]

let Docs:Pages:asm_assembler_memory_scale = [
    symbol = phrase { payload = "asm:{:assembler-memory-scale:*" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left * right
*pointer
Type*
```

Multiplies numbers, dereferences a native pointer, or forms a pointer type, depending on position."
    }
]

let Docs:Pages:asm_assembler_memory_scale_870eb6ef = [
    symbol = phrase { payload = "asm:{:assembler-memory-scale:+" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left + right
+expression
```

Adds numbers or concatenates runtime strings. Prefix `+` leaves a number unchanged."
    }
]

let Docs:Pages:asm_assembler_memory_scale_870eb6f1 = [
    symbol = phrase { payload = "asm:{:assembler-memory-scale:-" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left - right
-expression
```

Subtracts numbers. Prefix `-` negates a number."
    }
]

let Docs:Pages:asm_assembler_memory_term = [
    symbol = phrase { payload = "asm:{:assembler-memory-term:*" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left * right
*pointer
Type*
```

Multiplies numbers, dereferences a native pointer, or forms a pointer type, depending on position."
    }
]

let Docs:Pages:asm_assembler_memory_term_972f7745 = [
    symbol = phrase { payload = "asm:{:assembler-memory-term:+" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left + right
+expression
```

Adds numbers or concatenates runtime strings. Prefix `+` leaves a number unchanged."
    }
]

let Docs:Pages:asm_assembler_memory_term_972f7747 = [
    symbol = phrase { payload = "asm:{:assembler-memory-term:-" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left - right
-expression
```

Subtracts numbers. Prefix `-` negates a number."
    }
]

let Docs:Pages:asm_assembler_operand_size_bracket = [
    symbol = phrase { payload = "asm:{:assembler-operand-size-bracket:[" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
let Name = [ key = definition ... ]
```

Creates a nested phrase dictionary. Access a child with `Name:key`."
    }
]

let Docs:Pages:asm_assembler_operands = [
    symbol = phrase { payload = "asm:{:assembler-operands:[" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
let Name = [ key = definition ... ]
```

Creates a nested phrase dictionary. Access a child with `Name:key`."
    }
]

let Docs:Pages:asm_db = [
    symbol = phrase { payload = "asm:{:db" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
db value, ...
```

Emits 1-byte values in an `asm` block, using little-endian order."
    }
]

let Docs:Pages:asm_dd = [
    symbol = phrase { payload = "asm:{:dd" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
dd value, ...
```

Emits 4-byte values in an `asm` block, using little-endian order."
    }
]

let Docs:Pages:asm_dq = [
    symbol = phrase { payload = "asm:{:dq" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
dq value, ...
```

Emits 8-byte values in an `asm` block, using little-endian order."
    }
]

let Docs:Pages:asm_dw = [
    symbol = phrase { payload = "asm:{:dw" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
dw value, ...
```

Emits 2-byte values in an `asm` block, using little-endian order."
    }
]

let Docs:Pages:asm_invoke = [
    symbol = phrase { payload = "asm:{:invoke" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
invoke <phrase>
```

At top level, invokes the referenced phrase action. In an `asm` block, emits a native call to that action; typed functions may take arguments after the reference."
    }
]

let Docs:Pages:asm_resb = [
    symbol = phrase { payload = "asm:{:resb" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
resb count
```

Reserves `count` bytes in an assembler section; use `.bss` for uninitialized storage."
    }
]

let Docs:Pages:assembler = [
    symbol = phrase { payload = "assembler" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
asm {
    instruction operands
    ...
}
```

Assembles native instructions and labels. Use it as a `let` definition or after an `emit` directive.

**Example**

```recurloop
let answer = asm {
    mov rax, 42
    ret
}
```"
    }
]

let Docs:Pages:assert = [
    symbol = phrase { payload = "assert" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Fail when the condition is false.

```recurloop
assert condition
```

Checks a runtime condition and reports an error if it is false.

**Example**

```recurloop
assert answer == 42
```

## Syntax

```recurloop
<condition:expr>
```

## Example

```recurloop
assert 20 + 22 == 42
```

## Arguments

- ** ** — 
- **:** — 
- **condition** — True means success; false stops execution with a diagnostic."
    }
]

let Docs:Pages:break = [
    symbol = phrase { payload = "break" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
break
```

Leaves the nearest enclosing loop immediately."
    }
]

let Docs:Pages:cast = [
    symbol = phrase { payload = "cast" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
cast(Type, expression)
```

In a compiled function, explicitly converts an expression to the selected native type.

**Example (inside fn)**

```recurloop
let address = cast(u8*, &value)
```"
    }
]

let Docs:Pages:const = [
    symbol = phrase { payload = "const" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Create a constant.

```recurloop
const name = expression
```

Defines an immutable runtime value. In an `fn` body, an optional `:type` selects the native type.

**Example**

```recurloop
const answer = 6 * 7
```

## Syntax

```recurloop
<name:id> [\":\" <type:qualified-id>] \"=\" <value:expr>
```

## Example

```recurloop
const limit = 42
```

## Arguments

- ** ** — 
- **:** — 
- **type** — Optional native type.
- **value** — Constant expression; the value cannot be reassigned."
    }
]

let Docs:Pages:contains = [
    symbol = phrase { payload = "contains" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
contains(text, part)
```

Returns whether a runtime string contains `part`.

**Example**

```recurloop
contains(\"hello\", \"ell\")
```"
    }
]

let Docs:Pages:continue = [
    symbol = phrase { payload = "continue" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
continue
```

Skips the rest of the nearest loop body and checks its condition again."
    }
]

let Docs:Pages:db = [
    symbol = phrase { payload = "db" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
db value, ...
```

Emits 1-byte values in an `asm` block, using little-endian order."
    }
]

let Docs:Pages:dd = [
    symbol = phrase { payload = "dd" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
dd value, ...
```

Emits 4-byte values in an `asm` block, using little-endian order."
    }
]

let Docs:Pages:debug = [
    symbol = phrase { payload = "debug" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:stats
debug:run \"source.rl\"
debug:executable run \"path\"
```

Provides source and native debugging commands. Use `debug:break` to configure breakpoints before running."
    }
]

let Docs:Pages:debug_break = [
    symbol = phrase { payload = "debug:break" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:break phrase \"name\"
debug:break function \"name\"
debug:break line \"path.rl\":line
```

Adds a phrase, function or source-line breakpoint."
    }
]

let Docs:Pages:debug_break_function = [
    symbol = phrase { payload = "debug:break:function" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:break function \"name\"
```

Adds a breakpoint at a native function entry."
    }
]

let Docs:Pages:debug_break_line = [
    symbol = phrase { payload = "debug:break:line" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:break line \"path.rl\":line
```

Stops at a one-based source line. Example: `debug:break line \"main.rl\":12`."
    }
]

let Docs:Pages:debug_break_phrase = [
    symbol = phrase { payload = "debug:break:phrase" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:break phrase \"name\"
```

Stops when the named phrase is reached."
    }
]

let Docs:Pages:debug_breakpoints = [
    symbol = phrase { payload = "debug:breakpoints" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:breakpoints
```

Lists configured breakpoints and their identifiers."
    }
]

let Docs:Pages:debug_children = [
    symbol = phrase { payload = "debug:children" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:children \"variable.path\"
debug:children \"variable.path\", start, count
```

Lists native record fields or array elements. The default range starts at zero and takes up to 100 children; explicit count is limited to 1024."
    }
]

let Docs:Pages:debug_continue = [
    symbol = phrase { payload = "debug:continue" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:continue
```

Resumes execution until the next breakpoint or program exit."
    }
]

let Docs:Pages:debug_delete = [
    symbol = phrase { payload = "debug:delete" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:delete id
```

Deletes the breakpoint with the listed identifier."
    }
]

let Docs:Pages:debug_eval = [
    symbol = phrase { payload = "debug:eval" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:eval expression
```

Evaluates an expression in the current debugging context."
    }
]

let Docs:Pages:debug_executable = [
    symbol = phrase { payload = "debug:executable" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:executable run \"path\"
```

Starts a native executable under the debugger. Emit it with `emit executable debug` for source-level information."
    }
]

let Docs:Pages:debug_executable_run = [
    symbol = phrase { payload = "debug:executable:run" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:executable run \"path\"
```

Starts native debugging with the configured breakpoints."
    }
]

let Docs:Pages:debug_finish = [
    symbol = phrase { payload = "debug:finish" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:finish
```

Resumes until the current source scope or native function finishes."
    }
]

let Docs:Pages:debug_frame = [
    symbol = phrase { payload = "debug:frame" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:frame id
```

Selects a native call frame for variable inspection; frame identifiers start at zero."
    }
]

let Docs:Pages:debug_locals = [
    symbol = phrase { payload = "debug:locals" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:locals
```

Lists native local variables in the selected frame."
    }
]

let Docs:Pages:debug_next = [
    symbol = phrase { payload = "debug:next" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:next
```

Steps over the next phrase or native source statement."
    }
]

let Docs:Pages:debug_ping = [
    symbol = phrase { payload = "debug:ping" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:ping
```

Writes `pong`; useful for checking phrase aliases."
    }
]

let Docs:Pages:debug_registers = [
    symbol = phrase { payload = "debug:registers" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:registers
```

Displays native CPU registers."
    }
]

let Docs:Pages:debug_run = [
    symbol = phrase { payload = "debug:run" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:run \"path.rl\"
```

Executes source with phrase-aware debugging enabled."
    }
]

let Docs:Pages:debug_set = [
    symbol = phrase { payload = "debug:set" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:set name = expression
```

Writes a native scalar variable in the selected frame."
    }
]

let Docs:Pages:debug_stack = [
    symbol = phrase { payload = "debug:stack" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:stack
```

Lists native call frames and their identifiers."
    }
]

let Docs:Pages:debug_stats = [
    symbol = phrase { payload = "debug:stats" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:stats
```

Prints process CPU, memory and I/O metrics plus engine arena, JIT and timing statistics."
    }
]

let Docs:Pages:debug_step = [
    symbol = phrase { payload = "debug:step" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:step
```

Steps into the next phrase or native source statement."
    }
]

let Docs:Pages:debug_terminal = [
    symbol = phrase { payload = "debug:terminal" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:terminal \"device_path\"
```

Selects the terminal device for native application input and output."
    }
]

let Docs:Pages:debug_thread = [
    symbol = phrase { payload = "debug:thread" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:thread id
```

Selects a native thread using its listed identifier."
    }
]

let Docs:Pages:debug_threads = [
    symbol = phrase { payload = "debug:threads" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:threads
```

Lists threads in the native process."
    }
]

let Docs:Pages:debug_trace = [
    symbol = phrase { payload = "debug:trace" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:trace on
debug:trace off
```

Enables or disables phrase execution tracing."
    }
]

let Docs:Pages:debug_trace_off = [
    symbol = phrase { payload = "debug:trace:off" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:trace off
```

Disables phrase execution tracing."
    }
]

let Docs:Pages:debug_trace_on = [
    symbol = phrase { payload = "debug:trace:on" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:trace on
```

Enables phrase execution tracing."
    }
]

let Docs:Pages:debug_value = [
    symbol = phrase { payload = "debug:value" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:value \"variable.path\"
```

Displays a native variable or member from the selected frame. Example: `debug:value \"point.x\"`."
    }
]

let Docs:Pages:debug_where = [
    symbol = phrase { payload = "debug:where" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
debug:where
```

Shows the current execution location."
    }
]

let Docs:Pages:defer = [
    symbol = phrase { payload = "defer" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
defer cleanup_expression
```

In a compiled function, registers cleanup for exit. Deferred expressions run in reverse registration order, including when returning early.

**Example (inside fn)**

```recurloop
let buffer = alloc(u8[64])
defer free(buffer)
```"
    }
]

let Docs:Pages:dq = [
    symbol = phrase { payload = "dq" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
dq value, ...
```

Emits 8-byte values in an `asm` block, using little-endian order."
    }
]

let Docs:Pages:dw = [
    symbol = phrase { payload = "dw" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
dw value, ...
```

Emits 2-byte values in an `asm` block, using little-endian order."
    }
]

let Docs:Pages:else = [
    symbol = phrase { payload = "else" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
if condition { ... } else { ... }
```

Provides the alternative branch of `if`. Inside compiled functions, use `else if condition { ... }` for another condition."
    }
]

let Docs:Pages:emit = [
    symbol = phrase { payload = "emit" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Write native code or exact bytes.

```recurloop
emit executable \"path\" name = fn () -> i64 { ... }
emit object \"path.o\" name = fn (...) -> result { ... }
emit raw \"path.bin\" = hex { ... }
```

Writes a native executable, relocatable object or exact bytes. Add `debug` after `executable` to retain symbols and debugging metadata.

## Syntax

```recurloop
(executable [debug] | object | raw) <path:string> <definition:raw>
```

## Example

```recurloop
emit executable \"app\" app_main = fn () -> i64 { return 0 }
```

## Arguments

- ** ** — 
- **:** — 
- **definition** — name = fn (...) -> type {...}; raw uses = hex {...}.
- **path** — Destination file."
    }
]

let Docs:Pages:emit_executable = [
    symbol = phrase { payload = "emit:executable" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
emit executable \"path\" main = fn () -> i64 { ... }
emit executable debug \"path\" main = fn () -> i64 { ... }
```

Compiles and links a native executable. The `debug` form retains symbols and source/local information.

**Example**

```recurloop
emit executable \"./hello\" main = fn () -> i64 { return 0 }
```"
    }
]

let Docs:Pages:emit_executable_debug = [
    symbol = phrase { payload = "emit:executable:debug" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
emit executable debug \"path\" main = fn () -> i64 { ... }
```

Emits a native executable with symbols and source/local information for debugging."
    }
]

let Docs:Pages:emit_object = [
    symbol = phrase { payload = "emit:object" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
emit object \"path.o\" name = fn (...) -> result { ... }
```

Writes a relocatable native object. Link it into another output with `link object`.

**Example**

```recurloop
emit object \"add.o\" add = fn (a:i64, b:i64) -> i64 { return a + b }
```"
    }
]

let Docs:Pages:emit_raw = [
    symbol = phrase { payload = "emit:raw" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
emit raw \"path.bin\" = hex { byte ... }
```

Writes the generated bytes without an object or executable wrapper. Hex bytes use two hexadecimal digits.

**Example**

```recurloop
emit raw \"data.bin\" = hex { 52 4c 0a }
```"
    }
]

let Docs:Pages:ends_with = [
    symbol = phrase { payload = "ends_with" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
ends_with(text, suffix)
```

Returns whether a runtime string ends with `suffix`.

**Example**

```recurloop
ends_with(\"hello\", \"lo\")
```"
    }
]

let Docs:Pages:engine = [
    symbol = phrase { payload = "engine" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Load or save the language image.

```recurloop
engine import \"image.rli\"
engine export \"image.rli\"
```

Loads or saves a RecurLoop engine image containing phrases and their language definitions.

## Syntax

```recurloop
(import | export) <path:string>
```

## Example

```recurloop
engine export \"language.rli\"
```

## Arguments

- ** ** — 
- **:** — 
- **path** — An engine image (.rli). Export keeps phrases, docs and help."
    }
]

let Docs:Pages:engine_define = [
    symbol = phrase { payload = "engine:define" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
engine define {
    phrase_definitions
    ...
}
```

Replaces the engine using core-definition source. Intended for language bootstrap; ordinary programs extend the current engine with `let` and `syntax`."
    }
]

let Docs:Pages:engine_export = [
    symbol = phrase { payload = "engine:export" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
engine export \"image.rli\"
engine export <lexicon> \"fragment.rli\"
```

Saves the current engine or an isolated lexicon fragment. Use `engine import` for an engine and `merge` for a fragment."
    }
]

let Docs:Pages:engine_import = [
    symbol = phrase { payload = "engine:import" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
engine import \"image.rli\"
```

Loads an engine image into the current context. Place the import before source that uses its definitions."
    }
]

let Docs:Pages:exit_05617523 = [
    symbol = phrase { payload = "exit" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
exit
exit status
```

Stops source execution. Omit the status to use zero; a nonzero integer reports failure.

**Example**

```recurloop
exit 1
```"
    }
]

let Docs:Pages:extern = [
    symbol = phrase { payload = "extern" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
extern name(parameter:type, ...) -> result abi convention
```

Declares a function supplied by native code. Configure its library with `link` before calling it. A final `...` parameter declares a variadic function.

**Example**

```recurloop
link shared \"c\"
extern puts(text:u8*) -> i32 abi sysv-amd64
```"
    }
]

let Docs:Pages:false = [
    symbol = phrase { payload = "false" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
false
```

Boolean false literal."
    }
]

let Docs:Pages:fn = [
    symbol = phrase { payload = "fn" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Compile a typed function.

Compiles a typed function. Parameters use name:type; void returns no value. Omit the body to define a reusable signature. Call with name(arguments).

## Syntax

```recurloop
[<name:id>] \"(\" <parameters:raw> \")\" \"->\" <result:qualified-id> [<body:block>]
```

## Example

```recurloop
fn add(a:i64, b:i64) -> i64 { return a + b }
```

## Arguments

- ** ** — 
- **:** — 
- **body** — Statements in braces. return supplies the result.
- **parameters** — Comma-separated name:type pairs; leave empty for no parameters.
- **result** — Return type; use void when no value is returned."
    }
]

let Docs:Pages:forward = [
    symbol = phrase { payload = "forward" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
forward name(parameter:type, ...) -> result
```

Declares a function before its definition. The later `fn` must match the signature.

**Example**

```recurloop
forward odd(n:i64) -> i64
```"
    }
]

let Docs:Pages:function = [
    symbol = phrase { payload = "function" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
function name(parameter:type, ...) -> result abi convention
```

Attaches a typed call signature to an existing invokable phrase with a native module, such as one defined by `asm`. Use `fn` to write a new function."
    }
]

let Docs:Pages:hex = [
    symbol = phrase { payload = "hex" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
hex { byte ... }
```

Builds exact bytes from pairs of hexadecimal digits.

**Example**

```recurloop
let bytes = hex { 52 4c 0a }
```"
    }
]

let Docs:Pages:if = [
    symbol = phrase { payload = "if" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Execute a block when its condition is true.

```recurloop
if condition { ... } else { ... }
```

Runs the first block when the condition is true, otherwise the optional `else` block. Inside compiled functions, `else if` chains further conditions.

**Example**

```recurloop
if count > 0 { print \"ready\" } else { print \"empty\" }
```

## Syntax

```recurloop
<condition:expr> <accepted:block> [else <rejected:block>]
```

## Example

```recurloop
if count > 0 { print count }
```

## Arguments

- ** ** — 
- **:** — 
- **accepted** — Code executed when the condition is true.
- **condition** — An expression interpreted as true or false.
- **rejected** — Optional else block executed when the condition is false."
    }
]

let Docs:Pages:import = [
    symbol = phrase { payload = "import" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
import window
import vulkan
```

Loads an installed library by name using the same search path as --library. Imports its dependencies automatically."
    }
]

let Docs:Pages:include = [
    symbol = phrase { payload = "include" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Execute a source file here.

```recurloop
include \"path.rl\"
```

Executes another source file in the current context. Relative paths are resolved from the including file.

**Example**

```recurloop
include \"src/main.rl\"
```

## Syntax

```recurloop
<path:string>
```

## Example

```recurloop
include \"helpers.rl\"
```

## Arguments

- ** ** — 
- **:** — 
- **path** — Quoted path, relative to the including file."
    }
]

let Docs:Pages:invoke = [
    symbol = phrase { payload = "invoke" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
invoke <phrase>
```

At top level, invokes the referenced phrase action. In an `asm` block, emits a native call to that action; typed functions may take arguments after the reference."
    }
]

let Docs:Pages:len = [
    symbol = phrase { payload = "len" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
len(text)
```

Returns the byte length of a runtime string.

**Example**

```recurloop
len(\"hello\")
```"
    }
]

let Docs:Pages:let = [
    symbol = phrase { payload = "let" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Define a function, alias, dictionary or phrase.

```recurloop
let name = definition
```

At top level, creates a language phrase: a value, alias, dictionary, signature or compiled function. In an `fn` body, declares an immutable local; its type may be inferred.

**Example**

```recurloop
let branch = <if>
let Math = [
    answer = fn () -> i64 { return 42 }
]
let add = fn (a:i64, b:i64) -> i64 { return a + b }
assert Math:answer() == 42
assert add(20, 22) == 42
```

## Syntax

```recurloop
<name:qualified-id> = <definition:raw>
```

## Example

```recurloop
let say = <print>
```

## Arguments

- ** ** — 
- **:** — 
- **definition** — fn, phrase, a reference <name> or a dictionary [...]. Inside fn, let also binds expression values.
- **name** — New name; qualify it with a dictionary, e.g. Tools:say."
    }
]

let Docs:Pages:lexicon = [
    symbol = phrase { payload = "lexicon" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
let name = lexicon { ... }
```

Captures phrase definitions in a separate lexicon. Use `merge <name>` to add its phrases to the current dictionary.

**Example**

```recurloop
let utilities = lexicon { let ping = <debug:ping> }
merge <utilities>
```"
    }
]

let Docs:Pages:link = [
    symbol = phrase { payload = "link" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Configure native linker inputs.

```recurloop
link shared \"name\"
link object \"path.o\"
link archive \"path.a\"
link path \"directory\"
link library \"name\"
link clear
```

Adds native linker inputs or search paths. `shared` selects a shared library; `library` selects a static library by name. `clear` removes all configured inputs.

## Syntax

```recurloop
((shared | object | archive | path | library) <path:string> | clear)
```

## Example

```recurloop
link shared \"c\"
```

## Arguments

- ** ** — 
- **:** — 
- **path** — Library name for shared/library; filesystem path for object/archive/path."
    }
]

let Docs:Pages:link_archive = [
    symbol = phrase { payload = "link:archive" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
link archive \"path.a\"
```

Adds a native static archive."
    }
]

let Docs:Pages:link_clear = [
    symbol = phrase { payload = "link:clear" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
link clear
```

Clears configured native linker inputs and search paths."
    }
]

let Docs:Pages:link_library = [
    symbol = phrase { payload = "link:library" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
link library \"name\"
```

Links a static library by name."
    }
]

let Docs:Pages:link_object = [
    symbol = phrase { payload = "link:object" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
link object \"path.o\"
```

Adds a native object file."
    }
]

let Docs:Pages:link_path = [
    symbol = phrase { payload = "link:path" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
link path \"directory\"
```

Adds a directory to library lookup."
    }
]

let Docs:Pages:link_shared = [
    symbol = phrase { payload = "link:shared" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
link shared \"name\"
```

Links a shared library by name. Example: `link shared \"c\"`."
    }
]

let Docs:Pages:lower = [
    symbol = phrase { payload = "lower" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
lower(text)
```

Returns a copy of a runtime string converted to lowercase.

**Example**

```recurloop
lower(\"HELLO\")
```"
    }
]

let Docs:Pages:merge = [
    symbol = phrase { payload = "merge" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
merge <lexicon>
merge \"fragment.rli\"
```

Merges a captured lexicon or exported lexicon fragment into the current dictionary."
    }
]

let Docs:Pages:method = [
    symbol = phrase { payload = "method" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
method Record name(self:Record*, ...) -> result abi convention
```

Declares a typed method contract on a record. The first parameter is the receiver; invoke it as `instance.name(arguments)`."
    }
]

let Docs:Pages:module = [
    symbol = phrase { payload = "module" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Select native output modules and entry point.

```recurloop
module auto
module manual
module include symbol
module exclude symbol
module entry symbol
```

Controls which native modules enter output. `auto` includes dependencies; `manual` uses explicit selections. `dynamic` is an alias of `exclude`. `clear` resets selections; `embed`/`strip` include/omit language metadata.

## Syntax

```recurloop
(auto | manual | clear | embed | strip | (include | exclude | dynamic | entry) <symbol:qualified-id>)
```

## Example

```recurloop
module entry app_main
```

## Arguments

- ** ** — 
- **:** — 
- **symbol** — A native function or module name."
    }
]

let Docs:Pages:module_auto = [
    symbol = phrase { payload = "module:auto" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
module auto
```

Automatically includes reachable native dependencies."
    }
]

let Docs:Pages:module_clear = [
    symbol = phrase { payload = "module:clear" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
module clear
```

Resets native module selections."
    }
]

let Docs:Pages:module_dynamic = [
    symbol = phrase { payload = "module:dynamic" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
module dynamic symbol
```

Alias of `module exclude`: leaves the symbol outside the selected native modules."
    }
]

let Docs:Pages:module_embed = [
    symbol = phrase { payload = "module:embed" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
module embed
```

Includes language metadata in native output."
    }
]

let Docs:Pages:module_entry = [
    symbol = phrase { payload = "module:entry" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
module entry symbol
```

Selects the native entry symbol."
    }
]

let Docs:Pages:module_exclude = [
    symbol = phrase { payload = "module:exclude" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
module exclude symbol
```

Excludes a native module from output."
    }
]

let Docs:Pages:module_include = [
    symbol = phrase { payload = "module:include" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
module include symbol
```

Adds a native module to output."
    }
]

let Docs:Pages:module_manual = [
    symbol = phrase { payload = "module:manual" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
module manual
```

Uses explicit native module selections."
    }
]

let Docs:Pages:module_strip = [
    symbol = phrase { payload = "module:strip" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
module strip
```

Omits language metadata from native output. This does not control executable debug symbols."
    }
]

let Docs:Pages:none = [
    symbol = phrase { payload = "none" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Represents the absence of a phrase or value."
    }
]

let Docs:Pages:null = [
    symbol = phrase { payload = "null" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
null
```

Runtime null literal: absence of a value."
    }
]

let Docs:Pages:object = [
    symbol = phrase { payload = "object" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
emit object \"path.o\" name = definition
```

Selects relocatable native object output after `emit`. Use `record` for native data layout and `phrase { ... }` for phrase descriptors."
    }
]

let Docs:Pages:packed = [
    symbol = phrase { payload = "packed" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
record Name packed { field:type ... }
```

Removes padding between native record fields. Add `align(N)` after `packed` to request explicit alignment."
    }
]

let Docs:Pages:phrase_69191c22 = [
    symbol = phrase { payload = "phrase" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
let name = phrase {
    field = value
    ...
}
```

Builds a phrase descriptor. Fields select its type, prototype, action, dictionary, payload and metadata. References use `<path>`; flags use `true` or `false`.

**Example**

```recurloop
let branch = phrase {
    prototype = <if>
    docs = \"Run a block when its condition is true.\"
}
```"
    }
]

let Docs:Pages:phrase_types = [
    symbol = phrase { payload = "phrase-types" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
type = <phrase-types:kind>
```

Contains the execution kinds `data`, `elaborate`, `callable` and `scoped-callable`."
    }
]

let Docs:Pages:phrase_types_callable = [
    symbol = phrase { payload = "phrase-types:callable" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
type = <phrase-types:callable>
```

Invokes the phrase action when evaluated."
    }
]

let Docs:Pages:phrase_types_data = [
    symbol = phrase { payload = "phrase-types:data" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
type = <phrase-types:data>
```

Stores data without invoking an action during lookup."
    }
]

let Docs:Pages:phrase_types_elaborate = [
    symbol = phrase { payload = "phrase-types:elaborate" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
type = <phrase-types:elaborate>
```

Runs an action while source is being elaborated; use for language constructs."
    }
]

let Docs:Pages:phrase_types_scoped_callable = [
    symbol = phrase { payload = "phrase-types:scoped-callable" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
type = <phrase-types:scoped-callable>
```

Invokes an action and returns lookup to the parent dictionary."
    }
]

let Docs:Pages:pointer = [
    symbol = phrase { payload = "pointer" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
pointer Type* name
```

Declares a zero-initialized native pointer instance. Use `Type*` in parameter and local type annotations.

**Example**

```recurloop
pointer u8* buffer
```"
    }
]

let Docs:Pages:print = [
    symbol = phrase { payload = "print" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Print a value followed by a newline.

```recurloop
print expression
```

Formats a runtime expression and writes it followed by a newline.

**Example**

```recurloop
print \"Answer: \" + str(42)
```

## Syntax

```recurloop
<value:expr>
```

## Example

```recurloop
print 20 + 22
```

## Arguments

- ** ** — 
- **:** — 
- **value** — An expression to display."
    }
]

let Docs:Pages:record = [
    symbol = phrase { payload = "record" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Define a native record.

```recurloop
record Name {
    field:type
    ...
}
```

Defines a native record with calculated field offsets and alignment. Field types can be pointers, arrays or other records.

**Example**

```recurloop
record Point { x:i64 y:i64 }
```

## Syntax

```recurloop
<name:id> <fields:block>
```

## Example

```recurloop
record Point { x:i64 y:i64 }
```

## Arguments

- ** ** — 
- **:** — 
- **fields** — Fields as name:type pairs. Layout and alignment are calculated.
- **name** — Name of the new type."
    }
]

let Docs:Pages:recurloop_version = [
    symbol = phrase { payload = "recurloop_version" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
recurloop_version
```

Returns the running host release version as a string, without a `v` prefix."
    }
]

let Docs:Pages:replace = [
    symbol = phrase { payload = "replace" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
replace(text, from, to)
```

Replaces every occurrence of `from` in a runtime string. `from` must be nonempty.

**Example**

```recurloop
replace(\"hello\", \"l\", \"r\")
```"
    }
]

let Docs:Pages:resb = [
    symbol = phrase { payload = "resb" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
resb count
```

Reserves `count` bytes in an assembler section; use `.bss` for uninitialized storage."
    }
]

let Docs:Pages:return = [
    symbol = phrase { payload = "return" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
return expression
return
```

Leaves the current compiled function. Return an expression matching its result type; use bare `return` for `void`."
    }
]

let Docs:Pages:set = [
    symbol = phrase { payload = "set" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
set target = expression
```

Updates an existing binding, writable native target or phrase field. Plain `target = expression` also assigns runtime values.

**Example**

```recurloop
set count = count + 1
set branch.docs = \"Conditional branch.\"
```"
    }
]

let Docs:Pages:sizeof = [
    symbol = phrase { payload = "sizeof" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
sizeof(Type)
```

In a compiled function, returns the storage size of a complete object type in bytes.

**Example**

```recurloop
let buffer_size = fn () -> i64 {
    return sizeof(u8[64])
}
assert buffer_size() == 64
```"
    }
]

let Docs:Pages:starts_with = [
    symbol = phrase { payload = "starts_with" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
starts_with(text, prefix)
```

Returns whether a runtime string starts with `prefix`.

**Example**

```recurloop
starts_with(\"hello\", \"he\")
```"
    }
]

let Docs:Pages:str = [
    symbol = phrase { payload = "str" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
str(expression)
```

Returns the formatted text of a runtime value.

**Example**

```recurloop
str(42)
```"
    }
]

let Docs:Pages:struct = [
    symbol = phrase { payload = "struct" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Define a function, alias, dictionary or phrase.

```recurloop
struct Name = [ key = definition ... ]
```

Defines a phrase dictionary through the same grammar as `let`. Children are accessed with `Name:key`; use `record` for native data layout.

## Syntax

```recurloop
<name:qualified-id> = <definition:raw>
```

## Example

```recurloop
let say = <print>
```

## Arguments

- ** ** — 
- **:** — 
- **definition** — fn, phrase, a reference <name> or a dictionary [...]. Inside fn, let also binds expression values.
- **name** — New name; qualify it with a dictionary, e.g. Tools:say."
    }
]

let Docs:Pages:substr = [
    symbol = phrase { payload = "substr" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
substr(text, start)
substr(text, start, length)
```

Returns a substring using a zero-based byte offset. Omit `length` to take the remaining bytes. Start and length must be nonnegative.

**Example**

```recurloop
substr(\"hello\", 1, 3)
```"
    }
]

let Docs:Pages:syntax = [
    symbol = phrase { payload = "syntax" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Define a phrase pattern and its behavior.

Defines a phrase pattern. Captures <name:matcher>, [optional] and (a | b) describe accepted source. Finish with => replacement, as <phrase> or action fn. Attach help = <dictionary> to document arguments and provide a snippet.

## Syntax

```recurloop
[(extend | replace)] <name:id> <definition:rest>
```

## Example

```recurloop
syntax unless <condition:expr> <body:block> => if !(${condition}) ${body}
```

## Arguments

- ** ** — 
- **:** — 
- **definition** — Captures <name:matcher>, [optional], (a | b); finish with => replacement, as <phrase> or action fn.
- **name** — New phrase name; extend preserves the previous syntax as fallback."
    }
]

let Docs:Pages:trim = [
    symbol = phrase { payload = "trim" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
trim(text)
```

Returns a runtime string without leading or trailing whitespace.

**Example**

```recurloop
trim(\"  hello  \")
```"
    }
]

let Docs:Pages:true = [
    symbol = phrase { payload = "true" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
true
```

Boolean true literal."
    }
]

let Docs:Pages:type = [
    symbol = phrase { payload = "type" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
type(expression)
```

Returns a runtime type name: `null`, `bool`, `int`, `real` or `string`.

**Example**

```recurloop
type(42)
```"
    }
]

let Docs:Pages:upper = [
    symbol = phrase { payload = "upper" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
upper(text)
```

Returns a copy of a runtime string converted to uppercase.

**Example**

```recurloop
upper(\"hello\")
```"
    }
]

let Docs:Pages:value = [
    symbol = phrase { payload = "value" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
value(name)
```

Looks up a runtime binding by its string name.

**Example**

```recurloop
value(\"answer\")
```"
    }
]

let Docs:Pages:var = [
    symbol = phrase { payload = "var" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Create a mutable value.

```recurloop
var name = expression
```

Defines a mutable runtime value. In an `fn` body, an optional `:type` selects the native type.

**Example**

```recurloop
var count = 0
count += 1
```

## Syntax

```recurloop
<name:id> [\":\" <type:qualified-id>] \"=\" <value:expr>
```

## Example

```recurloop
var count = 0
count += 1
```

## Arguments

- ** ** — 
- **:** — 
- **name** — Name of the new variable.
- **type** — Optional native type; inferred when omitted.
- **value** — Initial value. Assignment may change it later."
    }
]

let Docs:Pages:while = [
    symbol = phrase { payload = "while" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "Repeat while the condition is true.

```recurloop
while condition { ... }
```

Repeats the block while the condition is true. The condition is checked before each iteration.

**Example**

```recurloop
var n = 0
while n < 3 {
    print n
    n += 1
}
```

## Syntax

```recurloop
<condition:expr> <body:block>
```

## Example

```recurloop
while count < 3 { count += 1 }
```

## Arguments

- ** ** — 
- **:** — 
- **body** — Update the condition or use break to end the loop.
- **condition** — Checked before each iteration."
    }
]

let Docs:Pages:bit_or = [
    symbol = phrase { payload = "|" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left | right
```

Combines integer bits with OR."
    }
]

let Docs:Pages:phrase_05814bde = [
    symbol = phrase { payload = "|=" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
target |= expression
```

Applies `|` to the target and expression, then stores the result in the target."
    }
]

let Docs:Pages:logical_or = [
    symbol = phrase { payload = "||" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
left || right
```

Logical OR; skips the right operand when the left is true."
    }
]

let Docs:Pages:phrase_000ac20d = [
    symbol = phrase { payload = "~" }
    section = phrase { payload = "API" }
    body = phrase {
        payload = "```recurloop
~expression
```

Inverts all integer bits."
    }
]

