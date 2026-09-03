get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
set(SHELL_DIR "${REPOSITORY_ROOT}/examples/07-workflows/shell-language")
set(IMAGE "/tmp/recurloop-shell-library.rli")
set(STDIN_SOURCE "/tmp/recurloop-shell-stdin.rl")

file(REMOVE "${IMAGE}" "/tmp/recurloop-shell-functions")

execute_process(
    COMMAND "${PROGRAM}" --file "${SHELL_DIR}/library.rl"
    RESULT_VARIABLE build_rc OUTPUT_VARIABLE build_out ERROR_VARIABLE build_err
)
if (NOT build_rc EQUAL 0 OR NOT build_out STREQUAL "" OR NOT build_err STREQUAL "" OR NOT EXISTS "${IMAGE}")
    message(FATAL_ERROR
        "Shell image build failed: status=${build_rc}, stdout='${build_out}', stderr='${build_err}'")
endif()

# This is the regression that originally exposed the second shell-only value
# store. Exercise stdin explicitly, not merely --string.
file(WRITE "${STDIN_SOURCE}" "var i = 5\nprint i\n")
execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" -
    INPUT_FILE "${STDIN_SOURCE}"
    RESULT_VARIABLE stdin_rc OUTPUT_VARIABLE stdin_out ERROR_VARIABLE stdin_err
)
if (NOT stdin_rc EQUAL 0 OR NOT stdin_out STREQUAL "5\n" OR NOT stdin_err STREQUAL "")
    message(FATAL_ERROR
        "Imported shell stdin values failed: status=${stdin_rc}, stdout='${stdin_out}', stderr='${stdin_err}'")
endif()

# Build-only implementation spellings are not root exports. A consumer can
# define the former helper names without colliding with the shell image.
file(WRITE "${STDIN_SOURCE}"
    "let shell_token_byte = <debug:ping>\n"
    "let shell_emit_byte = <debug:ping>\n"
    "let install_fn_rewrites = <debug:ping>\n"
    "let fork = <debug:ping>\n"
    "let Shell:Internal = []\n"
    "shell_token_byte\n"
    "shell_emit_byte\n"
    "install_fn_rewrites\n"
    "fork\n")
execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" -
    INPUT_FILE "${STDIN_SOURCE}"
    RESULT_VARIABLE private_rc OUTPUT_VARIABLE private_out ERROR_VARIABLE private_err
)
if (NOT private_rc EQUAL 0 OR NOT private_out STREQUAL "pong\npong\npong\npong\n" OR NOT private_err STREQUAL "")
    message(FATAL_ERROR
        "Shell implementation phrases leaked into root: status=${private_rc}, stdout='${private_out}', stderr='${private_err}'")
endif()

# Public shell syntax is permanent and cannot be silently shadowed after import.
file(WRITE "${STDIN_SOURCE}" "let run = <debug:ping>\n")
execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" -
    INPUT_FILE "${STDIN_SOURCE}"
    RESULT_VARIABLE collision_rc OUTPUT_VARIABLE collision_out ERROR_VARIABLE collision_err
)
if (collision_rc EQUAL 0 OR NOT collision_out STREQUAL "" OR NOT collision_err MATCHES
    "Cannot redefine permanent phrase 'run'")
    message(FATAL_ERROR
        "Permanent shell phrase collision was not rejected: status=${collision_rc}, stdout='${collision_out}', stderr='${collision_err}'")
endif()

# Unknown top-level input enters the shell phrase graph directly. Ordinary
# RecurLoop phrases retain longest-prefix priority, and explicit `run` remains
# available for scripts and compiled functions.
file(WRITE "${STDIN_SOURCE}"
    "echo direct-shell-command | tr a-z A-Z\n"
    "var language_value = 41\n"
    "set language_value += 1\n"
    "print language_value\n"
    "print PS1\n"
    "cd /tmp\n"
    "pwd\n"
    "/usr/bin/printenv PWD\n"
    "cd ..\n"
    "pwd\n")
execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" -
    INPUT_FILE "${STDIN_SOURCE}"
    RESULT_VARIABLE fallback_rc OUTPUT_VARIABLE fallback_out ERROR_VARIABLE fallback_err
)
if (NOT fallback_rc EQUAL 0 OR NOT fallback_out STREQUAL "DIRECT-SHELL-COMMAND\n42\n$ \n/tmp\n/tmp\n/\n" OR NOT fallback_err STREQUAL "")
    message(FATAL_ERROR
        "Shell fallback, PS1, or cd builtin failed: status=${fallback_rc}, stdout='${fallback_out}', stderr='${fallback_err}'")
