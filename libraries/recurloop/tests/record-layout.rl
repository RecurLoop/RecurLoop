recur {
    record Node {
        value:i64
        next:Node*
        lanes:u8[8]
    }

    fn node_size() -> i64 {
        return 24
    }

    const result = node_size()
    if result != 24 { return 51 }
    printf("layout=%lld\n", result)
}
