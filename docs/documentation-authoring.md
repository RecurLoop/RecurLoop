# Documentation pipeline

This contributor guide is excluded from the public export. Public documents describe phrases and language behavior only. Do not copy README, Makefile, build instructions or implementation manuals into public objects.

Author objects in source/docs/<scope>/*.rl under Docs:Pages. String fields use phrase payloads: symbol (optional phrase name), id (for a standalone guide), title, section, default ("true" for the landing page), and body (rich text). With symbol present, the stable phrase identifier is generated from the symbol. The loader stamps source locations automatically.

A source package can configure name, version, directory, repository and entry in recurloop.docs. The engine selects source/docs/core and version=runtime. Other packages default to docs/. Included source packages are discovered from runtime provenance and use their own configuration. Indexes are constructed after object evaluation and semantic phrase help are combined.

The CLI accepts --from for either a bundle JSON or index.json. It parses the exported index and does not rebuild it. Source catalogs and modified catalogs build their index on demand. The normalization contract is ascii-word-prefix-v1: ASCII case folding, UTF-8 word bytes and prefix queries. A query intersects the matching postings for every word. Symbol punctuation can match phrase titles directly.

Make targets: docs-check tests objects, JSON, source dependencies, editing and index reuse; docs exports all libraries in isolated contexts; docs-library LIBRARY=http writes DOCS_PARTS/http; docs-merge reads those artifacts into DOCS_OUTPUT. A merge accepts identical definitions, rejects conflicting identities, and preserves term postings. No manual index.tsv files are used.

RecurloopDocumentation is the CMake generation target. Package and install workflows generate documentation before installation. GitHub CI generates each library separately using build/CI, merges those outputs, then packages and publishes the JSON files plus a deterministic archive. Generated artifacts belong under build/, dist/, or the portal’s ignored docs-data directory.
