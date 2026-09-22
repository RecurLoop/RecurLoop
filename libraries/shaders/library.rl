// =============================================================================
// RecurLoop shaders
//
// GLSL/HLSL -> SPIR-V through shaderc's stable C API, plus a small native
// SPIR-V word encoder implemented entirely in RecurLoop source.
// =============================================================================

languagekit_native_begin

link shared "c"
link shared "shaderc"

extern shaderc_compiler_initialize() -> u8* abi sysv-amd64
extern shaderc_compiler_release(compiler:u8*) -> void abi sysv-amd64
extern shaderc_compile_options_initialize() -> u8* abi sysv-amd64
extern shaderc_compile_options_release(options:u8*) -> void abi sysv-amd64
extern shaderc_compile_options_set_source_language(options:u8*, language:i32) -> void abi sysv-amd64
extern shaderc_compile_options_set_target_env(options:u8*, target:i32, version:u32) -> void abi sysv-amd64
extern shaderc_compile_options_set_optimization_level(options:u8*, level:i32) -> void abi sysv-amd64
extern shaderc_compile_options_set_generate_debug_info(options:u8*) -> void abi sysv-amd64
extern shaderc_compile_into_spv(compiler:u8*, source:u8*, source_bytes:u64, shader_kind:i32, input_name:u8*, entry_point:u8*, options:u8*) -> u8* abi sysv-amd64
extern shaderc_result_get_compilation_status(result:u8*) -> i32 abi sysv-amd64
extern shaderc_result_get_length(result:u8*) -> u64 abi sysv-amd64
extern shaderc_result_get_bytes(result:u8*) -> u8* abi sysv-amd64
extern shaderc_result_get_error_message(result:u8*) -> u8* abi sysv-amd64
extern shaderc_result_release(result:u8*) -> void abi sysv-amd64

let Shaders = phrase { dictionary = true permanent = true }
let Shaders:Language = phrase { dictionary = true permanent = true }
let Shaders:Stage = phrase { dictionary = true permanent = true }
let Shaders:Optimization = phrase { dictionary = true permanent = true }
let Shaders:Source = phrase { dictionary = true permanent = true }
let Shaders:Source:GLSL = phrase { dictionary = true permanent = true }
let Shaders:Spirv = phrase { dictionary = true permanent = true }
let Shaders:Spirv:Opcode = phrase { dictionary = true permanent = true }

// Common SPIR-V 1.0 opcodes for source-defined shader backends. The generic
// Builder:instruction API is not limited to this starter set.
let Shaders:Spirv:Opcode:Name = fn () -> u32 { return 5 }
let Shaders:Spirv:Opcode:MemoryModel = fn () -> u32 { return 14 }
let Shaders:Spirv:Opcode:EntryPoint = fn () -> u32 { return 15 }
let Shaders:Spirv:Opcode:ExecutionMode = fn () -> u32 { return 16 }
let Shaders:Spirv:Opcode:Capability = fn () -> u32 { return 17 }
let Shaders:Spirv:Opcode:TypeVoid = fn () -> u32 { return 19 }
let Shaders:Spirv:Opcode:TypeBool = fn () -> u32 { return 20 }
let Shaders:Spirv:Opcode:TypeInt = fn () -> u32 { return 21 }
let Shaders:Spirv:Opcode:TypeFloat = fn () -> u32 { return 22 }
let Shaders:Spirv:Opcode:TypeVector = fn () -> u32 { return 23 }
let Shaders:Spirv:Opcode:TypePointer = fn () -> u32 { return 32 }
let Shaders:Spirv:Opcode:TypeFunction = fn () -> u32 { return 33 }
let Shaders:Spirv:Opcode:Constant = fn () -> u32 { return 43 }
let Shaders:Spirv:Opcode:Function = fn () -> u32 { return 54 }
let Shaders:Spirv:Opcode:FunctionParameter = fn () -> u32 { return 55 }
let Shaders:Spirv:Opcode:FunctionEnd = fn () -> u32 { return 56 }
let Shaders:Spirv:Opcode:Variable = fn () -> u32 { return 59 }
let Shaders:Spirv:Opcode:Load = fn () -> u32 { return 61 }
let Shaders:Spirv:Opcode:Store = fn () -> u32 { return 62 }
let Shaders:Spirv:Opcode:AccessChain = fn () -> u32 { return 65 }
let Shaders:Spirv:Opcode:Decorate = fn () -> u32 { return 71 }
let Shaders:Spirv:Opcode:MemberDecorate = fn () -> u32 { return 72 }
let Shaders:Spirv:Opcode:CompositeConstruct = fn () -> u32 { return 80 }
let Shaders:Spirv:Opcode:Label = fn () -> u32 { return 248 }
let Shaders:Spirv:Opcode:Return = fn () -> u32 { return 253 }

