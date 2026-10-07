// Remaining standard runtime/source grammar.

phrase runtime_values = "\0runtime-values" in root {
  dictionary
  type phrase_types_data
}

phrase scope_fallback = "\0scope-fallback" in root {
  type phrase_types_elaborate
  action host "scope.enter"
}

phrase tab = "\t" in root {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase newline = "\n" in root {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase vertical_tab = "\x0b" in root {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase carriage_return = "\r" in root {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase empty = " " in root {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase not = "!" in root {
  docs "```recurloop\n!expression\n```\n\nNegates a truth value."
  type phrase_types_data
}

phrase not_equal = "!=" in root {
  docs "```recurloop\nleft != right\n```\n\nTests inequality."
  type phrase_types_data
}

phrase percent = "%" in root {
  docs "```recurloop\nleft % right\n```\n\nComputes the remainder."
  type phrase_types_data
}

phrase percent_equals = "%=" in root {
  docs "```recurloop\ntarget %= expression\n```\n\nApplies `%` to the target and expression, then stores the result in the target."
  prototype expressions_infix_percent
  type phrase_types_data
}

phrase ampersand = "&" in root {
  docs "```recurloop\n&target\nleft & right\n```\n\nIn a compiled function, `&target` takes an address. Between integers, `&` combines bits with AND."
  type phrase_types_data
}

phrase and_and = "&&" in root {
  docs "```recurloop\nleft && right\n```\n\nLogical AND; skips the right operand when the left is false."
  type phrase_types_data
}

phrase lparen = "(" in root {
  type phrase_types_data
}

phrase rparen = ")" in root {
  type phrase_types_data
}

phrase star = "*" in root {
  docs "```recurloop\nleft * right\n*pointer\nType*\n```\n\nMultiplies numbers, dereferences a native pointer, or forms a pointer type, depending on position."
  type phrase_types_data
}

phrase star_equals = "*=" in root {
  docs "```recurloop\ntarget *= expression\n```\n\nApplies `*` to the target and expression, then stores the result in the target."
  prototype expressions_infix_star
  type phrase_types_data
}

phrase plus = "+" in root {
  docs "```recurloop\nleft + right\n+expression\n```\n\nAdds numbers or concatenates runtime strings. Prefix `+` leaves a number unchanged."
  type phrase_types_data
}

phrase plus_equals = "+=" in root {
  docs "```recurloop\ntarget += expression\n```\n\nApplies `+` to the target and expression, then stores the result in the target."
  prototype expressions_infix_plus
  type phrase_types_data
}

phrase comma = "," in root {
  type phrase_types_data
}

phrase minus = "-" in root {
  docs "```recurloop\nleft - right\n-expression\n```\n\nSubtracts numbers. Prefix `-` negates a number."
  type phrase_types_data
}

phrase minus_equals = "-=" in root {
  docs "```recurloop\ntarget -= expression\n```\n\nApplies `-` to the target and expression, then stores the result in the target."
  prototype expressions_infix_minus
  type phrase_types_data
}

phrase arrow = "->" in root {
  type phrase_types_data
}

phrase dot = "." in root {
  type phrase_types_data
}

phrase empty_671187 = "..." in root {
  type phrase_types_data
}

phrase bss = ".bss" in root {
  docs "```recurloop\n.bss\n```\n\nSelects the uninitialized data section in an `asm` block."
  type phrase_types_data
}

phrase data = ".data" in root {
  docs "```recurloop\n.data\n```\n\nSelects the writable initialized data section in an `asm` block."
  type phrase_types_data
}

phrase rodata = ".rodata" in root {
  docs "```recurloop\n.rodata\n```\n\nSelects the read-only data section in an `asm` block."
  type phrase_types_data
}

phrase section = ".section" in root {
  type phrase_types_data
}

phrase text = ".text" in root {
  docs "```recurloop\n.text\n```\n\nSelects the executable instruction section in an `asm` block."
  type phrase_types_data
}

phrase slash = "/" in root {
  docs "```recurloop\nleft / right\n```\n\nDivides numeric operands."
  type phrase_types_data
}

phrase block_comment = "/*" in root {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor root
}

phrase line_comment = "//" in root {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor root
}

phrase slash_equals = "/=" in root {
  docs "```recurloop\ntarget /= expression\n```\n\nApplies `/` to the target and expression, then stores the result in the target."
  prototype expressions_infix_slash
  type phrase_types_data
}

phrase colon = ":" in root {
  type phrase_types_data
}

// Managed-session controls are ordinary longest-prefix phrases. Their host
// actions only enqueue lifecycle operations; Session applies them after the
// current request transaction has committed.
phrase session_generations = ":generations" in root {
  docs "```recurloop\n:generations\n```\n\nShows project and session generation information."
  type phrase_types_elaborate
  action host "session.generations"
}

phrase session_help = ":help" in root {
  docs "```recurloop\n:help\n```\n\nLists commands available in a managed session."
  type phrase_types_elaborate
  action host "session.help"
}

phrase session_load = ":load" in root {
  docs "```recurloop\n:load \"path.rl\"\n```\n\nExecutes a source file in the current session."
  type phrase_types_elaborate
  action host "source.include"
}

phrase session_publish = ":publish" in root {
  docs "```recurloop\n:publish\n```\n\nPublishes the current session environment as a new project generation."
  type phrase_types_elaborate
  action host "session.publish"
}

phrase session_publish_prepare = ":publish-prepare" in root {
  docs "```recurloop\n:publish-prepare\n```\n\nPrepares a project generation for later publication with `:publish-commit`."
  type phrase_types_elaborate
  action host "session.publish-prepare"
}

phrase session_publish_commit = ":publish-commit" in root {
  docs "```recurloop\n:publish-commit\n```\n\nPublishes the generation prepared with `:publish-prepare`."
  type phrase_types_elaborate
  action host "session.publish-commit"
}

phrase session_quit = ":quit" in root {
  docs "```recurloop\n:quit\n```\n\nCloses the current managed session."
  type phrase_types_elaborate
  action host "session.quit"
}

phrase session_exit = ":exit" in root {
  docs "```recurloop\n:exit\n```\n\nAlias of `:quit`; closes the current managed session."
  type phrase_types_elaborate
  action host "session.quit"
}

phrase session_refresh = ":refresh" in root {
  docs "```recurloop\n:refresh\n```\n\nAdopts the latest published project environment in this session."
  type phrase_types_elaborate
  action host "session.refresh"
}

phrase session_baseline = ":baseline" in root {
  docs "```recurloop\n:baseline\n```\n\nResets the session to the project baseline generation."
  type phrase_types_elaborate
  action host "session.baseline"
}

phrase session_cache = ":cache" in root {
  kind "session command"
  color "#C586C0"
  docs "```recurloop\n:cache\n```\n\nEnables linked per-source project image caching for this session."
  type phrase_types_elaborate
  action host "session.cache"
}

phrase session_cache_exact = ":cache-exact" in root {
  kind "session command"
  color "#C586C0"
  docs "```recurloop\n:cache-exact\n```\n\nStarts the compatibility exact-cache mode used by older build clients; follows the project cache setting."
  type phrase_types_elaborate
  action host "session.cache-exact"
}

phrase session_cache_status = ":cache-status" in root {
  docs "```recurloop\n:cache-status\n```\n\nReports project module cache hit, miss and write counts."
  type phrase_types_elaborate
  action host "session.cache-status"
}

phrase session_cache_dependencies = ":cache-dependencies" in root {
  docs "```recurloop\n:cache-dependencies\n```\n\nLists dependencies recorded by the project module cache."
  type phrase_types_elaborate
  action host "session.cache-dependencies"
}

phrase semicolon = ";" in root {
  type phrase_types_data
}

phrase less = "<" in root {
  docs "```recurloop\nleft < right\n```\n\nTests whether the left operand is smaller."
  type phrase_types_data
}

phrase less_b2d74b = "<" in root {
  docs "```recurloop\n<Namespace:phrase>\n```\n\nReferences an existing phrase. Use references for aliases, prototypes, actions or lexicons."
  dictionary
  type phrase_types_elaborate
  action host "reference.enter"
}

phrase less_equal = "<=" in root {
  docs "```recurloop\nleft <= right\n```\n\nTests whether the left operand is smaller or equal."
  type phrase_types_data
}

phrase equals = "=" in root {
  docs "```recurloop\ntarget = expression\n```\n\nAssigns a value to a mutable target."
  type phrase_types_data
}

phrase equal_equal = "==" in root {
  docs "```recurloop\nleft == right\n```\n\nTests equality."
  type phrase_types_data
}

phrase greater = ">" in root {
  docs "```recurloop\nleft > right\n```\n\nTests whether the left operand is larger."
  type phrase_types_data
}

phrase greater_equal = ">=" in root {
  docs "```recurloop\nleft >= right\n```\n\nTests whether the left operand is larger or equal."
  type phrase_types_data
}

phrase question = "?" in root {
  docs "```recurloop\npointer_expression?\n```\n\nInside a pointer-returning compiled function, propagates a null pointer by returning null."
  type phrase_types_data
}

phrase lbracket = "[" in root {
  type phrase_types_data
}

phrase lbracket_862dc1 = "[" in root {
  docs "```recurloop\nlet Name = [ key = definition ... ]\n```\n\nCreates a nested phrase dictionary. Access a child with `Name:key`."
  dictionary
  type phrase_types_elaborate
  action host "dictionary.enter"
}

phrase rbracket = "]" in root {
  type phrase_types_data
}

phrase action = "action" in root {
  type phrase_types_data
}

phrase adc = "adc" in root {
  type phrase_types_data
}

phrase add = "add" in root {
  type phrase_types_data
}

phrase ah = "ah" in root {
  type phrase_types_data
}

phrase al = "al" in root {
  type phrase_types_data
}

phrase align = "align" in root {
  type phrase_types_data
}

phrase alloc = "alloc" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nalloc(Type)\n```\n\nIn a compiled function, allocates an object with `malloc` and returns `Type*`. Storage is uninitialized; check for a null pointer and release it with `free`.\n\n**Example (inside fn)**\n\n```recurloop\nlet point = alloc(Point)\nif !point { return 1 }\ndefer free(cast(u8*, point))\n```"
  type phrase_types_data
}

phrase sizeof = "sizeof" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nsizeof(Type)\n```\n\nIn a compiled function, returns the storage size of a complete object type in bytes.\n\n**Example (inside fn)**\n\n```recurloop\nlet bytes = sizeof(u8[64])\n```"
  type phrase_types_data
}

phrase and = "and" in root {
  type phrase_types_data
}

phrase archive = "archive" in root {
  type phrase_types_data
}

phrase assembler = "assembler" in root {
  prototype asm
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase auto = "auto" in root {
  type phrase_types_data
}

phrase ax = "ax" in root {
  type phrase_types_data
}

phrase bh = "bh" in root {
  type phrase_types_data
}

phrase bl = "bl" in root {
  type phrase_types_data
}

phrase bp = "bp" in root {
  type phrase_types_data
}

phrase bpl = "bpl" in root {
  type phrase_types_data
}

phrase break = "break" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nbreak\n```\n\nLeaves the nearest enclosing loop immediately."
  type phrase_types_data
}

phrase bswap = "bswap" in root {
  type phrase_types_data
}

phrase bx = "bx" in root {
  type phrase_types_data
}

phrase byte = "byte" in root {
  type phrase_types_data
}

phrase call = "call" in root {
  type phrase_types_data
}

phrase callee = "callee" in root {
  type phrase_types_data
}

phrase caller = "caller" in root {
  type phrase_types_data
}

phrase cast = "cast" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\ncast(Type, expression)\n```\n\nIn a compiled function, explicitly converts an expression to the selected native type.\n\n**Example (inside fn)**\n\n```recurloop\nlet address = cast(u8*, &value)\n```"
  type phrase_types_data
}

phrase cdq = "cdq" in root {
  type phrase_types_data
}

phrase ch = "ch" in root {
  type phrase_types_data
}

phrase cl = "cl" in root {
  type phrase_types_data
}

phrase clc = "clc" in root {
  type phrase_types_data
}

phrase cld = "cld" in root {
  type phrase_types_data
}

phrase cleanup = "cleanup" in root {
  type phrase_types_data
}

phrase clear = "clear" in root {
  type phrase_types_data
}

phrase cli = "cli" in root {
  type phrase_types_data
}

phrase cmc = "cmc" in root {
  type phrase_types_data
}

phrase cmp = "cmp" in root {
  type phrase_types_data
}

phrase contains = "contains" in root {
  docs "```recurloop\ncontains(text, part)\n```\n\nReturns whether a runtime string contains `part`.\n\n**Example**\n\n```recurloop\ncontains(\"hello\", \"ell\")\n```"
  type phrase_types_data
}

phrase continue = "continue" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\ncontinue\n```\n\nSkips the rest of the nearest loop body and checks its condition again."
  type phrase_types_elaborate
  action host "language.continue"
}

phrase cpuid = "cpuid" in root {
  type phrase_types_data
}

phrase cqo = "cqo" in root {
  type phrase_types_data
}

phrase cx = "cx" in root {
  type phrase_types_data
}

phrase db = "db" in root {
  docs "```recurloop\ndb value, ...\n```\n\nEmits 1-byte values in an `asm` block, using little-endian order."
  type phrase_types_data
}

phrase dd = "dd" in root {
  docs "```recurloop\ndd value, ...\n```\n\nEmits 4-byte values in an `asm` block, using little-endian order."
  type phrase_types_data
}

phrase debug = "debug" in root {
  docs "```recurloop\ndebug:stats\ndebug:run \"source.rl\"\ndebug:executable run \"path\"\n```\n\nProvides source and native debugging commands. Use `debug:break` to configure breakpoints before running."
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase dec = "dec" in root {
  type phrase_types_data
}

phrase defer = "defer" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\ndefer cleanup_expression\n```\n\nIn a compiled function, registers cleanup for exit. Deferred expressions run in reverse registration order, including when returning early.\n\n**Example (inside fn)**\n\n```recurloop\nlet buffer = alloc(u8[64])\ndefer free(buffer)\n```"
  type phrase_types_data
}

phrase dh = "dh" in root {
  type phrase_types_data
}

phrase di = "di" in root {
  type phrase_types_data
}

phrase dictionary = "dictionary" in root {
  type phrase_types_data
}

phrase dil = "dil" in root {
  type phrase_types_data
}

phrase div = "div" in root {
  type phrase_types_data
}

phrase dl = "dl" in root {
  type phrase_types_data
}

phrase down = "down" in root {
  type phrase_types_data
}

phrase dq = "dq" in root {
  docs "```recurloop\ndq value, ...\n```\n\nEmits 8-byte values in an `asm` block, using little-endian order."
  type phrase_types_data
}

phrase dw = "dw" in root {
  docs "```recurloop\ndw value, ...\n```\n\nEmits 2-byte values in an `asm` block, using little-endian order."
  type phrase_types_data
}

phrase dword = "dword" in root {
  type phrase_types_data
}

phrase dx = "dx" in root {
  type phrase_types_data
}

phrase dynamic = "dynamic" in root {
  type phrase_types_data
}

phrase eax = "eax" in root {
  type phrase_types_data
}

phrase ebp = "ebp" in root {
  type phrase_types_data
}

phrase ebx = "ebx" in root {
  type phrase_types_data
}

phrase ecx = "ecx" in root {
  type phrase_types_data
}

phrase edi = "edi" in root {
  type phrase_types_data
}

phrase edx = "edx" in root {
  type phrase_types_data
}

phrase else = "else" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nif condition { ... } else { ... }\n```\n\nProvides the alternative branch of `if`. Inside compiled functions, use `else if condition { ... }` for another condition."
  type phrase_types_data
}

phrase embed = "embed" in root {
  type phrase_types_data
}

phrase emit = "emit" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nemit executable \"path\" name = fn () -> i64 { ... }\nemit object \"path.o\" name = fn (...) -> result { ... }\nemit raw \"path.bin\" = hex { ... }\n```\n\nWrites a native executable, relocatable object or exact bytes. Add `debug` after `executable` to retain symbols and debugging metadata."
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase ends_with = "ends_with" in root {
  docs "```recurloop\nends_with(text, suffix)\n```\n\nReturns whether a runtime string ends with `suffix`.\n\n**Example**\n\n```recurloop\nends_with(\"hello\", \"lo\")\n```"
  type phrase_types_data
}

phrase engine = "engine" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nengine import \"image.rli\"\nengine export \"image.rli\"\n```\n\nLoads or saves a RecurLoop engine image containing phrases and their language definitions."
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase entry = "entry" in root {
  type phrase_types_data
}

phrase esi = "esi" in root {
  type phrase_types_data
}

phrase esp = "esp" in root {
  type phrase_types_data
}

phrase exclude = "exclude" in root {
  type phrase_types_data
}

phrase exec = "exec" in root {
  type phrase_types_data
}

phrase exit = "exit" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nexit\nexit status\n```\n\nStops source execution. Omit the status to use zero; a nonzero integer reports failure.\n\n**Example**\n\n```recurloop\nexit 1\n```"
  type phrase_types_elaborate
  action host "language.exit"
}

phrase false = "false" in root {
  kind "literal"
  color "#569CD6"
  docs "```recurloop\nfalse\n```\n\nBoolean false literal."
  type phrase_types_data
}

phrase fini_array = "fini-array" in root {
  type phrase_types_data
}

phrase floating = "floating" in root {
  type phrase_types_data
}

phrase floating_result = "floating-result" in root {
  type phrase_types_data
}

phrase hex = "hex" in root {
  docs "```recurloop\nhex { byte ... }\n```\n\nBuilds exact bytes from pairs of hexadecimal digits.\n\n**Example**\n\n```recurloop\nlet bytes = hex { 52 4c 0a }\n```"
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase hlt = "hlt" in root {
  type phrase_types_data
}

phrase idiv = "idiv" in root {
  type phrase_types_data
}

phrase if = "if" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nif condition { ... } else { ... }\n```\n\nRuns the first block when the condition is true, otherwise the optional `else` block. Inside compiled functions, `else if` chains further conditions.\n\n**Example**\n\n```recurloop\nif count > 0 { print \"ready\" } else { print \"empty\" }\n```"
  type phrase_types_data
}

phrase imul = "imul" in root {
  type phrase_types_data
}

phrase inc = "inc" in root {
  type phrase_types_data
}

phrase include = "include" in root {
  kind "keyword"
  color "#C586C0"
  docs "Loads and elaborates source from another file."
  type phrase_types_data
}

phrase include_b26ec9 = "include" in root {
  docs "```recurloop\ninclude \"path.rl\"\n```\n\nExecutes another source file in the current context. Relative paths are resolved from the including file.\n\n**Example**\n\n```recurloop\ninclude \"src/main.rl\"\n```"
  prototype include
  type phrase_types_elaborate
  action host "source.include"
}

phrase init_array = "init-array" in root {
  type phrase_types_data
}

phrase int = "int" in root {
  type phrase_types_data
}

phrase int3 = "int3" in root {
  type phrase_types_data
}

phrase integer = "integer" in root {
  type phrase_types_data
}

phrase ja = "ja" in root {
  type phrase_types_data
}

phrase jae = "jae" in root {
  type phrase_types_data
}

phrase jb = "jb" in root {
  type phrase_types_data
}

phrase jbe = "jbe" in root {
  type phrase_types_data
}

phrase jc = "jc" in root {
  type phrase_types_data
}

phrase je = "je" in root {
  type phrase_types_data
}

phrase jg = "jg" in root {
  type phrase_types_data
}

phrase jge = "jge" in root {
  type phrase_types_data
}

phrase jl = "jl" in root {
  type phrase_types_data
}

phrase jle = "jle" in root {
  type phrase_types_data
}

phrase jmp = "jmp" in root {
  type phrase_types_data
}

phrase jna = "jna" in root {
  type phrase_types_data
}

phrase jnae = "jnae" in root {
  type phrase_types_data
}

phrase jnb = "jnb" in root {
  type phrase_types_data
}

phrase jnbe = "jnbe" in root {
  type phrase_types_data
}

phrase jnc = "jnc" in root {
  type phrase_types_data
}

phrase jne = "jne" in root {
  type phrase_types_data
}

phrase jng = "jng" in root {
  type phrase_types_data
}

phrase jnge = "jnge" in root {
  type phrase_types_data
}

phrase jnl = "jnl" in root {
  type phrase_types_data
}

phrase jnle = "jnle" in root {
  type phrase_types_data
}

phrase jno = "jno" in root {
  type phrase_types_data
}

phrase jnp = "jnp" in root {
  type phrase_types_data
}

phrase jns = "jns" in root {
  type phrase_types_data
}

phrase jnz = "jnz" in root {
  type phrase_types_data
}

phrase jo = "jo" in root {
  type phrase_types_data
}

phrase jp = "jp" in root {
  type phrase_types_data
}

phrase jpe = "jpe" in root {
  type phrase_types_data
}

phrase jpo = "jpo" in root {
  type phrase_types_data
}

phrase js = "js" in root {
  type phrase_types_data
}

phrase jz = "jz" in root {
  type phrase_types_data
}

phrase lea = "lea" in root {
  type phrase_types_data
}

phrase leave = "leave" in root {
  type phrase_types_data
}

phrase len = "len" in root {
  docs "```recurloop\nlen(text)\n```\n\nReturns the byte length of a runtime string.\n\n**Example**\n\n```recurloop\nlen(\"hello\")\n```"
  type phrase_types_data
}

phrase let = "let" in root {
  kind "keyword"
  color "#569CD6"
  docs "```recurloop\nlet name = definition\n```\n\nAt top level, creates a language phrase: a value, alias, dictionary, signature or compiled function. In an `fn` body, declares an immutable local; its type may be inferred.\n\n**Example**\n\n```recurloop\nlet branch = <if>\nlet Math = [ answer = 42 ]\nlet add = fn (a:i64, b:i64) -> i64 { return a + b }\n```"
  dictionary
  type phrase_types_elaborate
  action host "let.enter"
}

phrase lexicon = "lexicon" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nlet name = lexicon { ... }\n```\n\nCaptures phrase definitions in a separate lexicon. Use `merge <name>` to add its phrases to the current dictionary.\n\n**Example**\n\n```recurloop\nlet utilities = lexicon { let ping = <debug:ping> }\nmerge <utilities>\n```"
  type phrase_types_elaborate
  action host "lexicon.create"
}

phrase library = "library" in root {
  type phrase_types_data
}

phrase lower = "lower" in root {
  docs "```recurloop\nlower(text)\n```\n\nReturns a copy of a runtime string converted to lowercase.\n\n**Example**\n\n```recurloop\nlower(\"HELLO\")\n```"
  type phrase_types_data
}

phrase manual = "manual" in root {
  type phrase_types_data
}

phrase merge = "merge" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nmerge <lexicon>\nmerge \"fragment.rli\"\n```\n\nMerges a captured lexicon or exported lexicon fragment into the current dictionary."
  type phrase_types_elaborate
  action host "lexicon.merge"
}

phrase mov = "mov" in root {
  type phrase_types_data
}

phrase movsx = "movsx" in root {
  type phrase_types_data
}

phrase movsxd = "movsxd" in root {
  type phrase_types_data
}

phrase movzx = "movzx" in root {
  type phrase_types_data
}

phrase mul = "mul" in root {
  type phrase_types_data
}

phrase neg = "neg" in root {
  type phrase_types_data
}

phrase nobits = "nobits" in root {
  type phrase_types_data
}

phrase none = "none" in root {
  kind "literal"
  color "#569CD6"
  docs "Represents the absence of a phrase or value."
  type phrase_types_data
}

phrase nop = "nop" in root {
  type phrase_types_data
}

phrase not_7a6e7b = "not" in root {
  type phrase_types_data
}

phrase note = "note" in root {
  type phrase_types_data
}

phrase null = "null" in root {
  docs "```recurloop\nnull\n```\n\nRuntime null literal: absence of a value."
  type phrase_types_data
}

phrase recurloop_version = "recurloop_version" in root {
  kind "literal"
  color "#569CD6"
  docs "```recurloop\nrecurloop_version\n```\n\nReturns the running host release version as a string, without a `v` prefix."
  type phrase_types_data
}

phrase object = "object" in root {
  kind "keyword"
  color "#569CD6"
  docs "```recurloop\nemit object \"path.o\" name = definition\n```\n\nSelects relocatable native object output after `emit`. Use `record` for native data layout and `phrase { ... }` for phrase descriptors."
  type phrase_types_data
}

phrase off = "off" in root {
  type phrase_types_data
}

phrase on = "on" in root {
  type phrase_types_data
}

phrase or = "or" in root {
  type phrase_types_data
}

phrase packed = "packed" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nrecord Name packed { field:type ... }\n```\n\nRemoves padding between native record fields. Add `align(N)` after `packed` to request explicit alignment."
  type phrase_types_data
}

phrase parent = "parent" in root {
  type phrase_types_data
}

phrase path = "path" in root {
  type phrase_types_data
}

phrase payload = "payload" in root {
  type phrase_types_data
}

phrase permanent = "permanent" in root {
  type phrase_types_data
}

phrase phrase = "phrase" in root {
  kind "keyword"
  color "#569CD6"
  docs "```recurloop\nlet name = phrase {\n    field = value\n    ...\n}\n```\n\nBuilds a phrase descriptor. Fields select its type, prototype, action, dictionary, payload and metadata. References use `<path>`; flags use `true` or `false`.\n\n**Example**\n\n```recurloop\nlet branch = phrase {\n    prototype = <if>\n    docs = \"Run a block when its condition is true.\"\n}\n```"
  type phrase_types_elaborate
  action host "phrase.define"
}


phrase pop = "pop" in root {
  type phrase_types_data
}

phrase popfq = "popfq" in root {
  type phrase_types_data
}

phrase preinit_array = "preinit-array" in root {
  type phrase_types_data
}

phrase prototype = "prototype" in root {
  type phrase_types_data
}

phrase push = "push" in root {
  type phrase_types_data
}

phrase pushfq = "pushfq" in root {
  type phrase_types_data
}

phrase qword = "qword" in root {
  type phrase_types_data
}

phrase r10 = "r10" in root {
  type phrase_types_data
}

phrase r10b = "r10b" in root {
  type phrase_types_data
}

phrase r10d = "r10d" in root {
  type phrase_types_data
}

phrase r10w = "r10w" in root {
  type phrase_types_data
}

phrase r11 = "r11" in root {
  type phrase_types_data
}

phrase r11b = "r11b" in root {
  type phrase_types_data
}

phrase r11d = "r11d" in root {
  type phrase_types_data
}

phrase r11w = "r11w" in root {
  type phrase_types_data
}

phrase r12 = "r12" in root {
  type phrase_types_data
}

phrase r12b = "r12b" in root {
  type phrase_types_data
}

phrase r12d = "r12d" in root {
  type phrase_types_data
}

phrase r12w = "r12w" in root {
  type phrase_types_data
}

phrase r13 = "r13" in root {
  type phrase_types_data
}

phrase r13b = "r13b" in root {
  type phrase_types_data
}

phrase r13d = "r13d" in root {
  type phrase_types_data
}

phrase r13w = "r13w" in root {
  type phrase_types_data
}

phrase r14 = "r14" in root {
  type phrase_types_data
}

phrase r14b = "r14b" in root {
  type phrase_types_data
}

phrase r14d = "r14d" in root {
  type phrase_types_data
}

phrase r14w = "r14w" in root {
  type phrase_types_data
}

phrase r15 = "r15" in root {
  type phrase_types_data
}

phrase r15b = "r15b" in root {
  type phrase_types_data
}

phrase r15d = "r15d" in root {
  type phrase_types_data
}

phrase r15w = "r15w" in root {
  type phrase_types_data
}

phrase r8 = "r8" in root {
  type phrase_types_data
}

phrase r8b = "r8b" in root {
  type phrase_types_data
}

phrase r8d = "r8d" in root {
  type phrase_types_data
}

phrase r8w = "r8w" in root {
  type phrase_types_data
}

phrase r9 = "r9" in root {
  type phrase_types_data
}

phrase r9b = "r9b" in root {
  type phrase_types_data
}

phrase r9d = "r9d" in root {
  type phrase_types_data
}

phrase r9w = "r9w" in root {
  type phrase_types_data
}

phrase rax = "rax" in root {
  type phrase_types_data
}

phrase rbp = "rbp" in root {
  type phrase_types_data
}

phrase rbx = "rbx" in root {
  type phrase_types_data
}

phrase rcx = "rcx" in root {
  type phrase_types_data
}

phrase rdi = "rdi" in root {
  type phrase_types_data
}

phrase rdtsc = "rdtsc" in root {
  type phrase_types_data
}

phrase rdx = "rdx" in root {
  type phrase_types_data
}

phrase replace = "replace" in root {
  docs "```recurloop\nreplace(text, from, to)\n```\n\nReplaces every occurrence of `from` in a runtime string. `from` must be nonempty.\n\n**Example**\n\n```recurloop\nreplace(\"hello\", \"l\", \"r\")\n```"
  type phrase_types_data
}

phrase resb = "resb" in root {
  docs "```recurloop\nresb count\n```\n\nReserves `count` bytes in an assembler section; use `.bss` for uninitialized storage."
  type phrase_types_data
}

phrase result = "result" in root {
  type phrase_types_data
}

phrase ret = "ret" in root {
  type phrase_types_data
}

phrase return = "return" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nreturn expression\nreturn\n```\n\nLeaves the current compiled function. Return an expression matching its result type; use bare `return` for `void`."
  type phrase_types_data
}

phrase rewrite = "rewrite" in root {
  type phrase_types_data
}

phrase rol = "rol" in root {
  type phrase_types_data
}

phrase ror = "ror" in root {
  type phrase_types_data
}

phrase rsi = "rsi" in root {
  type phrase_types_data
}

phrase rsp = "rsp" in root {
  type phrase_types_data
}

phrase sal = "sal" in root {
  type phrase_types_data
}

phrase sar = "sar" in root {
  type phrase_types_data
}

phrase sbb = "sbb" in root {
  type phrase_types_data
}

phrase serializable = "serializable" in root {
  type phrase_types_data
}

phrase shadow = "shadow" in root {
  type phrase_types_data
}

phrase shared = "shared" in root {
  type phrase_types_data
}

phrase shl = "shl" in root {
  type phrase_types_data
}

phrase shr = "shr" in root {
  type phrase_types_data
}

phrase si = "si" in root {
  type phrase_types_data
}

phrase sil = "sil" in root {
  type phrase_types_data
}

phrase sp = "sp" in root {
  type phrase_types_data
}

phrase spl = "spl" in root {
  type phrase_types_data
}

phrase stack = "stack" in root {
  type phrase_types_data
}

phrase starts_with = "starts_with" in root {
  docs "```recurloop\nstarts_with(text, prefix)\n```\n\nReturns whether a runtime string starts with `prefix`.\n\n**Example**\n\n```recurloop\nstarts_with(\"hello\", \"he\")\n```"
  type phrase_types_data
}

phrase stc = "stc" in root {
  type phrase_types_data
}

phrase std = "std" in root {
  type phrase_types_data
}

phrase sti = "sti" in root {
  type phrase_types_data
}

phrase str = "str" in root {
  docs "```recurloop\nstr(expression)\n```\n\nReturns the formatted text of a runtime value.\n\n**Example**\n\n```recurloop\nstr(42)\n```"
  type phrase_types_data
}

phrase strings = "strings" in root {
  type phrase_types_data
}

phrase strip = "strip" in root {
  type phrase_types_data
}

phrase struct = "struct" in root {
  docs "```recurloop\nstruct Name = [ key = definition ... ]\n```\n\nDefines a phrase dictionary through the same grammar as `let`. Children are accessed with `Name:key`; use `record` for native data layout."
  prototype let
  type phrase_types_elaborate
  action host "let.enter"
}

phrase sub = "sub" in root {
  type phrase_types_data
}

phrase substr = "substr" in root {
  docs "```recurloop\nsubstr(text, start)\nsubstr(text, start, length)\n```\n\nReturns a substring using a zero-based byte offset. Omit `length` to take the remaining bytes. Start and length must be nonnegative.\n\n**Example**\n\n```recurloop\nsubstr(\"hello\", 1, 3)\n```"
  type phrase_types_data
}

phrase successor = "successor" in root {
  type phrase_types_data
}

phrase syscall = "syscall" in root {
  type phrase_types_data
}

phrase test = "test" in root {
  type phrase_types_data
}

phrase tls = "tls" in root {
  type phrase_types_data
}

phrase trim = "trim" in root {
  docs "```recurloop\ntrim(text)\n```\n\nReturns a runtime string without leading or trailing whitespace.\n\n**Example**\n\n```recurloop\ntrim(\"  hello  \")\n```"
  type phrase_types_data
}

phrase true = "true" in root {
  kind "literal"
  color "#569CD6"
  docs "```recurloop\ntrue\n```\n\nBoolean true literal."
  type phrase_types_data
}

phrase type = "type" in root {
  kind "function"
  color "#DCDCAA"
  docs "```recurloop\ntype(expression)\n```\n\nReturns a runtime type name: `null`, `bool`, `int`, `real` or `string`.\n\n**Example**\n\n```recurloop\ntype(42)\n```"
  type phrase_types_data
}

phrase ud2 = "ud2" in root {
  type phrase_types_data
}

phrase up = "up" in root {
  type phrase_types_data
}

phrase upper = "upper" in root {
  docs "```recurloop\nupper(text)\n```\n\nReturns a copy of a runtime string converted to uppercase.\n\n**Example**\n\n```recurloop\nupper(\"hello\")\n```"
  type phrase_types_data
}

phrase value = "value" in root {
  docs "```recurloop\nvalue(name)\n```\n\nLooks up a runtime binding by its string name.\n\n**Example**\n\n```recurloop\nvalue(\"answer\")\n```"
  type phrase_types_data
}

phrase while = "while" in root {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nwhile condition { ... }\n```\n\nRepeats the block while the condition is true. The condition is checked before each iteration.\n\n**Example**\n\n```recurloop\nvar n = 0\nwhile n < 3 {\n    print n\n    n += 1\n}\n```"
  type phrase_types_data
}

phrase word = "word" in root {
  type phrase_types_data
}

phrase write = "write" in root {
  type phrase_types_data
}

phrase xchg = "xchg" in root {
  type phrase_types_data
}

phrase xor = "xor" in root {
  type phrase_types_data
}

phrase lbrace = "{" in root {
  type phrase_types_data
}

phrase lbrace_055f92 = "{" in root {
  dictionary
  prototype scope_fallback
  type phrase_types_elaborate
  action host "assembler.scope"
}

phrase or_or = "||" in root {
  docs "```recurloop\nleft || right\n```\n\nLogical OR; skips the right operand when the left is true."
  type phrase_types_data
}

phrase rbrace = "}" in root {
  type phrase_types_data
}

phrase runtime_values_active = "active" in runtime_values {
  prototype runtime_values_scopes_global
  type phrase_types_data
}

phrase runtime_values_scopes = "scopes" in runtime_values {
  dictionary
  type phrase_types_data
}

phrase block_comment_empty = "" in block_comment {
  type phrase_types_elaborate
  action host "source.progress-byte"
}

phrase block_comment_block_comment_end = "*/" in block_comment {
  type phrase_types_elaborate
  action host "lookup.leave"
}

phrase block_comment_empty_24358d = "\\*" in block_comment {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase line_comment_empty = "" in line_comment {
  type phrase_types_elaborate
  action host "source.progress-byte"
}

phrase line_comment_newline = "\n" in line_comment {
  type phrase_types_elaborate
  action host "lookup.leave"
}

phrase line_comment_empty_2d293a = "\\\n" in line_comment {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase less_empty = "" in less_b2d74b {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor less_b2d74b
}

phrase less_tab = "\t" in less_b2d74b {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase less_newline = "\n" in less_b2d74b {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase less_vertical_tab = "\x0b" in less_b2d74b {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase less_carriage_return = "\r" in less_b2d74b {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase less_empty_c5444e = " " in less_b2d74b {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase less_quote = "\"" in less_b2d74b {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor less_b2d74b
}

phrase less_apostrophe = "'" in less_b2d74b {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor less_b2d74b
}

phrase less_colon = ":" in less_b2d74b {
  type phrase_types_elaborate
  action host "reference.colon"
  successor less_b2d74b
}

phrase lbracket_empty = "" in lbracket_862dc1 {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor lbracket_862dc1
}

phrase lbracket_tab = "\t" in lbracket_862dc1 {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_newline = "\n" in lbracket_862dc1 {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_vertical_tab = "\x0b" in lbracket_862dc1 {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_carriage_return = "\r" in lbracket_862dc1 {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_empty_af8c91 = " " in lbracket_862dc1 {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_quote = "\"" in lbracket_862dc1 {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor lbracket_862dc1
}

phrase lbracket_apostrophe = "'" in lbracket_862dc1 {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor lbracket_862dc1
}

phrase lbracket_rbracket = "]" in lbracket_862dc1 {
  type phrase_types_elaborate
  action host "dictionary.leave"
}

phrase debug_debug_breakpoints = "\0debug-breakpoints" in debug {
  dictionary
  type phrase_types_data
}

phrase debug_tab = "\t" in debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_newline = "\n" in debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_vertical_tab = "\x0b" in debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_carriage_return = "\r" in debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_empty = " " in debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_colon = ":" in debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_break = "break" in debug {
  docs "```recurloop\ndebug:break phrase \"name\"\ndebug:break function \"name\"\ndebug:break line \"path.rl\":line\n```\n\nAdds a phrase, function or source-line breakpoint."
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase debug_breakpoints = "breakpoints" in debug {
  docs "```recurloop\ndebug:breakpoints\n```\n\nLists configured breakpoints and their identifiers."
  type phrase_types_scoped_callable
  action host "debugger.breakpoints"
}

phrase debug_continue = "continue" in debug {
  docs "```recurloop\ndebug:continue\n```\n\nResumes execution until the next breakpoint or program exit."
  type phrase_types_scoped_callable
  action host "debugger.continue"
}

phrase debug_delete = "delete" in debug {
  docs "```recurloop\ndebug:delete id\n```\n\nDeletes the breakpoint with the listed identifier."
  type phrase_types_scoped_callable
  action host "debugger.delete"
}

phrase debug_dictionary = "dictionary" in debug {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase debug_eval = "eval" in debug {
  docs "```recurloop\ndebug:eval expression\n```\n\nEvaluates an expression in the current debugging context."
  type phrase_types_scoped_callable
  action host "debugger.evaluate"
}

phrase debug_executable = "executable" in debug {
  docs "```recurloop\ndebug:executable run \"path\"\n```\n\nStarts a native executable under the debugger. Emit it with `emit executable debug` for source-level information."
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase debug_finish = "finish" in debug {
  docs "```recurloop\ndebug:finish\n```\n\nResumes until the current source scope or native function finishes."
  type phrase_types_scoped_callable
  action host "debugger.finish"
}

phrase debug_locals = "locals" in debug {
  docs "```recurloop\ndebug:locals\n```\n\nLists native local variables in the selected frame."
  type phrase_types_scoped_callable
  action host "debugger.locals"
}

phrase debug_children = "children" in debug {
  docs "```recurloop\ndebug:children \"variable.path\"\ndebug:children \"variable.path\", start, count\n```\n\nLists native record fields or array elements. The default range starts at zero and takes up to 100 children; explicit count is limited to 1024."
  type phrase_types_scoped_callable
  action host "debugger.children"
}

phrase debug_value = "value" in debug {
  docs "```recurloop\ndebug:value \"variable.path\"\n```\n\nDisplays a native variable or member from the selected frame. Example: `debug:value \"point.x\"`."
  type phrase_types_scoped_callable
  action host "debugger.value"
}

phrase debug_threads = "threads" in debug {
  docs "```recurloop\ndebug:threads\n```\n\nLists threads in the native process."
  type phrase_types_scoped_callable
  action host "debugger.threads"
}

phrase debug_thread = "thread" in debug {
  docs "```recurloop\ndebug:thread id\n```\n\nSelects a native thread using its listed identifier."
  type phrase_types_scoped_callable
  action host "debugger.thread"
}

phrase debug_next = "next" in debug {
  docs "```recurloop\ndebug:next\n```\n\nSteps over the next phrase or native source statement."
  type phrase_types_scoped_callable
  action host "debugger.next"
}

phrase debug_ping = "ping" in debug {
  docs "```recurloop\ndebug:ping\n```\n\nWrites `pong`; useful for checking phrase aliases."
  type phrase_types_scoped_callable
  action host "language.ping"
}

phrase debug_registers = "registers" in debug {
  docs "```recurloop\ndebug:registers\n```\n\nDisplays native CPU registers."
  type phrase_types_scoped_callable
  action host "debugger.registers"
}

phrase debug_run = "run" in debug {
  docs "```recurloop\ndebug:run \"path.rl\"\n```\n\nExecutes source with phrase-aware debugging enabled."
  type phrase_types_callable
  action host "debugger.run"
}

phrase debug_stats = "stats" in debug {
  docs "```recurloop\ndebug:stats\n```\n\nPrints process CPU, memory and I/O metrics plus engine arena, JIT and timing statistics."
  type phrase_types_scoped_callable
  action host "debug.stats"
}

phrase debug_step = "step" in debug {
  docs "```recurloop\ndebug:step\n```\n\nSteps into the next phrase or native source statement."
  type phrase_types_scoped_callable
  action host "debugger.step"
}

phrase debug_trace = "trace" in debug {
  docs "```recurloop\ndebug:trace on\ndebug:trace off\n```\n\nEnables or disables phrase execution tracing."
  dictionary
  type phrase_types_scoped_callable
  action host "debugger.trace"
}

phrase debug_where = "where" in debug {
  docs "```recurloop\ndebug:where\n```\n\nShows the current execution location."
  type phrase_types_scoped_callable
  action host "debugger.where"
}

phrase debug_workspace = "workspace" in debug {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase emit_language = "\0language" in emit {
  type phrase_types_data
  language compiler
}

phrase emit_tab = "\t" in emit {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_newline = "\n" in emit {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_vertical_tab = "\x0b" in emit {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_carriage_return = "\r" in emit {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_empty = " " in emit {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable = "executable" in emit {
  docs "```recurloop\nemit executable \"path\" main = fn () -> i64 { ... }\nemit executable debug \"path\" main = fn () -> i64 { ... }\n```\n\nCompiles and links a native executable. The `debug` form retains symbols and source/local information.\n\n**Example**\n\n```recurloop\nemit executable \"./hello\" main = fn () -> i64 { return 0 }\n```"
  dictionary
  type phrase_types_elaborate
  action host "assembler.output-begin"
}

phrase emit_object = "object" in emit {
  docs "```recurloop\nemit object \"path.o\" name = fn (...) -> result { ... }\n```\n\nWrites a relocatable native object. Link it into another output with `link object`.\n\n**Example**\n\n```recurloop\nemit object \"add.o\" add = fn (a:i64, b:i64) -> i64 { return a + b }\n```"
  dictionary
  type phrase_types_elaborate
  action host "assembler.output-begin"
}

phrase emit_raw = "raw" in emit {
  docs "```recurloop\nemit raw \"path.bin\" = hex { byte ... }\n```\n\nWrites the generated bytes without an object or executable wrapper. Hex bytes use two hexadecimal digits.\n\n**Example**\n\n```recurloop\nemit raw \"data.bin\" = hex { 52 4c 0a }\n```"
  dictionary
  type phrase_types_elaborate
  action host "assembler.output-begin"
}

phrase engine_tab = "\t" in engine {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase engine_newline = "\n" in engine {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase engine_vertical_tab = "\x0b" in engine {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase engine_carriage_return = "\r" in engine {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase engine_empty = " " in engine {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase engine_colon = ":" in engine {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase engine_define = "define" in engine {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nengine define {\n    phrase_definitions\n    ...\n}\n```\n\nReplaces the engine using core-definition source. Intended for language bootstrap; ordinary programs extend the current engine with `let` and `syntax`."
  type phrase_types_callable
  action host "engine.define"
}

phrase engine_export = "export" in engine {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nengine export \"image.rli\"\nengine export <lexicon> \"fragment.rli\"\n```\n\nSaves the current engine or an isolated lexicon fragment. Use `engine import` for an engine and `merge` for a fragment."
  type phrase_types_scoped_callable
  action host "engine.export"
}

phrase engine_import = "import" in engine {
  kind "keyword"
  color "#C586C0"
  docs "```recurloop\nengine import \"image.rli\"\n```\n\nLoads an engine image into the current context. Place the import before source that uses its definitions."
  type phrase_types_callable
  action host "engine.import"
}

phrase hex_tab = "\t" in hex {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_newline = "\n" in hex {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_vertical_tab = "\x0b" in hex {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_carriage_return = "\r" in hex {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_empty = " " in hex {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_lbrace = "{" in hex {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase let_language = "\0language" in let {
  type phrase_types_data
  language compiler
}

phrase let_equals = "=" in let {
  dictionary
  type phrase_types_elaborate
  action host "let.equals"
}

phrase lbrace_empty = "" in lbrace_055f92 {
  prototype root
  type phrase_types_elaborate
  action host "lookup.enter"
  successor lbrace_empty
}

phrase runtime_values_scopes_global = "global" in runtime_values_scopes {
  dictionary
  type phrase_types_data
}

phrase less_empty_empty = "" in less_empty {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase less_empty_tab = "\t" in less_empty {
  type phrase_types_elaborate
  action host "reference.whitespace"
}

phrase less_empty_newline = "\n" in less_empty {
  type phrase_types_elaborate
  action host "reference.whitespace"
}

phrase less_empty_vertical_tab = "\x0b" in less_empty {
  type phrase_types_elaborate
  action host "reference.whitespace"
}

phrase less_empty_carriage_return = "\r" in less_empty {
  type phrase_types_elaborate
  action host "reference.whitespace"
}

phrase less_empty_empty_5cc5a5 = " " in less_empty {
  type phrase_types_elaborate
  action host "reference.whitespace"
}

phrase less_empty_quote = "\"" in less_empty {
  prototype less_quote
  type phrase_types_elaborate
  action host "lookup.enter"
  successor none
}

phrase less_empty_empty_474108 = "${" in less_empty {
  type phrase_types_elaborate
  action host "name.interpolate"
}

phrase less_empty_apostrophe = "'" in less_empty {
  prototype less_apostrophe
  type phrase_types_elaborate
  action host "lookup.enter"
  successor none
}

phrase less_empty_colon = ":" in less_empty {
  prototype less_colon
  type phrase_types_elaborate
  action host "reference.colon"
  successor none
}

phrase less_empty_greater = ">" in less_empty {
  type phrase_types_elaborate
  action host "reference.commit"
}

phrase less_empty_backslash = "\\" in less_empty {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase less_empty_n = "\\n" in less_empty {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase less_empty_r = "\\r" in less_empty {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase less_empty_t = "\\t" in less_empty {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase less_empty_v = "\\v" in less_empty {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase less_quote_empty = "" in less_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase less_quote_quote = "\"" in less_quote {
  type phrase_types_elaborate
  action host "lookup.leave"
}

phrase less_quote_empty_4393b8 = "${" in less_quote {
  type phrase_types_elaborate
  action host "name.interpolate"
}

phrase less_quote_backslash = "\\" in less_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase less_quote_n = "\\n" in less_quote {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase less_quote_r = "\\r" in less_quote {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase less_quote_t = "\\t" in less_quote {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase less_quote_v = "\\v" in less_quote {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase less_apostrophe_empty = "" in less_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase less_apostrophe_empty_ae65c2 = "${" in less_apostrophe {
  type phrase_types_elaborate
  action host "name.interpolate"
}

phrase less_apostrophe_apostrophe = "'" in less_apostrophe {
  type phrase_types_elaborate
  action host "lookup.leave"
}

phrase less_apostrophe_backslash = "\\" in less_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase less_apostrophe_n = "\\n" in less_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase less_apostrophe_r = "\\r" in less_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase less_apostrophe_t = "\\t" in less_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase less_apostrophe_v = "\\v" in less_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase lbracket_empty_empty = "" in lbracket_empty {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase lbracket_empty_tab = "\t" in lbracket_empty {
  type phrase_types_elaborate
  action host "dictionary.whitespace"
}

phrase lbracket_empty_newline = "\n" in lbracket_empty {
  type phrase_types_elaborate
  action host "dictionary.whitespace"
}

phrase lbracket_empty_vertical_tab = "\x0b" in lbracket_empty {
  type phrase_types_elaborate
  action host "dictionary.whitespace"
}

phrase lbracket_empty_carriage_return = "\r" in lbracket_empty {
  type phrase_types_elaborate
  action host "dictionary.whitespace"
}

phrase lbracket_empty_empty_e94d03 = " " in lbracket_empty {
  type phrase_types_elaborate
  action host "dictionary.whitespace"
}

phrase lbracket_empty_quote = "\"" in lbracket_empty {
  prototype lbracket_quote
  type phrase_types_elaborate
  action host "lookup.enter"
  successor none
}

phrase lbracket_empty_empty_93bab9 = "${" in lbracket_empty {
  type phrase_types_elaborate
  action host "name.interpolate"
}

phrase lbracket_empty_apostrophe = "'" in lbracket_empty {
  prototype lbracket_apostrophe
  type phrase_types_elaborate
  action host "lookup.enter"
  successor none
}

phrase lbracket_empty_equals = "=" in lbracket_empty {
  dictionary
  type phrase_types_elaborate
  action host "dictionary.equals"
}

phrase lbracket_empty_backslash = "\\" in lbracket_empty {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase lbracket_empty_n = "\\n" in lbracket_empty {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase lbracket_empty_r = "\\r" in lbracket_empty {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase lbracket_empty_t = "\\t" in lbracket_empty {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase lbracket_empty_v = "\\v" in lbracket_empty {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase lbracket_empty_merge = "merge" in lbracket_empty {
  type phrase_types_elaborate
  action host "lexicon.merge"
}

phrase lbracket_quote_empty = "" in lbracket_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase lbracket_quote_quote = "\"" in lbracket_quote {
  type phrase_types_elaborate
  action host "lookup.leave"
}

phrase lbracket_quote_empty_6a50db = "${" in lbracket_quote {
  type phrase_types_elaborate
  action host "name.interpolate"
}

phrase lbracket_quote_backslash = "\\" in lbracket_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase lbracket_quote_n = "\\n" in lbracket_quote {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase lbracket_quote_r = "\\r" in lbracket_quote {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase lbracket_quote_t = "\\t" in lbracket_quote {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase lbracket_quote_v = "\\v" in lbracket_quote {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase lbracket_apostrophe_empty = "" in lbracket_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase lbracket_apostrophe_empty_b1c883 = "${" in lbracket_apostrophe {
  type phrase_types_elaborate
  action host "name.interpolate"
}

phrase lbracket_apostrophe_apostrophe = "'" in lbracket_apostrophe {
  type phrase_types_elaborate
  action host "lookup.leave"
}

phrase lbracket_apostrophe_backslash = "\\" in lbracket_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase lbracket_apostrophe_n = "\\n" in lbracket_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase lbracket_apostrophe_r = "\\r" in lbracket_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase lbracket_apostrophe_t = "\\t" in lbracket_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase lbracket_apostrophe_v = "\\v" in lbracket_apostrophe {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase debug_break_tab = "\t" in debug_break {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_break_newline = "\n" in debug_break {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_break_vertical_tab = "\x0b" in debug_break {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_break_carriage_return = "\r" in debug_break {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_break_empty = " " in debug_break {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_break_colon = ":" in debug_break {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_break_function = "function" in debug_break {
  docs "```recurloop\ndebug:break function \"name\"\n```\n\nAdds a breakpoint at a native function entry."
  type phrase_types_scoped_callable
  action host "debugger.break-function"
}

phrase debug_break_line = "line" in debug_break {
  docs "```recurloop\ndebug:break line \"path.rl\":line\n```\n\nStops at a one-based source line. Example: `debug:break line \"main.rl\":12`."
  type phrase_types_scoped_callable
  action host "debugger.break-line"
}

phrase debug_break_phrase = "phrase" in debug_break {
  docs "```recurloop\ndebug:break phrase \"name\"\n```\n\nStops when the named phrase is reached."
  type phrase_types_scoped_callable
  action host "debugger.break-phrase"
}

phrase debug_dictionary_tab = "\t" in debug_dictionary {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_dictionary_newline = "\n" in debug_dictionary {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_dictionary_vertical_tab = "\x0b" in debug_dictionary {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_dictionary_carriage_return = "\r" in debug_dictionary {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_dictionary_empty = " " in debug_dictionary {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_dictionary_colon = ":" in debug_dictionary {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_dictionary_dump = "dump" in debug_dictionary {
  type phrase_types_scoped_callable
  action host "debug.dictionary-dump"
}

phrase debug_executable_tab = "\t" in debug_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_executable_newline = "\n" in debug_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_executable_vertical_tab = "\x0b" in debug_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_executable_carriage_return = "\r" in debug_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_executable_empty = " " in debug_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_executable_colon = ":" in debug_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_executable_run = "run" in debug_executable {
  docs "```recurloop\ndebug:executable run \"path\"\n```\n\nStarts native debugging with the configured breakpoints."
  type phrase_types_callable
  action host "debugger.executable-run"
}

phrase debug_trace_off = "off" in debug_trace {
  docs "```recurloop\ndebug:trace off\n```\n\nDisables phrase execution tracing."
  prototype off
  type phrase_types_data
  action host ""
  boolean false
}

phrase debug_trace_on = "on" in debug_trace {
  docs "```recurloop\ndebug:trace on\n```\n\nEnables phrase execution tracing."
  prototype on
  type phrase_types_data
  action host ""
  boolean true
}

phrase debug_workspace_tab = "\t" in debug_workspace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_workspace_newline = "\n" in debug_workspace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_workspace_vertical_tab = "\x0b" in debug_workspace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_workspace_carriage_return = "\r" in debug_workspace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_workspace_empty = " " in debug_workspace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_workspace_colon = ":" in debug_workspace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase debug_workspace_print = "print" in debug_workspace {
  type phrase_types_scoped_callable
  action host "debug.workspace-print"
}

phrase emit_executable_tab = "\t" in emit_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_newline = "\n" in emit_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_vertical_tab = "\x0b" in emit_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_carriage_return = "\r" in emit_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_empty = " " in emit_executable {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_quote = "\"" in emit_executable {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase emit_executable_debug = "debug" in emit_executable {
  docs "```recurloop\nemit executable debug \"path\" main = fn () -> i64 { ... }\n```\n\nEmits a native executable with symbols and source/local information for debugging."
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase emit_executable_debug_tab = "\t" in emit_executable_debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_debug_newline = "\n" in emit_executable_debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_debug_vertical_tab = "\x0b" in emit_executable_debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_debug_carriage_return = "\r" in emit_executable_debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_debug_empty = " " in emit_executable_debug {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_debug_quote = "\"" in emit_executable_debug {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase emit_object_tab = "\t" in emit_object {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_object_newline = "\n" in emit_object {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_object_vertical_tab = "\x0b" in emit_object {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_object_carriage_return = "\r" in emit_object {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_object_empty = " " in emit_object {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_object_quote = "\"" in emit_object {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase emit_raw_tab = "\t" in emit_raw {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_raw_newline = "\n" in emit_raw {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_raw_vertical_tab = "\x0b" in emit_raw {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_raw_carriage_return = "\r" in emit_raw {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_raw_empty = " " in emit_raw {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_raw_quote = "\"" in emit_raw {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase hex_lbrace_empty = "" in hex_lbrace {
  type phrase_types_elaborate
  action host "hex.byte"
}

phrase hex_lbrace_tab = "\t" in hex_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_lbrace_newline = "\n" in hex_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_lbrace_vertical_tab = "\x0b" in hex_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_lbrace_carriage_return = "\r" in hex_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_lbrace_empty_86f142 = " " in hex_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase hex_lbrace_rbrace = "}" in hex_lbrace {
  type phrase_types_elaborate
  action host "lookup.leave"
}

phrase let_equals_empty = "" in let_equals {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase let_equals_empty_0240c0 = "" in let_equals {
  prototype root
  type phrase_types_elaborate
  action host "lookup.enter"
  successor let_equals_empty
}

phrase let_equals_tab = "\t" in let_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase let_equals_newline = "\n" in let_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase let_equals_vertical_tab = "\x0b" in let_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase let_equals_carriage_return = "\r" in let_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase let_equals_empty_489e3c = " " in let_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_empty_equals_empty = "" in lbracket_empty_equals {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase lbracket_empty_equals_empty_8e5e19 = "" in lbracket_empty_equals {
  prototype root
  type phrase_types_elaborate
  action host "lookup.enter"
  successor lbracket_empty_equals_empty
}

phrase lbracket_empty_equals_tab = "\t" in lbracket_empty_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_empty_equals_newline = "\n" in lbracket_empty_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_empty_equals_vertical_tab = "\x0b" in lbracket_empty_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_empty_equals_carriage_return = "\r" in lbracket_empty_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase lbracket_empty_equals_empty_e104d8 = " " in lbracket_empty_equals {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase emit_executable_quote_empty = "" in emit_executable_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase emit_executable_quote_quote = "\"" in emit_executable_quote {
  type phrase_types_elaborate
  action host "assembler.executable-end"
}

phrase emit_executable_quote_backslash = "\\" in emit_executable_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase emit_executable_quote_n = "\\n" in emit_executable_quote {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase emit_executable_quote_r = "\\r" in emit_executable_quote {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase emit_executable_quote_t = "\\t" in emit_executable_quote {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase emit_executable_quote_v = "\\v" in emit_executable_quote {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase emit_executable_debug_quote_empty = "" in emit_executable_debug_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase emit_executable_debug_quote_quote = "\"" in emit_executable_debug_quote {
  type phrase_types_elaborate
  action host "assembler.executable-debug-end"
}

phrase emit_executable_debug_quote_backslash = "\\" in emit_executable_debug_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase emit_executable_debug_quote_n = "\\n" in emit_executable_debug_quote {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase emit_executable_debug_quote_r = "\\r" in emit_executable_debug_quote {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase emit_executable_debug_quote_t = "\\t" in emit_executable_debug_quote {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase emit_executable_debug_quote_v = "\\v" in emit_executable_debug_quote {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase emit_object_quote_empty = "" in emit_object_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase emit_object_quote_quote = "\"" in emit_object_quote {
  type phrase_types_elaborate
  action host "assembler.object-end"
}

phrase emit_object_quote_backslash = "\\" in emit_object_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase emit_object_quote_n = "\\n" in emit_object_quote {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase emit_object_quote_r = "\\r" in emit_object_quote {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase emit_object_quote_t = "\\t" in emit_object_quote {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase emit_object_quote_v = "\\v" in emit_object_quote {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase emit_raw_quote_empty = "" in emit_raw_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase emit_raw_quote_quote = "\"" in emit_raw_quote {
  type phrase_types_elaborate
  action host "assembler.raw-end"
}

phrase emit_raw_quote_backslash = "\\" in emit_raw_quote {
  type phrase_types_elaborate
  action host "workspace.pass-byte"
}

phrase emit_raw_quote_n = "\\n" in emit_raw_quote {
  type phrase_types_elaborate
  action host "workspace.pass-lf"
}

phrase emit_raw_quote_r = "\\r" in emit_raw_quote {
  type phrase_types_elaborate
  action host "workspace.pass-cr"
}

phrase emit_raw_quote_t = "\\t" in emit_raw_quote {
  type phrase_types_elaborate
  action host "workspace.pass-tab"
}

phrase emit_raw_quote_v = "\\v" in emit_raw_quote {
  type phrase_types_elaborate
  action host "workspace.pass-vtab"
}

phrase let_equals_empty_empty = "" in let_equals_empty {
  type phrase_types_elaborate
  action host "let.commit-anonymous"
}

phrase empty_equals_empty_empty = "" in lbracket_empty_equals_empty {
  type phrase_types_elaborate
  action host "dictionary.commit"
}

// Bitwise punctuation is matched through the ordinary phrase dictionary.
phrase bit_pipe = "|" in root {
  docs "```recurloop\nleft | right\n```\n\nCombines integer bits with OR."
  type phrase_types_data
}

phrase bit_caret = "^" in root {
  docs "```recurloop\nleft ^ right\n```\n\nCombines integer bits with XOR."
  type phrase_types_data
}

phrase bit_tilde = "~" in root {
  docs "```recurloop\n~expression\n```\n\nInverts all integer bits."
  type phrase_types_data
}

phrase bit_shift_left = "<<" in root {
  docs "```recurloop\nleft << right\n```\n\nShifts integer bits left, discarding bits past the width."
  type phrase_types_data
}

phrase bit_shift_right = ">>" in root {
  docs "```recurloop\nleft >> right\n```\n\nShifts right arithmetically for signed types and logically for unsigned types."
  type phrase_types_data
}

phrase bit_and_equals = "&=" in root {
  docs "```recurloop\ntarget &= expression\n```\n\nApplies `&` to the target and expression, then stores the result in the target."
  prototype expressions_infix_bit_and
  type phrase_types_data
}

phrase bit_or_equals = "|=" in root {
  docs "```recurloop\ntarget |= expression\n```\n\nApplies `|` to the target and expression, then stores the result in the target."
  prototype expressions_infix_bit_or
  type phrase_types_data
}

phrase bit_xor_equals = "^=" in root {
  docs "```recurloop\ntarget ^= expression\n```\n\nApplies `^` to the target and expression, then stores the result in the target."
  prototype expressions_infix_bit_xor
  type phrase_types_data
}

phrase bit_shift_left_equals = "<<=" in root {
  docs "```recurloop\ntarget <<= expression\n```\n\nApplies `<<` to the target and expression, then stores the result in the target."
  prototype expressions_infix_shift_left
  type phrase_types_data
}

phrase bit_shift_right_equals = ">>=" in root {
  docs "```recurloop\ntarget >>= expression\n```\n\nApplies `>>` to the target and expression, then stores the result in the target."
  prototype expressions_infix_shift_right
  type phrase_types_data
}

phrase debug_terminal = "terminal" in debug {
  docs "```recurloop\ndebug:terminal \"device_path\"\n```\n\nSelects the terminal device for native application input and output."
  type phrase_types_scoped_callable
  action host "debugger.terminal"
}

phrase debug_stack = "stack" in debug {
  docs "```recurloop\ndebug:stack\n```\n\nLists native call frames and their identifiers."
  type phrase_types_scoped_callable
  action host "debugger.stack"
}

phrase debug_frame = "frame" in debug {
  docs "```recurloop\ndebug:frame id\n```\n\nSelects a native call frame for variable inspection; frame identifiers start at zero."
  type phrase_types_scoped_callable
  action host "debugger.frame"
}

phrase debug_set = "set" in debug {
  docs "```recurloop\ndebug:set name = expression\n```\n\nWrites a native scalar variable in the selected frame."
  type phrase_types_scoped_callable
  action host "debugger.set"
}
