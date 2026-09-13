link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64

let Geometry = []
record Geometry:Point {
    x:i64
    y:i64
    next:Geometry:Point*
}

let Geometry:Point:new = fn (x:i64, y:i64) -> Geometry:Point* {
    var point:Geometry:Point* = cast(Geometry:Point*, malloc(24))
    point.x = x
    point.y = y
    point.next = cast(Geometry:Point*, 0)
    return point
}

let Geometry:Point:sum = fn (self:Point*) -> i64 {
    return self.x + self.y
}

let record_parity = fn () -> i64 {
    const point = Geometry:Point:new(20, 22)
    const result = point.sum()
    free(cast(u8*, point))
    return result
}

assert record_parity() == 42