// shaderc_source_language
let Shaders:Language:GLSL = fn () -> i32 { return 0 }
let Shaders:Language:HLSL = fn () -> i32 { return 1 }

// shaderc_shader_kind. The GLSL aliases have these same values.
let Shaders:Stage:Vertex = fn () -> i32 { return 0 }
let Shaders:Stage:Fragment = fn () -> i32 { return 1 }
let Shaders:Stage:Compute = fn () -> i32 { return 2 }
let Shaders:Stage:Geometry = fn () -> i32 { return 3 }
let Shaders:Stage:TessControl = fn () -> i32 { return 4 }
let Shaders:Stage:TessEvaluation = fn () -> i32 { return 5 }

// shaderc_optimization_level
let Shaders:Optimization:Zero = fn () -> i32 { return 0 }
let Shaders:Optimization:Size = fn () -> i32 { return 1 }
let Shaders:Optimization:Performance = fn () -> i32 { return 2 }

record Shaders:Binary {
    words:u32*
    bytes:u64
    status:i32
    error:u8*
}

let Shaders:Binary:new = fn () -> Shaders:Binary* {
    let out = alloc(Shaders:Binary)
    if !out { return cast(Shaders:Binary*, 0) }
    out.words = cast(u32*, 0)
    out.bytes = 0
    out.status = 0
    out.error = cast(u8*, 0)
    return out
}

let Shaders:Binary:ok = fn (self:Shaders:Binary*) -> i64 {
    return self && self.status == 0 && self.words && self.bytes >= 20
}

// Keep Binary's storage opaque across .rli boundaries.  Access through these
// functions instead of relying on direct imported record-member access.
let Shaders:Binary:error_text = fn (self:Shaders:Binary*) -> u8* {
    if !self { return cast(u8*, 0) }
    return self.error
}

let Shaders:Binary:word_data = fn (self:Shaders:Binary*) -> u32* {
    if !self { return cast(u32*, 0) }
    return self.words
}

let Shaders:Binary:byte_size = fn (self:Shaders:Binary*) -> u64 {
    if !self { return 0 }
    return self.bytes
}

let Shaders:Binary:destroy = fn (self:Shaders:Binary*) -> void {
    if !self { return }
    if self.words { free(cast(u8*, self.words)) }
    if self.error { free(self.error) }
    free(cast(u8*, self))
}

let Shaders:copy_error = fn (source:u8*) -> u8* {
    if !source { return LanguageKit:copy_text("shader compilation failed") }
    return LanguageKit:copy_text(source)
}

