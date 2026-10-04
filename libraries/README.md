# RecurLoop libraries

Reusable RecurLoop source belongs here. The `examples/` tree demonstrates how
these libraries are imported and combined; it is not their source of truth.

- `recurloop/` — semantic core used to build the embedded `core.rli`.
- `language-kit/` — shared source-level language construction helpers.
- `shell/` — shell language library built on LanguageKit.
- `inferred/` — inferred-language library built on LanguageKit.
- `http/` — HTTP language library built on LanguageKit.
- `gui/` — source-defined application GUI API: windows, layout, widgets, events, timers and shortcuts. GTK3 is currently a replaceable private backend.
- `ide.rl` — GUI-independent IDE runtime: clean-process hot reload, Unix-runtime sessions, inotify and persistent terminal models. The concrete IDE UI lives in `examples/07-workflows/ide/*.rl`.
- `embed/` — generic compile-time binary embedding built on native `bits` literals.
- `bitwise/` — optional 64-bit bitwise functions implemented with RecurLoop `asm`.
- `shaders/` — optional GLSL/HLSL -> SPIR-V + native SPIR-V builder.
- `window/` — optional GLFW window/Vulkan-surface binding.
- `vulkan/` — optional Vulkan subset used by the hello-triangle workflow.
- `build/export.rl` — shared transient build helper used by `library.rl` files.

Build the distributable library images with:

```bash
make libraries
```

They are written to `build/Release/libraries/` and can be imported by name:

```bash
build/Release/bin/recurloop --library shell --library inferred -
```

`language-kit.rli` is the shared base. The shell, inferred, HTTP, GUI, and IDE images are
deterministic dependency deltas: importing one automatically imports
`language-kit.rli` first unless the same base image is already loaded. Keep the
standard-library images together when distributing them; dependency paths are
stored relative to the child image when possible.

A library source never owns a `/tmp` output path. The image destination is the
single process argument after `--`, for example:

```bash
build/Release/bin/recurloop \
  --file libraries/language-kit/library.rl \
  -- /tmp/language-kit.rli
```


## Optional graphics libraries

The graphics libraries are separate from the standard `make libraries` target
because they deliberately depend on system shared libraries. Build them with:

```bash
make graphics-libraries
```

This writes `shaders.rli`, `window.rli`, and `vulkan.rli` beside the standard
images and builds the dependency-free `embed.rli` automatically when needed,
without making GLFW/Vulkan/shaderc mandatory for normal RecurLoop builds or CI.
