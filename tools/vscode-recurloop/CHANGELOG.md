# Changelog

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