let Shaders:compile = fn (
    source:u8*, stage:i32, language:i32, input_name:u8*, entry_point:u8*,
    optimization:i32, debug_info:i32
) -> Shaders:Binary* {
    let output = Shaders:Binary:new()
    if !output { return output }
    if !source {
        output.status = -1
        output.error = LanguageKit:copy_text("shader source is null")
        return output
    }

    let compiler = shaderc_compiler_initialize()
    if !compiler {
        output.status = -1
        output.error = LanguageKit:copy_text("shaderc_compiler_initialize failed")
        return output
    }
    defer shaderc_compiler_release(compiler)

    let options = shaderc_compile_options_initialize()
    if !options {
        output.status = -1
        output.error = LanguageKit:copy_text("shaderc_compile_options_initialize failed")
        return output
    }
    defer shaderc_compile_options_release(options)

    shaderc_compile_options_set_source_language(options, language)
    // shaderc target=0 is Vulkan; version=0 maps to Vulkan 1.0.
    shaderc_compile_options_set_target_env(options, 0, 0)
    shaderc_compile_options_set_optimization_level(options, optimization)
    if debug_info { shaderc_compile_options_set_generate_debug_info(options) }

    var name = input_name
    var entry = entry_point
    if !name { name = "shader" }
    if !entry { entry = "main" }

    let result = shaderc_compile_into_spv(
        compiler,
        source,
        strlen(source),
        stage,
        name,
        entry,
        options
    )
    if !result {
        output.status = -1
        output.error = LanguageKit:copy_text("shaderc_compile_into_spv returned null")
        return output
    }
    defer shaderc_result_release(result)

    output.status = shaderc_result_get_compilation_status(result)
    if output.status != 0 {
        output.error = Shaders:copy_error(shaderc_result_get_error_message(result))
        return output
    }

    output.bytes = shaderc_result_get_length(result)
    if output.bytes < 20 || (output.bytes % 4) != 0 {
        output.status = -1
        output.error = LanguageKit:copy_text("shaderc returned an invalid SPIR-V byte stream")
        output.bytes = 0
        return output
    }

    output.words = cast(u32*, malloc(output.bytes))
    if !output.words {
        output.status = -1
        output.error = LanguageKit:copy_text("out of memory while copying SPIR-V")
        output.bytes = 0
        return output
    }
    memcpy(cast(u8*, output.words), shaderc_result_get_bytes(result), output.bytes)
    return output
}

let Shaders:compile_glsl = fn (source:u8*, stage:i32) -> Shaders:Binary* {
    return Shaders:compile(source, stage, Shaders:Language:GLSL(), "shader.glsl", "main", Shaders:Optimization:Performance(), 0)
}

let Shaders:compile_hlsl = fn (source:u8*, stage:i32) -> Shaders:Binary* {
    return Shaders:compile(source, stage, Shaders:Language:HLSL(), "shader.hlsl", "main", Shaders:Optimization:Performance(), 0)
}

let Shaders:glsl_vertex = fn (source:u8*) -> Shaders:Binary* {
    return Shaders:compile_glsl(source, Shaders:Stage:Vertex())
}

let Shaders:glsl_fragment = fn (source:u8*) -> Shaders:Binary* {
    return Shaders:compile_glsl(source, Shaders:Stage:Fragment())
}

let Shaders:hlsl_vertex = fn (source:u8*) -> Shaders:Binary* {
    return Shaders:compile_hlsl(source, Shaders:Stage:Vertex())
}

let Shaders:hlsl_fragment = fn (source:u8*) -> Shaders:Binary* {
    return Shaders:compile_hlsl(source, Shaders:Stage:Fragment())
}

// -----------------------------------------------------------------------------
// Native RecurLoop SPIR-V encoder.
//
// This intentionally starts below GLSL/HLSL. It lets source-defined RecurLoop
// code emit real SPIR-V instructions without shaderc. A future source-defined
// shader language can lower directly to this builder.
// -----------------------------------------------------------------------------

record Shaders:Spirv:Builder {
    words:u32*
    length:u64
    capacity:u64
    next_id:u32
}

let Shaders:Spirv:Builder:new = fn (capacity:u64) -> Shaders:Spirv:Builder* {
    if capacity < 32 { capacity = 32 }
    let self = alloc(Shaders:Spirv:Builder)
    if !self { return cast(Shaders:Spirv:Builder*, 0) }
    self.words = cast(u32*, malloc(capacity * sizeof(u32)))
    if !self.words { free(cast(u8*, self)); return cast(Shaders:Spirv:Builder*, 0) }
    self.length = 5
    self.capacity = capacity
    self.next_id = 1
    self.words[0] = 119734787
    self.words[1] = 65536
    self.words[2] = 0
    self.words[3] = 1
    self.words[4] = 0
    return self
}

