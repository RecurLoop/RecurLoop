target docs {
    include "tools/documentation-export.rl"
    assert Docs:Build:export_from_environment() == 0
}

target docs-check {
    import docs
    include "tests/tools/documentation-export.rl"
    include "tests/tools/docs-library.rl"
    assert DocsTests:all() == 0
}
