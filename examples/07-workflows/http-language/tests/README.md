# HTTP tests

Each HTTP case is independently runnable. The `.rl` file contains the server program, the `.expected` file contains the expected response, and the matching `.test.sh` contains the client request.

The easiest manual check is therefore:

```bash
examples/07-workflows/http-language/tests/echo.test.sh \
  build/Release/bin/recurloop
```

or:

```bash
examples/07-workflows/http-language/tests/query-header.test.sh \
  build/Release/bin/recurloop
```

Each script builds `/tmp/recurloop-http-library.rli` automatically when needed and reports `ok` only after the actual socket request matches the expected result.

`standalone.test.sh` additionally compiles `standalone.rl`, launches the
generated `/tmp/recurloop-http-server` directly, and checks its inline POST
handler over a real socket.

To inspect the server manually instead, build the image and start the `.rl` file yourself:

```bash
BIN=build/Release/bin/recurloop
$BIN --file libraries/language-kit/library.rl -- /tmp/recurloop-language-kit.rli
$BIN --import /tmp/recurloop-language-kit.rli \
  --file libraries/http/library.rl \
  -- /tmp/recurloop-http-library.rli
$BIN --import /tmp/recurloop-http-library.rli \
  --file examples/07-workflows/http-language/tests/echo.rl
```

Then send the corresponding request shown in `echo.test.sh` from another terminal.
