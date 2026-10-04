// Example application built and debugged by the IDE.
// It is intentionally independent from the IDE runtime and hot-reload cycle.

link shared "c"
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

let ExampleApplication = phrase { dictionary = true permanent = true }

let ExampleApplication:advance = fn (value:i64, step:i64) -> i64 {
    var next = value * 2
    next += step
    return next
}

let ExampleApplication:main = fn () -> i64 {
    var value:i64 = 3
    var step:i64 = 0

    printf("RecurLoop IDE example application\n")
    while step < 5 {
        value = ExampleApplication:advance(value, step)
        printf("step %lld -> %lld\n", step, value)
        step += 1
    }

    printf("result = %lld\n", value)
    return 0
}
