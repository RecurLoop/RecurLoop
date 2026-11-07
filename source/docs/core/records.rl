// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:records = [
    id = phrase { payload = "records" }
    title = phrase { payload = "Records" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "140" }
    body = phrase {
        payload = "Records describe native memory with named fields. Use them when several values must travel together through a typed interface.

## Declare a memory layout

`record` defines physical native layout, including field offsets, alignment,
arrays, nested records, packed layout, and recursive pointer fields.

Array fields support direct indexing (`state.bricks[index]`) and nested access
(`state.rows[row].cells[column]`), including assignment and taking an element's
address. A pointer cast is unnecessary.

```recurloop
record Point {
    x:i64
    y:i64
}

let Point:sum = fn (self:Point*) -> i64 {
    return self.x + self.y
}
```

## Methods and dictionary templates

A function whose first parameter is a pointer to the owning record is
available through method syntax (`point.sum()`).

Dictionary `struct` declarations are different: they create phrase templates
and inherited subdictionaries, not native memory layouts."
    }
]
