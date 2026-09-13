recur {
    record Geometry:Point {
        x:i64
        y:i64
        next:Geometry:Point*
    }
    fn Geometry:Point:new(x:i64, y:i64) -> Geometry:Point* {
        var point:Geometry:Point* = cast(Geometry:Point*, malloc(24))
        point.x = x
        point.y = y
        point.next = cast(Geometry:Point*, 0)
        return point
    }
    fn Geometry:Point:sum(self:Geometry:Point*) -> i64 {
        return self.x + self.y
    }
    const point = Geometry:Point:new(20, 22)
    const result = point.sum()
    free(cast(u8*, point))
    if result != 42 { return 1 }
    printf("point.sum() = %lld\n", result)
}
