recur {
    const memory = malloc(8)
    if !memory { return 1 }
    const typed = cast(i64*, memory)
    typed[0] = 42
    const result = typed[0]
    free(memory)
    if result != 42 { return 2 }
    printf("extern=%lld\n", result)
}