let Shaders:Spirv:Builder:reserve = fn (self:Shaders:Spirv:Builder*, words:u64) -> i64 {
    if !self { return 0 }
    let needed = self.length + words
    if needed <= self.capacity { return 1 }
    var capacity = self.capacity
    while capacity < needed { capacity *= 2 }
    let replacement = realloc(cast(u8*, self.words), capacity * sizeof(u32))
    if !replacement { return 0 }
    self.words = cast(u32*, replacement)
    self.capacity = capacity
    return 1
}

let Shaders:Spirv:Builder:id = fn (self:Shaders:Spirv:Builder*) -> u32 {
    let result = self.next_id
    self.next_id += 1
    self.words[3] = self.next_id
    return result
}

let Shaders:Spirv:Builder:push = fn (self:Shaders:Spirv:Builder*, word:u32) -> i64 {
    if !self.reserve(1) { return 0 }
    self.words[self.length] = word
    self.length += 1
    return 1
}

let Shaders:Spirv:Builder:instruction = fn (self:Shaders:Spirv:Builder*, opcode:u32, operands:u32*, operand_count:u32) -> i64 {
    let count = operand_count + 1
    if !self.reserve(count) { return 0 }
    self.words[self.length] = count * 65536 + opcode
    self.length += 1
    var i:u32 = 0
    while i < operand_count {
        self.words[self.length] = operands[i]
        self.length += 1
        i += 1
    }
    return 1
}

let Shaders:Spirv:Builder:emit0 = fn (self:Shaders:Spirv:Builder*, opcode:u32) -> i64 {
    return self.instruction(opcode, cast(u32*, 0), 0)
}

let Shaders:Spirv:Builder:emit1 = fn (self:Shaders:Spirv:Builder*, opcode:u32, a:u32) -> i64 {
    var data:u32 = a
    return self.instruction(opcode, &data, 1)
}

let Shaders:Spirv:Builder:emit2 = fn (self:Shaders:Spirv:Builder*, opcode:u32, a:u32, b:u32) -> i64 {
    let data = cast(u32*, malloc(2 * sizeof(u32))); if !data { return 0 }; defer free(cast(u8*, data))
    data[0] = a; data[1] = b
    return self.instruction(opcode, data, 2)
}

let Shaders:Spirv:Builder:emit3 = fn (self:Shaders:Spirv:Builder*, opcode:u32, a:u32, b:u32, c:u32) -> i64 {
    let data = cast(u32*, malloc(3 * sizeof(u32))); if !data { return 0 }; defer free(cast(u8*, data))
    data[0] = a; data[1] = b; data[2] = c
    return self.instruction(opcode, data, 3)
}

let Shaders:Spirv:Builder:emit4 = fn (self:Shaders:Spirv:Builder*, opcode:u32, a:u32, b:u32, c:u32, d:u32) -> i64 {
    let data = cast(u32*, malloc(4 * sizeof(u32))); if !data { return 0 }; defer free(cast(u8*, data))
    data[0] = a; data[1] = b; data[2] = c; data[3] = d
    return self.instruction(opcode, data, 4)
}

let Shaders:Spirv:Builder:finish = fn (self:Shaders:Spirv:Builder*) -> Shaders:Binary* {
    if !self { return cast(Shaders:Binary*, 0) }
    let output = Shaders:Binary:new()
    if !output { return output }
    output.bytes = self.length * 4
    output.words = cast(u32*, malloc(output.bytes))
    if !output.words {
        output.status = -1
        output.error = LanguageKit:copy_text("out of memory while finalizing SPIR-V")
        output.bytes = 0
        return output
    }
    memcpy(cast(u8*, output.words), cast(u8*, self.words), output.bytes)
    return output
}

let Shaders:Spirv:Builder:destroy = fn (self:Shaders:Spirv:Builder*) -> void {
    if !self { return }
    if self.words { free(cast(u8*, self.words)) }
    free(cast(u8*, self))
}


// -----------------------------------------------------------------------------
// Phrase-extensible shader source.
//
// `shader glsl { ... }` keeps ordinary GLSL untouched, but before the block is
// turned into a RecurLoop string literal it performs longest-prefix lookup in
// Shaders:Source:GLSL.  A child phrase can therefore replace a spelling by
// carrying text in its payload, or implement a structural construct with a
// normal RecurLoop phrase action. Unknown source is copied byte-for-byte.
//
// This deliberately is not a second GLSL parser. shaderc remains responsible
// for GLSL semantics/versioning; the lexicon only owns the extensions users
// explicitly add.
// -----------------------------------------------------------------------------

