# Application project

Copy this directory to start an application with an installed RecurLoop runtime.
It has no dependency on the RecurLoop source checkout. Native builds also need
Clang/LLD and the platform C development files on the runtime host.

```sh
recurloop --targets
recurloop --target run
recurloop --target test
recurloop --target build
./build/app
recurloop --debug-target debug
recurloop --target docs
recurloop --docs search "answer" --from build/docs/my-application.json
```

| Target | Responsibility |
| --- | --- |
| `run` | Run the application in the runtime; prints `42`. |
| `build` | Write the native executable `build/app`. |
| `build-debug` | Write `build/app-debug` with source debug information. |
| `debug` | Prepare `build-debug`, then select its executable for debugging. |
| `test` | Run assertions from `tests/main.rl`. |
| `docs` | Export the project's own manual and API help to `build/docs/my-application.json`. |
| `clean` | Remove the generated `build` directory. |

`run`, builds and documentation export do not run tests implicitly. Choose `test`
explicitly. Use `--debug-target debug` or VS Code F5 to start the debugger;
ordinary `--target debug` only prepares the executable and runs its empty body.
Set a breakpoint on `answer += 2` in `src/main.rl`, select **Application: debug**
and press F5. No separate build task is needed.

Application startup stays inside `Application:main`. Loading the project only
imports its vocabulary and definitions; target bodies run when selected. Test
sources are included only by `test`. Extend the source graph through includes
from the entry or other included application files.

## Documentation

Edit the package name and version in `recurloop.docs`, author manual objects in
`docs/*.rl`, and place concise API help in `.docs` metadata beside definitions.
Optionally add `repository=https://github.com/your-account/your-project` for
source links. Documentation objects are loaded separately with the Docs
vocabulary; their code fences are text and do not execute during export.

`recurloop --target docs` writes one portable v3 bundle containing pages,
navigation, rendered blocks and its search index. It excludes standard-library
manuals, requires no Git repository and does not start the application. Rename
the output filename in the `docs` target when renaming the package.

The JSON can be published as package documentation or loaded by a compatible
reader. It is a package bundle, not a collection `index.json` for the complete
RecurLoop website. The chapter **First project** in the public manual walks
through these exact project files.

Run `recurloop --target clean` to remove generated executables and JSON. Source
files, tests and authored documentation stay in the project.
