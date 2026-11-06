# Documentation library

Import docs before using Docs APIs or defining Docs:Pages objects. Concise phrase help stays on .docs; extended behavior is described by ordinary RecurLoop objects.

Source catalogs generate their index automatically. Docs:read_export reads JSON and its existing index; Docs:merge preserves and combines indexes. Docs:save_directory persists .rl objects. Catalog entries are borrowed, strings returned by as_text/as_json are owned, and Docs:destroy releases a catalog.

See ../../docs/documentation-authoring.md for the source contract and contributor workflow. This file is not exported as a public manual.
