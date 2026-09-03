// Records may live in ordinary dictionary namespaces.

link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

let Geometry = []

record Geometry:Point {
    x:i64
    y:i64
    // The type name is available while its fields are resolved, so records
    // may contain pointers to their own type.
    next:Geometry:Point*
}

// A function without a receiver remains a regular namespaced function.
let Geometry:Point:new = fn (x:i64, y:i64) -> Geometry:Point* {
    var point:Geometry:Point* = cast(Geometry:Point*, malloc(24))
    point.x = x
    point.y = y
    point.next = cast(Geometry:Point*, 0)
    return point
}

// The first parameter matches the owner type, so `sum` becomes a method.
let Geometry:Point:sum = fn (self:Point*) -> i64 {
    return self.x + self.y
}

let record_example = fn () -> i64 {
    const point = Geometry:Point:new(20, 22)
    const result = point.sum()
    free(cast(u8*, point))
    return result
}

assert record_example() == 42
print "point.sum() = " + str(record_example())

emit executable "/tmp/recurloop-records-and-methods" method_example = fn () -> i64 {
    printf("%lld\n", record_example())
    return 0
}