endif()

file(WRITE "${STDIN_SOURCE}"
    "run printf \"test\"\n"
    "var aaa = status\n"
    "print aaa\n"
    "set aaa = 7\n"
    "print aaa\n"
    "capture printf \"captured\"\n"
    "print captured\n")
execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" -
    INPUT_FILE "${STDIN_SOURCE}"
    RESULT_VARIABLE result_rc OUTPUT_VARIABLE result_out ERROR_VARIABLE result_err
)
if (NOT result_rc EQUAL 0 OR NOT result_out STREQUAL "test0\n7\ncaptured\n" OR NOT result_err STREQUAL "")
    message(FATAL_ERROR
        "Top-level shell results failed: status=${result_rc}, stdout='${result_out}', stderr='${result_err}'")
endif()

# Shell commands can be the RHS of ordinary top-level values. `run` stores an
# integer exit code, `capture` stores stdout text, and `set` preserves the
# existing value's type.
file(WRITE "${STDIN_SOURCE}"
    "var run_result = run true\n"
    "let capture_result = capture printf \"assigned\"\n"
    "print run_result\n"
    "print capture_result\n"
    "set run_result = run false\n"
    "print run_result\n"
    "set capture_result = capture printf \"changed\"\n"
    "print capture_result\n"
    "run true\n")
execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" -
    INPUT_FILE "${STDIN_SOURCE}"
    RESULT_VARIABLE assignment_rc OUTPUT_VARIABLE assignment_out ERROR_VARIABLE assignment_err
)
if (NOT assignment_rc EQUAL 0 OR NOT assignment_out STREQUAL "0\nassigned\n1\nchanged\n" OR
    NOT assignment_err STREQUAL "")
    message(FATAL_ERROR
        "Shell RHS assignments failed: status=${assignment_rc}, stdout='${assignment_out}', stderr='${assignment_err}'")
endif()

execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --file "${SHELL_DIR}/top_level.rl"
    RESULT_VARIABLE top_rc OUTPUT_VARIABLE top_out ERROR_VARIABLE top_err
)
set(TOP_EXPECTED [=[5
hello RECURLOOP #6
captured-5
7
/tmp
7
parallel-7
second-RecurLoop
]=])
if (NOT top_rc EQUAL 0 OR NOT top_out STREQUAL TOP_EXPECTED OR NOT top_err STREQUAL "")
    message(FATAL_ERROR
        "Top-level shell example failed: status=${top_rc}, stdout='${top_out}', stderr='${top_err}'")
endif()

execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --file "${SHELL_DIR}/pipeline.rl"
    RESULT_VARIABLE pipeline_rc OUTPUT_VARIABLE pipeline_out ERROR_VARIABLE pipeline_err
)
if (NOT pipeline_rc EQUAL 0 OR NOT pipeline_out STREQUAL "beta\n" OR NOT pipeline_err STREQUAL "")
    message(FATAL_ERROR
        "Shell pipeline example failed: status=${pipeline_rc}, stdout='${pipeline_out}', stderr='${pipeline_err}'")
endif()

execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --file "${SHELL_DIR}/functions.rl"
    RESULT_VARIABLE functions_build_rc OUTPUT_VARIABLE functions_build_out ERROR_VARIABLE functions_build_err
)
if (NOT functions_build_rc EQUAL 0 OR NOT functions_build_out STREQUAL "" OR NOT functions_build_err STREQUAL "")
    message(FATAL_ERROR
        "Shell functions example build failed: status=${functions_build_rc}, stdout='${functions_build_out}', stderr='${functions_build_err}'")
endif()
execute_process(
    COMMAND "/tmp/recurloop-shell-functions"
    RESULT_VARIABLE functions_rc OUTPUT_VARIABLE functions_out ERROR_VARIABLE functions_err
)
set(FUNCTIONS_EXPECTED "native-fn:42\ncaptured in fn: two\n")
if (NOT functions_rc EQUAL 0 OR NOT functions_out STREQUAL FUNCTIONS_EXPECTED OR NOT functions_err STREQUAL "")
    message(FATAL_ERROR
        "Shell functions executable failed: status=${functions_rc}, stdout='${functions_out}', stderr='${functions_err}'")
