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
  type phrase_types_data
}

phrase not_equal = "!=" in root {
  type phrase_types_data
}

phrase percent = "%" in root {
  type phrase_types_data
}

phrase percent_equals = "%=" in root {
  prototype expressions_infix_percent
  type phrase_types_data
}

phrase ampersand = "&" in root {
  type phrase_types_data
}

phrase and_and = "&&" in root {
  type phrase_types_data
}

phrase lparen = "(" in root {
  type phrase_types_data
}

phrase rparen = ")" in root {
  type phrase_types_data
}

phrase star = "*" in root {
  type phrase_types_data
}

phrase star_equals = "*=" in root {
  prototype expressions_infix_star
  type phrase_types_data
}

phrase plus = "+" in root {
  type phrase_types_data
}

phrase plus_equals = "+=" in root {
  prototype expressions_infix_plus
  type phrase_types_data
}

phrase comma = "," in root {
  type phrase_types_data
}

phrase minus = "-" in root {
  type phrase_types_data
}

phrase minus_equals = "-=" in root {
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
  type phrase_types_data
}

phrase data = ".data" in root {
  type phrase_types_data
}

phrase rodata = ".rodata" in root {
  type phrase_types_data
}

phrase section = ".section" in root {
  type phrase_types_data
}

phrase text = ".text" in root {
  type phrase_types_data
}

phrase slash = "/" in root {
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
  prototype expressions_infix_slash
  type phrase_types_data
}

phrase colon = ":" in root {
  type phrase_types_data
}

phrase semicolon = ";" in root {
  type phrase_types_data
}

phrase less = "<" in root {
  type phrase_types_data
}

phrase less_b2d74b = "<" in root {
  dictionary
  type phrase_types_elaborate
  action host "reference.enter"
}

phrase less_equal = "<=" in root {
  type phrase_types_data
}

phrase equals = "=" in root {
  type phrase_types_data
}

phrase equal_equal = "==" in root {
  type phrase_types_data
}

phrase greater = ">" in root {
  type phrase_types_data
}

phrase greater_equal = ">=" in root {
  type phrase_types_data
}

phrase question = "?" in root {
  type phrase_types_data
}

phrase lbracket = "[" in root {
  type phrase_types_data
}

phrase lbracket_862dc1 = "[" in root {
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
  type phrase_types_data
}

phrase continue = "continue" in root {
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
  type phrase_types_data
}

phrase dd = "dd" in root {
  type phrase_types_data
}

phrase debug = "debug" in root {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase dec = "dec" in root {
  type phrase_types_data
}

phrase defer = "defer" in root {
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
  type phrase_types_data
}

phrase dw = "dw" in root {
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
  type phrase_types_data
}

phrase embed = "embed" in root {
  type phrase_types_data
}

phrase emit = "emit" in root {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase ends_with = "ends_with" in root {
  type phrase_types_data
}

phrase engine = "engine" in root {
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
  type phrase_types_elaborate
  action host "language.exit"
}

phrase false = "false" in root {
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
  type phrase_types_data
}

phrase imul = "imul" in root {
  type phrase_types_data
}

phrase inc = "inc" in root {
  type phrase_types_data
}

phrase include = "include" in root {
  type phrase_types_data
}

phrase include_b26ec9 = "include" in root {
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
  type phrase_types_data
}

phrase let = "let" in root {
  dictionary
  type phrase_types_elaborate
  action host "let.enter"
}

phrase lexicon = "lexicon" in root {
  type phrase_types_elaborate
  action host "lexicon.create"
}

phrase library = "library" in root {
  type phrase_types_data
}

phrase lower = "lower" in root {
  type phrase_types_data
}

phrase manual = "manual" in root {
  type phrase_types_data
}

phrase merge = "merge" in root {
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
  type phrase_types_data
}

phrase object = "object" in root {
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
  type phrase_types_data
}

phrase resb = "resb" in root {
  type phrase_types_data
}

phrase result = "result" in root {
  type phrase_types_data
}

phrase ret = "ret" in root {
  type phrase_types_data
}

phrase return = "return" in root {
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
  type phrase_types_data
}

phrase strings = "strings" in root {
  type phrase_types_data
}

phrase strip = "strip" in root {
  type phrase_types_data
}

phrase struct = "struct" in root {
  prototype let
  type phrase_types_elaborate
  action host "let.enter"
}

phrase sub = "sub" in root {
  type phrase_types_data
}

phrase substr = "substr" in root {
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
  type phrase_types_data
}

phrase true = "true" in root {
  type phrase_types_data
}

phrase type = "type" in root {
  type phrase_types_data
}

phrase ud2 = "ud2" in root {
  type phrase_types_data
}

phrase up = "up" in root {
  type phrase_types_data
}

phrase upper = "upper" in root {
  type phrase_types_data
}

phrase value = "value" in root {
  type phrase_types_data
}

phrase while = "while" in root {
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
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase debug_breakpoints = "breakpoints" in debug {
  type phrase_types_scoped_callable
  action host "debugger.breakpoints"
}

phrase debug_continue = "continue" in debug {
  type phrase_types_scoped_callable
  action host "debugger.continue"
}

phrase debug_delete = "delete" in debug {
  type phrase_types_scoped_callable
  action host "debugger.delete"
}

phrase debug_dictionary = "dictionary" in debug {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase debug_eval = "eval" in debug {
  type phrase_types_scoped_callable
  action host "debugger.evaluate"
}

phrase debug_executable = "executable" in debug {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase debug_finish = "finish" in debug {
  type phrase_types_scoped_callable
  action host "debugger.finish"
}

phrase debug_locals = "locals" in debug {
  type phrase_types_scoped_callable
  action host "debugger.locals"
}

phrase debug_next = "next" in debug {
  type phrase_types_scoped_callable
  action host "debugger.next"
}

phrase debug_ping = "ping" in debug {
  type phrase_types_scoped_callable
  action host "language.ping"
}

phrase debug_registers = "registers" in debug {
  type phrase_types_scoped_callable
  action host "debugger.registers"
}

phrase debug_run = "run" in debug {
  type phrase_types_callable
  action host "debugger.run"
}

phrase debug_stats = "stats" in debug {
  type phrase_types_scoped_callable
  action host "debug.stats"
}

phrase debug_step = "step" in debug {
  type phrase_types_scoped_callable
  action host "debugger.step"
}

phrase debug_trace = "trace" in debug {
  dictionary
  type phrase_types_scoped_callable
  action host "debugger.trace"
}

phrase debug_where = "where" in debug {
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
  dictionary
  type phrase_types_elaborate
  action host "assembler.output-begin"
}

phrase emit_object = "object" in emit {
  dictionary
  type phrase_types_elaborate
  action host "assembler.output-begin"
}

phrase emit_raw = "raw" in emit {
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
  type phrase_types_callable
  action host "engine.define"
}

phrase engine_export = "export" in engine {
  type phrase_types_scoped_callable
  action host "engine.export"
}

phrase engine_import = "import" in engine {
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
  type phrase_types_scoped_callable
  action host "debugger.break-function"
}

phrase debug_break_line = "line" in debug_break {
  type phrase_types_scoped_callable
  action host "debugger.break-line"
}

phrase debug_break_phrase = "phrase" in debug_break {
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
  type phrase_types_callable
  action host "debugger.executable-run"
}

phrase debug_trace_off = "off" in debug_trace {
  prototype off
  type phrase_types_data
  action host ""
  boolean false
}

phrase debug_trace_on = "on" in debug_trace {
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
