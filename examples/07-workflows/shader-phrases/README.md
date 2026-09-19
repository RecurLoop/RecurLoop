# Phrase-extensible shaders

This example keeps GLSL as GLSL and lets the RecurLoop lexicon selectively add
new shader constructs. `shader glsl { ... }` and `shader spirv ... { ... }` capture the block while
RecurLoop compiles the surrounding function, then scan it left-to-right against
the `Shaders:Source:GLSL` dictionary.

Anything not present in that dictionary is copied byte-for-byte and remains the
responsibility of shaderc. This means GLSL versions, extensions, type rules and
preprocessor behavior do not have to be duplicated in RecurLoop.

A fixed spelling is just a phrase payload:

```rl
let Shaders:Source:GLSL:float3 = phrase {
    payload = "vec3"
}
```

A structural construct is an ordinary phrase action:

```rl
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
```

Then normal shader code can use both extensions:

```rl
let fragment_spirv = fn () -> BitString* {
    return shader spirv fragment {
#version 450
layout(location = 0) out vec4 outColor;
void main() {
    float light = saturate(-0.25);
    float3 color = float3(1.0, 0.5, 0.25) * light;
    outColor = vec4(color, 1.0);
}
    }
}
```

Build the graphics libraries, then run:

```bash
make graphics-libraries

build/Release/bin/recurloop \
  --library-path build/Release/libraries \
  --library shaders \
  --file examples/07-workflows/shader-phrases/main.rl
```

## Extension contract

The public extension surface is intentionally small:

- add children below `Shaders:Source:GLSL`;
- use `payload` for exact source replacement;
- use an action for structural syntax;
- `Shaders:Source:emit` appends generated source;
- `Shaders:Source:take_identifier` consumes one identifier after a phrase;
- `Shaders:Source:take_parenthesized` consumes a balanced GLSL argument group;
- `Shaders:Source:emit_expanded` recursively applies shader phrases to a nested
  fragment before appending it.

Longest-prefix lexicon lookup is used. Identifier boundaries are respected, and
comments/string literals are copied without expansion.

The showcase uses `shader spirv fragment`, so phrase expansion and shaderc both
run at source-compilation time and the resulting SPIR-V is embedded as native
read-only data. `shader glsl { ... }` remains available when expanded source text
is wanted instead.

The low-level `Shaders:Spirv:Builder` remains separate. A future native shader
frontend can lower phrase semantics directly to SPIR-V without changing this
GLSL compatibility surface.
