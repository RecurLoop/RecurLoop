# RecurLoop

RecurLoop is an experimental, extensible programming language and engine.
Named phrases represent values, namespaces and syntax, so language features can
be defined in source, composed as libraries and compiled to native code.
The language and library interfaces are evolving; current releases support Linux x86-64.

**[Documentation — recurloop.org/docs](https://recurloop.org/docs)** ·
[Examples](examples/README.md) · [Releases](https://github.com/RecurLoop/RecurLoop/releases)

## Install

Install the latest binary and standard libraries (Linux x86-64, glibc 2.35+):

```sh
curl -fsSL https://raw.githubusercontent.com/RecurLoop/RecurLoop/main/tools/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
recurloop --version
```

See [binary installation](https://recurloop.org/docs/core/installation) for updates,
custom locations and removal. For VS Code, start with the
[extension installation guide](https://recurloop.org/docs/core/installation-vscode),
which covers automatic runtime installation and selecting your own binary.

## Develop the runtime

Requires Linux x86-64, Git, Make, CMake 3.25+, Ninja and Clang with C++23 support.
LLVM is selected or downloaded automatically; see [toolchain setup](docs/releases.md#dependency-model).

```sh
git clone https://github.com/RecurLoop/RecurLoop.git
cd RecurLoop
make build libraries
./build/Release/bin/recurloop --string 'print 42'
make check
```

Use `--file path/to/program.rl` to run a file. See [release builds and full verification](docs/releases.md)
and [runtime architecture](docs/architecture.md) for further development details.

### Install from source

From the checkout, choose a user or system installation:

```sh
make install PREFIX="$HOME/.local"   # current user
# or:
sudo make install                  # system-wide: /usr/local
```

Both commands build and install the runtime, standard libraries and documentation.
For a user installation, add `~/.local/bin` to `PATH`. See
[installation layout and compatibility](docs/releases.md#linux-release-profile).

## Develop the VS Code extension

Requires Node.js 22+, npm and the VS Code `code` command on `PATH`:

```sh
make install-vscode-extension       # build, package and install the VSIX
```

Use `make vscode-extension` to build without installing. This checkout selects
`build/Release/bin/recurloop` in VS Code, so build the runtime first.
See [extension development](docs/vscode-development.md) for the F5 workflow and tests,
and the [editor guide](tools/vscode-recurloop/README.md) for project setup and features.

## Documentation and source map

- **Use the language:** [online documentation](https://recurloop.org/docs),
  [examples](examples/README.md), [library sources](libraries/README.md).
- **Understand the implementation:** [architecture and source layers](docs/architecture.md),
  [phrase processing](docs/phrase-processing.md), [core runtime](docs/core-runtime.md),
  [host ABI](docs/host-abi.md).
- **Work on tools:** [projects and targets](docs/projects.md),
  [project runtime](docs/project-runtime.md), [editor environment](docs/project-environment.md).
- **Publish changes:** [builds and releases](docs/releases.md),
  [documentation authoring and export](docs/documentation-authoring.md),
  [contributing](CONTRIBUTING.md).

Public documentation is authored as `.rl` objects in `source/docs/core/` and
`libraries/<name>/docs/`. The root `docs/` directory documents the implementation
and contributor workflows; it is excluded from the public website and CLI manuals.

[Apache-2.0 license](LICENSE) · [Trademarks](TRADEMARKS.md) · [Third-party notices](THIRD-PARTY.md)
