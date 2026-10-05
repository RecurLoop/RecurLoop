// One executable project definition for CLI, terminals and editors.
include "examples/07-workflows/ide/application/main.rl"

target build-release {
    emit executable "./.cache/recurloop/application" application_main = fn () -> i64 {
        return ExampleApplication:main()
    }
}

target build-debug {
    emit executable debug "./.cache/recurloop/application-debug" application_debug_main = fn () -> i64 {
        return ExampleApplication:main()
    }
}

target run depends [build-release] {
    ./.cache/recurloop/application
}

target debug depends [build-debug] debug executable ".cache/recurloop/application-debug" {
    var application_status = ExampleApplication:main()
}

target check {
    assert ExampleApplication:advance(3, 2) == 8
}