record Shaders:Source:Expansion {
    state:Context*
    owner:i64
    source:u8*
    bytes:i64
    position:i64
    output:LanguageKit:Text*
    failed:i64
}

let Shaders:Source:is_identifier_byte = fn (value:u8) -> i64 {
    return LanguageKit:is_alpha(value) || LanguageKit:is_digit(value) || value == 95
}

let Shaders:Source:session = fn (state:Context*) -> Shaders:Source:Expansion* {
    return cast(Shaders:Source:Expansion*, LanguageKit:state_get(state, "__shader_source_expansion"))
}

let Shaders:Source:fail = fn (state:Context*, message:u8*) -> void {
    let session = Shaders:Source:session(state)
    if session { session.failed = 1 }
    context:diagnostic:error(state, message)
}

let Shaders:Source:emit = fn (state:Context*, text:u8*) -> i64 {
    let session = Shaders:Source:session(state)
    if !session || !session.output || !text { return 0 }
    if !session.output.append(text) {
        session.failed = 1
        context:diagnostic:error(state, "shader source expansion ran out of memory")
        return 0
    }
    return 1
}

let Shaders:Source:emit_byte = fn (state:Context*, value:u8) -> i64 {
    let session = Shaders:Source:session(state)
    if !session || !session.output { return 0 }
    if !session.output.append_byte(value) {
        session.failed = 1
        context:diagnostic:error(state, "shader source expansion ran out of memory")
        return 0
    }
    return 1
}

let Shaders:Source:skip_space = fn (state:Context*) -> void {
    let session = Shaders:Source:session(state)
    if !session { return }
    while session.position < session.bytes && LanguageKit:is_space(session.source[session.position]) {
        session.position += 1
    }
}

let Shaders:Source:take_identifier = fn (state:Context*) -> u8* {
    let session = Shaders:Source:session(state)
    if !session { return cast(u8*, 0) }
    Shaders:Source:skip_space(state)
    let start = session.position
    if start >= session.bytes || !(LanguageKit:is_alpha(session.source[start]) || session.source[start] == 95) {
        Shaders:Source:fail(state, "shader phrase expects an identifier")
        return cast(u8*, 0)
    }
    session.position += 1
    while session.position < session.bytes && Shaders:Source:is_identifier_byte(session.source[session.position]) {
        session.position += 1
    }
    return LanguageKit:copy_bytes(&session.source[start], session.position - start)
}

// Consume a balanced `( ... )` after the currently matched phrase and return
// only its contents. Strings and comments are skipped while balancing so a
// phrase action can safely accept ordinary GLSL expressions.
let Shaders:Source:take_parenthesized = fn (state:Context*) -> u8* {
    let session = Shaders:Source:session(state)
    if !session { return cast(u8*, 0) }
    Shaders:Source:skip_space(state)
    if session.position >= session.bytes || session.source[session.position] != 40 {
        Shaders:Source:fail(state, "shader phrase expects (...)")
        return cast(u8*, 0)
    }

    session.position += 1
    let start = session.position
    var depth = 1
    var quote:u8 = 0
    var escaped = 0
    var line_comment = 0
    var block_comment = 0

    while session.position < session.bytes {
        let ch = session.source[session.position]
        let next = session.position + 1

        if line_comment {
            session.position += 1
            if ch == 10 || ch == 13 { line_comment = 0 }
        } else if block_comment {
            if ch == 42 && next < session.bytes && session.source[next] == 47 {
                session.position += 2
                block_comment = 0
            } else {
                session.position += 1
            }
        } else if quote != 0 {
            session.position += 1
            if escaped { escaped = 0 }
            else if ch == 92 { escaped = 1 }
            else if ch == quote { quote = 0 }
        } else if ch == 47 && next < session.bytes && session.source[next] == 47 {
            session.position += 2
            line_comment = 1
        } else if ch == 47 && next < session.bytes && session.source[next] == 42 {
            session.position += 2
            block_comment = 1
        } else if ch == 34 || ch == 39 {
            quote = ch
            session.position += 1
        } else if ch == 40 {
            depth += 1
            session.position += 1
        } else if ch == 41 {
            depth -= 1
            if depth == 0 {
                let finish = session.position
                session.position += 1
                return LanguageKit:copy_bytes(&session.source[start], finish - start)
            }
            session.position += 1
        } else {
            session.position += 1
        }
    }

    Shaders:Source:fail(state, "shader phrase has an unterminated (...)")
    return cast(u8*, 0)
}

