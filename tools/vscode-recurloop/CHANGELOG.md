# Changelog

## 0.2.10

- Navigate to type declarations and references from allocation, casts, size
  queries, function signatures and record fields, including qualified names.

- Add source-level library imports (`import window`, `import vulkan`) backed by
  the CLI library resolver. Include both binding images in installed runtimes
  and release packages; graphics libraries no longer need project-local copies.

- Preserve semantic inspection identities across engine imports and cached
  includes. Inspecting the project entry no longer crashes the shared runtime
  and closes its terminals, including while using `:target run`.

- Resolve colors and documentation from the final elaborated binding for both
  local and dictionary symbols. Link `let` declarations to their saved phrases,
  preserve shadowed versions and inherited styles, and honor explicit clearing.

- Link top-level function calls, including qualified and nested calls, to their
  phrase metadata so runtime colors and documentation appear at the call site.

- Support `set name.color = "#RRGGBB"` for local variables and function values,
  including immutable `let` bindings, through the shared local metadata handler.

- Show top-level runtime variable documentation on declarations and expression
  reads, including metadata attached with `set name.docs = "..."`.
- Support documentation for local variables in `fn`, with lexical scope and
  separate descriptions for shadowed bindings, without emitting runtime stores.
- Use the captured expression's source origin for semantic token locations and
  keep hover ranges from including the following token.

## 0.2.9

- Require RecurLoop 0.2.9 or a newer patch in the 0.2 series.
- Fix runtime phrase palette entries overwriting each other, which could color
  keywords such as `let` as identifiers with the default language libraries.
- Remove static syntax highlighting. Source uses the theme's plain text color
  until runtime inspection supplies colors in the project's language context.

## 0.2.8

- Require RecurLoop 0.2.8 or a newer patch in the 0.2 series.

## 0.2.7

- Show phrase span documentation in hovers when the selected symbol has no docs.
- Require RecurLoop 0.2.7 or a newer patch in the 0.2 series.

## 0.2.6

- Honor folder-specific runtime and analysis settings in multi-folder workspaces.
- Use the running server's executable for console clients and runtime diagnostics.
- Select the RecurLoop terminal profile automatically in workspaces with a saved
  project entry, including custom `recurloop.projectFile` paths.
- Detect projects at startup and restore previous workspace terminal settings
  when the last project entry is removed.

## 0.2.5

- Update managed runtimes automatically to the release bundled with an extension update.
- Add Update Runtime and Uninstall Runtime commands, including use without a project.
- Drain active project targets before runtime maintenance and remember manual removal.

## 0.2.4

- Enable console input colors from the current runtime's semantic metadata.
- Add VS Code shell integration markers for commands and their exit status.
- Wrap long console commands during editing and retain their full text in scrollback.

- Require RecurLoop 0.2.4 or a newer patch in the 0.2 series.
- Recheck runtime versions on selection even when a replaced executable retains
  the same timestamps and size.
- Offer Initialize Project when explicit runtime commands or debugging are used
  without a project entry.
- Add first-use instructions, platform support and runtime conflict guidance.

- Use the shared project target protocol; source-defined target blocks replace
  editor-specific JSON declarations and the TypeScript dependency walker.
- Use framed output and an explicit request status for server operations.
- Share the `.cache/recurloop` module/artifact directory with CLI project actions.
- Expand records, paged arrays and pointer pointees in locals and Watches;
  scalar fields/elements support evaluation and assignment.
- List and select native threads; frame and variable handles retain thread
  identity. Pause uses the controller's interrupt channel.

## 0.1.1

- Keep runtime resources and language providers dormant without a project;
  commands are silent no-ops and debug launches cancel without an error.
- Remove generic startup activation and dispose project services when the last
  workspace project entry disappears.
- Keep the repository's default RecurLoop terminal console for initialized
  projects; use the normal shell silently when no project entry is present.
- Require a saved workspace project entry before launching any runtime-backed
  features; loose files keep static highlighting without setup prompts.
- Add RecurLoop: Initialize Project to create an empty configured entry without
  overwriting existing source; observe entry creation/removal and custom paths.
- Document using the same project source with ordinary CLI --file and --serve.
- Default to `recurloop` on PATH; keep repository builds as workspace overrides.
- Report missing explicit executable paths without selecting another build.
- Offer a confirmed installation of a compatible full runtime when the default
  executable is missing, with file selection and deferral options.
- Store verified runtime releases in extension global storage on the workspace
  host, without administrator access or changes to the shell PATH.
- Add RecurLoop: Install Runtime and check runtime version compatibility.

## 0.1.0

- Initial language intelligence, shared project runtime, tasks and debugging.
