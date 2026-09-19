# RecurLoop libraries

Reusable RecurLoop source belongs here. The `examples/` tree demonstrates how
these libraries are imported and combined; it is not their source of truth.

- `recurloop/` — semantic core used to build the embedded `core.rli`.
- `language-kit/` — shared source-level language construction helpers.
- `shell/` — shell language library built on LanguageKit.
- `inferred/` — inferred-language library built on LanguageKit.
- `http/` — HTTP language library built on LanguageKit.
- `build/export.rl` — shared transient build helper used by `library.rl` files.

Build the distributable library images with:

```bash
make libraries
```

They are written to `build/Release/libraries/` and can be imported by name:

```bash
build/Release/bin/recurloop --library shell --library inferred -
```

`language-kit.rli` is the shared base. The shell, inferred, and HTTP images are
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