let Shaders:Source:copy_quoted = fn (session:Shaders:Source:Expansion*) -> i64 {
    let quote = session.source[session.position]
    if !session.output.append_byte(quote) { return 0 }
    session.position += 1
    var escaped = 0
    while session.position < session.bytes {
        let ch = session.source[session.position]
        session.position += 1
        if !session.output.append_byte(ch) { return 0 }
        if escaped { escaped = 0 }
        else if ch == 92 { escaped = 1 }
        else if ch == quote { return 1 }
    }
    return 1
}

let Shaders:Source:copy_comment = fn (session:Shaders:Source:Expansion*) -> i64 {
    let next = session.position + 1
    if next >= session.bytes || session.source[session.position] != 47 { return 0 }
    if session.source[next] == 47 {
        while session.position < session.bytes {
            let ch = session.source[session.position]
            session.position += 1
            if !session.output.append_byte(ch) { return 0 }
            if ch == 10 || ch == 13 { break }
        }
        return 1
    }
    if session.source[next] == 42 {
        if !session.output.append("/*") { return 0 }
        session.position += 2
        while session.position < session.bytes {
            let ch = session.source[session.position]
            if ch == 42 && session.position + 1 < session.bytes && session.source[session.position + 1] == 47 {
                if !session.output.append("*/") { return 0 }
                session.position += 2
                return 1
            }
            if !session.output.append_byte(ch) { return 0 }
            session.position += 1
        }
        return 1
    }
    return 0
}

let Shaders:Source:phrase_matches_boundary = fn (
    session:Shaders:Source:Expansion*, key_bytes:i64
) -> i64 {
    if key_bytes <= 0 { return 0 }
    let first = session.source[session.position]
    let last = session.source[session.position + key_bytes - 1]
    if Shaders:Source:is_identifier_byte(first) && session.position > 0 &&
       Shaders:Source:is_identifier_byte(session.source[session.position - 1]) {
        return 0
    }
    let after = session.position + key_bytes
    if Shaders:Source:is_identifier_byte(last) && after < session.bytes &&
       Shaders:Source:is_identifier_byte(session.source[after]) {
        return 0
    }
    return 1
}

let Shaders:Source:emit_payload = fn (state:Context*, phrase:i64) -> i64 {
    let bytes = cast(i64, context:phrase:payload:bytes(state, phrase))
    if bytes <= 0 { return 0 }
    let text = cast(u8*, malloc(bytes + 1))
    if !text {
        Shaders:Source:fail(state, "shader phrase payload allocation failed")
        return 0
    }
    defer free(text)
    if context:phrase:read(state, phrase, 0, text, cast(u64, bytes)) != cast(u64, bytes) {
        Shaders:Source:fail(state, "shader phrase payload could not be read")
        return 0
    }
    text[bytes] = 0
    return Shaders:Source:emit(state, text)
}

