# Shell tests

Build LanguageKit and the Shell image once:

```bash
BIN=build/Release/bin/recurloop
$BIN --file libraries/language-kit/library.rl -- /tmp/recurloop-language-kit.rli
$BIN --import /tmp/recurloop-language-kit.rli \
  --file libraries/shell/library.rl \
  -- /tmp/recurloop-shell-library.rli
```

Run a normal source test directly:

```bash
$BIN --import /tmp/recurloop-shell-library.rli \
  --file examples/07-workflows/shell-language/tests/top-level.rl
```

Compare with `top-level.expected`.

The compiled-function test is also a normal source file:

```bash
$BIN --import /tmp/recurloop-shell-library.rli \
  --file examples/07-workflows/shell-language/tests/compiled-functions.rl
/tmp/recurloop-shell-functions
```

The executable output is stored in `compiled-functions.expected`.
