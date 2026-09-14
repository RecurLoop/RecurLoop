// Assembler vocabulary. Registers, instructions, sections and widths are named declarations.

phrase asm = "asm" in root {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
}

phrase invoke = "invoke" in root {
  type phrase_types_elaborate
  action host "assembler.invoke"
  language compiler
}

phrase asm_language = "\0language" in asm {
  type phrase_types_data
  language compiler
}

phrase asm_tab = "\t" in asm {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_newline = "\n" in asm {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_vertical_tab = "\x0b" in asm {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_carriage_return = "\r" in asm {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_empty = " " in asm {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_lbrace = "{" in asm {
  dictionary
  type phrase_types_elaborate
  action host "assembler.begin"
}

phrase asm_lbrace_empty = "" in asm_lbrace {
  type phrase_types_elaborate
  action host "assembler.unknown"
}

phrase asm_lbrace_tab = "\t" in asm_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_lbrace_newline = "\n" in asm_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_lbrace_vertical_tab = "\x0b" in asm_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_lbrace_carriage_return = "\r" in asm_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_lbrace_empty_808d8d = " " in asm_lbrace {
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_lbrace_bss = ".bss" in asm_lbrace {
  prototype bss
  type phrase_types_elaborate
  action host "assembler.section"
  section bss
}

phrase asm_lbrace_data = ".data" in asm_lbrace {
  prototype data
  type phrase_types_elaborate
  action host "assembler.section"
  section data
}

phrase asm_lbrace_rodata = ".rodata" in asm_lbrace {
  prototype rodata
  type phrase_types_elaborate
  action host "assembler.section"
  section rodata
}

phrase asm_lbrace_section = ".section" in asm_lbrace {
  dictionary
  prototype section
  type phrase_types_elaborate
  action host "assembler.custom-section"
}

phrase asm_lbrace_text = ".text" in asm_lbrace {
  prototype text
  type phrase_types_elaborate
  action host "assembler.section"
  section text
}

phrase asm_lbrace_line_comment = "//" in asm_lbrace {
  type phrase_types_elaborate
  action host "assembler.comment"
}

phrase asm_lbrace_semicolon = ";" in asm_lbrace {
  prototype semicolon
  type phrase_types_elaborate
  action host "language.ignore"
}

phrase asm_lbrace_adc = "adc" in asm_lbrace {
  prototype adc
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "adc"
}

phrase asm_lbrace_add = "add" in asm_lbrace {
  prototype add
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "add"
}

phrase asm_lbrace_and = "and" in asm_lbrace {
  prototype and
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "and"
}

phrase asm_lbrace_assembler_memory_expect = "assembler-memory-expect" in asm_lbrace {
  dictionary
  type phrase_types_data
  action host ""
}

phrase asm_lbrace_assembler_memory_register = "assembler-memory-register" in asm_lbrace {
  dictionary
  type phrase_types_data
  action host ""
}

phrase asm_lbrace_assembler_memory_scale = "assembler-memory-scale" in asm_lbrace {
  dictionary
  type phrase_types_data
  action host ""
}

phrase asm_lbrace_assembler_memory_term = "assembler-memory-term" in asm_lbrace {
  dictionary
  type phrase_types_data
  action host ""
}

phrase asm_lbrace_assembler_operand_complete = "assembler-operand-complete" in asm_lbrace {
  dictionary
  type phrase_types_data
  action host ""
}

phrase asm_lbrace_assembler_operand_size_bracket = "assembler-operand-size-bracket" in asm_lbrace {
  dictionary
  type phrase_types_data
  action host ""
}

phrase asm_lbrace_assembler_operand_size_whitespace = "assembler-operand-size-whitespace" in asm_lbrace {
  dictionary
  type phrase_types_data
  action host ""
}

phrase asm_lbrace_assembler_operands = "assembler-operands" in asm_lbrace {
  dictionary
  type phrase_types_data
  action host ""
}

phrase asm_lbrace_bswap = "bswap" in asm_lbrace {
  prototype bswap
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "bswap"
}

phrase asm_lbrace_call = "call" in asm_lbrace {
  prototype call
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "call"
}

phrase asm_lbrace_cdq = "cdq" in asm_lbrace {
  prototype cdq
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "cdq"
}

phrase asm_lbrace_clc = "clc" in asm_lbrace {
  prototype clc
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "clc"
}

phrase asm_lbrace_cld = "cld" in asm_lbrace {
  prototype cld
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "cld"
}

phrase asm_lbrace_cli = "cli" in asm_lbrace {
  prototype cli
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "cli"
}

phrase asm_lbrace_cmc = "cmc" in asm_lbrace {
  prototype cmc
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "cmc"
}

phrase asm_lbrace_cmp = "cmp" in asm_lbrace {
  prototype cmp
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "cmp"
}

phrase asm_lbrace_cpuid = "cpuid" in asm_lbrace {
  prototype cpuid
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "cpuid"
}

phrase asm_lbrace_cqo = "cqo" in asm_lbrace {
  prototype cqo
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "cqo"
}

phrase asm_lbrace_db = "db" in asm_lbrace {
  prototype db
  type phrase_types_elaborate
  action host "assembler.bytes"
  byte-width 1
}

phrase asm_lbrace_dd = "dd" in asm_lbrace {
  prototype dd
  type phrase_types_elaborate
  action host "assembler.bytes"
  byte-width 4
}

phrase asm_lbrace_dec = "dec" in asm_lbrace {
  prototype dec
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "dec"
}

phrase asm_lbrace_div = "div" in asm_lbrace {
  prototype div
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "div"
}

phrase asm_lbrace_dq = "dq" in asm_lbrace {
  prototype dq
  type phrase_types_elaborate
  action host "assembler.bytes"
  byte-width 8
}

phrase asm_lbrace_dw = "dw" in asm_lbrace {
  prototype dw
  type phrase_types_elaborate
  action host "assembler.bytes"
  byte-width 2
}

phrase asm_lbrace_hlt = "hlt" in asm_lbrace {
  prototype hlt
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "hlt"
}

phrase asm_lbrace_idiv = "idiv" in asm_lbrace {
  prototype idiv
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "idiv"
}

phrase asm_lbrace_imul = "imul" in asm_lbrace {
  prototype imul
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "imul"
}

phrase asm_lbrace_inc = "inc" in asm_lbrace {
  prototype inc
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "inc"
}

phrase asm_lbrace_int = "int" in asm_lbrace {
  prototype int
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "int"
}

phrase asm_lbrace_int3 = "int3" in asm_lbrace {
  prototype int3
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "int3"
}

phrase asm_lbrace_invoke = "invoke" in asm_lbrace {
  prototype invoke
  type phrase_types_elaborate
  action host "assembler.invoke"
}

phrase asm_lbrace_ja = "ja" in asm_lbrace {
  prototype ja
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "ja"
}

phrase asm_lbrace_jae = "jae" in asm_lbrace {
  prototype jae
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jae"
}

phrase asm_lbrace_jb = "jb" in asm_lbrace {
  prototype jb
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jb"
}

phrase asm_lbrace_jbe = "jbe" in asm_lbrace {
  prototype jbe
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jbe"
}

phrase asm_lbrace_jc = "jc" in asm_lbrace {
  prototype jc
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jc"
}

phrase asm_lbrace_je = "je" in asm_lbrace {
  prototype je
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "je"
}

phrase asm_lbrace_jg = "jg" in asm_lbrace {
  prototype jg
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jg"
}

phrase asm_lbrace_jge = "jge" in asm_lbrace {
  prototype jge
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jge"
}

phrase asm_lbrace_jl = "jl" in asm_lbrace {
  prototype jl
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jl"
}

phrase asm_lbrace_jle = "jle" in asm_lbrace {
  prototype jle
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jle"
}

phrase asm_lbrace_jmp = "jmp" in asm_lbrace {
  prototype jmp
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jmp"
}

phrase asm_lbrace_jna = "jna" in asm_lbrace {
  prototype jna
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jna"
}

phrase asm_lbrace_jnae = "jnae" in asm_lbrace {
  prototype jnae
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jnae"
}

phrase asm_lbrace_jnb = "jnb" in asm_lbrace {
  prototype jnb
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jnb"
}

phrase asm_lbrace_jnbe = "jnbe" in asm_lbrace {
  prototype jnbe
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jnbe"
}

phrase asm_lbrace_jnc = "jnc" in asm_lbrace {
  prototype jnc
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jnc"
}

phrase asm_lbrace_jne = "jne" in asm_lbrace {
  prototype jne
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jne"
}

phrase asm_lbrace_jng = "jng" in asm_lbrace {
  prototype jng
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jng"
}

phrase asm_lbrace_jnge = "jnge" in asm_lbrace {
  prototype jnge
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jnge"
}

phrase asm_lbrace_jnl = "jnl" in asm_lbrace {
  prototype jnl
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jnl"
}

phrase asm_lbrace_jnle = "jnle" in asm_lbrace {
  prototype jnle
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jnle"
}

phrase asm_lbrace_jno = "jno" in asm_lbrace {
  prototype jno
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jno"
}

phrase asm_lbrace_jnp = "jnp" in asm_lbrace {
  prototype jnp
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jnp"
}

phrase asm_lbrace_jns = "jns" in asm_lbrace {
  prototype jns
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jns"
}

phrase asm_lbrace_jnz = "jnz" in asm_lbrace {
  prototype jnz
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jnz"
}

phrase asm_lbrace_jo = "jo" in asm_lbrace {
  prototype jo
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jo"
}

phrase asm_lbrace_jp = "jp" in asm_lbrace {
  prototype jp
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jp"
}

phrase asm_lbrace_jpe = "jpe" in asm_lbrace {
  prototype jpe
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jpe"
}

phrase asm_lbrace_jpo = "jpo" in asm_lbrace {
  prototype jpo
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jpo"
}

phrase asm_lbrace_js = "js" in asm_lbrace {
  prototype js
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "js"
}

phrase asm_lbrace_jz = "jz" in asm_lbrace {
  prototype jz
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "jz"
}

phrase asm_lbrace_lea = "lea" in asm_lbrace {
  prototype lea
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "lea"
}

phrase asm_lbrace_leave = "leave" in asm_lbrace {
  prototype leave
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "leave"
}

phrase asm_lbrace_mov = "mov" in asm_lbrace {
  prototype mov
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "mov"
}

phrase asm_lbrace_movsx = "movsx" in asm_lbrace {
  prototype movsx
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "movsx"
}

phrase asm_lbrace_movsxd = "movsxd" in asm_lbrace {
  prototype movsxd
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "movsxd"
}

phrase asm_lbrace_movzx = "movzx" in asm_lbrace {
  prototype movzx
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "movzx"
}

phrase asm_lbrace_mul = "mul" in asm_lbrace {
  prototype mul
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "mul"
}

phrase asm_lbrace_neg = "neg" in asm_lbrace {
  prototype neg
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "neg"
}

phrase asm_lbrace_nop = "nop" in asm_lbrace {
  prototype nop
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "nop"
}

phrase asm_lbrace_not = "not" in asm_lbrace {
  prototype not_7a6e7b
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "not"
}

phrase asm_lbrace_or = "or" in asm_lbrace {
  prototype or
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "or"
}

phrase asm_lbrace_pop = "pop" in asm_lbrace {
  prototype pop
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "pop"
}

phrase asm_lbrace_popfq = "popfq" in asm_lbrace {
  prototype popfq
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "popfq"
}

phrase asm_lbrace_push = "push" in asm_lbrace {
  prototype push
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "push"
}

phrase asm_lbrace_pushfq = "pushfq" in asm_lbrace {
  prototype pushfq
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "pushfq"
}

phrase asm_lbrace_rdtsc = "rdtsc" in asm_lbrace {
  prototype rdtsc
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "rdtsc"
}

phrase asm_lbrace_resb = "resb" in asm_lbrace {
  prototype resb
  type phrase_types_elaborate
  action host "assembler.reserve"
}

phrase asm_lbrace_ret = "ret" in asm_lbrace {
  prototype ret
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "ret"
}

phrase asm_lbrace_rol = "rol" in asm_lbrace {
  prototype rol
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "rol"
}

phrase asm_lbrace_ror = "ror" in asm_lbrace {
  prototype ror
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "ror"
}

phrase asm_lbrace_sal = "sal" in asm_lbrace {
  prototype sal
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "sal"
}

phrase asm_lbrace_sar = "sar" in asm_lbrace {
  prototype sar
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "sar"
}

phrase asm_lbrace_sbb = "sbb" in asm_lbrace {
  prototype sbb
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "sbb"
}

phrase asm_lbrace_shl = "shl" in asm_lbrace {
  prototype shl
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "shl"
}

phrase asm_lbrace_shr = "shr" in asm_lbrace {
  prototype shr
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "shr"
}

phrase asm_lbrace_stc = "stc" in asm_lbrace {
  prototype stc
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "stc"
}

phrase asm_lbrace_std = "std" in asm_lbrace {
  prototype std
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "std"
}

phrase asm_lbrace_sti = "sti" in asm_lbrace {
  prototype sti
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "sti"
}

phrase asm_lbrace_sub = "sub" in asm_lbrace {
  prototype sub
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "sub"
}

phrase asm_lbrace_syscall = "syscall" in asm_lbrace {
  prototype syscall
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "syscall"
}

phrase asm_lbrace_test = "test" in asm_lbrace {
  prototype test
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "test"
}

phrase asm_lbrace_ud2 = "ud2" in asm_lbrace {
  prototype ud2
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "ud2"
}

phrase asm_lbrace_xchg = "xchg" in asm_lbrace {
  prototype xchg
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "xchg"
}

phrase asm_lbrace_xor = "xor" in asm_lbrace {
  prototype xor
  type phrase_types_elaborate
  action host "assembler.instruction"
  instruction "xor"
}

phrase asm_lbrace_rbrace = "}" in asm_lbrace {
  prototype rbrace
  type phrase_types_elaborate
  action host "assembler.end"
}

phrase asm_lbrace_section_align = "align" in asm_lbrace_section {
  prototype align
  type phrase_types_data
  action host ""
  section-alignment
}

phrase asm_lbrace_section_alloc = "alloc" in asm_lbrace_section {
  prototype alloc
  type phrase_types_data
  action host ""
  section-flag alloc
}

phrase asm_lbrace_section_dynamic = "dynamic" in asm_lbrace_section {
  prototype dynamic
  type phrase_types_data
  action host ""
  section-type dynamic
}

phrase asm_lbrace_section_exec = "exec" in asm_lbrace_section {
  prototype exec
  type phrase_types_data
  action host ""
  section-flag exec
}

phrase asm_lbrace_section_fini_array = "fini-array" in asm_lbrace_section {
  prototype fini_array
  type phrase_types_data
  action host ""
  section-type fini-array
}

phrase asm_lbrace_section_init_array = "init-array" in asm_lbrace_section {
  prototype init_array
  type phrase_types_data
  action host ""
  section-type init-array
}

phrase asm_lbrace_section_merge = "merge" in asm_lbrace_section {
  prototype merge
  type phrase_types_data
  action host ""
  section-flag merge
}

phrase asm_lbrace_section_nobits = "nobits" in asm_lbrace_section {
  prototype nobits
  type phrase_types_data
  action host ""
  section-type nobits
}

phrase asm_lbrace_section_note = "note" in asm_lbrace_section {
  prototype note
  type phrase_types_data
  action host ""
  section-type note
}

phrase asm_lbrace_section_preinit_array = "preinit-array" in asm_lbrace_section {
  prototype preinit_array
  type phrase_types_data
  action host ""
  section-type preinit-array
}

phrase asm_lbrace_section_strings = "strings" in asm_lbrace_section {
  prototype strings
  type phrase_types_data
  action host ""
  section-flag strings
}

phrase asm_lbrace_section_tls = "tls" in asm_lbrace_section {
  prototype tls
  type phrase_types_data
  action host ""
  section-flag tls
}

phrase asm_lbrace_section_write = "write" in asm_lbrace_section {
  prototype write
  type phrase_types_data
  action host ""
  section-flag write
}

phrase asm_lbrace_assembler_memory_expect_empty = "" in asm_lbrace_assembler_memory_expect {
  type phrase_types_elaborate
  action host "assembler.operand-dynamic"
}

phrase asm_lbrace_assembler_memory_expect_tab = "\t" in asm_lbrace_assembler_memory_expect {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_expect_vertical_tab = "\x0b" in asm_lbrace_assembler_memory_expect {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_expect_carriage_return = "\r" in asm_lbrace_assembler_memory_expect {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_expect_empty_c56680 = " " in asm_lbrace_assembler_memory_expect {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_expect_star = "*" in asm_lbrace_assembler_memory_expect {
  prototype star
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_expect_plus = "+" in asm_lbrace_assembler_memory_expect {
  prototype plus
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_expect_comma = "," in asm_lbrace_assembler_memory_expect {
  prototype comma
  type phrase_types_elaborate
  action host "assembler.operand-separator"
}

phrase asm_lbrace_assembler_memory_expect_minus = "-" in asm_lbrace_assembler_memory_expect {
  prototype minus
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_expect_line_comment = "//" in asm_lbrace_assembler_memory_expect {
  type phrase_types_elaborate
  action host "assembler.operand-comment"
}

phrase asm_lbrace_assembler_memory_expect_rbracket = "]" in asm_lbrace_assembler_memory_expect {
  prototype rbracket
  type phrase_types_elaborate
  action host "assembler.memory-end"
}

phrase asm_lbrace_assembler_memory_expect_ah = "ah" in asm_lbrace_assembler_memory_expect {
  prototype ah
  type phrase_types_elaborate
  action host "assembler.operand"
  register ah code 4 bits 8 high true rex false
}

phrase asm_lbrace_assembler_memory_expect_al = "al" in asm_lbrace_assembler_memory_expect {
  prototype al
  type phrase_types_elaborate
  action host "assembler.operand"
  register al code 0 bits 8 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_ax = "ax" in asm_lbrace_assembler_memory_expect {
  prototype ax
  type phrase_types_elaborate
  action host "assembler.operand"
  register ax code 0 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_bh = "bh" in asm_lbrace_assembler_memory_expect {
  prototype bh
  type phrase_types_elaborate
  action host "assembler.operand"
  register bh code 7 bits 8 high true rex false
}

phrase asm_lbrace_assembler_memory_expect_bl = "bl" in asm_lbrace_assembler_memory_expect {
  prototype bl
  type phrase_types_elaborate
  action host "assembler.operand"
  register bl code 3 bits 8 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_bp = "bp" in asm_lbrace_assembler_memory_expect {
  prototype bp
  type phrase_types_elaborate
  action host "assembler.operand"
  register bp code 5 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_bpl = "bpl" in asm_lbrace_assembler_memory_expect {
  prototype bpl
  type phrase_types_elaborate
  action host "assembler.operand"
  register bpl code 5 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_bx = "bx" in asm_lbrace_assembler_memory_expect {
  prototype bx
  type phrase_types_elaborate
  action host "assembler.operand"
  register bx code 3 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_ch = "ch" in asm_lbrace_assembler_memory_expect {
  prototype ch
  type phrase_types_elaborate
  action host "assembler.operand"
  register ch code 5 bits 8 high true rex false
}

phrase asm_lbrace_assembler_memory_expect_cl = "cl" in asm_lbrace_assembler_memory_expect {
  prototype cl
  type phrase_types_elaborate
  action host "assembler.operand"
  register cl code 1 bits 8 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_cx = "cx" in asm_lbrace_assembler_memory_expect {
  prototype cx
  type phrase_types_elaborate
  action host "assembler.operand"
  register cx code 1 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_dh = "dh" in asm_lbrace_assembler_memory_expect {
  prototype dh
  type phrase_types_elaborate
  action host "assembler.operand"
  register dh code 6 bits 8 high true rex false
}

phrase asm_lbrace_assembler_memory_expect_di = "di" in asm_lbrace_assembler_memory_expect {
  prototype di
  type phrase_types_elaborate
  action host "assembler.operand"
  register di code 7 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_dil = "dil" in asm_lbrace_assembler_memory_expect {
  prototype dil
  type phrase_types_elaborate
  action host "assembler.operand"
  register dil code 7 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_dl = "dl" in asm_lbrace_assembler_memory_expect {
  prototype dl
  type phrase_types_elaborate
  action host "assembler.operand"
  register dl code 2 bits 8 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_dx = "dx" in asm_lbrace_assembler_memory_expect {
  prototype dx
  type phrase_types_elaborate
  action host "assembler.operand"
  register dx code 2 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_eax = "eax" in asm_lbrace_assembler_memory_expect {
  prototype eax
  type phrase_types_elaborate
  action host "assembler.operand"
  register eax code 0 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_ebp = "ebp" in asm_lbrace_assembler_memory_expect {
  prototype ebp
  type phrase_types_elaborate
  action host "assembler.operand"
  register ebp code 5 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_ebx = "ebx" in asm_lbrace_assembler_memory_expect {
  prototype ebx
  type phrase_types_elaborate
  action host "assembler.operand"
  register ebx code 3 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_ecx = "ecx" in asm_lbrace_assembler_memory_expect {
  prototype ecx
  type phrase_types_elaborate
  action host "assembler.operand"
  register ecx code 1 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_edi = "edi" in asm_lbrace_assembler_memory_expect {
  prototype edi
  type phrase_types_elaborate
  action host "assembler.operand"
  register edi code 7 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_edx = "edx" in asm_lbrace_assembler_memory_expect {
  prototype edx
  type phrase_types_elaborate
  action host "assembler.operand"
  register edx code 2 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_esi = "esi" in asm_lbrace_assembler_memory_expect {
  prototype esi
  type phrase_types_elaborate
  action host "assembler.operand"
  register esi code 6 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_esp = "esp" in asm_lbrace_assembler_memory_expect {
  prototype esp
  type phrase_types_elaborate
  action host "assembler.operand"
  register esp code 4 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r10 = "r10" in asm_lbrace_assembler_memory_expect {
  prototype r10
  type phrase_types_elaborate
  action host "assembler.operand"
  register r10 code 10 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r10b = "r10b" in asm_lbrace_assembler_memory_expect {
  prototype r10b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r10b code 10 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_r10d = "r10d" in asm_lbrace_assembler_memory_expect {
  prototype r10d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r10d code 10 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r10w = "r10w" in asm_lbrace_assembler_memory_expect {
  prototype r10w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r10w code 10 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r11 = "r11" in asm_lbrace_assembler_memory_expect {
  prototype r11
  type phrase_types_elaborate
  action host "assembler.operand"
  register r11 code 11 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r11b = "r11b" in asm_lbrace_assembler_memory_expect {
  prototype r11b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r11b code 11 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_r11d = "r11d" in asm_lbrace_assembler_memory_expect {
  prototype r11d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r11d code 11 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r11w = "r11w" in asm_lbrace_assembler_memory_expect {
  prototype r11w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r11w code 11 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r12 = "r12" in asm_lbrace_assembler_memory_expect {
  prototype r12
  type phrase_types_elaborate
  action host "assembler.operand"
  register r12 code 12 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r12b = "r12b" in asm_lbrace_assembler_memory_expect {
  prototype r12b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r12b code 12 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_r12d = "r12d" in asm_lbrace_assembler_memory_expect {
  prototype r12d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r12d code 12 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r12w = "r12w" in asm_lbrace_assembler_memory_expect {
  prototype r12w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r12w code 12 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r13 = "r13" in asm_lbrace_assembler_memory_expect {
  prototype r13
  type phrase_types_elaborate
  action host "assembler.operand"
  register r13 code 13 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r13b = "r13b" in asm_lbrace_assembler_memory_expect {
  prototype r13b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r13b code 13 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_r13d = "r13d" in asm_lbrace_assembler_memory_expect {
  prototype r13d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r13d code 13 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r13w = "r13w" in asm_lbrace_assembler_memory_expect {
  prototype r13w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r13w code 13 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r14 = "r14" in asm_lbrace_assembler_memory_expect {
  prototype r14
  type phrase_types_elaborate
  action host "assembler.operand"
  register r14 code 14 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r14b = "r14b" in asm_lbrace_assembler_memory_expect {
  prototype r14b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r14b code 14 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_r14d = "r14d" in asm_lbrace_assembler_memory_expect {
  prototype r14d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r14d code 14 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r14w = "r14w" in asm_lbrace_assembler_memory_expect {
  prototype r14w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r14w code 14 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r15 = "r15" in asm_lbrace_assembler_memory_expect {
  prototype r15
  type phrase_types_elaborate
  action host "assembler.operand"
  register r15 code 15 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r15b = "r15b" in asm_lbrace_assembler_memory_expect {
  prototype r15b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r15b code 15 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_r15d = "r15d" in asm_lbrace_assembler_memory_expect {
  prototype r15d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r15d code 15 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r15w = "r15w" in asm_lbrace_assembler_memory_expect {
  prototype r15w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r15w code 15 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r8 = "r8" in asm_lbrace_assembler_memory_expect {
  prototype r8
  type phrase_types_elaborate
  action host "assembler.operand"
  register r8 code 8 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r8b = "r8b" in asm_lbrace_assembler_memory_expect {
  prototype r8b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r8b code 8 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_r8d = "r8d" in asm_lbrace_assembler_memory_expect {
  prototype r8d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r8d code 8 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r8w = "r8w" in asm_lbrace_assembler_memory_expect {
  prototype r8w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r8w code 8 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r9 = "r9" in asm_lbrace_assembler_memory_expect {
  prototype r9
  type phrase_types_elaborate
  action host "assembler.operand"
  register r9 code 9 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r9b = "r9b" in asm_lbrace_assembler_memory_expect {
  prototype r9b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r9b code 9 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_r9d = "r9d" in asm_lbrace_assembler_memory_expect {
  prototype r9d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r9d code 9 bits 32 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_r9w = "r9w" in asm_lbrace_assembler_memory_expect {
  prototype r9w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r9w code 9 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_rax = "rax" in asm_lbrace_assembler_memory_expect {
  prototype rax
  type phrase_types_elaborate
  action host "assembler.operand"
  register rax code 0 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_rbp = "rbp" in asm_lbrace_assembler_memory_expect {
  prototype rbp
  type phrase_types_elaborate
  action host "assembler.operand"
  register rbp code 5 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_rbx = "rbx" in asm_lbrace_assembler_memory_expect {
  prototype rbx
  type phrase_types_elaborate
  action host "assembler.operand"
  register rbx code 3 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_rcx = "rcx" in asm_lbrace_assembler_memory_expect {
  prototype rcx
  type phrase_types_elaborate
  action host "assembler.operand"
  register rcx code 1 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_rdi = "rdi" in asm_lbrace_assembler_memory_expect {
  prototype rdi
  type phrase_types_elaborate
  action host "assembler.operand"
  register rdi code 7 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_rdx = "rdx" in asm_lbrace_assembler_memory_expect {
  prototype rdx
  type phrase_types_elaborate
  action host "assembler.operand"
  register rdx code 2 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_rsi = "rsi" in asm_lbrace_assembler_memory_expect {
  prototype rsi
  type phrase_types_elaborate
  action host "assembler.operand"
  register rsi code 6 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_rsp = "rsp" in asm_lbrace_assembler_memory_expect {
  prototype rsp
  type phrase_types_elaborate
  action host "assembler.operand"
  register rsp code 4 bits 64 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_si = "si" in asm_lbrace_assembler_memory_expect {
  prototype si
  type phrase_types_elaborate
  action host "assembler.operand"
  register si code 6 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_sil = "sil" in asm_lbrace_assembler_memory_expect {
  prototype sil
  type phrase_types_elaborate
  action host "assembler.operand"
  register sil code 6 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_expect_sp = "sp" in asm_lbrace_assembler_memory_expect {
  prototype sp
  type phrase_types_elaborate
  action host "assembler.operand"
  register sp code 4 bits 16 high false rex false
}

phrase asm_lbrace_assembler_memory_expect_spl = "spl" in asm_lbrace_assembler_memory_expect {
  prototype spl
  type phrase_types_elaborate
  action host "assembler.operand"
  register spl code 4 bits 8 high false rex true
}

phrase asm_lbrace_assembler_memory_register_empty = "" in asm_lbrace_assembler_memory_register {
  type phrase_types_elaborate
  action host "assembler.operand-dynamic"
}

phrase asm_lbrace_assembler_memory_register_tab = "\t" in asm_lbrace_assembler_memory_register {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_register_vertical_tab = "\x0b" in asm_lbrace_assembler_memory_register {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_register_carriage_return = "\r" in asm_lbrace_assembler_memory_register {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_register_empty_acbc8b = " " in asm_lbrace_assembler_memory_register {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_register_star = "*" in asm_lbrace_assembler_memory_register {
  prototype star
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_register_plus = "+" in asm_lbrace_assembler_memory_register {
  prototype plus
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_register_comma = "," in asm_lbrace_assembler_memory_register {
  prototype comma
  type phrase_types_elaborate
  action host "assembler.operand-separator"
}

phrase asm_lbrace_assembler_memory_register_minus = "-" in asm_lbrace_assembler_memory_register {
  prototype minus
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_register_line_comment = "//" in asm_lbrace_assembler_memory_register {
  type phrase_types_elaborate
  action host "assembler.operand-comment"
}

phrase asm_lbrace_assembler_memory_register_rbracket = "]" in asm_lbrace_assembler_memory_register {
  prototype rbracket
  type phrase_types_elaborate
  action host "assembler.memory-end"
}

phrase asm_lbrace_assembler_memory_scale_empty = "" in asm_lbrace_assembler_memory_scale {
  type phrase_types_elaborate
  action host "assembler.operand-dynamic"
}

phrase asm_lbrace_assembler_memory_scale_tab = "\t" in asm_lbrace_assembler_memory_scale {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_scale_vertical_tab = "\x0b" in asm_lbrace_assembler_memory_scale {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_scale_carriage_return = "\r" in asm_lbrace_assembler_memory_scale {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_scale_empty_197f8c = " " in asm_lbrace_assembler_memory_scale {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_scale_star = "*" in asm_lbrace_assembler_memory_scale {
  prototype star
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_scale_plus = "+" in asm_lbrace_assembler_memory_scale {
  prototype plus
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_scale_comma = "," in asm_lbrace_assembler_memory_scale {
  prototype comma
  type phrase_types_elaborate
  action host "assembler.operand-separator"
}

phrase asm_lbrace_assembler_memory_scale_minus = "-" in asm_lbrace_assembler_memory_scale {
  prototype minus
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_scale_line_comment = "//" in asm_lbrace_assembler_memory_scale {
  type phrase_types_elaborate
  action host "assembler.operand-comment"
}

phrase asm_lbrace_assembler_memory_scale_rbracket = "]" in asm_lbrace_assembler_memory_scale {
  prototype rbracket
  type phrase_types_elaborate
  action host "assembler.memory-end"
}

phrase asm_lbrace_assembler_memory_term_empty = "" in asm_lbrace_assembler_memory_term {
  type phrase_types_elaborate
  action host "assembler.operand-dynamic"
}

phrase asm_lbrace_assembler_memory_term_tab = "\t" in asm_lbrace_assembler_memory_term {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_term_vertical_tab = "\x0b" in asm_lbrace_assembler_memory_term {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_term_carriage_return = "\r" in asm_lbrace_assembler_memory_term {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_term_empty_0400b5 = " " in asm_lbrace_assembler_memory_term {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_memory_term_star = "*" in asm_lbrace_assembler_memory_term {
  prototype star
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_term_plus = "+" in asm_lbrace_assembler_memory_term {
  prototype plus
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_term_comma = "," in asm_lbrace_assembler_memory_term {
  prototype comma
  type phrase_types_elaborate
  action host "assembler.operand-separator"
}

phrase asm_lbrace_assembler_memory_term_minus = "-" in asm_lbrace_assembler_memory_term {
  prototype minus
  type phrase_types_elaborate
  action host "assembler.memory-operator"
}

phrase asm_lbrace_assembler_memory_term_line_comment = "//" in asm_lbrace_assembler_memory_term {
  type phrase_types_elaborate
  action host "assembler.operand-comment"
}

phrase asm_lbrace_assembler_memory_term_rbracket = "]" in asm_lbrace_assembler_memory_term {
  prototype rbracket
  type phrase_types_elaborate
  action host "assembler.memory-end"
}

phrase asm_lbrace_assembler_operand_complete_empty = "" in asm_lbrace_assembler_operand_complete {
  type phrase_types_elaborate
  action host "assembler.operand-dynamic"
}

phrase asm_lbrace_assembler_operand_complete_tab = "\t" in asm_lbrace_assembler_operand_complete {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_complete_vertical_tab = "\x0b" in asm_lbrace_assembler_operand_complete {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_complete_carriage_return = "\r" in asm_lbrace_assembler_operand_complete {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_complete_empty_05704c = " " in asm_lbrace_assembler_operand_complete {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_complete_comma = "," in asm_lbrace_assembler_operand_complete {
  prototype comma
  type phrase_types_elaborate
  action host "assembler.operand-separator"
}

phrase asm_lbrace_assembler_operand_complete_line_comment = "//" in asm_lbrace_assembler_operand_complete {
  type phrase_types_elaborate
  action host "assembler.operand-comment"
}

phrase asm_lbrace_assembler_operand_size_bracket_empty = "" in asm_lbrace_assembler_operand_size_bracket {
  type phrase_types_elaborate
  action host "assembler.operand-dynamic"
}

phrase asm_lbrace_assembler_operand_size_bracket_tab = "\t" in asm_lbrace_assembler_operand_size_bracket {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_size_bracket_vertical_tab = "\x0b" in asm_lbrace_assembler_operand_size_bracket {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_size_bracket_carriage_return = "\r" in asm_lbrace_assembler_operand_size_bracket {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_size_bracket_empty_7a71fe = " " in asm_lbrace_assembler_operand_size_bracket {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_size_bracket_comma = "," in asm_lbrace_assembler_operand_size_bracket {
  prototype comma
  type phrase_types_elaborate
  action host "assembler.operand-separator"
}

phrase asm_lbrace_assembler_operand_size_bracket_line_comment = "//" in asm_lbrace_assembler_operand_size_bracket {
  type phrase_types_elaborate
  action host "assembler.operand-comment"
}

phrase asm_lbrace_assembler_operand_size_bracket_lbracket = "[" in asm_lbrace_assembler_operand_size_bracket {
  prototype lbracket_862dc1
  type phrase_types_elaborate
  action host "assembler.memory-begin"
}

phrase asm_lbrace_assembler_operand_size_whitespace_empty = "" in asm_lbrace_assembler_operand_size_whitespace {
  type phrase_types_elaborate
  action host "assembler.operand-dynamic"
}

phrase asm_lbrace_assembler_operand_size_whitespace_tab = "\t" in asm_lbrace_assembler_operand_size_whitespace {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_size_whitespace_vertical_tab = "\x0b" in asm_lbrace_assembler_operand_size_whitespace {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_size_whitespace_carriage_return = "\r" in asm_lbrace_assembler_operand_size_whitespace {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_size_whitespace_empty_e52e6a = " " in asm_lbrace_assembler_operand_size_whitespace {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operand_size_whitespace_comma = "," in asm_lbrace_assembler_operand_size_whitespace {
  prototype comma
  type phrase_types_elaborate
  action host "assembler.operand-separator"
}

phrase asm_lbrace_assembler_operand_size_whitespace_line_comment = "//" in asm_lbrace_assembler_operand_size_whitespace {
  type phrase_types_elaborate
  action host "assembler.operand-comment"
}

phrase asm_lbrace_assembler_operands_empty = "" in asm_lbrace_assembler_operands {
  type phrase_types_elaborate
  action host "assembler.operand-dynamic"
}

phrase asm_lbrace_assembler_operands_tab = "\t" in asm_lbrace_assembler_operands {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operands_vertical_tab = "\x0b" in asm_lbrace_assembler_operands {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operands_carriage_return = "\r" in asm_lbrace_assembler_operands {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operands_empty_d2f6b7 = " " in asm_lbrace_assembler_operands {
  type phrase_types_elaborate
  action host "assembler.operand-whitespace"
}

phrase asm_lbrace_assembler_operands_comma = "," in asm_lbrace_assembler_operands {
  prototype comma
  type phrase_types_elaborate
  action host "assembler.operand-separator"
}

phrase asm_lbrace_assembler_operands_line_comment = "//" in asm_lbrace_assembler_operands {
  type phrase_types_elaborate
  action host "assembler.operand-comment"
}

phrase asm_lbrace_assembler_operands_lbracket = "[" in asm_lbrace_assembler_operands {
  prototype lbracket_862dc1
  type phrase_types_elaborate
  action host "assembler.memory-begin"
}

phrase asm_lbrace_assembler_operands_ah = "ah" in asm_lbrace_assembler_operands {
  prototype ah
  type phrase_types_elaborate
  action host "assembler.operand"
  register ah code 4 bits 8 high true rex false
}

phrase asm_lbrace_assembler_operands_al = "al" in asm_lbrace_assembler_operands {
  prototype al
  type phrase_types_elaborate
  action host "assembler.operand"
  register al code 0 bits 8 high false rex false
}

phrase asm_lbrace_assembler_operands_ax = "ax" in asm_lbrace_assembler_operands {
  prototype ax
  type phrase_types_elaborate
  action host "assembler.operand"
  register ax code 0 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_bh = "bh" in asm_lbrace_assembler_operands {
  prototype bh
  type phrase_types_elaborate
  action host "assembler.operand"
  register bh code 7 bits 8 high true rex false
}

phrase asm_lbrace_assembler_operands_bl = "bl" in asm_lbrace_assembler_operands {
  prototype bl
  type phrase_types_elaborate
  action host "assembler.operand"
  register bl code 3 bits 8 high false rex false
}

phrase asm_lbrace_assembler_operands_bp = "bp" in asm_lbrace_assembler_operands {
  prototype bp
  type phrase_types_elaborate
  action host "assembler.operand"
  register bp code 5 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_bpl = "bpl" in asm_lbrace_assembler_operands {
  prototype bpl
  type phrase_types_elaborate
  action host "assembler.operand"
  register bpl code 5 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_bx = "bx" in asm_lbrace_assembler_operands {
  prototype bx
  type phrase_types_elaborate
  action host "assembler.operand"
  register bx code 3 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_byte = "byte" in asm_lbrace_assembler_operands {
  prototype byte
  type phrase_types_elaborate
  action host "assembler.operand-size"
  operand-size 8
}

phrase asm_lbrace_assembler_operands_ch = "ch" in asm_lbrace_assembler_operands {
  prototype ch
  type phrase_types_elaborate
  action host "assembler.operand"
  register ch code 5 bits 8 high true rex false
}

phrase asm_lbrace_assembler_operands_cl = "cl" in asm_lbrace_assembler_operands {
  prototype cl
  type phrase_types_elaborate
  action host "assembler.operand"
  register cl code 1 bits 8 high false rex false
}

phrase asm_lbrace_assembler_operands_cx = "cx" in asm_lbrace_assembler_operands {
  prototype cx
  type phrase_types_elaborate
  action host "assembler.operand"
  register cx code 1 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_dh = "dh" in asm_lbrace_assembler_operands {
  prototype dh
  type phrase_types_elaborate
  action host "assembler.operand"
  register dh code 6 bits 8 high true rex false
}

phrase asm_lbrace_assembler_operands_di = "di" in asm_lbrace_assembler_operands {
  prototype di
  type phrase_types_elaborate
  action host "assembler.operand"
  register di code 7 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_dil = "dil" in asm_lbrace_assembler_operands {
  prototype dil
  type phrase_types_elaborate
  action host "assembler.operand"
  register dil code 7 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_dl = "dl" in asm_lbrace_assembler_operands {
  prototype dl
  type phrase_types_elaborate
  action host "assembler.operand"
  register dl code 2 bits 8 high false rex false
}

phrase asm_lbrace_assembler_operands_dword = "dword" in asm_lbrace_assembler_operands {
  prototype dword
  type phrase_types_elaborate
  action host "assembler.operand-size"
  operand-size 32
}

phrase asm_lbrace_assembler_operands_dx = "dx" in asm_lbrace_assembler_operands {
  prototype dx
  type phrase_types_elaborate
  action host "assembler.operand"
  register dx code 2 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_eax = "eax" in asm_lbrace_assembler_operands {
  prototype eax
  type phrase_types_elaborate
  action host "assembler.operand"
  register eax code 0 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_ebp = "ebp" in asm_lbrace_assembler_operands {
  prototype ebp
  type phrase_types_elaborate
  action host "assembler.operand"
  register ebp code 5 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_ebx = "ebx" in asm_lbrace_assembler_operands {
  prototype ebx
  type phrase_types_elaborate
  action host "assembler.operand"
  register ebx code 3 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_ecx = "ecx" in asm_lbrace_assembler_operands {
  prototype ecx
  type phrase_types_elaborate
  action host "assembler.operand"
  register ecx code 1 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_edi = "edi" in asm_lbrace_assembler_operands {
  prototype edi
  type phrase_types_elaborate
  action host "assembler.operand"
  register edi code 7 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_edx = "edx" in asm_lbrace_assembler_operands {
  prototype edx
  type phrase_types_elaborate
  action host "assembler.operand"
  register edx code 2 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_esi = "esi" in asm_lbrace_assembler_operands {
  prototype esi
  type phrase_types_elaborate
  action host "assembler.operand"
  register esi code 6 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_esp = "esp" in asm_lbrace_assembler_operands {
  prototype esp
  type phrase_types_elaborate
  action host "assembler.operand"
  register esp code 4 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_qword = "qword" in asm_lbrace_assembler_operands {
  prototype qword
  type phrase_types_elaborate
  action host "assembler.operand-size"
  operand-size 64
}

phrase asm_lbrace_assembler_operands_r10 = "r10" in asm_lbrace_assembler_operands {
  prototype r10
  type phrase_types_elaborate
  action host "assembler.operand"
  register r10 code 10 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_r10b = "r10b" in asm_lbrace_assembler_operands {
  prototype r10b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r10b code 10 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_r10d = "r10d" in asm_lbrace_assembler_operands {
  prototype r10d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r10d code 10 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_r10w = "r10w" in asm_lbrace_assembler_operands {
  prototype r10w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r10w code 10 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_r11 = "r11" in asm_lbrace_assembler_operands {
  prototype r11
  type phrase_types_elaborate
  action host "assembler.operand"
  register r11 code 11 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_r11b = "r11b" in asm_lbrace_assembler_operands {
  prototype r11b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r11b code 11 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_r11d = "r11d" in asm_lbrace_assembler_operands {
  prototype r11d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r11d code 11 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_r11w = "r11w" in asm_lbrace_assembler_operands {
  prototype r11w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r11w code 11 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_r12 = "r12" in asm_lbrace_assembler_operands {
  prototype r12
  type phrase_types_elaborate
  action host "assembler.operand"
  register r12 code 12 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_r12b = "r12b" in asm_lbrace_assembler_operands {
  prototype r12b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r12b code 12 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_r12d = "r12d" in asm_lbrace_assembler_operands {
  prototype r12d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r12d code 12 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_r12w = "r12w" in asm_lbrace_assembler_operands {
  prototype r12w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r12w code 12 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_r13 = "r13" in asm_lbrace_assembler_operands {
  prototype r13
  type phrase_types_elaborate
  action host "assembler.operand"
  register r13 code 13 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_r13b = "r13b" in asm_lbrace_assembler_operands {
  prototype r13b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r13b code 13 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_r13d = "r13d" in asm_lbrace_assembler_operands {
  prototype r13d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r13d code 13 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_r13w = "r13w" in asm_lbrace_assembler_operands {
  prototype r13w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r13w code 13 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_r14 = "r14" in asm_lbrace_assembler_operands {
  prototype r14
  type phrase_types_elaborate
  action host "assembler.operand"
  register r14 code 14 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_r14b = "r14b" in asm_lbrace_assembler_operands {
  prototype r14b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r14b code 14 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_r14d = "r14d" in asm_lbrace_assembler_operands {
  prototype r14d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r14d code 14 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_r14w = "r14w" in asm_lbrace_assembler_operands {
  prototype r14w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r14w code 14 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_r15 = "r15" in asm_lbrace_assembler_operands {
  prototype r15
  type phrase_types_elaborate
  action host "assembler.operand"
  register r15 code 15 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_r15b = "r15b" in asm_lbrace_assembler_operands {
  prototype r15b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r15b code 15 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_r15d = "r15d" in asm_lbrace_assembler_operands {
  prototype r15d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r15d code 15 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_r15w = "r15w" in asm_lbrace_assembler_operands {
  prototype r15w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r15w code 15 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_r8 = "r8" in asm_lbrace_assembler_operands {
  prototype r8
  type phrase_types_elaborate
  action host "assembler.operand"
  register r8 code 8 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_r8b = "r8b" in asm_lbrace_assembler_operands {
  prototype r8b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r8b code 8 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_r8d = "r8d" in asm_lbrace_assembler_operands {
  prototype r8d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r8d code 8 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_r8w = "r8w" in asm_lbrace_assembler_operands {
  prototype r8w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r8w code 8 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_r9 = "r9" in asm_lbrace_assembler_operands {
  prototype r9
  type phrase_types_elaborate
  action host "assembler.operand"
  register r9 code 9 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_r9b = "r9b" in asm_lbrace_assembler_operands {
  prototype r9b
  type phrase_types_elaborate
  action host "assembler.operand"
  register r9b code 9 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_r9d = "r9d" in asm_lbrace_assembler_operands {
  prototype r9d
  type phrase_types_elaborate
  action host "assembler.operand"
  register r9d code 9 bits 32 high false rex false
}

phrase asm_lbrace_assembler_operands_r9w = "r9w" in asm_lbrace_assembler_operands {
  prototype r9w
  type phrase_types_elaborate
  action host "assembler.operand"
  register r9w code 9 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_rax = "rax" in asm_lbrace_assembler_operands {
  prototype rax
  type phrase_types_elaborate
  action host "assembler.operand"
  register rax code 0 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_rbp = "rbp" in asm_lbrace_assembler_operands {
  prototype rbp
  type phrase_types_elaborate
  action host "assembler.operand"
  register rbp code 5 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_rbx = "rbx" in asm_lbrace_assembler_operands {
  prototype rbx
  type phrase_types_elaborate
  action host "assembler.operand"
  register rbx code 3 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_rcx = "rcx" in asm_lbrace_assembler_operands {
  prototype rcx
  type phrase_types_elaborate
  action host "assembler.operand"
  register rcx code 1 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_rdi = "rdi" in asm_lbrace_assembler_operands {
  prototype rdi
  type phrase_types_elaborate
  action host "assembler.operand"
  register rdi code 7 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_rdx = "rdx" in asm_lbrace_assembler_operands {
  prototype rdx
  type phrase_types_elaborate
  action host "assembler.operand"
  register rdx code 2 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_rsi = "rsi" in asm_lbrace_assembler_operands {
  prototype rsi
  type phrase_types_elaborate
  action host "assembler.operand"
  register rsi code 6 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_rsp = "rsp" in asm_lbrace_assembler_operands {
  prototype rsp
  type phrase_types_elaborate
  action host "assembler.operand"
  register rsp code 4 bits 64 high false rex false
}

phrase asm_lbrace_assembler_operands_si = "si" in asm_lbrace_assembler_operands {
  prototype si
  type phrase_types_elaborate
  action host "assembler.operand"
  register si code 6 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_sil = "sil" in asm_lbrace_assembler_operands {
  prototype sil
  type phrase_types_elaborate
  action host "assembler.operand"
  register sil code 6 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_sp = "sp" in asm_lbrace_assembler_operands {
  prototype sp
  type phrase_types_elaborate
  action host "assembler.operand"
  register sp code 4 bits 16 high false rex false
}

phrase asm_lbrace_assembler_operands_spl = "spl" in asm_lbrace_assembler_operands {
  prototype spl
  type phrase_types_elaborate
  action host "assembler.operand"
  register spl code 4 bits 8 high false rex true
}

phrase asm_lbrace_assembler_operands_word = "word" in asm_lbrace_assembler_operands {
  prototype word
  type phrase_types_elaborate
  action host "assembler.operand-size"
  operand-size 16
}
