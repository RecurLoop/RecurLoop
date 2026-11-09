// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:first_project = [
    id = phrase { payload = "first-project" }
    title = phrase { payload = "First project" }
    section = phrase { payload = "Getting started" }
    order = phrase { payload = "45" }
    body = phrase {
        payload = "Create an application with conventional targets for running, native builds, debugging, testing, documentation and cleanup. The same project works from the CLI, VS Code tasks and the project console.

Install the [RecurLoop binary](installation.rl) or follow [VS Code setup](installation-vscode.rl). You can copy the complete [application starter](https://github.com/RecurLoop/RecurLoop/tree/main/examples/07-workflows/application-project), or create the files below. The starter needs only an installed runtime, not the runtime's source repository.

## Create the project folder

```console
mkdir -p my-application/src my-application/tests my-application/docs my-application/.vscode
cd my-application
```

Alternatively, open a new folder in VS Code and run **RecurLoop: Initialize Project**. It creates an empty entry without replacing an existing file; add the following files yourself.

Create all the files below before running the target commands in this chapter. The entry includes both the application source and its manual.

```text
my-application/
  recurloop.project.rl
  recurloop.docs
  .gitignore
  .vscode/launch.json
  src/main.rl
  tests/main.rl
  docs/overview.rl
```

## Define the application

Save this as `src/main.rl`:

```recurloop
// Loading the project defines the application without starting it.
let Application = [
    answer = fn () -> i64 {
        var answer:i64 = 40
        answer += 2
        return answer
    }
    main = fn () -> i64 {
        printf(\"%ld\\n\", Application:answer())
        return 0
    }
]
set Application:answer.docs = \"Returns the application's answer: 42.\"
set Application:main.docs = \"Prints the answer and returns exit status 0.\"
```

`Application:answer` computes 42. `Application:main` prints it and returns exit status 0. Loading the source only defines functions and their short API help; it does not start the application.

## Define the project targets

Save this as `recurloop.project.rl`:

```recurloop
import project
import docs
include \"src/main.rl\"
include \"docs/overview.rl\"

target run {
    assert Application:main() == 0
}

target build {
    let prepared = run mkdir -p build
    assert prepared == 0
    module auto
    emit executable \"./build/app\" application_main = fn () -> i64 {
        return Application:main()
    }
}

target build-debug {
    let prepared = run mkdir -p build
    assert prepared == 0
    module auto
    emit executable debug \"./build/app-debug\" application_debug_main = fn () -> i64 {
        return Application:main()
    }
}

target debug depends [build-debug] debug executable \"./build/app-debug\" {}

target test {
    include \"tests/main.rl\"
}

target docs {
    let prepared = run mkdir -p build/docs
    assert prepared == 0
    assert Docs:export_package(\".\", \"build/docs/my-application.json\") == 1
}

target clean {
    let cleaned = run rm -rf -- build
    assert cleaned == 0
}
```

| Target | Responsibility |
| --- | --- |
| `run` | Run the application in the runtime; no executable file is needed. |
| `build` | Create the native executable `build/app`. |
| `build-debug` | Create `build/app-debug` with source debug information. |
| `debug` | Prepare `build-debug`, then select its executable for debugging. |
| `test` | Execute assertions from `tests/main.rl`. |
| `docs` | Export the project's manual and API help to `build/docs/my-application.json`. |
| `clean` | Remove only the generated `build` directory. |

These names are project conventions, not reserved keywords. Running or building does not implicitly run tests. The only dependency here is `debug` on `build-debug`. A shared dependency executes once per request; targets do not automatically skip work based on file timestamps.

Keep imports and shared application definitions outside target bodies. Keep startup, tests, native output and documentation export inside their targets. Tests are included only by `test`. The Docs vocabulary and `docs/overview.rl` are loaded with the project so the editor can analyze the manual without running an export. Merely placing a source file in the folder does not include it in the project's processing graph.

## Add tests

Save this as `tests/main.rl`:

```recurloop
assert Application:answer() == 42
```

Run it explicitly:

```console
recurloop --targets
recurloop --target test
recurloop --target run
recurloop --target build
./build/app
```

`test` succeeds silently; both ways of running the application print `42`. A failed assertion makes the selected target fail.

Project actions discover the nearest saved `recurloop.project.rl` by searching the current directory and its parents. Select an explicit entry with `recurloop --project recurloop.project.rl --target run`. Includes resolve relative to their source file; generated paths such as `./build/app` use the project working directory. See [Project paths](../../../libraries/project/docs/root-paths.rl).

Project mode supplies Project, Shell and Inferred by default. Explicit `--library` options replace the Shell/Inferred defaults. Use project actions for this workflow rather than directly evaluating the entry with `--file`.

## Author and export documentation

Save the package settings as `recurloop.docs`:

```ini
name=my-application
version=0.1.0
directory=docs
entry=recurloop.project.rl
```

Change the name and version for your project. Optionally add a `repository` URL for source links. Rename the output file in the `docs` target when changing the package name.

Save this manual object as `docs/overview.rl`:

```recurloop
let Docs:Pages:overview = [
    id = phrase { payload = \"overview\" }
    title = phrase { payload = \"My application\" }
    section = phrase { payload = \"Guides\" }
    default = phrase { payload = \"true\" }
    order = phrase { payload = \"10\" }
    body = phrase {
        payload = \"## Run the application

Run `recurloop --target run` from the project directory. The application prints
`42` and exits successfully.

## Test and build

Use `recurloop --target test` to check the answer. Use `recurloop --target build`
to create `build/app`, then run `./build/app`.

## Export this manual

Run `recurloop --target docs`. The portable bundle in
`build/docs/my-application.json` contains this guide, API help and a search index.\"
    }
]
```

The entry's `import docs` supplies the vocabulary used by manual objects, and its top-level `include \"docs/overview.rl\"` makes this file available to the editor's semantic analysis. Add more `.rl` objects under `docs` and include them from the entry or another included source; put concise `.docs` help beside the application's API definitions.

If the editor reports \"source is outside the current project processing graph; semantic analysis is unavailable\", check that the manual is included outside a deferred target body and save the entry. The `directory=docs` setting controls documentation export discovery; it does not itself include files in the editor's processing graph. Loading manual objects defines data only; `recurloop --target docs` performs the export.

```console
recurloop --target docs
recurloop --docs list --from build/docs/my-application.json
recurloop --docs search \"answer\" --from build/docs/my-application.json
recurloop --docs show overview --from build/docs/my-application.json
```

The `docs` target combines the project's manual objects and API help into a portable v3 package bundle, including navigation, rendered blocks and the search index. It excludes standard-library manuals, works without a Git repository, and neither starts the application nor runs tests. Code fences inside documentation remain text during export. The result can be published as package documentation or loaded by a compatible reader. It is a package bundle, not a website collection `index.json` or an HTML site.

## Configure F5 debugging in VS Code

Native builds need Clang/LLD and platform C development files on the runtime host. On Debian/Ubuntu, install them with `sudo apt install clang-22 lld-22 libc6-dev`. Native debugging currently uses Linux x86-64 and requires permission to trace the child process with `ptrace`. In WSL, SSH or a container, install the extension and tools in that environment.

Save this as `.vscode/launch.json`:

```json
{
  \"version\": \"0.2.0\",
  \"configurations\": [
    {
      \"name\": \"Application: debug\",
      \"type\": \"recurloop\",
      \"request\": \"launch\",
      \"target\": \"debug\",
      \"stopOnEntry\": false
    }
  ]
}
```

If the file already exists, add the configuration to its existing array. The `target` value names the project's `debug` target.

1. Open the project folder as a trusted workspace and save the source and project files.
2. Set a breakpoint on `answer += 2` in `src/main.rl`.
3. Select **Application: debug** in **Run and Debug**, then press **F5**.
4. The `build-debug` dependency creates `build/app-debug`; the debugger stops at your breakpoint. Expand **Variables → Locals**: `answer` is 40.
5. Press **F10** to see it become 42, then **F5** to finish. The program prints `42` and exits with status 0.

Dependencies prepare the executable, so no separate `preLaunchTask` is needed. Application I/O uses its terminal; **Debug Console** evaluates expressions while stopped. Set `stopOnEntry` to `true` if you want an initial stop before reaching a breakpoint. **Run Without Debugging** executes the target's ordinary body: the `debug` body is empty, so select the `run` target for ordinary execution.

The same workflow is available in the CLI:

```console
recurloop --target build-debug
./build/app-debug
recurloop --debug-target debug
```

The last command starts the interactive debugger. Ordinary `--target debug` only prepares its dependency and executes the empty body. See [Project debugging](../../../libraries/project/docs/debug-targets.rl).

## Run tasks and use the project console

Choose **Terminal → Run Task** to select `run`, `test`, `build` or `docs`. Target discovery uses the saved project entry; no `tasks.json` is needed.

Run **RecurLoop: Open Project Console**. Enter these commands separately:

```text
print Application:answer()
:targets
:target test
```

The console shares project definitions and keeps its own session state. After changing `answer += 2` to `answer += 3` and saving, enter `:refresh`, then `print Application:answer()`: the result becomes 43. The `test` target now fails; restore 2 before continuing. VS Code reloads saved source before running targets, while an existing console needs `:refresh` to adopt a new publication.

A failed project reload retains the previous valid publication. Check diagnostics before assuming edited code is active. After replacing the runtime binary or using **RecurLoop: Restart Language Runtime**, reopen consoles.

## Keep generated files separate

Save this as `.gitignore`:

```text
/build/
/.cache/
```

Run `recurloop --target clean` to remove the generated `build` directory. Source files, tests, manual objects and the project entry remain intact. The next build or documentation export recreates its output directory. Cleanup does not remove the runtime's project cache.

Continue with [Values](values.rl) or the [Project library](../../../libraries/project/docs/usage.rl)."
    }
]
