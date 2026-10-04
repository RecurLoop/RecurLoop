// VS Code project entry. Executed and published by the shared RecurLoop server.
// Configured terminal libraries are imported into the immutable baseline.
// Includes define the source/dependency graph used for contextual inspection.
include "examples/07-workflows/ide/application/main.rl"

let VSCode = phrase { dictionary = true }
// Editor integration reads this value by executing `VSCode:describe project`.
// Commands are ordinary RecurLoop source; dependencies run once in graph order.
syntax VSCode:describe "project" => {
    print "{"
    print "  \"workspace\": \".\","
    print "  \"application\": \"examples/07-workflows/ide/application/main.rl\","
    print "  \"targets\": ["
    print "    {"
    print "      \"name\": \"build-release\","
    print "      \"command\": \"emit executable \\\"./.cache/recurloop-vscode/application\\\" vscode_application_main = fn () -> i64 { return ExampleApplication:main() }\""
    print "    },"
    print "    {"
    print "      \"name\": \"build-debug\","
    print "      \"command\": \"emit executable debug \\\"./.cache/recurloop-vscode/application-debug\\\" vscode_application_debug_main = fn () -> i64 { return ExampleApplication:main() }\""
    print "    },"
    print "    {"
    print "      \"name\": \"run\","
    print "      \"dependencies\": ["
    print "        \"build-release\""
    print "      ],"
    print "      \"command\": \"./.cache/recurloop-vscode/application\""
    print "    },"
    print "    {"
    print "      \"name\": \"debug\","
    print "      \"dependencies\": [\"build-debug\"],"
    print "      \"command\": \"var application_status = ExampleApplication:main()\","
    print "      \"debugExecutable\": \".cache/recurloop-vscode/application-debug\""
    print "    },"
    print "    {"
    print "      \"name\": \"check\","
    print "      \"command\": \"assert ExampleApplication:advance(3, 2) == 8\""
    print "    }"
    print "  ]"
    print "}"
}
