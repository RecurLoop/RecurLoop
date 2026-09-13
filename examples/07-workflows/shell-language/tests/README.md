# Shell tests

Build LanguageKit and the Shell image once:

```bash
BIN=build/Release/bin/recurloop
$BIN --file examples/07-workflows/language-kit/library.rl
$BIN --import /tmp/recurloop-language-kit.rli \
  --file examples/07-workflows/shell-language/library.rl
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
