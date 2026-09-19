# Vulkan standalone executable

This showcase emits a regular Linux ELF with RecurLoop's `emit executable`. The
shader bodies are phrase-extensible GLSL, but shaderc runs while RecurLoop is
compiling `standalone.rl`; the resulting SPIR-V is embedded directly in the
executable as read-only data.

Build the optional graphics libraries:

```bash
make graphics-libraries
```

Emit the executable:

```bash
build/Release/bin/recurloop \
  --library-path build/Release/libraries \
  --library shaders \
  --library window \
  --library vulkan \
  --file examples/07-workflows/vulkan-hello-triangle-executable/standalone.rl
```

Run it without RecurLoop or `LD_PRELOAD`:

```bash
/tmp/recurloop-vulkan-triangle
```

`standalone.rl` clears the build-time link set after the embedded shaders have
been compiled and links only libc, GLFW, and Vulkan for the final executable.
`libshaderc` is therefore a build-time dependency, not a runtime dependency.

Useful checks:

```bash
file /tmp/recurloop-vulkan-triangle
ldd /tmp/recurloop-vulkan-triangle
readelf -d /tmp/recurloop-vulkan-triangle | grep NEEDED
```

The expected runtime dependencies do not include `libshaderc`. `module auto`
closes the native function dependency graph and `module strip` keeps the output
stripped.

The same embedding primitive is generic: `Embed:emit_bytes` lowers arbitrary
compile-time binary data to a native `bits"..."` literal, so shaders do not need
a custom asset container or ELF section.
