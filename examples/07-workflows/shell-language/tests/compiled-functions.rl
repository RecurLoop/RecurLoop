// The same shell phrases are valid inside compiled functions. Function-local
// interpolation is compiled to native code and therefore reads native locals.
//
// Build:
//   Recurloop --import /tmp/recurloop-shell-library.rli \
//       --file examples/07-workflows/shell-language/functions.rl
// Run:
//   /tmp/recurloop-shell-functions

let shell_functions_main = fn (argc:i64, argv:u8**) -> i64 {
    var label = "native-fn"
    var number = 40

    let code = run printf "{label}:{number + 2}\\n"
    if code != 0 { return code }

    let result = capture printf "one\\ntwo\\n" | tail -n 1
    if !result { return 100 }
    defer free(result)
    printf("captured in fn: %s", result)
    return 0
}

emit executable "/tmp/recurloop-shell-functions" shell_functions_entry = fn (argc:i64, argv:u8**) -> i64 {
    return shell_functions_main(argc, argv)
}
