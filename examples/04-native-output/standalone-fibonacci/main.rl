// Compile a regular RecurLoop function into a standalone Linux executable.
// After this source runs, try: /tmp/recurloop-fibonacci 8

link shared "c"
extern atoi(text:u8*) -> i64 abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

fn fibonacci(value:i64) -> i64 {
    if value < 2 {
        return value
    }
    return fibonacci(value - 1) + fibonacci(value - 2)
}

assert fibonacci(10) == 55

module auto
module clear
emit executable "/tmp/recurloop-fibonacci" main = fn (argc:i64, argv:u8**) -> i64 {
    if argc < 2 {
        printf("usage: recurloop-fibonacci COUNT\n")
        return 1
    }

    let count = atoi(argv[1])
    var index = 1
    while index <= count {
        printf("%lld\n", fibonacci(index))
        index += 1
    }
    return 0
}
