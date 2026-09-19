// Phrase-extensible GLSL showcase.
// Requires: --library shaders

let ShaderPhraseShowcase = phrase { dictionary = true permanent = true }

// The smallest extension possible: a lexicon phrase whose payload replaces the
// matched spelling. Both the type spelling and constructor below become `vec3`.
let Shaders:Source:GLSL:float3 = phrase {
    payload = "vec3"
}

// Structural extensions are ordinary RecurLoop phrase actions. The expander
// has already consumed `saturate`; this action consumes the following balanced
// parenthesized GLSL expression and emits a standard GLSL clamp expression.
let Shaders:Source:GLSL:saturate = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let value = Shaders:Source:take_parenthesized(state)
        if !value { return }
        defer free(value)

        Shaders:Source:emit(state, "clamp(")
        Shaders:Source:emit_expanded(state, value)
        Shaders:Source:emit(state, ", 0.0, 1.0)")
    }
}

let ShaderPhraseShowcase:fragment_spirv = fn () -> BitString* {
    return shader spirv fragment {
#version 450
layout(location = 0) out vec4 outColor;

void main() {
    // Unknown GLSL passes through unchanged. Phrase spellings inside comments
    // are deliberately not expanded: saturate(float3).
    float light = saturate(-0.25);
    float3 color = float3(1.0, 0.5, 0.25) * light;
    outColor = vec4(color, 1.0);
}
    }
}

let ShaderPhraseShowcase:run = fn () -> i64 {
    let binary = ShaderPhraseShowcase:fragment_spirv()
    if !binary || Embed:bytes(binary) < 20 { return 1 }
    let words = cast(u32*, Embed:data(binary))
    if !words || words[0] != 119734787 { return 2 }
    printf("shader phrase showcase ok (%llu embedded SPIR-V bytes)\n", Embed:bytes(binary))
    return 0
}

var shader_phrase_showcase_result = ShaderPhraseShowcase:run()
assert shader_phrase_showcase_result == 0
