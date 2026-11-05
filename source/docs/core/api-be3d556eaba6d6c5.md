```recurloop
alloc(Type)
```

In a compiled function, allocates an object with `malloc` and returns `Type*`. Storage is uninitialized; check for a null pointer and release it with `free`.

**Example (inside fn)**

```recurloop
let point = alloc(Point)
if !point { return 1 }
defer free(cast(u8*, point))
```