endif()

# Executable documentation for asynchronous Invocation objects and native
# RecurLoop function stages in a pipeline.
execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --file "${SHELL_DIR}/bash_like.rl"
    RESULT_VARIABLE bash_like_build_rc OUTPUT_VARIABLE bash_like_build_out ERROR_VARIABLE bash_like_build_err
)
if (NOT bash_like_build_rc EQUAL 0 OR NOT bash_like_build_out STREQUAL "0\nassigned\n" OR
    NOT bash_like_build_err STREQUAL "")
    message(FATAL_ERROR
        "Bash-like example build failed: status=${bash_like_build_rc}, stdout='${bash_like_build_out}', stderr='${bash_like_build_err}'")
endif()
execute_process(
    COMMAND "/tmp/recurloop-bash-like"
    RESULT_VARIABLE bash_like_rc OUTPUT_VARIABLE bash_like_out ERROR_VARIABLE bash_like_err
)
set(BASH_LIKE_EXPECTED [=[async: first + second
function stage: MIXED CASE
result object: stdout=partial, exit=7
]=])
if (NOT bash_like_rc EQUAL 0 OR NOT bash_like_out STREQUAL BASH_LIKE_EXPECTED OR NOT bash_like_err STREQUAL "")
    message(FATAL_ERROR
        "Bash-like example failed: status=${bash_like_rc}, stdout='${bash_like_out}', stderr='${bash_like_err}'")
endif()

execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --file "${SHELL_DIR}/example.rl"
    RESULT_VARIABLE example_build_rc OUTPUT_VARIABLE example_build_out ERROR_VARIABLE example_build_err
)
if (NOT example_build_rc EQUAL 0 OR NOT example_build_out STREQUAL "" OR NOT example_build_err STREQUAL "")
    message(FATAL_ERROR
        "Shell application example build failed: status=${example_build_rc}, stdout='${example_build_out}', stderr='${example_build_err}'")
endif()
execute_process(
    COMMAND "/tmp/recurloop-shell-app-example"
    RESULT_VARIABLE example_rc OUTPUT_VARIABLE example_out ERROR_VARIABLE example_err
)
set(EXAMPLE_EXPECTED [=[RecurLoop imported shell library example
run imported from .rli: OK
captured: three
environment: enabled
pipeline/redirection from .rli: OK
capture from .rli:              OK
directory scope from .rli:      OK
environment scope from .rli:    OK
parallel jobs from .rli:        OK
typed RecurLoop + shell DSL:     OK
all imported shell library checks passed
]=])
if (NOT example_rc EQUAL 0 OR NOT example_out STREQUAL EXAMPLE_EXPECTED OR NOT example_err STREQUAL "")
    message(FATAL_ERROR
        "Shell application example failed: status=${example_rc}, stdout='${example_out}', stderr='${example_err}'")
endif()

file(WRITE "${STDIN_SOURCE}" "var i = 5\nrun printf \"{missing}\\\\n\"\n")
execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" -
    INPUT_FILE "${STDIN_SOURCE}"
    RESULT_VARIABLE error_rc OUTPUT_VARIABLE error_out ERROR_VARIABLE error_err
)
if (error_rc EQUAL 0 OR NOT error_out STREQUAL "" OR NOT error_err MATCHES
    "<input>:2:[0-9]+: expression: undefined variable: 'missing'")
    message(FATAL_ERROR
        "Shell interpolation diagnostic failed: status=${error_rc}, stdout='${error_out}', stderr='${error_err}'")
endif()

file(REMOVE
    "${STDIN_SOURCE}"
    "${IMAGE}"
    "/tmp/recurloop-shell-functions"
    "/tmp/recurloop-bash-like"
    "/tmp/recurloop-shell-app-example"
    "/tmp/recurloop-shell-import-pipeline.txt"
    "/tmp/recurloop-shell-import-cwd.txt"
    "/tmp/recurloop-shell-import-env.txt"
    "/tmp/recurloop-shell-import-a.txt"
    "/tmp/recurloop-shell-import-b.txt"
    "/tmp/recurloop-shell-import-c.txt"
)
