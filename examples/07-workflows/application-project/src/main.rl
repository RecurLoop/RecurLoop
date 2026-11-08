// Loading the project defines the application without starting it.
let Application = [
    answer = fn () -> i64 {
        var answer:i64 = 40
        answer += 2
        return answer
    }
    main = fn () -> i64 {
        printf("%ld\n", Application:answer())
        return 0
    }
]
set Application:answer.docs = "Returns the application's answer: 42."
set Application:main.docs = "Prints the answer and returns exit status 0."
