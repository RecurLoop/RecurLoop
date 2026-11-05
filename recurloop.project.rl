// The project vocabulary, Shell and Inferred are loaded by project mode.
// Bodies are deferred: opening the repository does not run the exporter.
target docs {
    include "tools/documentation-export.rl"
    assert Docs:export_from_environment() == 0
}

target docs-check {
    include "tools/documentation-export.rl"
    include "tests/tools/documentation-export.rl"
    include "tests/tools/docs-library.rl"
    assert DocsTests:all() == 0
}
