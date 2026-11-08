# Documentation pipeline

This contributor guide is excluded from the public export. Public documents describe phrases and language behavior only. Do not copy README, Makefile, build instructions or implementation manuals into public objects.

Author language objects in source/docs/core/*.rl and library objects in libraries/<name>/docs/*.rl under Docs:Pages. A library owns its documentation alongside its code; source/docs does not contain library manuals. String fields use phrase payloads: symbol (optional phrase name), id (for a standalone guide), title, section, default ("true" for the landing page), order (an optional integer payload from 0 to 1000000), and body (rich text). With symbol present, the stable phrase identifier is generated from the symbol. The loader stamps source locations automatically.

A source package can configure name, version, directory, repository and entry in its own recurloop.docs. Standard libraries each have this descriptor next to their docs directory. Optional image selects an installed library image for semantic phrase help instead of executing a library-build entry point. Optional repository-directory prefixes source links when a package lives in a monorepo; remove that prefix and update repository when extracting the package into its own repository. Neither code nor docs paths need to change. The engine selects source/docs/core and version=runtime. Other packages default to docs/. Included source packages are discovered from runtime provenance and use their own configuration. Indexes are constructed after object evaluation and semantic phrase help are combined.

## Reading paths and chapter titles

Use short concept titles in the sidebar, such as Configuration, Views, Reloading and Source inspection. Put precise tasks, constraints and failure handling under level-two and level-three headings in the chapter body; those headings generate On this page. Keep full examples intact and explain ownership alongside the operation that needs it.

Set a positive order payload on each guide to define the learning path. The default page stays first; other positive ranks follow in ascending order. Zero or an omitted field retains alphabetical fallback after ranked guides. Use gaps such as 10, 20 and 30 so another chapter can be inserted later. Keep a section's chapters together in that sequence; API references normally omit the rank and follow the learning chapters.

Navigation groups, page arrays, Previous/Next links, source persistence and JSON merging preserve this order. Portable v3 bundles carry the optional numeric order on pages; older v3 bundles without it remain readable. Conflicting ranks for the same identity fail a merge, just like conflicting content. No frontend list or manual index owns the order.

## Search and export

Source-authored pages take precedence when the CLI adds standard manuals. Standard rich pages replace generated code-only bodies, and live inline help is retained; installed descriptions fill missing inline help. New standard pages reuse exported term postings, while changed local entries rebuild their own index. Explicit JSON merges remain strict and reject conflicting content or versions. Child runtimes use normal library discovery and inherit explicit CLI library paths, rather than guessing a build-tree directory for installed executables.

The CLI accepts --from for either a bundle JSON or index.json. It parses the exported index and does not rebuild it. Source catalogs and modified catalogs build their index on demand. The normalization contract is ascii-word-prefix-v1: ASCII case folding, UTF-8 word bytes and prefix queries. A query intersects the matching postings for every word. Symbol punctuation can match phrase titles directly.

Each standard library manual has an overview plus focused guide objects with complete code examples. Keep executable snippets self-contained: import their vocabulary and assert deterministic results, including captured output when relevant. GUI and server examples define callable functions without starting event/accept loops during checks. docs-examples follows the core learning chapters, then the library manuals, evaluating every recurloop or rl code fence in an isolated runtime and working directory, with a timeout. It also checks the native-output artifacts and runs both emitted executables; this requires the documented Clang/LLD tools. Core API invocation templates are reference forms rather than standalone examples; console sessions are descriptive and are not executed. docs-check and GitHub CI run this check automatically.

Make targets: docs-check tests objects, JSON, source dependencies, editing, index reuse and executable manual examples; docs exports all libraries in isolated contexts; docs-library LIBRARY=http writes DOCS_PARTS/http; docs-merge reads those artifacts into DOCS_OUTPUT. A merge accepts identical definitions, rejects conflicting identities, and preserves term postings. No manual index.tsv files are used.

RecurloopDocumentation is the CMake generation target. Package and install workflows generate documentation before installation. GitHub CI generates each library separately using build/CI, merges those outputs, then packages and publishes the JSON files plus a deterministic archive. Generated artifacts belong under build/, dist/, or the portal’s ignored docs-data directory.
