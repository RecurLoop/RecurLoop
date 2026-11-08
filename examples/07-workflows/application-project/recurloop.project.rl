import project
include "src/main.rl"

target run {
    assert Application:main() == 0
}

target build {
    let prepared = run mkdir -p build
    assert prepared == 0
    module auto
    emit executable "./build/app" application_main = fn () -> i64 {
        return Application:main()
    }
}

target build-debug {
    let prepared = run mkdir -p build
    assert prepared == 0
    module auto
    emit executable debug "./build/app-debug" application_debug_main = fn () -> i64 {
        return Application:main()
    }
}

target debug depends [build-debug] debug executable "./build/app-debug" {}

target test {
    include "tests/main.rl"
}

target docs {
    import docs
    let prepared = run mkdir -p build/docs
    assert prepared == 0
    assert Docs:export_package(".", "build/docs/my-application.json") == 1
}

target clean {
    let cleaned = run rm -rf -- build
    assert cleaned == 0
}