let Shaders:Source:expand = fn (state:Context*, owner:i64, source:u8*, bytes:i64) -> u8* {
    if !state || !owner || !source || bytes < 0 { return cast(u8*, 0) }
    let output = LanguageKit:Text:new()
    if !output { return cast(u8*, 0) }

    let session = alloc(Shaders:Source:Expansion)
    if !session { output.destroy(); return cast(u8*, 0) }
    session.state = state
    session.owner = owner
    session.source = source
    session.bytes = bytes
    session.position = 0
    session.output = output
    session.failed = 0

    let previous = LanguageKit:state_get(state, "__shader_source_expansion")
    if !LanguageKit:state_pointer_set(state, "__shader_source_expansion", cast(i64, session)) {
        free(cast(u8*, session))
        output.destroy()
        return cast(u8*, 0)
    }

    while session.position < session.bytes && !session.failed {
        let ch = session.source[session.position]

        if ch == 34 || ch == 39 {
            if !Shaders:Source:copy_quoted(session) { session.failed = 1 }
        } else if ch == 47 && session.position + 1 < session.bytes &&
                  (session.source[session.position + 1] == 47 || session.source[session.position + 1] == 42) {
            if !Shaders:Source:copy_comment(session) { session.failed = 1 }
        } else {
            let remaining = session.bytes - session.position
            let matched = context:phrase:find:longest(state, owner, source, cast(u64, session.position), cast(u64, remaining))
            if matched {
                let key_bytes = cast(i64, context:phrase:key(state, matched, cast(u8*, 0), 0))
                if key_bytes > 0 && Shaders:Source:phrase_matches_boundary(session, key_bytes) {
                    session.position += key_bytes
                    let flags = context:phrase:flags(state, matched)
                    if ((flags / 64) % 2) != 0 {
                        context:phrase:dispatch(state, matched)
                    } else if !Shaders:Source:emit_payload(state, matched) {
                        var i:i64 = 0
                        while i < key_bytes {
                            if !session.output.append_byte(session.source[session.position - key_bytes + i]) { session.failed = 1 }
                            i += 1
                        }
                    }
                } else {
                    if !session.output.append_byte(ch) { session.failed = 1 }
                    session.position += 1
                }
            } else {
                if !session.output.append_byte(ch) { session.failed = 1 }
                session.position += 1
            }
        }
    }

    LanguageKit:state_pointer_set(state, "__shader_source_expansion", previous)
    let failed = session.failed
    free(cast(u8*, session))
    if failed {
        output.destroy()
        return cast(u8*, 0)
    }
    let result = output.take()
    output.destroy()
    return result
}

let Shaders:Source:expand_glsl = fn (state:Context*, source:u8*, bytes:i64) -> u8* {
    let shaders = context:phrase:find(state, "Shaders")
    if !shaders { return cast(u8*, 0) }
    let source_owner = context:phrase:find:exact(state, shaders, "Source")
    if !source_owner { return cast(u8*, 0) }
    let glsl = context:phrase:find:exact(state, source_owner, "GLSL")
    if !glsl { return cast(u8*, 0) }
    return Shaders:Source:expand(state, glsl, source, bytes)
}

// Expand another source fragment using the same dictionary and append it to the
// active output. Useful for structural phrase actions such as `saturate(...)`.
let Shaders:Source:emit_expanded = fn (state:Context*, source:u8*) -> i64 {
    let session = Shaders:Source:session(state)
    if !session || !source { return 0 }
    let owner = session.owner
    let expanded = Shaders:Source:expand(state, owner, source, cast(i64, strlen(source)))
    if !expanded { return 0 }
    defer free(expanded)
    return Shaders:Source:emit(state, expanded)
}

let Shaders:Source:emit_string_literal = fn (state:Context*, source:u8*) -> void {
    if !source { return }
    let quoted = LanguageKit:Text:new()
    if !quoted {
        context:diagnostic:error(state, "shader string emission ran out of memory")
        return
    }
    defer quoted.destroy()
    if !quoted.append("\"") { return }

    var i:i64 = 0
    let bytes = cast(i64, strlen(source))
    while i < bytes {
        let ch = source[i]
        if ch == 34 { if !quoted.append("\\\"") { return } }
        else if ch == 92 { if !quoted.append("\\\\") { return } }
        else if ch == 10 { if !quoted.append("\\n") { return } }
        else if ch == 13 { if !quoted.append("\\r") { return } }
        else if ch == 9 { if !quoted.append("\\t") { return } }
        else if !quoted.append_byte(ch) { return }
        i += 1
    }
    if !quoted.append("\"") { return }
    context:syntax:emit(state, quoted.data)
}

