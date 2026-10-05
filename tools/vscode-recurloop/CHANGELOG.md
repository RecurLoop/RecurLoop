# Changelog

## 0.1.2

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
