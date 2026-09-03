// ============================================================================
// RecurLoop shell DSL - application using a prebuilt language image
//
// First build the reusable shell image:
//   Recurloop --file examples/07-workflows/shell-language/library.rl
//
// Then compile this application in a fresh RecurLoop process:
//   Recurloop --import /tmp/recurloop-shell-library.rli \\
//       --file examples/07-workflows/shell-language/example.rl
//
// Run:
//   /tmp/recurloop-shell-app-example
//
// This file intentionally contains NO implementation of run/capture/pipelines,
// directory/environment scopes, or parallel jobs. Those constructs come from
// /tmp/recurloop-shell-library.rli.
// ============================================================================

let ShellApp = []

let ShellApp:check_text_file = fn (path:u8*, expected_first:u8) -> i64 {
    let file = fopen(path, "rb")
    if !file { return 0 }
    var byte = 0
    let got = fread(&byte, 1, 1, file)
    fclose(file)
    if got != 1 { return 0 }
    return byte == expected_first
}

let shell_app_main = fn (argc:i64, argv:u8**) -> i64 {
    printf("RecurLoop imported shell library example\n")

    // ------------------------------------------------------------------------
    // 1. A normal external command.
    // ------------------------------------------------------------------------
    let basic = run printf "run imported from .rli: OK\\n"
    if basic != 0 { return 10 }

    // ------------------------------------------------------------------------
    // 2. Native pipeline + output redirection.
    // ------------------------------------------------------------------------
    let pipeline = run printf "alpha\\nbeta\\ngamma\\n" | grep beta > "/tmp/recurloop-shell-import-pipeline.txt"

    if pipeline != 0 { return 11 }

    // ------------------------------------------------------------------------
    // 3. Capture stdout from a native pipeline.
    // ------------------------------------------------------------------------
    let captured = capture printf "one\\ntwo\\nthree\\n" | tail -n 1

    if !captured { return 12 }
    defer free(captured)
    printf("captured: %s", captured)

    // ------------------------------------------------------------------------
    // 4. Scoped current working directory.
    // ------------------------------------------------------------------------
    if 1 {
        let directory_guard = Shell:cwd_enter("/tmp")
        if !directory_guard { return 14 }
        defer Shell:cwd_leave(directory_guard)
        let cwd = run pwd > "recurloop-shell-import-cwd.txt"
        if cwd != 0 { return 14 }
    }

    // ------------------------------------------------------------------------
    // 5. Scoped environment variables inherited by child processes.
    // ------------------------------------------------------------------------
    if 1 {
        let shell_env = Shell:env_enter("RECURLOOP_IMPORTED_SHELL", "enabled")
        let value_env = Shell:env_enter("RECURLOOP_IMPORTED_VALUE", "42")
        if !shell_env || !value_env { return 15 }
        defer Shell:env_leave(shell_env)
        defer Shell:env_leave(value_env)

        let env = capture printenv RECURLOOP_IMPORTED_SHELL
        if !env { return 15 }
        defer free(env)
        printf("environment: %s", env)

        let write_env = run printenv RECURLOOP_IMPORTED_VALUE > "/tmp/recurloop-shell-import-env.txt"

        if write_env != 0 { return 17 }
    }

    // Scoped variables must be restored when environment{} finishes.
    if getenv("RECURLOOP_IMPORTED_SHELL") { return 18 }
    if getenv("RECURLOOP_IMPORTED_VALUE") { return 19 }

    // ------------------------------------------------------------------------
    // 6. Parallel process groups. Each job may itself contain a pipeline.
    // ------------------------------------------------------------------------
    let jobs = Shell:Parallel:new()
    if !jobs { return 20 }
    defer Shell:Parallel:destroy(jobs)
    if !jobs.spawn_command("printf", "parallel-a\\n", "/tmp/recurloop-shell-import-a.txt") { return 20 }
    if !jobs.spawn_command("printf", "parallel-b\\n", "/tmp/recurloop-shell-import-b.txt") { return 20 }
    if !jobs.spawn_command("printf", "parallel-c\\n", "/tmp/recurloop-shell-import-c.txt") { return 20 }
    if jobs.wait() != 0 { return 20 }

    // ------------------------------------------------------------------------
    // 7. Mix ordinary typed RecurLoop code with shell DSL constructs.
    // ------------------------------------------------------------------------
    var successful_commands = 0
    var i = 0
    while i < 3 {
        let iteration = capture printf "iteration\\n"
        if !iteration { return 20 }
        defer free(iteration)
        successful_commands += 1
        i += 1
    }

    if successful_commands != 3 { return 21 }

    if !ShellApp:check_text_file("/tmp/recurloop-shell-import-pipeline.txt", 98) { return 22 }
    if !ShellApp:check_text_file("/tmp/recurloop-shell-import-env.txt", 52) { return 23 }
    if !ShellApp:check_text_file("/tmp/recurloop-shell-import-a.txt", 112) { return 24 }
    if !ShellApp:check_text_file("/tmp/recurloop-shell-import-b.txt", 112) { return 25 }
    if !ShellApp:check_text_file("/tmp/recurloop-shell-import-c.txt", 112) { return 26 }

    printf("pipeline/redirection from .rli: OK\n")
    printf("capture from .rli:              OK\n")
    printf("directory scope from .rli:      OK\n")
    printf("environment scope from .rli:    OK\n")
    printf("parallel jobs from .rli:        OK\n")
    printf("typed RecurLoop + shell DSL:     OK\n")
    printf("all imported shell library checks passed\n")
    return 0
}

emit executable "/tmp/recurloop-shell-app-example" shell_app_entry = fn (argc:i64, argv:u8**) -> i64 {
    return shell_app_main(argc, argv)
}