// Capture and phrase-expand the GLSL body shared by both source and embedded
// SPIR-V expressions. The braces belong to the syntax capture, not the shader.
let Shaders:Source:capture_glsl = fn (state:Context*) -> u8* {
    if !context:syntax:active(state) {
        context:diagnostic:error(state, "shader { ... } is an expression and must be used inside compiled code")
        return cast(u8*, 0)
    }
    let block = context:syntax:capture(state, "body")
    if !block {
        context:diagnostic:error(state, "shader expects a block")
        return cast(u8*, 0)
    }
    let bytes = cast(i64, strlen(block))
    if bytes < 2 {
        context:diagnostic:error(state, "shader received an invalid block")
        return cast(u8*, 0)
    }
    return Shaders:Source:expand_glsl(state, &block[1], bytes - 2)
}

// Compile phrase-expanded GLSL while RecurLoop is compiling the surrounding
// function, then lower the resulting bytes to a normal embedded bits literal.
// shaderc is therefore a build-time dependency, not a runtime dependency of
// executables that only use `shader spirv ...`.
let Shaders:Source:emit_spirv = fn (state:Context*, stage:i32) -> void {
    let source = Shaders:Source:capture_glsl(state)
    if !source { return }
    defer free(source)

    let binary = Shaders:compile(
        source,
        stage,
        Shaders:Language:GLSL(),
        "embedded.glsl",
        "main",
        Shaders:Optimization:Performance(),
        0
    )
    if !binary {
        context:diagnostic:error(state, "shader compilation result allocation failed")
        return
    }
    defer Shaders:Binary:destroy(binary)
    if !Shaders:Binary:ok(binary) {
        context:diagnostic:error(state, Shaders:Binary:error_text(binary))
        return
    }
    if !Embed:emit_bytes(state, cast(u8*, Shaders:Binary:word_data(binary)), Shaders:Binary:byte_size(binary)) {
        context:diagnostic:error(state, "could not embed compiled SPIR-V")
    }
}

let Shaders:Stage:from_name = fn (name:u8*) -> i32 {
    if LanguageKit:text_equal(name, "vertex") { return Shaders:Stage:Vertex() }
    if LanguageKit:text_equal(name, "fragment") { return Shaders:Stage:Fragment() }
    if LanguageKit:text_equal(name, "compute") { return Shaders:Stage:Compute() }
    if LanguageKit:text_equal(name, "geometry") { return Shaders:Stage:Geometry() }
    if LanguageKit:text_equal(name, "tess_control") { return Shaders:Stage:TessControl() }
    if LanguageKit:text_equal(name, "tess_evaluation") { return Shaders:Stage:TessEvaluation() }
    return -1
}

// One syntax action owns the whole shader family. `glsl` emits expanded source;
// `spirv <stage>` compiles the same source and embeds the resulting bytes.
// Keeping a single action also avoids separate syntax variants drifting apart.
syntax shader (glsl | spirv <stage:id>) <body:block> action fn (state:Context*, called:Phrase*) -> void {
    if !context:syntax:capture:exists(state, "stage") {
        let expanded = Shaders:Source:capture_glsl(state)
        if !expanded { return }
        defer free(expanded)
        Shaders:Source:emit_string_literal(state, expanded)
        return
    }

    let stage_name = context:syntax:capture(state, "stage")
    let stage = Shaders:Stage:from_name(stage_name)
    if stage < 0 {
        context:diagnostic:error(state, "unknown shader stage")
        return
    }
    Shaders:Source:emit_spirv(state, stage)
}

set shaderc_compiler_initialize.serializable = false
set shaderc_compiler_release.serializable = false
set shaderc_compile_options_initialize.serializable = false
set shaderc_compile_options_release.serializable = false
set shaderc_compile_options_set_source_language.serializable = false
set shaderc_compile_options_set_target_env.serializable = false
set shaderc_compile_options_set_optimization_level.serializable = false
set shaderc_compile_options_set_generate_debug_info.serializable = false
set shaderc_compile_into_spv.serializable = false
set shaderc_result_get_compilation_status.serializable = false
set shaderc_result_get_length.serializable = false
set shaderc_result_get_bytes.serializable = false
set shaderc_result_get_error_message.serializable = false
set shaderc_result_release.serializable = false

languagekit_native_end
include "../build/export.rl"
__recurloop_export_library
