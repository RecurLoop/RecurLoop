# shaders.rli

Source-defined shader support for RecurLoop.

The production frontend uses shaderc's C API for GLSL and HLSL and returns an
owned SPIR-V binary. The library explicitly targets Vulkan 1.0/SPIR-V 1.0 for
the starter Vulkan binding.

The same file also contains `Shaders:Spirv:Builder`, an independent RecurLoop
SPIR-V encoder. It owns a growable `u32` word buffer, writes the SPIR-V module
header, allocates result IDs, encodes the `(wordCount << 16) | opcode` header
for arbitrary instructions, and finalizes to the same `Shaders:Binary` type as
shaderc. This is intentionally a backend primitive rather than an incomplete
GLSL clone: a RecurLoop-native shader DSL can lower to it later.


## Compile-time SPIR-V

`shader spirv vertex { ... }`, `shader spirv fragment { ... }`, and
`shader spirv compute { ... }` use the same `Shaders:Source:GLSL` phrase
dictionary as `shader glsl { ... }`, but compile the expanded source immediately
with shaderc while RecurLoop is compiling the surrounding function. The result
is emitted through the generic `embed.rli` helper as a native `bits"..."`
literal, so it lands directly in read-only native data.

```rl
let vertex = fn () -> BitString* {
    return shader spirv vertex {
#version 450
void main() {
    gl_Position = vec4(0.0);
}
    }
}
```

At runtime there is no shader compilation or allocation. `Embed:data(blob)` and
`Embed:bytes(blob)` expose the embedded bytes. An executable can therefore use
shaderc only as a build-time dependency and omit it from its runtime link set.

The embedding mechanism is intentionally not shader-specific: `Embed:emit_bytes`
can be used by any source-time producer for generated tables, fonts, images,
serialized assets, or other binary data.

## HLSL backend note

`Shaders:compile_hlsl` currently goes through shaderc/glslang because that keeps
the RecurLoop binding tiny and source-only. Upstream shaderc has deprecated HLSL
input and says it may be removed in a future release. The public RecurLoop API is
kept separate from shaderc so this backend can later be switched to DXC/Slang
without changing callers. The native `Shaders:Spirv:Builder` is independent of
shaderc.

## Phrase-extensible GLSL

The library also exposes `shader glsl { ... }`. The block is expanded while
RecurLoop compiles the surrounding function. Ordinary GLSL is copied unchanged;
only spellings present in the dedicated `Shaders:Source:GLSL` phrase dictionary
are intercepted.

This keeps GLSL maintenance with shaderc instead of cloning the GLSL grammar in
RecurLoop. Extensions stay native to the RecurLoop model:

```rl
let Shaders:Source:GLSL:float3 = phrase {
    payload = "vec3"
}
```

For structural syntax, use a normal phrase action together with the deliberately
small source-expansion API (`emit`, `take_identifier`, `take_parenthesized`, and
`emit_expanded`). Actions are serialized with the lexicon, so an extension can
live in its own `.rli` and add shader vocabulary without changing this library.

Comments and string literals are passed through without phrase expansion, and
identifier-boundary checks prevent a phrase such as `saturate` from matching the
middle of a longer identifier.

See `examples/07-workflows/shader-phrases/`.
