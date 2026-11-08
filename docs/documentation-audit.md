# Public documentation example audit

Audited on 2026-11-08, starting at <https://recurloop.org/docs/core/overview>.
The twelve published bundles matched the checkout's existing exports: version
0.2.12, revision `7ebb45032f5f44e7b52f0a8f33ff49c07a3093e0`.
The published installer was also identical to `tools/install.sh`.

## Method and coverage

Installed the published release under `/tmp/recurloop-docs-install`, without
changing the user's installation. Walked the core guides and each library's
guide sequence, running code in separate processes and working directories.
Checked displayed output as well as exit status; successful evaluation alone
missed the Shell formatting problem below.

| Guide scope | Examples after corrections |
| --- | ---: |
| Core | 19 |
| LanguageKit | 6 |
| Shell | 12 |
| Inferred | 6 |
| Http | 8 |
| Gui | 8 |
| IDE | 5 |
| Project | 4 |
| Embed | 4 |
| Window | 4 |
| Vulkan | 6 |
| Docs | 5 |
| Total | 87 |

The original published guides contained 85 executable examples, including the
native-output block omitted by the previous test. All evaluated successfully,
but several Shell examples produced incorrect text. Two new capture examples
assert the actual output.

Additional checks used the published binary:

- Installation, version reporting and standard-library discovery outside the checkout.
- First-program output, documentation search, symbol help, JSON export/search
  and merging the same export twice.
- Twelve HTTP requests against the documented handlers and servers: exact and
  wildcard routes, HEAD, decoded/missing/empty query values, binary bodies,
  JSON and headers, absent/present token headers, and one-connection serving.
- Project targets `application`, `all` and `prepare_binary`, including shared
  prerequisite execution and running the generated application.
- Native raw bytes, ELF object output, and running release and debug executables.
- Sixty-eight concrete API examples, with their library imports supplied.
  Invocation signatures and examples requiring application-specific values,
  files, pointers or an enclosing function were not treated as standalone programs.

GUI, IDE and window examples were imported and compiled; interactive display
and GPU event loops were not exercised. VS Code installation and system-wide
installation commands were reviewed without changing the editor or `/usr/local`.

## Corrections

- Shell consumes one backslash-escaping layer in command arguments. Formats such
  as `printf "hello\n"` printed `hellon`; examples now preserve the backslash for
  `printf`. The guide explains this difference from ordinary string literals.
- The `let` API example used an invalid numeric dictionary definition. It now
  defines and calls a valid function in that dictionary.
- The inline `environment` example put a Shell command and the closing brace on
  one line. It now uses a multiline body, imports Shell and checks the status.
- Native output now lists the required host tools, uses paths in the working
  directory, and shows how to run and inspect the generated files.
- Function types, metadata, syntax rewrites and the documentation round trip now
  include calls and assertions. The `sizeof` example supplies its enclosing function.
- Project instructions name the file to save. Documentation CLI examples now
  create the exports they consume and explain which commands require a source package.

The example runner now handles both `recurloop` and `rl` fences, follows guide
order, gives each example its own working directory, supports installed library
layouts and verifies native artifacts and executable exit status. A separate
mixed-fence check confirmed that declarations do not leak between examples.

## Verification

- `make check` passed.
- `make docs-check` passed the documentation, CLI, export/merge and example checks.
- `make docs-examples` passed all 87 guide examples.
- The same 87 corrected examples passed with the downloaded release binary and
  its installed libraries.
- All 68 selected API examples passed after correction, using the downloaded binary.
- The twelve HTTP checks and three selected project targets passed.
- CLI export/merge preserved all 997 pages; the sample search returned 14 matches.
- A deliberately incorrect Shell format failed the new output assertion.

Regenerated bundles are in `build/Release/documentation/`, using
`cmake --build --preset release --target RecurloopDocumentation`. These changes
have not been published to the website.
